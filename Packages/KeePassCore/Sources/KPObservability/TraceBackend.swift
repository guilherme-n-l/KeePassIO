/// A destination for span begin and end events.
///
/// Backends receive only the span name, a per-span ID and an optional
/// numeric argument (a size or count). They never receive entry data.
public protocol TraceBackend: Sendable {
    func begin(_ span: SpanName, id: UInt64, argument: UInt64)
    func end(_ span: SpanName, id: UInt64, argument: UInt64)
}
