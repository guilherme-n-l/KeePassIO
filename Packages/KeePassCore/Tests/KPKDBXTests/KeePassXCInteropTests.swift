import Foundation
import KPModel
import KPOTP
import KPSession
import Testing

@testable import KPKDBX

/// End-to-end checks against the real KeePassXC command-line tool: files
/// we write must open in KeePassXC, changes KeePassXC makes must come back
/// intact, and timestamps must agree. Skipped when keepassxc-cli isn't
/// installed; CI installs it.
@Suite(.enabled(if: KeePassXC.path != nil, "keepassxc-cli is not installed"))
struct KeePassXCInteropTests {
    let codec = KDBXCodec()
    let directory: URL
    let password = "interop password"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("KPKDBXInterop-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func keePassXCReadsOurFileAndWeReadItsChanges() async throws {
        let file = directory.appendingPathComponent("ours.kdbx")
        let key = CompositeKey(password: SecretString(password))
        var database = try KDBXCodecTests.sampleDatabase()
        // A real "now", so the timestamp check below is meaningful.
        let now = Date()
        database.root.groups[0].entries[0].times.lastModification = now
        try await codec.encode(database, settings: fastSettings, key: key, context: nil).write(to: file)

        // KeePassXC sees our values.
        let shown = try KeePassXC.run(
            ["show", "-s", "-a", "Password", "-a", "URL", file.path, "Work/Mail"],
            input: password
        )
        #expect(shown == "pässwörd 🔑\nhttps://mail.example.com")
        let totp = try KeePassXC.run(["show", "--totp", file.path, "Work/Mail"], input: password)
        let otp = try OTP(uri: "otpauth://totp/Mail:alice?secret=JBSWY3DPEHPK3PXP")
        #expect([otp.code(at: Date()), otp.code(at: Date().addingTimeInterval(-30))].contains(totp))

        // KeePassXC adds an entry and saves the file.
        _ = try KeePassXC.run(
            ["add", "-u", "bob", "-p", "--url", "https://bank.example", file.path, "Work/Bank"],
            input: "\(password)\nbank secret"
        )

        let decoded = try await codec.decode(Data(contentsOf: file), key: key, memoryLimit: nil)
        let work = try #require(decoded.database.root.groups.first { $0.name == "Work" })
        let bank = try #require(work.entries.first { $0.title == "Bank" })
        #expect(bank.userName == "bob")
        #expect(bank.password.reveal() == "bank secret")
        let mail = try #require(work.entries.first { $0.title == "Mail" })
        #expect(mail.password.reveal() == "pässwörd 🔑")
        #expect(mail.fields["Recovery Code"] == .protected("1234-5678"))
        #expect(mail.attachments["hello.txt"] == Data("hello".utf8))
        #expect(mail.history.count == 1)

        // Timestamps agree with KeePassXC's clock (a two-day epoch error
        // would show here).
        #expect(abs(bank.times.creation.timeIntervalSinceNow) < 120)
        #expect(abs(mail.times.lastModification.timeIntervalSince(now)) < 1)
    }

    @Test func keyFileDatabasesInteroperate() async throws {
        let file = directory.appendingPathComponent("keyfile.kdbx")
        let keyFileURL = directory.appendingPathComponent("vault.key")
        let keyFile = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        try keyFile.write(to: keyFileURL)
        let key = CompositeKey(password: SecretString(password), keyFileData: keyFile)
        try await codec.encode(try KDBXCodecTests.sampleDatabase(), settings: fastSettings, key: key, context: nil)
            .write(to: file)

        let shown = try KeePassXC.run(
            ["show", "-s", "-a", "UserName", "-k", keyFileURL.path, file.path, "Work/Mail"],
            input: password
        )
        #expect(shown == "alice@example.com")
    }

    @Test func kdbx3FilesAreRejectedBeforeDecrypting() async throws {
        let file = directory.appendingPathComponent("legacy.kdbx")
        // keepassxc-cli db-create writes KDBX 3.1.
        _ = try KeePassXC.run(["db-create", "-p", file.path], input: "\(password)\n\(password)")

        await #expect(throws: CodecError.unsupportedFormat("KDBX 3.1")) {
            _ = try await codec.decode(
                Data(contentsOf: file),
                key: CompositeKey(password: SecretString(password)),
                memoryLimit: nil
            )
        }
    }
}

enum KeePassXC {
    static let path: String? = {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["KEEPASSXC_CLI"], !explicit.isEmpty { return explicit }
        let candidates =
            (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/keepassxc-cli" }
            + ["/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Runs keepassxc-cli with `input` on stdin (one line per prompt) and
    /// returns stdout without the trailing newline.
    static func run(_ arguments: [String], input: String) throws -> String {
        guard let path else { throw Failure(description: "keepassxc-cli not found") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(Data((input + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(
                description:
                    "keepassxc-cli \(arguments.first ?? "") failed: \(String(bytes: errors, encoding: .utf8) ?? "")"
            )
        }
        var text = String(bytes: output, encoding: .utf8) ?? ""
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}
