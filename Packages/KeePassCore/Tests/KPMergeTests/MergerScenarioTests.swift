import Foundation
import Testing

@testable import KPMerge
@testable import KPModel

/// Hand-written cases for each merge rule.
struct MergerScenarioTests {
    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func time(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    struct Fixture {
        var base: Database
        let groupID: UUID
        let entryID: UUID
    }

    static func fixture() throws -> Fixture {
        var database = Database.empty(name: "Shared")
        database.meta.settingsChanged = t0
        database.root.times = Times(creation: t0)
        let group = Group(name: "Email", times: Times(creation: t0))
        var entry = Entry(times: Times(creation: t0))
        entry.title = "Mail"
        entry.userName = "alice"
        entry.password = "one"
        entry.url = "https://mail.example.com"
        try database.add(group, to: database.root.id)
        try database.add(entry, to: group.id)
        return Fixture(base: database, groupID: group.id, entryID: entry.id)
    }

    @Test func identicalCopiesProduceNoChanges() throws {
        let fixture = try Self.fixture()
        let result = Merger.merge(local: fixture.base, remote: fixture.base, base: fixture.base)
        #expect(result.merged == fixture.base)
        #expect(result.report.isEmpty)
    }

    @Test func newerRemoteEditWinsAndLocalVersionGoesToHistory() throws {
        let fixture = try Self.fixture()
        var local = fixture.base
        var remote = fixture.base
        var localEntry = try #require(local.entry(withID: fixture.entryID))
        localEntry.password = "local"
        try local.update(localEntry, at: Self.time(1))
        var remoteEntry = try #require(remote.entry(withID: fixture.entryID))
        remoteEntry.password = "remote"
        try remote.update(remoteEntry, at: Self.time(2))

        let result = Merger.merge(local: local, remote: remote)
        let merged = try #require(result.merged.entry(withID: fixture.entryID))

        #expect(merged.password.reveal() == "remote")
        #expect(merged.times.lastModification == Self.time(2))
        let historyPasswords = merged.history.map { $0.password.reveal() }
        #expect(historyPasswords.contains("one"))
        #expect(historyPasswords.contains("local"))
        #expect(result.report.changes.contains(.entryUpdated(id: fixture.entryID, title: "Mail")))
    }

    @Test func threeWayMergeKeepsEditsToDifferentFields() throws {
        let fixture = try Self.fixture()
        var local = fixture.base
        var remote = fixture.base
        var localEntry = try #require(local.entry(withID: fixture.entryID))
        localEntry.userName = "alice@example.com"
        try local.update(localEntry, at: Self.time(1))
        var remoteEntry = try #require(remote.entry(withID: fixture.entryID))
        remoteEntry.password = "rotated"
        try remote.update(remoteEntry, at: Self.time(2))

        let result = Merger.merge(local: local, remote: remote, base: fixture.base)
        let merged = try #require(result.merged.entry(withID: fixture.entryID))

        #expect(merged.userName == "alice@example.com")
        #expect(merged.password.reveal() == "rotated")
        #expect(result.report.conflicts.isEmpty)
    }

    @Test func threeWayMergeReportsConflictsOnTheSameField() throws {
        let fixture = try Self.fixture()
        var local = fixture.base
        var remote = fixture.base
        var localEntry = try #require(local.entry(withID: fixture.entryID))
        localEntry.password = "local"
        try local.update(localEntry, at: Self.time(3))
        var remoteEntry = try #require(remote.entry(withID: fixture.entryID))
        remoteEntry.password = "remote"
        try remote.update(remoteEntry, at: Self.time(2))

        let result = Merger.merge(local: local, remote: remote, base: fixture.base)
        let merged = try #require(result.merged.entry(withID: fixture.entryID))

        #expect(merged.password.reveal() == "local")
        #expect(merged.history.contains { $0.password.reveal() == "remote" })
        #expect(
            result.report.conflicts == [
                MergeConflict(entryID: fixture.entryID, title: "Mail", fields: ["Password"], winner: .local)
            ]
        )
    }

    @Test func entriesAddedOnEitherSideAreKept() throws {
        let fixture = try Self.fixture()
        var local = fixture.base
        var remote = fixture.base
        var localNew = Entry(times: Times(creation: Self.time(1)))
        localNew.title = "Local only"
        try local.add(localNew, to: fixture.groupID)
        var remoteNew = Entry(times: Times(creation: Self.time(1)))
        remoteNew.title = "Remote only"
        try remote.add(remoteNew, to: fixture.groupID)

        let result = Merger.merge(local: local, remote: remote, base: fixture.base)
        #expect(result.merged.entry(withID: localNew.id) != nil)
        #expect(result.merged.entry(withID: remoteNew.id) != nil)
        #expect(result.merged.location(ofEntry: remoteNew.id)?.parentID == fixture.groupID)
        #expect(result.report.changes.contains(.entryAdded(id: remoteNew.id, title: "Remote only")))
    }

    @Test func recordedDeletionWinsOverAnOlderVersion() throws {
        let fixture = try Self.fixture()
        var local = fixture.base
        local.meta.recycleBinEnabled = false
        try local.deleteEntry(fixture.entryID, at: Self.time(5))

        let result = Merger.merge(local: fixture.base, remote: local)
        #expect(result.merged.entry(withID: fixture.entryID) == nil)
        #expect(result.merged.deletedObjects[fixture.entryID] == Self.time(5))
        #expect(result.report.changes.contains(.entryDeleted(id: fixture.entryID, title: "Mail")))
    }

    @Test func editAfterDeletionRestoresTheEntry() throws {
        let fixture = try Self.fixture()
        var deleter = fixture.base
        deleter.meta.recycleBinEnabled = false
        try deleter.deleteEntry(fixture.entryID, at: Self.time(5))
        var editor = fixture.base
        var entry = try #require(editor.entry(withID: fixture.entryID))
        entry.notes = "still needed"
        try editor.update(entry, at: Self.time(6))

        let result = Merger.merge(local: deleter, remote: editor)
        #expect(result.merged.entry(withID: fixture.entryID)?.notes == "still needed")
        #expect(result.merged.deletedObjects[fixture.entryID] == nil)
        #expect(result.report.changes.contains(.entryRestored(id: fixture.entryID, title: "Mail")))
    }

    @Test func deletionWithoutRecordIsDetectedFromTheBase() throws {
        let fixture = try Self.fixture()
        var remote = fixture.base
        // A client that removes entries without writing DeletedObjects.
        remote.root.groups[0].entries.removeAll()

        let result = Merger.merge(local: fixture.base, remote: remote, base: fixture.base)
        #expect(result.merged.entry(withID: fixture.entryID) == nil)
    }

    @Test func newerMoveWins() throws {
        let fixture = try Self.fixture()
        var remote = fixture.base
        let work = Group(name: "Work", times: Times(creation: Self.time(1)))
        try remote.add(work, to: remote.root.id)
        try remote.moveEntry(fixture.entryID, to: work.id, at: Self.time(2))

        let result = Merger.merge(local: fixture.base, remote: remote, base: fixture.base)
        #expect(result.merged.location(ofEntry: fixture.entryID)?.parentID == work.id)
        #expect(result.merged.entry(withID: fixture.entryID)?.previousParentGroup == fixture.groupID)
    }

    @Test func deletedGroupIsKeptWhenTheOtherSideAddedToIt() throws {
        let fixture = try Self.fixture()
        var deleter = fixture.base
        deleter.meta.recycleBinEnabled = false
        try deleter.deleteGroup(fixture.groupID, at: Self.time(5))
        var adder = fixture.base
        var newEntry = Entry(times: Times(creation: Self.time(6)))
        newEntry.title = "Added later"
        try adder.add(newEntry, to: fixture.groupID)

        let result = Merger.merge(local: adder, remote: deleter)
        #expect(result.merged.group(withID: fixture.groupID) != nil)
        #expect(result.merged.entry(withID: newEntry.id) != nil)
        #expect(result.merged.entry(withID: fixture.entryID) == nil)
        #expect(result.report.changes.contains(.groupKept(id: fixture.groupID, name: "Email")))
    }

    @Test func newerSettingsWin() throws {
        let fixture = try Self.fixture()
        var remote = fixture.base
        remote.meta.name = "Renamed"
        remote.meta.settingsChanged = Self.time(1)

        let result = Merger.merge(local: fixture.base, remote: remote)
        #expect(result.merged.meta.name == "Renamed")
        #expect(result.report.changes.contains(.settingsUpdated))
    }

    @Test func differentRootUUIDsAreTreatedAsTheSameRoot() throws {
        let fixture = try Self.fixture()
        var remote = fixture.base
        remote.root.id = UUID()
        var extra = Entry(times: Times(creation: Self.time(1)))
        extra.title = "At root"
        try remote.add(extra, to: remote.root.id)

        let result = Merger.merge(local: fixture.base, remote: remote)
        #expect(result.merged.root.id == fixture.base.root.id)
        #expect(result.merged.location(ofEntry: extra.id)?.parentID == fixture.base.root.id)
    }
}
