import Foundation
import Synchronization
import Testing

@testable import KPModel
@testable import KPSession

/// A file that can be taken away, like one deleted in Files or on a
/// drive that went offline.
final class RemovableFile: DatabaseFile {
    let file: LocalDatabaseFile
    private let failure = Mutex<FileError?>(nil)

    init(file: LocalDatabaseFile) {
        self.file = file
    }

    var displayName: String { file.displayName }

    /// Makes every read and write fail with `error`; nil brings the file
    /// back as it was.
    func fail(with error: FileError?) {
        failure.withLock { $0 = error }
    }

    func read() async throws(FileError) -> (data: Data, version: FileVersion) {
        if let error = failure.withLock({ $0 }) { throw error }
        return try await file.read()
    }

    func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        if let error = failure.withLock({ $0 }) { throw error }
        return try await file.write(data, expecting: expected)
    }
}

/// What happens to edits when the database's file can't be reached.
@MainActor
struct UnreachableFileTests {
    let directory: URL
    let codec = InMemoryCodec()
    let key = CompositeKey(password: "correct horse")
    let file: RemovableFile
    let copy: LocalDatabaseFile

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("UnreachableFile-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = RemovableFile(file: LocalDatabaseFile(url: directory.appendingPathComponent("vault.kdbx")))
        copy = LocalDatabaseFile(url: directory.appendingPathComponent("vault.pending.kdbx"))
    }

    func makeSession() -> DatabaseSession {
        DatabaseSession(file: file, codec: codec)
    }

    @Test func aFailedSaveKeepsTheEditsInMemory() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        file.fail(with: .notFound)
        let entry = session.newEntry(title: "Added while the file was gone")
        try session.addEntry(entry)

        await #expect(throws: SessionError.file(.notFound)) { try await session.save() }

        #expect(session.state == .unlocked)
        #expect(session.hasUnsavedChanges)
        #expect(session.database?.entry(withID: entry.id) != nil)

        // Once the file is back, the same session saves as usual.
        file.fail(with: nil)
        try await session.save()
        #expect(!session.hasUnsavedChanges)
    }

    @Test func editsKeptInACopySurviveLockingAndMergeBackIn() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        let saved = session.newEntry(title: "Saved")
        try session.addEntry(saved)
        try await session.save()

        file.fail(with: .ioFailure("offline"))
        let unsaved = session.newEntry(title: "Not saved yet", password: "kept")
        try session.addEntry(unsaved)
        await #expect(throws: SessionError.file(.ioFailure("offline"))) { try await session.save() }

        try await session.writeCopy(to: copy)
        // Writing the copy isn't saving: the file is still behind.
        #expect(session.hasUnsavedChanges)
        session.lock()

        file.fail(with: nil)
        let reopened = makeSession()
        await reopened.unlock(with: key)
        #expect(reopened.database?.entry(withID: unsaved.id) == nil)
        try await reopened.mergeChanges(from: copy)
        try await reopened.save()

        let final = makeSession()
        await final.unlock(with: key)
        #expect(final.database?.entry(withID: unsaved.id)?.password.reveal() == "kept")
        #expect(final.database?.root.allEntries.map(\.title).sorted() == ["Not saved yet", "Saved"])
    }

    @Test func theCopyOpensOnItsOwnWithTheSameKey() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        let entry = session.newEntry(title: "Mail")
        try session.addEntry(entry)
        file.fail(with: .notFound)

        try await session.writeCopy(to: copy)

        // The original never comes back: the copy is a whole database.
        let restored = DatabaseSession(file: copy, codec: codec)
        await restored.unlock(with: key)
        #expect(restored.state == .unlocked)
        #expect(restored.database?.entry(withID: entry.id) != nil)
        #expect(restored.database?.meta.name == "Personal")
    }

    @Test func aLockedSessionHasNothingToCopy() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        session.lock()
        await #expect(throws: SessionError.locked) { try await session.writeCopy(to: copy) }
        #expect(!FileManager.default.fileExists(atPath: copy.url.path))
    }

    @Test func unlockingReportsAMissingFile() async throws {
        let session = makeSession()
        try await session.create(name: "Personal", key: key)
        session.lock()
        file.fail(with: .notFound)

        await session.unlock(with: key)
        #expect(session.state == .failed(.file(.notFound)))
    }

    @Test func onlyFileFailuresCountAsUnreachable() {
        #expect(SessionError.file(.notFound).isUnreachableFile)
        #expect(SessionError.file(.accessDenied).isUnreachableFile)
        #expect(SessionError.file(.ioFailure("offline")).isUnreachableFile)
        #expect(!SessionError.invalidKey.isUnreachableFile)
        #expect(!SessionError.corrupted("bad header").isUnreachableFile)
        #expect(!SessionError.locked.isUnreachableFile)
    }
}
