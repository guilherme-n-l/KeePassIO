import Foundation
import KPAppState
import KPModel
import KPPlatform
import KPSession

/// Database files: new databases before they get a place in Files, copies
/// for sharing, AutoFill's pending changes and website icons.
extension AppModel {
    /// Writes a new database to a temporary file; `adopt(_:movedTo:)` takes
    /// it over once the user has moved it to its place in Files.
    func prepareDatabase(name: String, password: String) async -> PendingDatabase? {
        let fileName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Passwords" : name
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent(fileName).appendingPathExtension("kdbx")
        let key = CompositeKey(password: SecretString(password))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let session = DatabaseSession(file: LocalDatabaseFile(url: url), codec: codec)
            try await session.create(name: fileName, key: key, settings: newDatabaseSettings)
            session.lock()
            return PendingDatabase(url: url, key: key)
        } catch {
            errorMessage = String(localized: "Couldn't create the database: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes a new database's temporary file (after moving or cancelling).
    func discard(_ pending: PendingDatabase) {
        try? FileManager.default.removeItem(at: pending.url.deletingLastPathComponent())
    }

    /// A copy of a database's file to hand to the share sheet, named after
    /// the file.
    func shareableCopy(of reference: DatabaseReference) async -> URL? {
        let file = BookmarkedFile(bookmark: reference.bookmark, displayName: reference.displayName)
        do {
            let (data, _) = try await file.read()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(reference.displayName).appendingPathExtension("kdbx")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = String(localized: "Couldn't read the database file to share it.")
            return nil
        }
    }

    /// Downloads website icons for the given entries that have a URL and
    /// no custom icon yet. Returns how many icons were set.
    @discardableResult
    func downloadIcons(for entryIDs: [UUID], in session: DatabaseSession) async -> Int {
        guard settings.mayDownloadFavicons else { return 0 }
        var count = 0
        for id in entryIDs {
            guard let entry = session.database?.entry(withID: id), !entry.url.isEmpty else { continue }
            guard let png = await WebsiteIcon.fetch(for: entry.url) else { continue }
            if (try? session.setCustomIcon(png, forEntry: id)) != nil {
                count += 1
            }
        }
        return count
    }

    /// Locks every open database (saving changes first). Does nothing,
    /// and leaves navigation alone, when none is open.
    /// Brings in entries AutoFill saved while it couldn't reach the
    /// database file, then deletes its copy once they're saved here.
    func mergePendingChanges(for id: UUID, into session: DatabaseSession) async {
        guard let pending = SharedFiles.pendingChanges(for: id),
            FileManager.default.fileExists(atPath: pending.url.path)
        else { return }
        do {
            try await session.mergeChanges(from: pending)
            await save(session)
            if !session.hasUnsavedChanges {
                try? FileManager.default.removeItem(at: pending.url)
            }
        } catch {
            errorMessage = String(localized: "Changes made in AutoFill couldn't be merged: \(error.userMessage)")
        }
    }
}
