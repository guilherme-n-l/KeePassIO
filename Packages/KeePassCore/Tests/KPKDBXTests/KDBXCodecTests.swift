import Foundation
import KPModel
import KPSession
import Testing

@testable import KPKDBX

/// Cheap key derivation so tests run fast.
let fastSettings = EncryptionSettings(
    cipher: .aes256,
    keyDerivation: .argon2id(iterations: 1, memoryBytes: 1 << 20, parallelism: 1)
)

/// A whole-second date, since KDBX stores times in seconds.
func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

struct KDBXCodecTests {
    let codec = KDBXCodec()
    let key = CompositeKey(password: "correct horse battery staple")

    static func sampleDatabase() throws -> Database {
        var database = Database.empty(name: "Sample")
        database.meta.description = "For tests"
        database.meta.defaultUserName = "alice"
        database.meta.historyMaxItems = 5
        database.meta.settingsChanged = date(1_700_000_000)
        database.meta.customIcons[UUID()] = Data([0x89, 0x50, 0x4e, 0x47])
        database.meta.customData["KeePassIO_Test"] = "1"
        database.root.times = Times(creation: date(1_700_000_000))
        database.deletedObjects[UUID()] = date(1_700_000_500)

        var work = Group(name: "Work", times: Times(creation: date(1_700_000_100)))
        work.notes = "Work accounts"
        work.tags = ["job"]
        work.customData["GroupKey"] = "value"

        var mail = Entry(times: Times(creation: date(1_700_000_200), expiry: date(1_900_000_000), usageCount: 3))
        mail.title = "Mail"
        mail.userName = "alice@example.com"
        mail.password = "pässwörd 🔑"
        mail.url = "https://mail.example.com"
        mail.notes = "Line one\nLine two"
        mail.tags = ["email", "personal"]
        mail.fields["Recovery Code"] = .protected("1234-5678")
        mail.fields["Account"] = .plain("Premium")
        mail.fields["otp"] = .protected("otpauth://totp/Mail:alice?secret=JBSWY3DPEHPK3PXP")
        mail.attachments["hello.txt"] = Data("hello".utf8)
        mail.attachments["same.txt"] = Data("hello".utf8)
        mail.customData["EntryKey"] = "entry value"
        mail.foregroundColor = "#FF0000"
        mail.overrideURL = "cmd://open"
        var older = mail
        older.password = "old password"
        older.times.lastModification = date(1_700_000_150)
        mail.history = [older.historySnapshot]
        work.entries = [mail]
        database.root.groups = [work]
        return database
    }

    @Test func roundTripPreservesEverythingTheModelHolds() async throws {
        let original = try Self.sampleDatabase()
        let data = try await codec.encode(original, settings: fastSettings, key: key, context: nil)
        let decoded = try await codec.decode(data, key: key, memoryLimit: nil)

        #expect(decoded.database.meta.name == "Sample")
        #expect(decoded.database.meta.description == "For tests")
        #expect(decoded.database.meta.customIcons == original.meta.customIcons)
        #expect(decoded.database.deletedObjects == original.deletedObjects)
        #expect(decoded.database.root.groups == original.root.groups)
        #expect(decoded.settings == fastSettings)
    }

    @Test func savingAgainWithContextKeepsContentAndIdenticalAttachmentsShareStorage() async throws {
        let original = try Self.sampleDatabase()
        let first = try await codec.encode(original, settings: fastSettings, key: key, context: nil)
        let decoded = try await codec.decode(first, key: key, memoryLimit: nil)
        let second = try await codec.encode(
            decoded.database,
            settings: decoded.settings,
            key: key,
            context: decoded.context
        )
        let again = try await codec.decode(second, key: key, memoryLimit: nil)

        #expect(again.database.root == decoded.database.root)
        let context = try #require(again.context?.value as? KDBXContext)
        // hello.txt and same.txt have the same bytes; history refers to
        // them too. One pool entry is enough.
        #expect(context.content.innerHeader.binaryContent.count == 1)
    }

    @Test func wrongPasswordIsReportedAsInvalidKey() async throws {
        let data = try await codec.encode(try Self.sampleDatabase(), settings: fastSettings, key: key, context: nil)
        await #expect(throws: CodecError.invalidKey) {
            _ = try await codec.decode(data, key: CompositeKey(password: "wrong"), memoryLimit: nil)
        }
    }

    @Test func keyFileOnlyAndPasswordPlusKeyFile() async throws {
        let keyFile = Data((0..<64).map { UInt8($0) })
        for key in [CompositeKey(keyFileData: keyFile), CompositeKey(password: "pw", keyFileData: keyFile)] {
            let data = try await codec.encode(try Self.sampleDatabase(), settings: fastSettings, key: key, context: nil)
            let decoded = try await codec.decode(data, key: key, memoryLimit: nil)
            #expect(decoded.database.meta.name == "Sample")
            await #expect(throws: CodecError.invalidKey) {
                _ = try await codec.decode(data, key: CompositeKey(password: "pw"), memoryLimit: nil)
            }
        }
    }

    @Test(arguments: [
        EncryptionSettings(
            cipher: .chacha20,
            keyDerivation: .argon2d(iterations: 1, memoryBytes: 1 << 20, parallelism: 1)
        ),
        EncryptionSettings(cipher: .aes256, keyDerivation: .aesKDF(rounds: 1_000), compressed: false),
    ])
    func otherCiphersAndKeyDerivations(settings: EncryptionSettings) async throws {
        let data = try await codec.encode(try Self.sampleDatabase(), settings: settings, key: key, context: nil)
        let decoded = try await codec.decode(data, key: key, memoryLimit: nil)
        #expect(decoded.settings == settings)
        #expect(decoded.database.root.groups.first?.entries.first?.title == "Mail")
    }

    @Test func memoryLimitIsCheckedBeforeDerivingTheKey() async throws {
        let heavy = EncryptionSettings(
            cipher: .aes256,
            keyDerivation: .argon2id(iterations: 1, memoryBytes: 256 << 20, parallelism: 1)
        )
        // The memory check reads only the header, so the expensive key
        // derivation never runs here.
        let small = try await codec.encode(try Self.sampleDatabase(), settings: fastSettings, key: key, context: nil)
        var decoded = try await codec.decode(small, key: key, memoryLimit: 16 << 20)
        #expect(decoded.database.meta.name == "Sample")

        let data = try await codec.encode(decoded.database, settings: heavy, key: key, context: decoded.context)
        await #expect(throws: CodecError.keyDerivationTooExpensive(memoryBytes: 256 << 20)) {
            decoded = try await codec.decode(data, key: key, memoryLimit: 120 << 20)
        }
    }

    @Test func garbageIsReportedAsCorrupted() async {
        await #expect(throws: CodecError.self) {
            _ = try await codec.decode(Data("not a database".utf8), key: key, memoryLimit: nil)
        }
    }
}
