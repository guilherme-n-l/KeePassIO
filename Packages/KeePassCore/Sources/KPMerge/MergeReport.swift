import Foundation
import KPModel

/// Which copy a merged value came from.
public enum MergeSide: Sendable, Equatable, Hashable {
    case local
    case remote
}

/// One change merging made to the local database, for the review screen.
public enum MergeChange: Sendable, Equatable, Hashable {
    case entryAdded(id: UUID, title: String)
    case entryUpdated(id: UUID, title: String)
    case entryMoved(id: UUID, title: String, toGroup: UUID)
    case entryDeleted(id: UUID, title: String)
    /// Deleted on one side but changed on the other after the deletion, so
    /// it was kept.
    case entryRestored(id: UUID, title: String)
    case groupAdded(id: UUID, name: String)
    case groupUpdated(id: UUID, name: String)
    case groupMoved(id: UUID, name: String, toGroup: UUID)
    case groupDeleted(id: UUID, name: String)
    /// A group deleted on the other side was kept because it still has
    /// entries or subgroups after merging.
    case groupKept(id: UUID, name: String)
    case settingsUpdated
}

/// Both sides changed the same fields of an entry since the common base.
/// The newer side won; the other version is in the entry's history and the
/// user can pick per field on the review screen.
public struct MergeConflict: Sendable, Equatable, Hashable {
    public let entryID: UUID
    public let title: String
    public let fields: [String]
    public let winner: MergeSide
}

public struct MergeReport: Sendable, Equatable {
    public var changes: [MergeChange] = []
    public var conflicts: [MergeConflict] = []

    /// True when the merged database is identical in content to local.
    public var isEmpty: Bool { changes.isEmpty && conflicts.isEmpty }
}

public struct MergeResult: Sendable, Equatable {
    public let merged: Database
    public let report: MergeReport
}
