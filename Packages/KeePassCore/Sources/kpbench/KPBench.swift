import ArgumentParser
import Foundation
import KPObservability

@main
struct KPBench: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kpbench",
        abstract: "Benchmarks and traces KeePassIOS core operations.",
        subcommands: [Spans.self, ProbeCheck.self]
    )
}

/// Prints the span catalog, one `id<TAB>name` line per span. The bpftrace
/// wrapper uses it to turn numeric span IDs into names.
struct Spans: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List span IDs and names.")

    func run() {
        for span in SpanName.allCases {
            print("\(span.rawValue)\t\(span.displayName)")
        }
    }
}

/// Runs a small synthetic workload through nested spans with known
/// durations, so the tracing pipeline (probes, recorder, trace export) can
/// be checked end to end without a database.
struct ProbeCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-check",
        abstract: "Emit a known pattern of spans to verify tracing tools."
    )

    @Option(help: "How many times to run the pattern.")
    var iterations = 20

    @Option(help: "Write a Chrome/Perfetto trace of the run to this path.")
    var trace: String?

    @Option(help: "Seconds to wait before starting, so a profiler can attach.")
    var startDelay = 0.0

    func run() throws {
        let recorder = RecordingBackend()
        Trace.bootstrap(Trace.defaultBackends() + [recorder])

        if startDelay > 0 {
            Thread.sleep(forTimeInterval: startDelay)
        }

        for _ in 0..<iterations {
            Trace.span(.unlockTotal) {
                Trace.span(.kdfArgon2, argument: 64 << 20) { Thread.sleep(forTimeInterval: 0.002) }
                Trace.span(.kdbxDecrypt, argument: 1 << 20) { Thread.sleep(forTimeInterval: 0.001) }
            }
        }

        let histograms = LatencyHistogram.byName(recorder.spans)
        for span in SpanName.allCases {
            guard let histogram = histograms[span] else { continue }
            let median = (histogram.quantileUpperBound(0.5) ?? 0) / 1_000
            print("\(span.displayName): \(histogram.count) spans, p50 < \(median) µs")
        }

        if let trace {
            try ChromeTrace.json(for: recorder.spans).write(to: URL(fileURLWithPath: trace))
            print("Trace written to \(trace)")
        }
    }
}
