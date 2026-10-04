import Foundation
import Testing

@testable import KPAppState

struct AppStateStoreTests {
    let directory: URL
    let store: AppStateStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateStoreTests-\(UUID().uuidString)")
        store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    }

    @Test func missingFileLoadsDefaults() async throws {
        let state = try await store.load()
        #expect(state == AppState())
        #expect(state.settings.networkAllowed == false)
        #expect(state.settings.autoLockSeconds == 120)
    }

    @Test func updatesPersist() async throws {
        let reference = DatabaseReference(displayName: "Personal", bookmark: Data([1, 2, 3]))
        try await store.update { state in
            state.databases.append(reference)
            state.settings.quickCreateDatabaseID = reference.id
        }

        let reloaded = try await AppStateStore(fileURL: store.fileURL).load()
        #expect(reloaded.databases == [reference])
        #expect(reloaded.settings.quickCreateDatabaseID == reference.id)
        #expect(reloaded.database(withID: reference.id)?.displayName == "Personal")
    }

    @Test func updateKeepsChangesWrittenByAnotherProcess() async throws {
        // Simulates the AutoFill extension and the app sharing one file.
        let extensionStore = AppStateStore(fileURL: store.fileURL)
        let first = DatabaseReference(displayName: "A", bookmark: Data())
        try await store.update { $0.databases.append(first) }
        try await extensionStore.update { state in
            state.databases[0].pendingSync = true
        }
        try await store.update { $0.settings.autoLockSeconds = 60 }

        let state = try await store.load()
        #expect(state.databases.first?.pendingSync == true)
        #expect(state.settings.autoLockSeconds == 60)
    }

    @Test func missingFieldsGetDefaults() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"version": 1, "settings": {"autoLockSeconds": 30}}"#
        try Data(json.utf8).write(to: store.fileURL)

        let state = try await store.load()
        #expect(state.databases.isEmpty)
        #expect(state.settings.autoLockSeconds == 30)
        #expect(state.settings.clipboardClearSeconds == 30)
        #expect(state.settings.generator == GeneratorSettings())
    }

    @Test func refusesFilesFromNewerVersions() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "somethingNew": true}"#.utf8).write(to: store.fileURL)

        await #expect(throws: AppStateStore.StoreError.newerVersion(99)) { try await store.load() }
        await #expect(throws: AppStateStore.StoreError.newerVersion(99)) {
            try await store.update { $0.settings.autoLockSeconds = 1 }
        }
        // The newer file is left untouched.
        let contents = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(contents.contains("somethingNew"))
    }

    @Test func reportsCorruptedFiles() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        await #expect(throws: AppStateStore.StoreError.corrupted) { try await store.load() }
    }

    @Test func networkFeaturesNeedTheGlobalSwitch() {
        var settings = Settings()
        settings.faviconDownloadEnabled = true
        settings.breachCheckEnabled = true
        #expect(!settings.mayDownloadFavicons)
        #expect(!settings.mayCheckBreaches)
        settings.networkAllowed = true
        #expect(settings.mayDownloadFavicons)
        #expect(settings.mayCheckBreaches)
    }
}
