import Foundation
import Synchronization

/// Keeps a latency histogram per span, the always-on aggregation behind
/// the app's Diagnostics screen. Like an eBPF map, it stores only counts
/// per duration bucket, so it stays small however long the app runs.
public final class HistogramBackend: TraceBackend {
    private let open = Mutex<[UInt64: ContinuousClock.Instant]>([:])
    private let state = Mutex<[SpanName: LatencyHistogram]>([:])

    public init() {}

    public func begin(_ span: SpanName, id: UInt64, argument: UInt64) {
        let now = ContinuousClock.now
        open.withLock { $0[id] = now }
    }

    public func end(_ span: SpanName, id: UInt64, argument: UInt64) {
        let now = ContinuousClock.now
        guard let start = open.withLock({ $0.removeValue(forKey: id) }) else { return }
        let nanoseconds = (now - start).nanoseconds
        state.withLock { $0[span, default: LatencyHistogram()].record(nanoseconds: nanoseconds) }
    }

    public var histograms: [SpanName: LatencyHistogram] {
        state.withLock { $0 }
    }

    /// JSON for bug reports: span names, counts and bucket counts only.
    public func exportJSON(appVersion: String, osVersion: String) throws -> Data {
        struct Export: Encodable {
            let appVersion: String
            let osVersion: String
            let exportedAt: Date
            let bucketUpperBoundsMicroseconds: [UInt64]
            let spans: [String: LatencyHistogram]
        }
        let export = Export(
            appVersion: appVersion,
            osVersion: osVersion,
            exportedAt: Date(),
            bucketUpperBoundsMicroseconds: (0..<LatencyHistogram.bucketCount).map {
                LatencyHistogram.upperBoundNanoseconds(ofBucket: $0) / 1_000
            },
            spans: Dictionary(uniqueKeysWithValues: histograms.map { ($0.key.displayName, $0.value) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }
}
