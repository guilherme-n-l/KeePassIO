import Foundation

/// A database file with a local copy of its last known contents.
///
/// Every successful read or write of the original also refreshes the copy.
/// The app uses this to keep the copy current; the AutoFill extension,
/// which often can't reach files held by other apps' File Providers, falls
/// back to the copy when the original can't be read. The copy is the
/// encrypted file itself, so it is no more exposed than the original.
public struct CachedDatabaseFile: DatabaseFile {
    public let original: any DatabaseFile
    public let cache: LocalDatabaseFile
    /// Read the copy when the original can't be read. Off in the app, so a
    /// deleted or moved original is reported instead of hidden.
    public let fallsBackToCache: Bool

    public init(original: any DatabaseFile, cache: LocalDatabaseFile, fallsBackToCache: Bool) {
        self.original = original
        self.cache = cache
        self.fallsBackToCache = fallsBackToCache
    }

    public var displayName: String { original.displayName }

    public func read() async throws(FileError) -> (data: Data, version: FileVersion) {
        do {
            let result = try await original.read()
            await refreshCache(with: result.data)
            return result
        } catch {
            guard fallsBackToCache, let cached = try? await cache.read() else { throw error }
            return cached
        }
    }

    public func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        let version = try await original.write(data, expecting: expected)
        await refreshCache(with: data)
        return version
    }

    /// Failing to update the copy never fails the read or write.
    private func refreshCache(with data: Data) async {
        try? FileManager.default.createDirectory(
            at: cache.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try? await cache.write(data, expecting: nil)
    }
}
