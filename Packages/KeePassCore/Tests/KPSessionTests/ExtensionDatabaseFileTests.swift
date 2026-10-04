import Foundation
import Testing

@testable import KPModel
@testable import KPSession

@MainActor
struct ExtensionDatabaseFileTests {
    let directory: URL
    let codec = InMemoryCodec()
    let key = CompositeKey(password: "correct horse")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionFileTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var original: LocalDatabaseFile { LocalDatabaseFile(url: directory.appendingPathComponent("vault.kdbx")) }
    var cache: LocalDatabaseFile { LocalDatabaseFile(url: directory.appendingPathComponent("Cache/vault.kdbx")) }
    var pending: LocalDatabaseFile {
        LocalDatabaseFile(url: directory.appendingPathComponent("Cache/vault.pending.kdbx"))
    }

    /// The original can't be reached, as with another app's File Provider.
    struct UnreachableFile: DatabaseFile {
        var displayName: String { "vault" }
        func read() async throws(FileError) -> (data: Data, version: FileVersion) { throw .accessDenied }
        func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
            throw .accessDenied
        }
    }

    @Test func entriesAddedOfflineReachTheAppByMerging() async throws {
        // The app creates the database and keeps a cached copy.
        let app = DatabaseSession(
            file: CachedDatabaseFile(original: original, cache: cache, fallsBackToCache: false),
            codec: codec
        )
        try await app.create(name: "Personal", key: key)
        let shared = app.newEntry(title: "Shared")
        try app.addEntry(shared)
        try await app.save()

        // AutoFill can't reach the original: it reads the cache and saves
        // a new entry to the pending copy.
        let file = ExtensionDatabaseFile(original: UnreachableFile(), cache: cache, pending: pending)
        let autoFill = DatabaseSession(file: file, codec: codec)
        await autoFill.unlock(with: key)
        #expect(autoFill.database?.entry(withID: shared.id) != nil)
        let added = autoFill.newEntry(title: "From AutoFill")
        try autoFill.addEntry(added)
        try await autoFill.save()
        #expect(file.hasPendingChanges)

        // Meanwhile the app adds an entry of its own.
        let appOnly = app.newEntry(title: "Added in the app")
        try app.addEntry(appOnly)
        try await app.save()

        // The app merges the pending copy: both new entries survive.
        try await app.mergeChanges(from: pending)
        try await app.save()
        #expect(app.database?.entry(withID: added.id)?.title == "From AutoFill")
        #expect(app.database?.entry(withID: appOnly.id) != nil)
        #expect(app.database?.entry(withID: shared.id) != nil)
    }

    @Test func reachableOriginalIsWrittenDirectly() async throws {
        let app = DatabaseSession(file: original, codec: codec)
        try await app.create(name: "Personal", key: key)
        let file = ExtensionDatabaseFile(original: original, cache: cache, pending: pending)
        let autoFill = DatabaseSession(file: file, codec: codec)
        await autoFill.unlock(with: key)
        try autoFill.addEntry(autoFill.newEntry(title: "Direct"))
        try await autoFill.save()
        #expect(!file.hasPendingChanges)

        let reopened = DatabaseSession(file: original, codec: codec)
        await reopened.unlock(with: key)
        #expect(reopened.database?.root.allEntries.map(\.title) == ["Direct"])
    }
}
