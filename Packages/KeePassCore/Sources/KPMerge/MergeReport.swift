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

/// Both sides changed the same fields of an entry since the version they
/// last shared. Unless `MergeChoices` says otherwise the newer side
/// (`winner`) is kept; the other version is in the entry's history.
public struct MergeConflict: Sendable, Equatable, Hashable {
    public let entryID: UUID
    public let title: String
    /// Names of the conflicting fields. A conflicting attachment is listed
    /// as `attachmentField(name)`.
    public let fields: [String]
    public let winner: MergeSide

    private static let attachmentPrefix = "attachment: "

    /// How a conflicting attachment appears in `fields`.
    public static func attachmentField(_ name: String) -> String {
        attachmentPrefix + name
    }

    /// The attachment a name in `fields` stands for; nil for a regular
    /// field.
    public static func attachmentName(ofField field: String) -> String? {
        field.hasPrefix(attachmentPrefix) ? String(field.dropFirst(attachmentPrefix.count)) : nil
    }
}

/// Which side to keep for conflicting fields, when the user decides
/// instead of letting the newer side win. Fields without a choice, and
/// choices for fields that don't conflict, follow the usual rules.
public struct MergeChoices: Sendable, Equatable {
    private var sides: [UUID: [String: MergeSide]] = [:]

    public init() {}

    public var isEmpty: Bool { sides.isEmpty }

    /// The side chosen for a field of an entry, named as in
    /// `MergeConflict.fields`.
    public subscript(entryID: UUID, field: String) -> MergeSide? {
        get { sides[entryID]?[field] }
        set {
            sides[entryID, default: [:]][field] = newValue
            if sides[entryID]?.isEmpty == true {
                sides[entryID] = nil
            }
        }
    }
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
