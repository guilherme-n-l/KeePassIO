import Crypto
import Foundation

/// Identifies one version of a file, to notice changes made elsewhere
/// (another app, a sync client, an extension) before overwriting them.
///
/// The content hash is what makes the check reliable: two saves of a
/// database often produce files of the same size, and modification times
/// can be too coarse to tell writes a few milliseconds apart.
public struct FileVersion: Sendable, Equatable, Hashable {
    public var modificationDate: Date?
    public var size: Int
    /// SHA-256 of the file's bytes.
    public var contentHash: Data

    public init(modificationDate: Date?, size: Int, contentHash: Data) {
        self.modificationDate = modificationDate
        self.size = size
        self.contentHash = contentHash
    }

    public init(of data: Data, modificationDate: Date?) {
        self.init(modificationDate: modificationDate, size: data.count, contentHash: Data(SHA256.hash(data: data)))
    }
}

public enum FileError: Error, Equatable, Sendable {
    /// The file changed since it was read; the caller should merge.
    case changedOnDisk(current: FileVersion)
    case notFound
    case accessDenied
    case ioFailure(String)
}

/// Where a database's bytes live. The app's implementation uses
/// security-scoped bookmarks and `NSFileCoordinator`; tests and Linux use
/// `LocalDatabaseFile`.
public protocol DatabaseFile: Sendable {
    var displayName: String { get }
    func read() async throws(FileError) -> (data: Data, version: FileVersion)
    /// Writes atomically, failing with `.changedOnDisk` when the file's
    /// current content isn't the `expected` version's (compared by content
    /// hash). Returns the new version.
    func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion
}

/// A plain file on the local file system, written with a temporary file
/// and rename so readers never see a partial file.
public struct LocalDatabaseFile: DatabaseFile {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var displayName: String { url.deletingPathExtension().lastPathComponent }

    public func read() async throws(FileError) -> (data: Data, version: FileVersion) {
        guard FileManager.default.fileExists(atPath: url.path) else { throw .notFound }
        do {
            let data = try Data(contentsOf: url)
            return (data, FileVersion(of: data, modificationDate: try modificationDate()))
        } catch let error as FileError {
            throw error
        } catch {
            throw .ioFailure(error.localizedDescription)
        }
    }

    public func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        if let expected, FileManager.default.fileExists(atPath: url.path) {
            let current = try await read().version
            guard current.contentHash == expected.contentHash else { throw .changedOnDisk(current: current) }
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .ioFailure(error.localizedDescription)
        }
        return FileVersion(of: data, modificationDate: try modificationDate())
    }

    private func modificationDate() throws(FileError) -> Date? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        } catch {
            throw .notFound
        }
    }
}
