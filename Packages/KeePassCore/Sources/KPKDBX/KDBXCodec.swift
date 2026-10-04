import Foundation
import KDBXKit
import KPModel
import KPObservability
import KPSession

/// Reads and writes KDBX 4.x files through the vendored KDBXKit.
///
/// Older formats (KDBX 3.x, KDB) are refused before any key derivation
/// runs, with an error the app turns into conversion instructions.
public struct KDBXCodec: DatabaseCodec {
    /// Upper bounds on key-derivation cost accepted from a file, checked
    /// before deriving, so a malicious file can't exhaust memory or time.
    public var limits: KDFParameterLimits

    public init(
        limits: KDFParameterLimits = KDFParameterLimits(
            maxArgon2Memory: 1 << 30,
            maxArgon2Iterations: 1_000,
            maxArgon2Parallelism: 64,
            maxAESKDFRounds: 100_000_000
        )
    ) {
        self.limits = limits
    }

    public func decode(_ data: Data, key: CompositeKey, memoryLimit: UInt64?) async throws -> DecodedDatabase {
        let header: Header
        do {
            header = try Trace.span(.kdbxHeader, argument: UInt64(data.count)) {
                try KDBXReader.parseHeader(data)
            }
        } catch {
            throw Self.codecError(for: error)
        }
        guard !header.formatVersion.isLegacy3x else {
            throw CodecError.unsupportedFormat("KDBX \(header.formatVersion)")
        }
        let settings = try EncryptionSettings(header: header)
        if let memoryLimit, settings.keyDerivation.memoryBytes > memoryLimit {
            throw CodecError.keyDerivationTooExpensive(memoryBytes: settings.keyDerivation.memoryBytes)
        }

        let unlock = try Self.unlockData(for: key)
        let content: KDBXContent
        do {
            content = try Trace.span(.kdbxDecrypt, argument: UInt64(data.count)) {
                try KDBXReader.parse(data, unlockData: unlock, kdfLimits: limits)
            }
        } catch {
            throw Self.codecError(for: error)
        }
        let database = Trace.span(.kdbxXML) { KDBXMapping.model(from: content) }
        return DecodedDatabase(
            database: database,
            settings: settings,
            context: FormatContext(KDBXContext(content: content))
        )
    }

    public func encode(
        _ database: Database,
        settings: EncryptionSettings,
        key: CompositeKey,
        context: FormatContext?
    ) async throws -> Data {
        let previous = (context?.value as? KDBXContext)?.content
        var content =
            previous
            ?? KDBXContent.makeEmpty(
                databaseName: database.meta.name,
                kdf: settings.kdfParameters(),
                generator: "KeePassIOS"
            )
        if previous == nil || EncryptionSettings(maybeHeader: content.header) != settings {
            content.header = Header(
                formatVersion: .v4_1,
                encryptionAlgorithm: settings.cipher == .chacha20 ? .ChaCha20 : .AES256CBC,
                compressionAlgorithm: settings.compressed ? .gzip : .none,
                masterSalt: Self.randomBytes(32),
                encryptionNonce: Self.randomBytes(settings.cipher == .chacha20 ? 12 : 16),
                kdfParameters: settings.kdfParameters(),
                publicCustomData: content.header.publicCustomData
            )
        }
        let mapped = KDBXMapping.kdbx(from: database, previous: content.database)
        content.database = mapped.database
        content.innerHeader.binaryContent = mapped.binaries
        content.database.meta.generator = "KeePassIOS"

        let unlock = try Self.unlockData(for: key)
        let output = OutputStream(toMemory: ())
        output.open()
        defer { output.close() }
        do {
            try KDBXWriter(to: output).write(content, unlockData: unlock)
        } catch {
            throw CodecError.corrupted("write failed: \(error)")
        }
        guard let data = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw CodecError.corrupted("write produced no data")
        }
        return data
    }

    // MARK: Helpers

    static func unlockData(for key: CompositeKey) throws -> UnlockData {
        do {
            switch (key.password, key.keyFileData) {
            case (let password?, let keyFile):
                return try UnlockData(masterPassword: password.reveal(), keyFile: keyFile)
            case (nil, let keyFile?):
                return try UnlockData(keyFile: keyFile)
            case (nil, nil):
                throw CodecError.invalidKey
            }
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.corrupted("unreadable key file")
        }
    }

    static func codecError(for error: any Error) -> CodecError {
        guard let error = error as? KDBXReader.Error else {
            return .corrupted(String(describing: error))
        }
        switch error {
        case .wrongCredentials:
            return .invalidKey
        case .unsupportedFormatVersion(let major, let minor):
            return .unsupportedFormat("KDBX \(major).\(minor)")
        case .unsupportedEncryption, .unsupportedKDF, .unsupportedCompression:
            return .unsupportedFormat("cipher or key derivation")
        case .kdfParametersOutOfRange(let reason):
            return .corrupted("key derivation settings out of range: \(reason)")
        default:
            return .corrupted(String(describing: error))
        }
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// KDBXKit's view of the last file read, so saving keeps metadata
/// KPModel doesn't cover (memory protection, colors, header data, ...).
struct KDBXContext: Sendable {
    let content: KDBXContent
}

extension EncryptionSettings {
    init(header: Header) throws {
        let cipher: Cipher = header.encryptionAlgorithm == .ChaCha20 ? .chacha20 : .aes256
        let derivation: KeyDerivation
        switch header.kdfParameters {
        case .argon2id(let argon, _):
            derivation = .argon2id(
                iterations: argon.iterations,
                memoryBytes: argon.memory,
                parallelism: argon.parallelism
            )
        case .argon2d(let argon, _):
            derivation = .argon2d(
                iterations: argon.iterations,
                memoryBytes: argon.memory,
                parallelism: argon.parallelism
            )
        case .aes(let aes, _):
            derivation = .aesKDF(rounds: aes.rounds)
        case .unknown:
            throw CodecError.unsupportedFormat("key derivation")
        }
        self.init(cipher: cipher, keyDerivation: derivation, compressed: header.compressionAlgorithm != .none)
    }

    init?(maybeHeader header: Header) {
        guard let settings = try? EncryptionSettings(header: header) else { return nil }
        self = settings
    }

    func kdfParameters() -> KDFParameters {
        let salt = KDBXCodec.randomBytes(32)
        switch keyDerivation {
        case .argon2id(let iterations, let memory, let parallelism):
            return .argon2id(
                .init(version: .v1_3, salt: salt, iterations: iterations, memory: memory, parallelism: parallelism),
                additional: [:]
            )
        case .argon2d(let iterations, let memory, let parallelism):
            return .argon2d(
                .init(version: .v1_3, salt: salt, iterations: iterations, memory: memory, parallelism: parallelism),
                additional: [:]
            )
        case .aesKDF(let rounds):
            return .aes(.init(salt: salt, rounds: rounds), additional: [:])
        }
    }
}
