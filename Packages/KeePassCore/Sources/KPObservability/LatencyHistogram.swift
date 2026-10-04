/// Fixed-size latency histogram with power-of-two microsecond buckets.
///
/// Bucket `i` counts durations in `[2^i, 2^(i+1))` microseconds; bucket 0
/// also holds anything under 1 µs, and the last bucket holds everything
/// from about 1 hour up. The fixed layout keeps it small enough to keep
/// on device for every span and to merge across sessions, the same shape
/// bpftrace's `hist()` prints.
public struct LatencyHistogram: Sendable, Equatable, Codable {
    public static let bucketCount = 32

    public private(set) var buckets: [UInt64]
    public private(set) var count: UInt64 = 0
    public private(set) var totalNanoseconds: UInt64 = 0
    public private(set) var maxNanoseconds: UInt64 = 0

    // `count` here is a stored sample count, not a collection count.
    public var isEmpty: Bool { count == 0 }  // swiftlint:disable:this empty_count

    public init() {
        buckets = Array(repeating: 0, count: Self.bucketCount)
    }

    public mutating func record(nanoseconds: UInt64) {
        buckets[Self.bucket(for: nanoseconds)] += 1
        count += 1
        totalNanoseconds &+= nanoseconds
        maxNanoseconds = max(maxNanoseconds, nanoseconds)
    }

    public mutating func merge(_ other: LatencyHistogram) {
        for index in buckets.indices {
            buckets[index] += other.buckets[index]
        }
        count += other.count
        totalNanoseconds &+= other.totalNanoseconds
        maxNanoseconds = max(maxNanoseconds, other.maxNanoseconds)
    }

    /// The upper bound, in nanoseconds, of the bucket containing the given
    /// quantile (0...1). Returns nil when the histogram is empty.
    public func quantileUpperBound(_ quantile: Double) -> UInt64? {
        guard !isEmpty else { return nil }
        let target = UInt64((Double(count) * min(max(quantile, 0), 1)).rounded(.up))
        var seen: UInt64 = 0
        for (index, bucketCount) in buckets.enumerated() {
            seen += bucketCount
            if seen >= max(target, 1) {
                return Self.upperBoundNanoseconds(ofBucket: index)
            }
        }
        return maxNanoseconds
    }

    static func bucket(for nanoseconds: UInt64) -> Int {
        let microseconds = nanoseconds / 1_000
        guard microseconds > 0 else { return 0 }
        let log2 = UInt64.bitWidth - 1 - microseconds.leadingZeroBitCount
        return min(log2, bucketCount - 1)
    }

    static func upperBoundNanoseconds(ofBucket index: Int) -> UInt64 {
        (UInt64(1) << UInt64(index + 1)) * 1_000
    }
}

extension LatencyHistogram {
    /// Builds one histogram per span name from recorded spans.
    public static func byName(_ spans: [RecordedSpan]) -> [SpanName: LatencyHistogram] {
        var result: [SpanName: LatencyHistogram] = [:]
        for span in spans {
            result[span.span, default: LatencyHistogram()].record(nanoseconds: span.durationNanoseconds)
        }
        return result
    }
}
