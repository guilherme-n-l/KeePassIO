import Foundation
import KPModel
import Synchronization

@testable import KPSession

/// A stand-in for the KDBX codec: "encrypts" by storing the database in
/// memory and writing a token, and checks the key on decode. Lets session
/// logic be tested without a real file format.
final class InMemoryCodec: DatabaseCodec {
    private struct Stored {
        let database: Database
        let settings: EncryptionSettings
        let key: CompositeKey
    }

    private let storage = Mutex<[Data: Stored]>([:])

    func decode(_ data: Data, key: CompositeKey, memoryLimit: UInt64?) async throws -> DecodedDatabase {
        guard let stored = storage.withLock({ $0[data] }) else {
            throw CodecError.corrupted("unknown token")
        }
        let memory = stored.settings.keyDerivation.memoryBytes
        if let memoryLimit, memory > memoryLimit {
            throw CodecError.keyDerivationTooExpensive(memoryBytes: memory)
        }
        guard key == stored.key else { throw CodecError.invalidKey }
        return DecodedDatabase(database: stored.database, settings: stored.settings)
    }

    func encode(_ database: Database, settings: EncryptionSettings, key: CompositeKey) async throws -> Data {
        let token = Data(UUID().uuidString.utf8)
        storage.withLock { $0[token] = Stored(database: database, settings: settings, key: key) }
        return token
    }
}
