import Synchronization

/// One completed span, with times relative to the recorder's creation.
public struct RecordedSpan: Sendable, Equatable {
    public let span: SpanName
    public let id: UInt64
    public let argument: UInt64
    public let startNanoseconds: UInt64
    public let durationNanoseconds: UInt64
    /// Identifies the thread or task context that ran the span, so trace
    /// viewers can draw nested spans on one track.
    public let track: UInt64
}

/// Keeps every completed span in memory. Benchmarks and tests install it to
/// read timings back, export traces and fill histograms.
public final class RecordingBackend: TraceBackend {
    private struct OpenSpan {
        let start: ContinuousClock.Instant
        let track: UInt64
    }

    private let origin = ContinuousClock.now
    private let state = Mutex<(open: [UInt64: OpenSpan], done: [RecordedSpan])>(([:], []))
    private let trackProvider: @Sendable () -> UInt64

    /// - Parameter trackProvider: Returns an ID for the current thread or
    ///   task. Defaults to a single track.
    public init(trackProvider: @escaping @Sendable () -> UInt64 = { 0 }) {
        self.trackProvider = trackProvider
    }

    public func begin(_ span: SpanName, id: UInt64, argument: UInt64) {
        let open = OpenSpan(start: .now, track: trackProvider())
        state.withLock { $0.open[id] = open }
    }

    public func end(_ span: SpanName, id: UInt64, argument: UInt64) {
        let now = ContinuousClock.now
        state.withLock { state in
            guard let open = state.open.removeValue(forKey: id) else { return }
            state.done.append(
                RecordedSpan(
                    span: span,
                    id: id,
                    argument: argument,
                    startNanoseconds: (open.start - origin).nanoseconds,
                    durationNanoseconds: (now - open.start).nanoseconds,
                    track: open.track
                )
            )
        }
    }

    /// Completed spans in the order they finished.
    public var spans: [RecordedSpan] {
        state.withLock { $0.done }
    }

    /// Removes all completed spans.
    public func reset() {
        state.withLock { $0.done.removeAll() }
    }
}

extension Duration {
    var nanoseconds: UInt64 {
        let (seconds, attoseconds) = components
        return UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds)) / 1_000_000_000
    }
}
