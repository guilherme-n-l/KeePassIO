import Foundation

/// Loads and saves `AppState` as a JSON file.
///
/// Writes are atomic (write to a temporary file, then rename), so a crash
/// or a concurrent reader never sees a half-written file. Every update
/// re-reads the file first, so changes made by an extension since the last
/// read are kept rather than overwritten.
public actor AppStateStore {
    public enum StoreError: Error, Equatable {
        /// The file was written by a newer version of the app. It is left
        /// untouched rather than downgraded.
        case newerVersion(Int)
        case corrupted
    }

    public nonisolated let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The store in the shared App Group container, or nil if the
    /// container isn't available (for example in unit tests).
    public static func shared(appGroup: String = "group.dev.guilhermenl.keepassio") -> AppStateStore? {
        #if canImport(Darwin)
            guard
                let container = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: appGroup
                )
            else { return nil }
            return AppStateStore(fileURL: container.appendingPathComponent("AppState.json"))
        #else
            return nil
        #endif
    }

    /// The saved state, or a fresh default state if no file exists yet.
    public func load() throws(StoreError) -> AppState {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return AppState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(AppState.self, from: data) else {
            if let version = try? decoder.decode(VersionOnly.self, from: data).version,
                version > AppState.currentVersion
            {
                throw .newerVersion(version)
            }
            throw .corrupted
        }
        guard state.version <= AppState.currentVersion else { throw .newerVersion(state.version) }
        return state
    }

    /// Applies `change` to the current state on disk and saves the result.
    @discardableResult
    public func update(_ change: @Sendable (inout AppState) -> Void) throws -> AppState {
        var state = try load()
        change(&state)
        state.version = AppState.currentVersion
        try save(state)
        return state
    }

    private func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private struct VersionOnly: Decodable {
        let version: Int
    }
}
