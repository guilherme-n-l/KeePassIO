import Foundation
import Testing

@testable import KPMerge
@testable import KPModel

/// Merging two files with no saved base: the common version comes from
/// the entries' histories, and the user can choose the side of each
/// conflicting field.
struct MergerConflictTests {
    typealias Scenarios = MergerScenarioTests

    struct Copies {
        var local: Database
        var remote: Database
        let entryID: UUID
    }

    /// Two copies of the fixture whose entry was edited on both sides:
    /// locally first, then remotely.
    static func copies(
        local localEdit: (inout Entry) -> Void,
        remote remoteEdit: (inout Entry) -> Void
    ) throws -> Copies {
        let fixture = try Scenarios.fixture()
        var copies = Copies(local: fixture.base, remote: fixture.base, entryID: fixture.entryID)
        var localEntry = try #require(copies.local.entry(withID: fixture.entryID))
        localEdit(&localEntry)
        try copies.local.update(localEntry, at: Scenarios.time(1))
        var remoteEntry = try #require(copies.remote.entry(withID: fixture.entryID))
        remoteEdit(&remoteEntry)
        try copies.remote.update(remoteEntry, at: Scenarios.time(2))
        return copies
    }

    @Test func sharedHistoryStandsInForTheBase() throws {
        let copies = try Self.copies(
            local: { $0.userName = "alice@example.com" },
            remote: { $0.password = "rotated" }
        )

        let result = Merger.merge(local: copies.local, remote: copies.remote)
        let merged = try #require(result.merged.entry(withID: copies.entryID))

        #expect(merged.userName == "alice@example.com")
        #expect(merged.password.reveal() == "rotated")
        #expect(result.report.conflicts.isEmpty)
        #expect(result.report.changes == [.entryUpdated(id: copies.entryID, title: "Mail")])
    }

    @Test func fieldsEditedOnBothSidesConflictAndTheNewerSideWins() throws {
        let copies = try Self.copies(
            local: {
                $0.password = "local"
                $0.url = "https://local.example.com"
            },
            remote: {
                $0.password = "remote"
                $0.notes = "Only changed remotely"
            }
        )

        let result = Merger.merge(local: copies.local, remote: copies.remote)
        let merged = try #require(result.merged.entry(withID: copies.entryID))

        #expect(merged.password.reveal() == "remote")
        #expect(merged.url == "https://local.example.com")
        #expect(merged.notes == "Only changed remotely")
        let conflict = try #require(result.report.conflicts.first)
        #expect(result.report.conflicts.count == 1)
        #expect(conflict.entryID == copies.entryID)
        #expect(conflict.fields == ["Password"])
        #expect(conflict.winner == .remote)
    }

    @Test func aChoiceKeepsTheOlderSideAndNothingIsLost() throws {
        let copies = try Self.copies(
            local: {
                $0.password = "local"
                $0.userName = "local user"
            },
            remote: {
                $0.password = "remote"
                $0.userName = "remote user"
            }
        )
        var choices = MergeChoices()
        choices[copies.entryID, "Password"] = .local

        let result = Merger.merge(local: copies.local, remote: copies.remote, choices: choices)
        let merged = try #require(result.merged.entry(withID: copies.entryID))

        #expect(merged.password.reveal() == "local")
        #expect(merged.userName == "remote user")
        #expect(result.report.conflicts.first?.fields == ["Password", "UserName"])
        let history = merged.history.map { "\($0.userName)/\($0.password.reveal())" }
        #expect(history == ["alice/one", "local user/local", "remote user/remote"])

        // Merging the same file again changes nothing: the choice sticks.
        let again = Merger.merge(local: result.merged, remote: copies.remote)
        #expect(again.merged == result.merged)
        #expect(again.report.isEmpty)
    }

    @Test func attachmentsConflictAndCanBeChosen() throws {
        let copies = try Self.copies(
            local: { $0.attachments["key.txt"] = Data("local".utf8) },
            remote: { $0.attachments["key.txt"] = Data("remote".utf8) }
        )
        let field = MergeConflict.attachmentField("key.txt")
        #expect(MergeConflict.attachmentName(ofField: field) == "key.txt")
        #expect(MergeConflict.attachmentName(ofField: "Password") == nil)

        let byDefault = Merger.merge(local: copies.local, remote: copies.remote)
        #expect(byDefault.report.conflicts.first?.fields == [field])
        #expect(byDefault.merged.entry(withID: copies.entryID)?.attachments["key.txt"] == Data("remote".utf8))

        var choices = MergeChoices()
        choices[copies.entryID, field] = .local
        let chosen = Merger.merge(local: copies.local, remote: copies.remote, choices: choices)
        #expect(chosen.merged.entry(withID: copies.entryID)?.attachments["key.txt"] == Data("local".utf8))
    }

    @Test func choicesForFieldsThatDoNotConflictAreIgnored() throws {
        let copies = try Self.copies(
            local: { $0.userName = "alice@example.com" },
            remote: { $0.password = "rotated" }
        )
        var choices = MergeChoices()
        choices[copies.entryID, "Password"] = .local
        choices[UUID(), "Password"] = .remote

        let result = Merger.merge(local: copies.local, remote: copies.remote, choices: choices)
        #expect(result == Merger.merge(local: copies.local, remote: copies.remote))
        #expect(result.merged.entry(withID: copies.entryID)?.password.reveal() == "rotated")
    }

    @Test func choicesCanBeCleared() {
        let id = UUID()
        var choices = MergeChoices()
        #expect(choices.isEmpty)
        choices[id, "Password"] = .local
        #expect(choices[id, "Password"] == .local)
        #expect(choices[id, "Notes"] == nil)
        choices[id, "Password"] = nil
        #expect(choices.isEmpty)
    }

    @Test func withoutAnySharedVersionTheNewerEntryWins() throws {
        var copies = try Self.copies(local: { $0.password = "local" }, remote: { $0.password = "remote" })
        // History trimmed away on one side: nothing left in common.
        var remoteEntry = try #require(copies.remote.entry(withID: copies.entryID))
        remoteEntry.history = []
        let groupID = try #require(copies.remote.location(ofEntry: copies.entryID)?.parentID)
        copies.remote.root.modifyGroup(groupID) { $0.entries = [remoteEntry] }

        let result = Merger.merge(local: copies.local, remote: copies.remote)
        let merged = try #require(result.merged.entry(withID: copies.entryID))
        #expect(merged.password.reveal() == "remote")
        #expect(result.report.conflicts.isEmpty)
        #expect(merged.history.map { $0.password.reveal() } == ["one", "local"])
    }

    /// Whatever sides are chosen, every version of every entry survives
    /// as the current content or in history.
    @Test(arguments: MergerPropertyTests.seeds)
    func choicesNeverLoseAVersion(seed: UInt64) throws {
        let scenario = try MergerPropertyTests.scenario(seed: seed)
        var random = MergerPropertyTests.SeededGenerator(state: seed)
        var choices = MergeChoices()
        for conflict in Merger.merge(local: scenario.local, remote: scenario.remote).report.conflicts {
            for field in conflict.fields {
                choices[conflict.entryID, field] = Bool.random(using: &random) ? .local : .remote
            }
        }

        let merged = Merger.merge(local: scenario.local, remote: scenario.remote, choices: choices).merged
        for side in [scenario.local, scenario.remote] {
            for entry in side.root.allEntries {
                guard let result = merged.entry(withID: entry.id) else {
                    #expect(merged.deletedObjects[entry.id] != nil, "entry vanished without a deletion record")
                    continue
                }
                let versions = [result] + result.history
                for version in [entry] + entry.history {
                    #expect(
                        versions.contains { $0.hasSameContent(as: version) },
                        "a version of \(entry.title) was lost"
                    )
                }
            }
        }
        let again = Merger.merge(local: merged, remote: scenario.remote)
        #expect(again.merged == merged)
    }
}
