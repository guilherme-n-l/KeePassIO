import Foundation
import Testing

@testable import KPMerge
@testable import KPModel

/// Randomized checks: two copies are edited independently from a shared
/// base, then merged. Seeds are fixed so failures reproduce.
struct MergerPropertyTests {
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    static let seeds: [UInt64] = Array(1...60)

    static func makeBase(_ random: inout SeededGenerator) throws -> Database {
        var database = Database.empty(name: "Base")
        database.meta.historyMaxItems = -1
        database.meta.historyMaxSize = -1
        database.meta.recycleBinEnabled = false
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        database.meta.settingsChanged = t0
        var groupIDs = [database.root.id]
        for index in 0..<4 {
            let group = Group(name: "Group \(index)", times: Times(creation: t0))
            try database.add(group, to: groupIDs.randomElement(using: &random) ?? database.root.id)
            groupIDs.append(group.id)
        }
        for index in 0..<12 {
            var entry = Entry(times: Times(creation: t0))
            entry.title = "Entry \(index)"
            entry.password = SecretString("password \(index)")
            try database.add(entry, to: groupIDs.randomElement(using: &random) ?? database.root.id)
        }
        return database
    }

    /// Applies a few random edits. `clock` keeps every timestamp unique
    /// across both copies, so "newer" is always well defined.
    static func edit(
        _ database: inout Database,
        side: String,
        clock: inout Double,
        using random: inout SeededGenerator
    ) throws {
        for _ in 0..<Int.random(in: 1...8, using: &random) {
            clock += 1
            let now = Date(timeIntervalSince1970: 1_000_000 + clock)
            let entries = database.root.allEntries
            var groupIDs: [UUID] = []
            database.root.forEachGroup { group, _ in groupIDs.append(group.id) }

            switch Int.random(in: 0..<10, using: &random) {
            case 0..<4:
                guard var entry = entries.randomElement(using: &random) else { continue }
                let field = ["Password", "UserName", "Notes", "URL", "Custom"].randomElement(using: &random) ?? "Notes"
                entry.fields[field] = .plain("\(side) edit \(clock)")
                try database.update(entry, at: now)
            case 4..<6:
                var entry = Entry(times: Times(creation: now))
                entry.title = "\(side) new \(clock)"
                try database.add(entry, to: groupIDs.randomElement(using: &random) ?? database.root.id)
            case 6..<8:
                guard let entry = entries.randomElement(using: &random),
                    let target = groupIDs.randomElement(using: &random)
                else { continue }
                try database.moveEntry(entry.id, to: target, at: now)
            default:
                guard let entry = entries.randomElement(using: &random) else { continue }
                try database.deleteEntry(entry.id, at: now)
            }
        }
    }

    struct Scenario {
        let base: Database
        let local: Database
        let remote: Database
    }

    static func scenario(seed: UInt64) throws -> Scenario {
        var random = SeededGenerator(state: seed)
        let base = try makeBase(&random)
        var local = base
        var remote = base
        var clock = 0.0
        try edit(&local, side: "local", clock: &clock, using: &random)
        try edit(&remote, side: "remote", clock: &clock, using: &random)
        return Scenario(base: base, local: local, remote: remote)
    }

    /// Every version of an entry that exists on either side ends up as the
    /// merged entry's current content or in its history, unless the entry
    /// was deleted.
    @Test(arguments: seeds)
    func nothingIsLost(seed: UInt64) throws {
        let scenario = try Self.scenario(seed: seed)
        for base in [nil, scenario.base] as [Database?] {
            let merged = Merger.merge(local: scenario.local, remote: scenario.remote, base: base).merged
            for side in [scenario.local, scenario.remote] {
                for entry in side.root.allEntries {
                    guard let result = merged.entry(withID: entry.id) else {
                        #expect(merged.deletedObjects[entry.id] != nil, "entry vanished without a deletion record")
                        continue
                    }
                    let versions = [result] + result.history
                    for version in [entry] + entry.history {
                        let found = versions.contains { $0.hasSameContent(as: version) }
                        #expect(found, "a version of \(entry.title) was lost")
                    }
                }
            }
        }
    }

    @Test(arguments: seeds)
    func mergingIsIdempotent(seed: UInt64) throws {
        let scenario = try Self.scenario(seed: seed)
        let once = Merger.merge(local: scenario.local, remote: scenario.remote, base: scenario.base).merged
        let twice = Merger.merge(local: once, remote: scenario.remote, base: scenario.base).merged
        #expect(twice == once)
        let withItself = Merger.merge(local: once, remote: once, base: once)
        #expect(withItself.merged == once)
        #expect(withItself.report.isEmpty)
    }

    /// Swapping local and remote gives the same entries with the same
    /// current content.
    @Test(arguments: seeds)
    func orderDoesNotChangeTheContent(seed: UInt64) throws {
        let scenario = try Self.scenario(seed: seed)
        for base in [nil, scenario.base] as [Database?] {
            let forward = Merger.merge(local: scenario.local, remote: scenario.remote, base: base).merged
            let backward = Merger.merge(local: scenario.remote, remote: scenario.local, base: base).merged
            let forwardEntries = Dictionary(uniqueKeysWithValues: forward.root.allEntries.map { ($0.id, $0) })
            let backwardEntries = Dictionary(uniqueKeysWithValues: backward.root.allEntries.map { ($0.id, $0) })
            #expect(Set(forwardEntries.keys) == Set(backwardEntries.keys))
            for (id, entry) in forwardEntries {
                let other = try #require(backwardEntries[id])
                #expect(entry.hasSameContent(as: other))
                #expect(forward.location(ofEntry: id)?.parentID == backward.location(ofEntry: id)?.parentID)
            }
        }
    }

    @Test(arguments: seeds)
    func treeStaysWellFormed(seed: UInt64) throws {
        let scenario = try Self.scenario(seed: seed)
        let merged = Merger.merge(local: scenario.local, remote: scenario.remote, base: scenario.base).merged
        var seen = Set<UUID>()
        merged.root.forEachGroup { group, _ in
            #expect(seen.insert(group.id).inserted, "group appears twice")
            for entry in group.entries {
                #expect(seen.insert(entry.id).inserted, "entry appears twice")
                #expect(merged.deletedObjects[entry.id] == nil, "live entry is also marked deleted")
            }
        }
    }
}
