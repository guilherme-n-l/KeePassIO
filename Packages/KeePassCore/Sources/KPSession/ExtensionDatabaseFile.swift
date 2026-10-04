import Foundation

/// How app extensions (AutoFill) reach a database: the original when
/// they can, otherwise copies in the App Group.
///
///     read:  original ──fails──► pending copy ──missing──► cache copy
///     write: original ──fails──► pending copy (the app merges it later)
///
/// Extensions often can't reach files held by another app's File
/// Provider. A save that can't reach the original goes to the pending
/// copy, a complete encrypted database; the app merges it into the
/// original the next time it unlocks the database
/// (`DatabaseSession.mergeChanges(from:)`) and deletes it.
public struct ExtensionDatabaseFile: DatabaseFile {
    public let original: any DatabaseFile
    /// The app's copy of the original's last known contents.
    public let cache: LocalDatabaseFile
    /// Changes the extension couldn't write to the original.
    public let pending: LocalDatabaseFile

    public init(original: any DatabaseFile, cache: LocalDatabaseFile, pending: LocalDatabaseFile) {
        self.original = original
        self.cache = cache
        self.pending = pending
    }

    public var displayName: String { original.displayName }

    /// Whether there are changes waiting for the app to merge.
    public var hasPendingChanges: Bool {
        FileManager.default.fileExists(atPath: pending.url.path)
    }

    public func read() async throws(FileError) -> (data: Data, version: FileVersion) {
        do {
            return try await original.read()
        } catch {
            if let pendingCopy = try? await pending.read() { return pendingCopy }
            if let cachedCopy = try? await cache.read() { return cachedCopy }
            throw error
        }
    }

    public func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        do {
            return try await original.write(data, expecting: expected)
        } catch .changedOnDisk(let current) {
            // Reachable but changed: the session merges and tries again.
            throw .changedOnDisk(current: current)
        } catch {
            try? FileManager.default.createDirectory(
                at: pending.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try await pending.write(data, expecting: nil)
        }
    }
}
