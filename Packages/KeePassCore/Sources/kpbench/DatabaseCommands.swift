import ArgumentParser
import Foundation
import KPKDBX
import KPMerge
import KPModel
import KPObservability
import KPSearch
import KPSession

/// Options shared by commands that trace a run.
struct TraceOptions: ParsableArguments {
    @Option(help: "Write a Chrome/Perfetto trace of the run to this path.")
    var trace: String?

    @Option(help: "Seconds to wait before starting, so a profiler can attach.")
    var startDelay = 0.0

    func start() -> RecordingBackend {
        let recorder = RecordingBackend()
        Trace.bootstrap(Trace.defaultBackends() + [recorder])
        if startDelay > 0 {
            Thread.sleep(forTimeInterval: startDelay)
        }
        return recorder
    }

    func finish(_ recorder: RecordingBackend) throws {
        let histograms = LatencyHistogram.byName(recorder.spans)
        for span in SpanName.allCases {
            guard let histogram = histograms[span] else { continue }
            let total = Double(histogram.totalNanoseconds) / 1_000_000
            let name = span.displayName.padding(toLength: 20, withPad: " ", startingAt: 0)
            print(name + String(format: "%5d× %10.2f ms total", Int(histogram.count), total))
        }
        if let trace {
            try ChromeTrace.json(for: recorder.spans).write(to: URL(fileURLWithPath: trace))
            print("Trace written to \(trace)")
        }
    }
}

/// Creates a database with generated entries, for benchmarks.
struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a test database with N generated entries.")

    @Argument(help: "Output .kdbx path.") var path: String
    @Option(help: "Number of entries.") var entries = 1_000
    @Option(help: "History items per entry.") var history = 1
    @Option(help: "Password.") var password = "benchmark"
    @Option(help: "Argon2id memory in MiB (1 for fast test files).") var memory: UInt64 = 64

    func run() async throws {
        var database = Database.empty(name: "Benchmark")
        database.meta.historyMaxItems = -1
        var groupIDs = [database.root.id]
        for index in 0..<max(1, entries / 100) {
            let group = Group(name: "Group \(index)")
            try database.add(group, to: database.root.id)
            groupIDs.append(group.id)
        }
        for index in 0..<entries {
            var entry = Entry()
            entry.title = "Entry \(index)"
            entry.userName = "user\(index)@example.com"
            entry.password = SecretString("password-\(index)-\(UUID().uuidString)")
            entry.url = "https://site\(index % 500).example.com/login"
            entry.notes = "Notes for entry \(index)"
            let groupID = groupIDs[index % groupIDs.count]
            try database.add(entry, to: groupID)
            for version in 0..<history {
                var updated = entry
                updated.notes = "Notes for entry \(index), version \(version + 1)"
                try database.update(updated, at: Date().addingTimeInterval(Double(version + 1)))
                entry = updated
            }
        }
        let settings = EncryptionSettings(
            cipher: .aes256,
            keyDerivation: .argon2id(iterations: 2, memoryBytes: memory << 20, parallelism: 2)
        )
        let data = try await KDBXCodec().encode(
            database,
            settings: settings,
            key: CompositeKey(password: SecretString(password)),
            context: nil
        )
        try data.write(to: URL(fileURLWithPath: path))
        print("Wrote \(entries) entries (\(data.count / 1024) KiB) to \(path)")
    }
}

/// Unlocks a database, builds the search index and runs a few searches:
/// the work the app does when the user opens a database.
struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Unlock a database, index it and search it, traced.")

    @Argument(help: "Path to a .kdbx file.") var path: String
    @Option(help: "Password.") var password = "benchmark"
    @Option(help: "Key file path.") var keyFile: String?
    @Option(help: "How many times to open the database.") var iterations = 1
    @OptionGroup var traceOptions: TraceOptions

    func run() async throws {
        let recorder = traceOptions.start()
        let key = CompositeKey(
            password: SecretString(password),
            keyFileData: try keyFile.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        )
        var entryCount = 0
        for _ in 0..<iterations {
            let decoded = try await Trace.span(.unlockTotal) {
                try await KDBXCodec().decode(
                    Data(contentsOf: URL(fileURLWithPath: path)),
                    key: key,
                    memoryLimit: nil
                )
            }
            let index = SearchIndex(decoded.database)
            for query in ["entry", "user12", "site4", "notes version"] {
                _ = index.search(query, limit: 50)
            }
            entryCount = index.count
        }
        print("Opened \(path): \(entryCount) entries")
        try traceOptions.finish(recorder)
    }
}

/// Merges two databases and saves the result.
struct MergeFiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge",
        abstract: "Merge two databases (same password) and report what changed."
    )

    @Argument(help: "Local database.") var local: String
    @Argument(help: "Remote database.") var remote: String
    @Option(help: "Write the merged database here.") var output: String?
    @Option(help: "Password for both.") var password = "benchmark"
    @OptionGroup var traceOptions: TraceOptions

    func run() async throws {
        let recorder = traceOptions.start()
        let codec = KDBXCodec()
        let key = CompositeKey(password: SecretString(password))
        let localDecoded = try await codec.decode(
            Data(contentsOf: URL(fileURLWithPath: local)),
            key: key,
            memoryLimit: nil
        )
        let remoteDecoded = try await codec.decode(
            Data(contentsOf: URL(fileURLWithPath: remote)),
            key: key,
            memoryLimit: nil
        )
        let result = Merger.merge(local: localDecoded.database, remote: remoteDecoded.database)
        print("\(result.report.changes.count) changes, \(result.report.conflicts.count) conflicts")
        if let output {
            let data = try await Trace.span(.saveEncrypt) {
                try await codec.encode(
                    result.merged,
                    settings: localDecoded.settings,
                    key: key,
                    context: localDecoded.context
                )
            }
            try data.write(to: URL(fileURLWithPath: output))
            print("Merged database written to \(output)")
        }
        try traceOptions.finish(recorder)
    }
}
