import Foundation

/// Converts recorded spans into the Chrome trace event JSON format, which
/// ui.perfetto.dev and chrome://tracing open directly.
public enum ChromeTrace {
    private struct Event: Encodable {
        let name: String
        let cat = "keepassios"
        let ph = "X"
        let ts: Double
        let dur: Double
        let pid = 1
        let tid: UInt64
        let args: Args
    }

    private struct Args: Encodable {
        let id: UInt64
        let argument: UInt64
    }

    private struct File: Encodable {
        let traceEvents: [Event]
        let displayTimeUnit = "ms"
    }

    /// JSON for the given spans. Times are in microseconds, as the format
    /// expects.
    public static func json(for spans: [RecordedSpan]) throws -> Data {
        let events = spans.map { span in
            Event(
                name: span.span.displayName,
                ts: Double(span.startNanoseconds) / 1_000,
                dur: Double(span.durationNanoseconds) / 1_000,
                tid: span.track,
                args: Args(id: span.id, argument: span.argument)
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(File(traceEvents: events))
    }
}
