import Foundation

/// Identifies one version of a file, to notice changes made elsewhere
/// (another app, a sync client, an extension) before overwriting them.
public struct FileVersion: Sendable, Equatable, Hashable {
    public var modificationDate: Date?
    public var size: Int

    public init(modificationDate: Date?, size: Int) {
        self.modificationDate = modificationDate
        self.size = size
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
    /// current version isn't `expected`. Returns the new version.
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
            return (data, try currentVersion())
        } catch let error as FileError {
            throw error
        } catch {
            throw .ioFailure(error.localizedDescription)
        }
    }

    public func write(_ data: Data, expecting expected: FileVersion?) async throws(FileError) -> FileVersion {
        if let expected, FileManager.default.fileExists(atPath: url.path) {
            let current = try currentVersion()
            guard current == expected else { throw .changedOnDisk(current: current) }
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .ioFailure(error.localizedDescription)
        }
        return try currentVersion()
    }

    func currentVersion() throws(FileError) -> FileVersion {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileVersion(
                modificationDate: attributes[.modificationDate] as? Date,
                size: (attributes[.size] as? NSNumber)?.intValue ?? 0
            )
        } catch {
            throw .notFound
        }
    }
}
