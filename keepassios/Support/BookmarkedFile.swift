import Foundation
import KPSession

/// A database file the user picked in the Files app, reached through a
/// security-scoped bookmark.
///
/// Reads and writes go through `NSFileCoordinator`, so File Provider
/// extensions (iCloud Drive, Dropbox, ...) see consistent files and
/// download them first when needed. Writes are atomic and check, by
/// content hash, that the file is still the version that was read.
struct BookmarkedFile: DatabaseFile {
    let bookmark: Data
    let displayName: String

    func read() async throws(FileError) -> (data: Data, version: FileVersion) {
        let url = try resolve()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<(Data, FileVersion), FileError> = .failure(.notFound)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                let data = try Data(contentsOf: readURL)
                result = .success((data, FileVersion(of: data, modificationDate: Self.modificationDate(of: readURL))))
            } catch {
                result = .failure(.ioFailure(error.localizedDescription))
            }
        }
        if let coordinationError { throw .ioFailure(coordinationError.localizedDescription) }
        return try result.get()
    }

    func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        let url = try resolve()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<FileVersion, FileError> = .failure(.accessDenied)
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { writeURL in
            if let expected, let currentData = try? Data(contentsOf: writeURL) {
                let current = FileVersion(of: currentData, modificationDate: Self.modificationDate(of: writeURL))
                if current.contentHash != expected.contentHash {
                    result = .failure(.changedOnDisk(current: current))
                    return
                }
            }
            do {
                try data.write(to: writeURL, options: .atomic)
                result = .success(FileVersion(of: data, modificationDate: Self.modificationDate(of: writeURL)))
            } catch {
                result = .failure(.ioFailure(error.localizedDescription))
            }
        }
        if let coordinationError { throw .ioFailure(coordinationError.localizedDescription) }
        return try result.get()
    }

    private func resolve() throws(FileError) -> URL {
        var stale = false
        do {
            return try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        } catch {
            throw .notFound
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Creates a bookmark for a URL from the document picker.
    static func makeBookmark(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
