import Foundation
import Testing

@testable import KPSession

struct CachedDatabaseFileTests {
    let directory: URL
    let original: LocalDatabaseFile
    let cache: LocalDatabaseFile

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CacheTests-\(UUID())")
        original = LocalDatabaseFile(url: directory.appendingPathComponent("vault.kdbx"))
        cache = LocalDatabaseFile(url: directory.appendingPathComponent("Cache/vault.kdbx"))
    }

    @Test func readsAndWritesRefreshTheCopy() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: original.url)
        let file = CachedDatabaseFile(original: original, cache: cache, fallsBackToCache: false)

        let first = try await file.read()
        #expect(try Data(contentsOf: cache.url) == Data("v1".utf8))

        _ = try await file.write(Data("v2".utf8), expecting: first.version)
        #expect(try Data(contentsOf: cache.url) == Data("v2".utf8))
    }

    @Test func fallsBackToTheCopyOnlyWhenAllowed() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: original.url)
        _ = try await CachedDatabaseFile(original: original, cache: cache, fallsBackToCache: false).read()
        try FileManager.default.removeItem(at: original.url)

        await #expect(throws: FileError.notFound) {
            try await CachedDatabaseFile(original: original, cache: cache, fallsBackToCache: false).read()
        }
        let cached = try await CachedDatabaseFile(original: original, cache: cache, fallsBackToCache: true).read()
        #expect(cached.data == Data("v1".utf8))
    }
}
