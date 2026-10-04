import Foundation
import Testing

@testable import KPObservability

// Trace's backends are process-wide, so tests that install them run serially.
@Suite(.serialized)
struct TraceTests {
    @Test func spanReturnsTheBodysResultAndIsRecorded() throws {
        let recorder = RecordingBackend()
        Trace.bootstrap([recorder])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        let value = Trace.span(.kdbxDecrypt, argument: 42) { 7 }

        #expect(value == 7)
        let spans = recorder.spans
        #expect(spans.count == 1)
        #expect(spans.first?.span == .kdbxDecrypt)
        #expect(spans.first?.argument == 42)
    }

    @Test func nestedSpansFinishInsideOut() {
        let recorder = RecordingBackend()
        Trace.bootstrap([recorder])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        Trace.span(.unlockTotal) {
            Trace.span(.kdfArgon2) {}
            Trace.span(.kdbxDecrypt) {}
        }

        #expect(recorder.spans.map(\.span) == [.kdfArgon2, .kdbxDecrypt, .unlockTotal])
        let outer = recorder.spans[2]
        for inner in recorder.spans.prefix(2) {
            #expect(inner.startNanoseconds >= outer.startNanoseconds)
            #expect(inner.durationNanoseconds <= outer.durationNanoseconds)
        }
    }

    @Test func spanEndsWhenTheBodyThrows() {
        struct Failure: Error {}
        let recorder = RecordingBackend()
        Trace.bootstrap([recorder])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        #expect(throws: Failure.self) {
            try Trace.span(.saveFsync) { throw Failure() }
        }
        #expect(recorder.spans.map(\.span) == [.saveFsync])
    }

    @Test func asyncSpanIsRecorded() async {
        let recorder = RecordingBackend()
        Trace.bootstrap([recorder])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        let value = await Trace.span(.mergePlan) {
            await Task.yield()
            return "done"
        }

        #expect(value == "done")
        #expect(recorder.spans.map(\.span) == [.mergePlan])
    }

    @Test func emptyBackendListDisablesTracing() {
        Trace.bootstrap([])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        #expect(Trace.span(.searchQuery) { 1 } == 1)
    }
}

struct SpanNameTests {
    @Test func idsAndNamesAreUnique() {
        let ids = SpanName.allCases.map(\.rawValue)
        let names = SpanName.allCases.map(\.displayName)
        #expect(Set(ids).count == ids.count)
        #expect(Set(names).count == names.count)
    }
}

struct LatencyHistogramTests {
    @Test(arguments: [
        (UInt64(0), 0),
        (999, 0),
        (1_000, 0),
        (1_999, 0),
        (2_000, 1),
        (1_000_000, 9),
        (UInt64.max, LatencyHistogram.bucketCount - 1),
    ])
    func bucketing(nanoseconds: UInt64, expected: Int) {
        #expect(LatencyHistogram.bucket(for: nanoseconds) == expected)
    }

    @Test func quantilesAndMerge() {
        var fast = LatencyHistogram()
        for _ in 0..<99 { fast.record(nanoseconds: 1_500) }
        var slow = LatencyHistogram()
        slow.record(nanoseconds: 3_000_000)

        fast.merge(slow)

        #expect(fast.count == 100)
        #expect(fast.maxNanoseconds == 3_000_000)
        #expect(fast.quantileUpperBound(0.5) == 2_000)
        #expect(fast.quantileUpperBound(1.0) == 4_096_000)
        #expect(LatencyHistogram().quantileUpperBound(0.5) == nil)
    }
}

struct ChromeTraceTests {
    @Test func exportsCompleteEventsInMicroseconds() throws {
        let span = RecordedSpan(
            span: .saveEncrypt,
            id: 3,
            argument: 1_024,
            startNanoseconds: 2_000,
            durationNanoseconds: 5_000,
            track: 9
        )

        let data = try ChromeTrace.json(for: [span])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try #require(object["traceEvents"] as? [[String: Any]])
        let event = try #require(events.first)

        #expect(event["name"] as? String == "save.encrypt")
        #expect(event["ph"] as? String == "X")
        #expect(event["ts"] as? Double == 2)
        #expect(event["dur"] as? Double == 5)
        #expect(event["tid"] as? Int == 9)
    }
}

@Suite(.serialized)
struct HistogramBackendTests {
    @Test func aggregatesPerSpanAndExports() throws {
        let backend = HistogramBackend()
        Trace.bootstrap([backend])
        defer { Trace.bootstrap(Trace.defaultBackends()) }

        for _ in 0..<5 {
            Trace.span(.searchQuery) {}
        }
        Trace.span(.saveFsync) {}

        let histograms = backend.histograms
        #expect(histograms[.searchQuery]?.count == 5)
        #expect(histograms[.saveFsync]?.count == 1)

        let json = try backend.exportJSON(appVersion: "1.0 (1)", osVersion: "test")
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let spans = try #require(object["spans"] as? [String: Any])
        #expect(Set(spans.keys) == ["search.query", "save.fsync"])
        #expect((object["bucketUpperBoundsMicroseconds"] as? [Int])?.first == 2)
    }
}
