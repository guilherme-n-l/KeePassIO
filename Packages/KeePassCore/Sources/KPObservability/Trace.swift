import Synchronization

/// Entry point for instrumenting code.
///
/// Wrap an operation in `Trace.span` and every installed backend sees it:
/// signposts on Apple platforms, uprobe markers on Linux, and in-memory
/// recording when a benchmark asks for it.
///
/// ```swift
/// let database = try Trace.span(.kdbxDecrypt, argument: UInt64(fileSize)) {
///     try decrypt(file)
/// }
/// ```
public enum Trace {
    private static let backends = Mutex<[any TraceBackend]>(defaultBackends())
    private static let nextID = Atomic<UInt64>(1)

    /// Backends for the current task only, replacing the global ones.
    /// Tests use it to record their own spans without seeing spans from
    /// code running concurrently elsewhere in the process.
    @TaskLocal public static var taskBackends: [any TraceBackend]?

    /// Replaces the installed backends. Call it once at startup, before
    /// any span runs; an empty list disables tracing.
    public static func bootstrap(_ newBackends: [any TraceBackend]) {
        backends.withLock { $0 = newBackends }
    }

    /// The backends installed when `bootstrap` hasn't been called.
    public static func defaultBackends() -> [any TraceBackend] {
        #if canImport(os)
            [SignpostBackend()]
        #elseif os(Linux)
            [ProbeBackend()]
        #else
            []
        #endif
    }

    /// Runs `body` inside a span.
    ///
    /// - Parameters:
    ///   - span: The operation being measured.
    ///   - argument: A size or count that helps interpret the timing, such
    ///     as a file size in bytes. Never pass anything derived from secrets.
    public static func span<Result>(
        _ span: SpanName,
        argument: UInt64 = 0,
        _ body: () throws -> Result
    ) rethrows -> Result {
        let (id, active) = begin(span, argument: argument)
        defer { end(span, id: id, argument: argument, backends: active) }
        return try body()
    }

    /// Async version of ``span(_:argument:_:)``.
    public static func span<Result>(
        _ span: SpanName,
        argument: UInt64 = 0,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Result
    ) async rethrows -> Result {
        let (id, active) = begin(span, argument: argument)
        defer { end(span, id: id, argument: argument, backends: active) }
        return try await body()
    }

    private static func begin(_ span: SpanName, argument: UInt64) -> (UInt64, [any TraceBackend]) {
        let active = taskBackends ?? backends.withLock { $0 }
        let id = nextID.wrappingAdd(1, ordering: .relaxed).oldValue
        for backend in active {
            backend.begin(span, id: id, argument: argument)
        }
        return (id, active)
    }

    private static func end(
        _ span: SpanName,
        id: UInt64,
        argument: UInt64,
        backends active: [any TraceBackend]
    ) {
        for backend in active.reversed() {
            backend.end(span, id: id, argument: argument)
        }
    }
}
