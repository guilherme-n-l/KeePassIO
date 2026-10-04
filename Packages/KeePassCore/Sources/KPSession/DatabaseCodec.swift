import Foundation
import KPModel

/// What unlocks a database: a password, a key file, or both.
public struct CompositeKey: Sendable, Equatable {
    public var password: SecretString?
    /// The key file's raw contents. KDBX derives the key from them.
    public var keyFileData: Data?

    public init(password: SecretString? = nil, keyFileData: Data? = nil) {
        self.password = password
        self.keyFileData = keyFileData
    }

    public var isEmpty: Bool { password == nil && keyFileData == nil }
}

/// How a database file is encrypted. Kept from the opened file so saving
/// doesn't silently change the user's settings.
public struct EncryptionSettings: Sendable, Equatable, Hashable {
    public enum Cipher: String, Sendable, CaseIterable {
        case aes256
        case chacha20
    }

    public enum KeyDerivation: Sendable, Equatable, Hashable {
        case argon2id(iterations: UInt64, memoryBytes: UInt64, parallelism: UInt32)
        case argon2d(iterations: UInt64, memoryBytes: UInt64, parallelism: UInt32)
        case aesKDF(rounds: UInt64)

        /// Memory the key derivation needs, used to decide whether an
        /// extension can unlock the database within its memory limit.
        public var memoryBytes: UInt64 {
            switch self {
            case .argon2id(_, let memory, _), .argon2d(_, let memory, _): memory
            case .aesKDF: 0
            }
        }
    }

    public var cipher: Cipher
    public var keyDerivation: KeyDerivation
    public var compressed: Bool

    public init(cipher: Cipher, keyDerivation: KeyDerivation, compressed: Bool = true) {
        self.cipher = cipher
        self.keyDerivation = keyDerivation
        self.compressed = compressed
    }

    /// Defaults for new databases: AES-256 with Argon2id, 64 MiB, 2
    /// iterations, which unlocks in well under a second on recent iPhones
    /// and fits within the AutoFill extension's memory.
    public static let recommended = EncryptionSettings(
        cipher: .aes256,
        keyDerivation: .argon2id(iterations: 2, memoryBytes: 64 << 20, parallelism: 2)
    )
}

/// A decoded file: the content plus the settings needed to write it back.
public struct DecodedDatabase: Sendable, Equatable {
    public var database: Database
    public var settings: EncryptionSettings

    public init(database: Database, settings: EncryptionSettings) {
        self.database = database
        self.settings = settings
    }
}

public enum CodecError: Error, Equatable, Sendable {
    /// The key is wrong (or the file was tampered with).
    case invalidKey
    /// KDBX 3.1, KDB 1.x or a cipher this app doesn't support.
    case unsupportedFormat(String)
    case corrupted(String)
    /// Key derivation would need more memory than allowed here (used by
    /// extensions to hand off to the app).
    case keyDerivationTooExpensive(memoryBytes: UInt64)
}

/// Reads and writes a file format. The KDBX implementation lives in its
/// own module so this layer stays independent of the parsing library.
public protocol DatabaseCodec: Sendable {
    func decode(_ data: Data, key: CompositeKey, memoryLimit: UInt64?) async throws -> DecodedDatabase
    func encode(_ database: Database, settings: EncryptionSettings, key: CompositeKey) async throws -> Data
}
