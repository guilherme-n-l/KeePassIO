import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Screens inside an unlocked database, pushed onto the library's
/// navigation stack by value so that locking can pop them all at once.
nonisolated enum DatabaseRoute: Hashable {
    case group(database: UUID, group: UUID)
    case entry(database: UUID, entry: UUID)
    case history(database: UUID, entry: UUID)
}

/// An entry or group being dragged to another group.
nonisolated struct DraggedItem: Codable, Hashable, Identifiable, Transferable {
    nonisolated enum Kind: String, Codable {
        case entry
        case group
    }

    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .keepassItem)
    }
}

extension UTType {
    /// Entries and groups dragged within the app; declared in
    /// Config/keepassios-Info.plist.
    nonisolated static let keepassItem = UTType(exportedAs: "dev.guilhermenl.keepassio.item")
}

/// Goes back to a level of the open database: 0 is its top level, 1 a
/// group in it, and so on. Used by the path bar; call it like a function.
///
/// A struct rather than a bare closure so the environment can compare it:
/// SwiftUI can't compare closures and would refresh every reader on each
/// update. All instances compare equal because the one the library sets
/// reads the navigation path when called, so its behavior never changes.
nonisolated struct GoToDatabaseLevelAction: Equatable, Sendable {
    let action: @MainActor @Sendable (Int) -> Void

    @MainActor func callAsFunction(_ level: Int) {
        action(level)
    }

    static func == (_: Self, _: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var goToDatabaseLevel = GoToDatabaseLevelAction { _ in }
}
