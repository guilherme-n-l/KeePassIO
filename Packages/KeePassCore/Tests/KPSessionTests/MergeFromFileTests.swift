import Foundation
import Testing

@testable import KPMerge
@testable import KPModel
@testable import KPSession

/// Merging another database file the user picks: preview first, then
/// apply with their choices.
@MainActor
struct MergeFromFileTests {
    let directory: URL
    let codec = InMemoryCodec()
    let key = CompositeKey(password: "correct horse")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MergeFromFile-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> LocalDatabaseFile {
        LocalDatabaseFile(url: directory.appendingPathComponent("\(name).kdbx"))
    }

    /// A clock that moves a minute forward each time it's read, so edits
    /// in different sessions have distinct, ordered times.
    static func tickingClock(startingAt minutes: Int) -> @Sendable () -> Date {
        let ticks = TickCounter(minutes)
        return { Date(timeIntervalSince1970: 1_000_000 + Double(ticks.next()) * 60) }
    }

    struct Pair {
        let phone: DatabaseSession
        let laptop: DatabaseSession
        let entryID: UUID
    }

    /// A database with one entry, and a copy of its file opened and edited
    /// separately: the phone changes the password, then the laptop
    /// changes it too and adds an entry.
    func makePair(laptopKey: CompositeKey? = nil) async throws -> Pair {
        let phone = DatabaseSession(file: file("phone"), codec: codec, clock: Self.tickingClock(startingAt: 0))
        try await phone.create(name: "Personal", key: key)
        let entry = phone.newEntry(title: "Mail", userName: "alice", password: "one")
        try phone.addEntry(entry)
        try await phone.save()

        let laptop = DatabaseSession(file: file("laptop"), codec: codec, clock: Self.tickingClock(startingAt: 100))
        try await laptop.create(name: "Personal", key: laptopKey ?? key)
        try laptop.merge(try #require(phone.database))
        try await laptop.save()

        var onPhone = try #require(phone.database?.entry(withID: entry.id))
        onPhone.password = "from phone"
        try phone.updateEntry(onPhone)
        try await phone.save()

        var onLaptop = try #require(laptop.database?.entry(withID: entry.id))
        onLaptop.password = "from laptop"
        try laptop.updateEntry(onLaptop)
        try laptop.addEntry(laptop.newEntry(title: "Added on laptop"))
        try await laptop.save()
        return Pair(phone: phone, laptop: laptop, entryID: entry.id)
    }

    @Test func previewChangesNothing() async throws {
        let pair = try await makePair()
        let before = pair.phone.database

        let preview = try await pair.phone.previewMerge(from: file("laptop"))

        #expect(pair.phone.database == before)
        #expect(!pair.phone.hasUnsavedChanges)
        #expect(pair.phone.lastMergeReport == nil)
        #expect(preview.sourceName == "laptop")
        #expect(preview.report.conflicts.map(\.fields) == [["Password"]])
        #expect(preview.report.conflicts.first?.winner == .remote)
        #expect(preview.report.changes.contains { $0 == .entryUpdated(id: pair.entryID, title: "Mail") })
        #expect(preview.local.entry(withID: pair.entryID)?.password.reveal() == "from phone")
        #expect(preview.remote.entry(withID: pair.entryID)?.password.reveal() == "from laptop")
    }

    @Test func applyMergesWithTheNewerSideByDefault() async throws {
        let pair = try await makePair()
        let preview = try await pair.phone.previewMerge(from: file("laptop"))

        let report = try pair.phone.applyMerge(preview)

        #expect(report == preview.report)
        #expect(pair.phone.hasUnsavedChanges)
        // The user reviewed the changes before applying: no second review.
        #expect(pair.phone.lastMergeReport == nil)
        let database = try #require(pair.phone.database)
        #expect(database.entry(withID: pair.entryID)?.password.reveal() == "from laptop")
        #expect(database.root.allEntries.map(\.title).sorted() == ["Added on laptop", "Mail"])
        #expect(pair.phone.searchIndex?.search("laptop").count == 1)

        try await pair.phone.save()
        let reopened = DatabaseSession(file: file("phone"), codec: codec)
        await reopened.unlock(with: key)
        #expect(reopened.database?.root.allEntries.count == 2)
    }

    @Test func applyKeepsTheChosenSide() async throws {
        let pair = try await makePair()
        let preview = try await pair.phone.previewMerge(from: file("laptop"))
        var choices = MergeChoices()
        choices[pair.entryID, "Password"] = .local

        try pair.phone.applyMerge(preview, choices: choices)

        let merged = try #require(pair.phone.database?.entry(withID: pair.entryID))
        #expect(merged.password.reveal() == "from phone")
        #expect(merged.history.map { $0.password.reveal() }.contains("from laptop"))
        #expect(pair.phone.database?.root.allEntries.count == 2)
    }

    @Test func aFileWithAnotherKeyNeedsThatKey() async throws {
        let laptopKey = CompositeKey(password: "another key")
        let pair = try await makePair(laptopKey: laptopKey)

        await #expect(throws: SessionError.invalidKey) {
            _ = try await pair.phone.previewMerge(from: file("laptop"))
        }
        let preview = try await pair.phone.previewMerge(from: file("laptop"), key: laptopKey)
        try pair.phone.applyMerge(preview)
        try await pair.phone.save()

        // The merged database keeps its own key.
        let reopened = DatabaseSession(file: file("phone"), codec: codec)
        await reopened.unlock(with: key)
        #expect(reopened.database?.root.allEntries.count == 2)
    }

    @Test func mergingAnIdenticalFileChangesNothing() async throws {
        let pair = try await makePair()
        let preview = try await pair.phone.previewMerge(from: file("phone"))
        #expect(preview.report.isEmpty)
        try pair.phone.applyMerge(preview)
        #expect(!pair.phone.hasUnsavedChanges)
    }

    @Test func missingFilesAndLockedSessionsAreReported() async throws {
        let pair = try await makePair()
        await #expect(throws: SessionError.file(.notFound)) {
            _ = try await pair.phone.previewMerge(from: file("nowhere"))
        }
        let preview = try await pair.phone.previewMerge(from: file("laptop"))
        pair.phone.lock()
        #expect(throws: SessionError.locked) {
            try pair.phone.applyMerge(preview)
        }
        await #expect(throws: SessionError.locked) {
            _ = try await pair.phone.previewMerge(from: file("laptop"))
        }
    }

    @Test func automaticMergeReportsCanBeDismissed() async throws {
        let pair = try await makePair()
        try await pair.phone.mergeChanges(from: file("laptop"))
        #expect(pair.phone.lastMergeReport?.isEmpty == false)
        pair.phone.dismissMergeReport()
        #expect(pair.phone.lastMergeReport == nil)
        #expect(pair.phone.hasUnsavedChanges)
    }
}
