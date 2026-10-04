import Foundation
import KPAppState
import KPKDBX
import KPModel
import KPPlatform
import KPSession
import Observation
import UIKit

/// App-wide state: the database library, settings and open sessions.
@MainActor
@Observable
final class AppModel {
    private(set) var state = AppState()
    // Sessions are created lazily while views are being built, so changes
    // to this dictionary must not trigger view updates themselves; each
    // session is observable on its own.
    @ObservationIgnored private(set) var sessions: [UUID: DatabaseSession] = [:]
    var errorMessage: String?
    /// Set by the quick-create intent; the UI shows the quick-create sheet
    /// (after unlocking) when it is true.
    var quickCreateRequested = false
    /// Databases the user locked with the Lock button. Their unlock screen
    /// waits for the user instead of asking for Face ID straight away,
    /// until the user leaves it.
    var lockedByUser: Set<UUID> = []
    /// Bumped whenever databases are locked, so the library can close
    /// the screens that showed their contents.
    private(set) var lockCount = 0

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
            let id = UUID()
            let session = DatabaseSession(file: Self.cached(LocalDatabaseFile(url: url), id: id), codec: codec)
            try await session.create(
                name: fileName,
                key: CompositeKey(password: SecretString(password)),
                settings: newDatabaseSettings
            )
            let reference = DatabaseReference(
                id: id,
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
        QuickUnlock.remove(for: id)
        SharedFiles.removeDatabaseCache(for: id)
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
        let session = DatabaseSession(file: Self.cached(file, id: reference.id), codec: codec)
        sessions[reference.id] = session
        return session
    }

    /// Keeps the App Group copy of the file current for the AutoFill
    /// extension, which can't always reach the original.
    private static func cached(_ file: any DatabaseFile, id: UUID) -> any DatabaseFile {
        guard let cache = SharedFiles.databaseCache(for: id) else { return file }
        return CachedDatabaseFile(original: file, cache: cache, fallsBackToCache: false)
    }

    /// Remembers (or, with nil, forgets) which key file a database uses.
    func setKeyFileBookmark(_ bookmark: Data?, for id: UUID) async {
        state =
            (try? await store.update { state in
                if let index = state.databases.firstIndex(where: { $0.id == id }) {
                    state.databases[index].keyFileBookmark = bookmark
                }
            }) ?? state
    }

    func markOpened(_ id: UUID) async {
        state =
            (try? await store.update { state in
                if let index = state.databases.firstIndex(where: { $0.id == id }) {
                    state.databases[index].lastOpened = Date()
                }
            }) ?? state
    }

    func setQuickUnlock(_ enabled: Bool, for id: UUID) async {
        state =
            (try? await store.update { state in
                if let index = state.databases.firstIndex(where: { $0.id == id }) {
                    state.databases[index].quickUnlockEnabled = enabled
                }
            }) ?? state
    }

    /// Locks a database because the user asked to.
    func lock(_ session: DatabaseSession) {
        if let id = sessions.first(where: { $0.value === session })?.key {
            lockedByUser.insert(id)
        }
        saveAndLock(session)
        lockCount += 1
    }

    func rename(_ id: UUID, to alias: String) async {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        state =
            (try? await store.update { state in
                if let index = state.databases.firstIndex(where: { $0.id == id }) {
                    state.databases[index].alias = trimmed.isEmpty ? nil : trimmed
                }
            }) ?? state
    }

    func setQuickCreateDatabase(_ id: UUID?) async {
        var settings = settings
        settings.quickCreateDatabaseID = id
        await updateSettings(settings)
    }

    func forgetQuickUnlock(for id: UUID) async {
        QuickUnlock.remove(for: id)
        await setQuickUnlock(false, for: id)
    }

    func isUnlocked(_ id: UUID) -> Bool {
        sessions[id]?.state == .unlocked
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
    func lockAll() {
        let open = sessions.values.filter { $0.state == .unlocked }
        guard !open.isEmpty else { return }
        for session in open {
            saveAndLock(session)
        }
        lockCount += 1
    }

    var hasUnlockedDatabase: Bool {
        sessions.values.contains { $0.state == .unlocked }
    }

    /// Locking drops the decrypted database, so unsaved edits are written
    /// first. Edits are normally saved as they're made (see
    /// `autosave(_:)`); this covers locking in the moment between. The
    /// save asks iOS for time to finish if the app is going to the
    /// background.
    private func saveAndLock(_ session: DatabaseSession) {
        guard session.hasUnsavedChanges || session.isSaving else {
            session.lock()
            return
        }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save before locking")
        Task {
            await save(session)
            session.lock()
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    /// Saves a database's changes, reporting failures in the library.
    func save(_ session: DatabaseSession) async {
        while session.isSaving {
            try? await Task.sleep(for: .milliseconds(50))
        }
        do {
            // Edits made while a save was running are saved by another pass.
            var passes = 0
            while session.hasUnsavedChanges, passes < 3 {
                try await session.save()
                passes += 1
            }
        } catch {
            errorMessage = String(
                localized: "Your latest changes couldn't be saved: \(error.userMessage)"
            )
        }
    }

    // MARK: Settings

    func updateSettings(_ settings: Settings) async {
        state = (try? await store.update { $0.settings = settings }) ?? state
    }
}
