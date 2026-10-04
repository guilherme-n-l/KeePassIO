import Foundation
import KPAppState
import KPKDBX
import KPModel
import KPSession
import Observation

/// App-wide state: the database library, settings and open sessions.
@MainActor
@Observable
final class AppModel {
    private(set) var state = AppState()
    private(set) var sessions: [UUID: DatabaseSession] = [:]
    var errorMessage: String?
    /// Set by the quick-create intent; the UI shows the quick-create sheet
    /// (after unlocking) when it is true.
    var quickCreateRequested = false

    private let store: AppStateStore
    let codec: any DatabaseCodec
    /// Encryption for new databases. UI tests use a cheap key derivation
    /// so they run quickly on simulators.
    let newDatabaseSettings: EncryptionSettings

    init(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        let isUITest = launchArguments.contains("-UITest")
        let fallbackURL = URL.applicationSupportDirectory.appendingPathComponent("AppState.json")
        store = (isUITest ? nil : AppStateStore.shared()) ?? AppStateStore(fileURL: fallbackURL)
        codec = KDBXCodec()
        newDatabaseSettings =
            isUITest
            ? EncryptionSettings(
                cipher: .aes256,
                keyDerivation: .argon2id(iterations: 1, memoryBytes: 1 << 20, parallelism: 1)
            )
            : .recommended
        if launchArguments.contains("-UITestReset") {
            try? FileManager.default.removeItem(at: fallbackURL)
            try? FileManager.default.removeItem(at: Self.documentsDirectory)
        }
    }

    static var documentsDirectory: URL { URL.documentsDirectory }

    func load() async {
        do {
            state = try await store.load()
        } catch {
            errorMessage = String(
                localized: "Couldn't read the app's settings. Defaults are used until you change them."
            )
        }
    }

    var databases: [DatabaseReference] { state.databases }
    var settings: Settings { state.settings }

    // MARK: Library

    /// Adds a database the user picked in the Files app.
    func addDatabase(at url: URL) async {
        do {
            let bookmark = try BookmarkedFile.makeBookmark(for: url)
            let name = url.deletingPathExtension().lastPathComponent
            let reference = DatabaseReference(displayName: name, bookmark: bookmark)
            state = try await store.update { $0.databases.append(reference) }
        } catch {
            errorMessage = String(localized: "Couldn't add the database: \(error.localizedDescription)")
        }
    }

    /// Creates a new database in the app's Documents folder, which the
    /// Files app shows under "On My iPhone".
    func createDatabase(name: String, password: String) async -> UUID? {
        let fileName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Passwords" : name
        let url = Self.documentsDirectory.appendingPathComponent(fileName).appendingPathExtension("kdbx")
        do {
            try FileManager.default.createDirectory(at: Self.documentsDirectory, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = String(localized: "A database named \(fileName) already exists.")
                return nil
            }
            let session = DatabaseSession(file: LocalDatabaseFile(url: url), codec: codec)
            try await session.create(
                name: fileName,
                key: CompositeKey(password: SecretString(password)),
                settings: newDatabaseSettings
            )
            let reference = DatabaseReference(
                displayName: fileName,
                bookmark: try BookmarkedFile.makeBookmark(for: url),
                lastOpened: Date()
            )
            state = try await store.update { $0.databases.append(reference) }
            sessions[reference.id] = session
            return reference.id
        } catch {
            errorMessage = String(localized: "Couldn't create the database: \(error.localizedDescription)")
            return nil
        }
    }

    func removeDatabase(_ id: UUID) async {
        sessions[id]?.lock()
        sessions[id] = nil
        state = (try? await store.update { $0.databases.removeAll { $0.id == id } }) ?? state
    }

    /// The session for a database, created locked on first use.
    func session(for reference: DatabaseReference) -> DatabaseSession {
        if let session = sessions[reference.id] {
            return session
        }
        let file = BookmarkedFile(bookmark: reference.bookmark, displayName: reference.displayName)
        let session = DatabaseSession(file: file, codec: codec)
        sessions[reference.id] = session
        return session
    }

    func markOpened(_ id: UUID) async {
        state =
            (try? await store.update { state in
                if let index = state.databases.firstIndex(where: { $0.id == id }) {
                    state.databases[index].lastOpened = Date()
                }
            }) ?? state
    }

    func lockAll() {
        for session in sessions.values {
            session.lock()
        }
    }

    // MARK: Settings

    func updateSettings(_ change: @escaping (inout Settings) -> Void) async {
        state = (try? await store.update { change(&$0.settings) }) ?? state
    }
}
