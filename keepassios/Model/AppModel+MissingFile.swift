import Foundation
import KPAppState
import KPPlatform
import KPSession

/// What the app does when a database's file can't be reached: moved,
/// deleted, or on a drive that is offline.
///
///     saving:    file ──fails──► kept copy on this device (complete, encrypted)
///     unlocking: file ──found──► kept copy merged in, then deleted
///                file ──gone───► locate the file, restore the kept copy
///                                to a new place, or remove the database
///
/// The kept copy is the same App Group file AutoFill writes to when it
/// can't reach the original, so one merge on unlock covers both.
extension AppModel {
    func id(of session: DatabaseSession) -> UUID? {
        sessions.first { $0.value === session }?.key
    }

    /// Writes a database's unsaved changes to the kept copy after a save
    /// couldn't reach the file, so locking or quitting doesn't lose them.
    /// Tells the user once, not after every edit. Returns false when the
    /// copy couldn't be written either.
    func keepChanges(of session: DatabaseSession) async -> Bool {
        guard let id = id(of: session), let kept = SharedFiles.pendingChanges(for: id) else { return false }
        do {
            if FileManager.default.fileExists(atPath: kept.url.path) {
                // AutoFill may have left changes there that this session
                // hasn't seen yet: bring them in before replacing the copy.
                try? await session.mergeChanges(from: kept)
            }
            try FileManager.default.createDirectory(
                at: kept.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await session.writeCopy(to: kept)
        } catch {
            return false
        }
        if unreachableDatabases.insert(id).inserted {
            errorMessage = String(
                localized:
                    "The database file can't be reached. It may have been moved or deleted, or its storage is offline. Your changes are kept on this device and are added to the file the next time it opens."
            )
        }
        return true
    }

    /// Whether a database's file is gone: deleted (or in Recently
    /// Deleted), or moved where the app can't follow it.
    func isFileMissing(_ reference: DatabaseReference) -> Bool {
        BookmarkedFile(bookmark: reference.bookmark, displayName: reference.displayName).isMissing
    }

    /// Whether this device has a copy of a database to restore: the
    /// changes kept when a save failed, or the file as last read.
    func hasKeptCopy(of id: UUID) -> Bool {
        keptCopy(of: id) != nil
    }

    /// The most complete copy on this device: kept changes are written
    /// from the whole database, so they come before the last-read file.
    private func keptCopy(of id: UUID) -> LocalDatabaseFile? {
        [SharedFiles.pendingChanges(for: id), SharedFiles.databaseCache(for: id)]
            .compactMap(\.self)
            .first { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// A database file made from the copy kept on this device, for the
    /// user to put back in Files; `relocateDatabase(_:to:)` then points
    /// the database at it.
    func restoredFile(for reference: DatabaseReference) -> URL? {
        guard let kept = keptCopy(of: reference.id) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Restore-\(UUID().uuidString)")
        let url = folder.appendingPathComponent(reference.displayName).appendingPathExtension("kdbx")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: kept.url, to: url)
            return url
        } catch {
            errorMessage = String(localized: "Couldn't restore the copy: \(error.localizedDescription)")
            return nil
        }
    }
}
