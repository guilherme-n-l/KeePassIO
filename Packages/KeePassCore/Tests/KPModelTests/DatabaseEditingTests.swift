import Foundation
import Testing

@testable import KPModel

struct DatabaseEditingTests {
    static let t0 = Date(timeIntervalSince1970: 1_000_000)
    static let t1 = t0.addingTimeInterval(60)
    static let t2 = t0.addingTimeInterval(120)

    struct Fixture {
        var database: Database
        let email: Group
        var entry: Entry
    }

    func makeFixture() throws -> Fixture {
        var database = Database.empty(name: "Test")
        let email = Group(name: "Email", times: Times(creation: Self.t0))
        var entry = Entry(times: Times(creation: Self.t0))
        entry.title = "Mail"
        entry.userName = "alice"
        entry.password = "hunter2"
        try database.add(email, to: database.root.id)
        try database.add(entry, to: email.id)
        return Fixture(database: database, email: email, entry: entry)
    }

    @Test func addAndFind() throws {
        let fixture = try makeFixture()
        let database = fixture.database
        let email = fixture.email
        let entry = fixture.entry
        #expect(database.entry(withID: entry.id)?.title == "Mail")
        #expect(database.location(ofEntry: entry.id)?.path == [database.root.id, email.id])
        #expect(database.activeEntries.count == 1)
    }

    @Test func updateRecordsHistoryAndTime() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        var entry = fixture.entry
        entry.password = "correct horse"
        try database.update(entry, at: Self.t1)

        let stored = try #require(database.entry(withID: entry.id))
        #expect(stored.password.reveal() == "correct horse")
        #expect(stored.times.lastModification == Self.t1)
        #expect(stored.history.count == 1)
        #expect(stored.history[0].password.reveal() == "hunter2")
        #expect(stored.history[0].history.isEmpty)
    }

    @Test func unchangedUpdateIsANoOp() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let entry = fixture.entry
        try database.update(entry, at: Self.t1)
        let stored = try #require(database.entry(withID: entry.id))
        #expect(stored.history.isEmpty)
        #expect(stored.times.lastModification == Self.t0)
    }

    @Test func historyIsTrimmedToTheLimit() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        var entry = fixture.entry
        database.meta.historyMaxItems = 3
        for index in 0..<10 {
            entry.notes = "version \(index)"
            try database.update(entry, at: Self.t0.addingTimeInterval(Double(index + 1)))
        }
        let stored = try #require(database.entry(withID: entry.id))
        #expect(stored.history.count == 3)
        #expect(stored.history.last?.notes == "version 8")
    }

    @Test func deleteGoesThroughTheRecycleBinThenForever() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let entry = fixture.entry
        try database.deleteEntry(entry.id, at: Self.t1)

        let binID = try #require(database.meta.recycleBinID)
        #expect(database.location(ofEntry: entry.id)?.parentID == binID)
        #expect(database.activeEntries.isEmpty)
        #expect(database.deletedObjects.isEmpty)

        try database.deleteEntry(entry.id, at: Self.t2)
        #expect(database.entry(withID: entry.id) == nil)
        #expect(database.deletedObjects[entry.id] == Self.t2)
    }

    @Test func deleteWithoutRecycleBinIsPermanent() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let entry = fixture.entry
        database.meta.recycleBinEnabled = false
        try database.deleteEntry(entry.id, at: Self.t1)
        #expect(database.entry(withID: entry.id) == nil)
        #expect(database.deletedObjects[entry.id] == Self.t1)
    }

    @Test func moveRecordsPreviousParent() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let email = fixture.email
        let entry = fixture.entry
        let work = Group(name: "Work")
        try database.add(work, to: database.root.id)
        try database.moveEntry(entry.id, to: work.id, at: Self.t1)

        let moved = try #require(database.entry(withID: entry.id))
        #expect(database.location(ofEntry: entry.id)?.parentID == work.id)
        #expect(moved.previousParentGroup == email.id)
        #expect(moved.times.locationChanged == Self.t1)
    }

    @Test func groupMovesAndDeletes() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let email = fixture.email
        let entry = fixture.entry
        let archive = Group(name: "Archive")
        try database.add(archive, to: database.root.id)

        #expect(throws: EditError.cannotMoveGroupIntoItself) {
            try database.moveGroup(archive.id, to: archive.id)
        }
        try database.moveGroup(email.id, to: archive.id, at: Self.t1)
        #expect(database.location(ofGroup: email.id)?.parentID == archive.id)

        database.meta.recycleBinEnabled = false
        try database.deleteGroup(archive.id, at: Self.t2)
        #expect(database.group(withID: email.id) == nil)
        #expect(database.deletedObjects[archive.id] == Self.t2)
        #expect(database.deletedObjects[email.id] == Self.t2)
        #expect(database.deletedObjects[entry.id] == Self.t2)
        #expect(throws: EditError.cannotDeleteRoot) { try database.deleteGroup(database.root.id) }
    }

    @Test func emptyRecycleBin() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let email = fixture.email
        let entry = fixture.entry
        try database.deleteGroup(email.id, at: Self.t1)
        #expect(database.entry(withID: entry.id) != nil)
        database.emptyRecycleBin(at: Self.t2)
        #expect(database.entry(withID: entry.id) == nil)
        #expect(database.deletedObjects[entry.id] == Self.t2)
        #expect(database.recycleBin?.groups.isEmpty == true)
    }

    @Test func renameGroup() throws {
        let fixture = try makeFixture()
        var database = fixture.database
        let email = fixture.email
        var renamed = email
        renamed.name = "Mail"
        try database.updateGroupProperties(renamed, at: Self.t1)
        #expect(database.group(withID: email.id)?.name == "Mail")
        #expect(database.group(withID: email.id)?.times.lastModification == Self.t1)
    }
}

struct SecretStringTests {
    @Test func neverPrintsItsValue() {
        let secret: SecretString = "hunter2"
        #expect("\(secret)" == "<secret>")
        #expect(String(reflecting: secret) == "<secret: 7 bytes>")
        #expect(!String(describing: Mirror(reflecting: secret).children.map(\.value)).contains("hunter2"))
        var dumped = ""
        dump(secret, to: &dumped)
        #expect(!dumped.contains("hunter2"))
        #expect(secret.reveal() == "hunter2")
    }

    @Test func equalityAndUnicode() {
        #expect(SecretString("pässwörd 🔑") == SecretString("pässwörd 🔑"))
        #expect(SecretString("a") != SecretString("b"))
        #expect(SecretString("pässwörd 🔑").reveal() == "pässwörd 🔑")
        #expect(SecretString.empty.isEmpty)
    }
}
