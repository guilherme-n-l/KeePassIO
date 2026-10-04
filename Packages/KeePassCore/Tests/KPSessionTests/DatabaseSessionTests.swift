import Foundation
import Testing

@testable import KPMerge
@testable import KPModel
@testable import KPSession

@MainActor
struct DatabaseSessionTests {
    let directory: URL
    let codec = InMemoryCodec()
    let key = CompositeKey(password: "correct horse")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SessionTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeSession(_ name: String = "vault") -> DatabaseSession {
        DatabaseSession(file: LocalDatabaseFile(url: directory.appendingPathComponent("\(name).kdbx")), codec: codec)
    }

    @Test func createEditSaveAndReopen() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        #expect(session.state == .unlocked)

        let entry = session.newEntry(title: "Mail", userName: "alice", password: "hunter2")
        try session.addEntry(entry)
        #expect(session.hasUnsavedChanges)
        #expect(session.searchIndex?.search("mail").map(\.entryID) == [entry.id])

        try await session.save()
        #expect(!session.hasUnsavedChanges)

        let reopened = makeSession()
        await reopened.unlock(with: key)
        #expect(reopened.state == .unlocked)
        #expect(reopened.database?.entry(withID: entry.id)?.password.reveal() == "hunter2")
        #expect(reopened.database?.meta.name == "Personal")
    }

    @Test func customIconsAreSharedBetweenEntries() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        let first = session.newEntry(title: "Mail")
        let second = session.newEntry(title: "Calendar")
        try session.addEntry(first)
        try session.addEntry(second)
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        try session.setCustomIcon(png, forEntry: first.id)
        try session.setCustomIcon(png, forEntry: second.id)

        let database = try #require(session.database)
        #expect(database.meta.customIcons.count == 1)
        let iconID = try #require(database.entry(withID: first.id)?.customIconID)
        #expect(database.entry(withID: second.id)?.customIconID == iconID)
        #expect(database.meta.customIcons[iconID] == png)
        #expect(session.hasUnsavedChanges)
    }

    @Test func wrongKeyFails() async throws {
        try await makeSession().create(name: "Personal", key: key)
        let session = makeSession()
        await session.unlock(with: CompositeKey(password: "wrong"))
        #expect(session.state == .failed(.invalidKey))
        #expect(session.database == nil)
    }

    @Test func missingFileFails() async {
        let session = makeSession("missing")
        await session.unlock(with: key)
        #expect(session.state == .failed(.file(.notFound)))
    }

    @Test func emptyKeyIsRejected() async {
        await #expect(throws: SessionError.emptyKey) {
            try await makeSession().create(name: "x", key: CompositeKey())
        }
    }

    @Test func memoryLimitBlocksExpensiveKeyDerivation() async throws {
        try await makeSession().create(name: "Personal", key: key)
        let session = DatabaseSession(
            file: LocalDatabaseFile(url: directory.appendingPathComponent("vault.kdbx")),
            codec: codec,
            memoryLimit: 16 << 20
        )
        await session.unlock(with: key)
        #expect(session.state == .failed(.keyDerivationTooExpensive(memoryBytes: 64 << 20)))
    }

    @Test func lockForgetsEverything() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        try session.addEntry(session.newEntry(title: "Mail"))
        session.lock()
        #expect(session.state == .locked)
        #expect(session.database == nil)
        #expect(session.searchIndex == nil)
        #expect(throws: SessionError.locked) { try session.addEntry(Entry()) }
        await #expect(throws: SessionError.locked) { try await session.save() }
    }

    @Test func saveMergesChangesMadeElsewhere() async throws {
        let creator = makeSession()
        try await creator.create(name: "Shared", key: key)
        let shared = creator.newEntry(title: "Shared", password: "one")
        try creator.addEntry(shared)
        try await creator.save()

        // Two sessions open the same file, like the app and an extension.
        let app = makeSession()
        await app.unlock(with: key)
        let other = makeSession()
        await other.unlock(with: key)

        let fromOther = other.newEntry(title: "Added by extension")
        try other.addEntry(fromOther)
        try await other.save()

        let fromApp = app.newEntry(title: "Added in app")
        try app.addEntry(fromApp)
        try await app.save()

        let added = MergeChange.entryAdded(id: fromOther.id, title: "Added by extension")
        #expect(app.lastMergeReport?.changes.contains(added) == true)
        let final = makeSession()
        await final.unlock(with: key)
        let titles = Set(final.database?.root.allEntries.map(\.title) ?? [])
        #expect(titles == ["Shared", "Added by extension", "Added in app"])
    }

    @Test func mergeAnotherCopy() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        var copy = try #require(session.database)
        var entry = Entry(times: Times(creation: Date().addingTimeInterval(10)))
        entry.title = "From working copy"
        try copy.add(entry, to: copy.root.id)

        try session.merge(copy)
        #expect(session.database?.entry(withID: entry.id) != nil)
        #expect(session.hasUnsavedChanges)
    }
}

struct AutoLockPolicyTests {
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func locksAfterIdleTimeout() {
        let policy = AutoLockPolicy(timeout: 60)
        #expect(!policy.shouldLock(lastActivity: now.addingTimeInterval(-59), backgroundedAt: nil, now: now))
        #expect(policy.shouldLock(lastActivity: now.addingTimeInterval(-60), backgroundedAt: nil, now: now))
    }

    @Test func locksAfterBackgroundTimeout() {
        let policy = AutoLockPolicy(timeout: 60)
        #expect(!policy.shouldLock(lastActivity: now, backgroundedAt: now.addingTimeInterval(-10), now: now))
        #expect(policy.shouldLock(lastActivity: now, backgroundedAt: now.addingTimeInterval(-61), now: now))
    }

    @Test func zeroTimeoutLocksOnBackgroundOnly() {
        let policy = AutoLockPolicy(timeout: 0)
        #expect(!policy.shouldLock(lastActivity: .distantPast, backgroundedAt: nil, now: now))
        #expect(policy.shouldLock(lastActivity: now, backgroundedAt: now, now: now))
    }
}

struct LocalDatabaseFileTests {
    @Test func detectsSameSizeChangesMadeImmediately() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalFile-\(UUID()).kdbx")
        let file = LocalDatabaseFile(url: url)
        let first = try await file.write(Data("version-a".utf8), expecting: nil)

        // Another writer replaces the file right away with content of the
        // same size, so size and (coarse) modification time can't tell.
        try Data("version-b".utf8).write(to: url, options: .atomic)

        await #expect(throws: FileError.self) {
            _ = try await file.write(Data("version-c".utf8), expecting: first)
        }
        #expect(try Data(contentsOf: url) == Data("version-b".utf8))

        let current = try await file.read().version
        _ = try await file.write(Data("version-c".utf8), expecting: current)
        #expect(try Data(contentsOf: url) == Data("version-c".utf8))
    }
}
