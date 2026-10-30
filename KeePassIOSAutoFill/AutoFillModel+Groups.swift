import Foundation
import KPAppState
import KPModel
import KPSession

/// Where entries created in AutoFill go: every group by path, starting on
/// the one used last time for the same database.
extension AutoFillModel {
    /// A group a new entry can go to, named by its path.
    struct GroupChoice: Identifiable, Hashable {
        let id: UUID
        let path: String
    }

    /// Every group of the open database except the recycle bin, in tree
    /// order, named by path; the top level goes by the database's name.
    var groupChoices: [GroupChoice] {
        guard let database = session?.database else { return [] }
        let top = database.meta.name.isEmpty ? database.root.name : database.meta.name
        return database.activeGroupPaths.map { group in
            GroupChoice(id: group.id, path: group.names.isEmpty ? top : group.names.joined(separator: " / "))
        }
    }

    private static let lastGroupKey = "lastNewEntryGroup"

    /// The group the last entry made here for this database went to, if
    /// it still exists, otherwise the top level.
    var defaultGroupID: UUID? {
        guard let database = session?.database, let databaseID = selected?.id else { return nil }
        let saved = UserDefaults.standard.dictionary(forKey: Self.lastGroupKey)?[databaseID.uuidString] as? String
        if let id = saved.flatMap(UUID.init(uuidString:)), groupChoices.contains(where: { $0.id == id }) {
            return id
        }
        return database.root.id
    }

    /// Remembers the group a new entry went to, as the next default.
    func rememberGroup(_ groupID: UUID) {
        guard let databaseID = selected?.id else { return }
        var saved = UserDefaults.standard.dictionary(forKey: Self.lastGroupKey) ?? [:]
        saved[databaseID.uuidString] = groupID.uuidString
        UserDefaults.standard.set(saved, forKey: Self.lastGroupKey)
    }
}
