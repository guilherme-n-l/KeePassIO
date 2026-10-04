#if canImport(Darwin)
    import Foundation
    import KPSession

    /// Files the app and its extensions share through the App Group.
    public enum SharedFiles {
        public static let appGroup = "group.dev.guilhermenl.keepassios"

        /// Where the copy of a database's encrypted file is kept for the
        /// AutoFill extension (see `CachedDatabaseFile`).
        public static func databaseCache(for databaseID: UUID) -> LocalDatabaseFile? {
            file(named: databaseID.uuidString)
        }

        /// Changes AutoFill saved while it couldn't reach the original (see
        /// `ExtensionDatabaseFile`); the app merges and deletes them.
        public static func pendingChanges(for databaseID: UUID) -> LocalDatabaseFile? {
            file(named: "\(databaseID.uuidString).pending")
        }

        public static func removeDatabaseCache(for databaseID: UUID) {
            for file in [databaseCache(for: databaseID), pendingChanges(for: databaseID)].compactMap(\.self) {
                try? FileManager.default.removeItem(at: file.url)
            }
        }

        private static func file(named name: String) -> LocalDatabaseFile? {
            guard
                let container = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: appGroup
                )
            else { return nil }
            let url =
                container
                .appendingPathComponent("DatabaseCache", isDirectory: true)
                .appendingPathComponent(name)
                .appendingPathExtension("kdbx")
            return LocalDatabaseFile(url: url)
        }
    }

    /// Reads key files the user picked, through file coordination so a
    /// file in iCloud Drive or another provider is downloaded first.
    public enum KeyFile {
        /// The file's contents, or nil when it can't be read or is empty.
        public static func read(_ url: URL) async -> Data? {
            await Task.detached {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var coordinationError: NSError?
                var data: Data?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                    data = try? Data(contentsOf: readURL)
                }
                return data?.isEmpty == false ? data : nil
            }.value
        }

        /// A remembered key file: its name and contents, or nil when the
        /// bookmark no longer resolves or the file can't be read.
        public static func read(bookmark: Data) async -> (name: String, data: Data)? {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
                let data = await read(url)
            else { return nil }
            return (url.lastPathComponent, data)
        }

        /// A bookmark to remember the key file by. Only the location is
        /// remembered; the key file itself is never copied.
        public static func bookmark(for url: URL) -> Data? {
            try? BookmarkedFile.makeBookmark(for: url)
        }
    }
#endif
