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

extension EnvironmentValues {
    /// Goes back to a level of the open database: 0 is its top level, 1
    /// a group in it, and so on. Used by the path bar.
    @Entry var goToDatabaseLevel: @MainActor @Sendable (Int) -> Void = { _ in }
}
