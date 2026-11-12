import Foundation
import KPModel
import Testing

@testable import KPSearch

struct AutoFillMatcherTests {
    typealias Service = AutoFillService

    static func add(_ database: inout Database, _ title: String, _ change: (inout Entry) -> Void = { _ in }) throws
        -> UUID
    {
        var entry = Entry()
        entry.title = title
        change(&entry)
        try database.add(entry, to: database.root.id)
        return entry.id
    }

    static let app = Service(
        kind: .app,
        identifier: "ABCDE12345.br.com.example.passageiro.mobizapsp",
        displayName: "Mobizap SP"
    )

    @Test func appMatchesRankLinkedThenAndroidThenName() throws {
        var database = Database.empty(name: "Test")
        let byName = try Self.add(&database, "car/mobizap")
        let android = try Self.add(&database, "Taxi") {
            $0.fields["AndroidApp"] = .plain("br.com.example.passageiro.mobizapsp")
        }
        let linked = try Self.add(&database, "Rides") { $0.linkApp("br.com.example.passageiro.mobizapsp") }
        _ = try Self.add(&database, "Unrelated") { $0.url = "https://example.com" }

        let matches = AutoFillMatcher.matches(for: [Self.app], in: database)
        #expect(matches.map(\.entryID) == [linked, android, byName])
        #expect(matches.map(\.reason) == [.linkedApp, .androidApp, .similarName])
    }

    @Test func anEntryAppearsOnceWithItsBestReason() throws {
        var database = Database.empty(name: "Test")
        let both = try Self.add(&database, "Mobizap") {
            $0.linkApp("br.com.example.passageiro.mobizapsp")
            $0.fields["AndroidApp"] = .plain("br.com.example.passageiro.mobizapsp")
        }
        let matches = AutoFillMatcher.matches(for: [Self.app, Self.app], in: database)
        #expect(matches == [AutoFillMatcher.Match(entryID: both, reason: .linkedApp)])
    }

    @Test func websitesKeepTheirOrderAndAnAppLinkOutranksThem() throws {
        var database = Database.empty(name: "Test")
        let exact = try Self.add(&database, "b") { $0.url = "https://login.example.com/signin" }
        let domain = try Self.add(&database, "a") { $0.url = "https://example.com" }
        let linked = try Self.add(&database, "c") { $0.linkApp("com.example.app") }
        let services = [
            Service(kind: .url, identifier: "https://login.example.com/signin"),
            Service(kind: .app, identifier: "com.example.app"),
        ]
        let matches = AutoFillMatcher.matches(for: services, in: database)
        #expect(matches.map(\.entryID) == [linked, exact, domain])
        #expect(matches.map(\.reason) == [.linkedApp, .exactURL, .sameDomain])
    }

    @Test func sameReasonSortsByTitle() throws {
        var database = Database.empty(name: "Test")
        let zulu = try Self.add(&database, "Zulu") { $0.linkApp("com.example.app") }
        let alpha = try Self.add(&database, "alpha") { $0.linkApp("com.example.app") }
        let matches = AutoFillMatcher.matches(for: [Service(kind: .app, identifier: "com.example.app")], in: database)
        #expect(matches.map(\.entryID) == [alpha, zulu])
    }

    /// An app ID is not a website: before, iOS's app identifiers were
    /// read as hosts, and Android app links in URL fields matched sites.
    @Test func appIDsAndAppLinksNeverMatchWebsites() throws {
        var database = Database.empty(name: "Test")
        _ = try Self.add(&database, "Site") { $0.url = "https://mobizapsp.passageiro.example.com.br" }
        let androidURL = try Self.add(&database, "Android link") { $0.url = "androidapp://com.example.shop" }
        #expect(AutoFillMatcher.matches(for: [Self.app], in: database).isEmpty)
        #expect(URLMatcher.matches(for: "https://shop.example.com", in: database).isEmpty)
        let app = Service(kind: .app, identifier: "com.example.shop")
        #expect(AutoFillMatcher.matches(for: [app], in: database).map(\.entryID) == [androidURL])
    }

    @Test func expiredAndRecycledEntriesAreSkipped() throws {
        var database = Database.empty(name: "Test")
        _ = try Self.add(&database, "Old") {
            $0.linkApp("com.example.app")
            $0.times.expiry = Date(timeIntervalSince1970: 0)
        }
        let recycled = try Self.add(&database, "Gone") { $0.linkApp("com.example.app") }
        try database.deleteEntry(recycled, at: Date())
        let matches = AutoFillMatcher.matches(for: [Service(kind: .app, identifier: "com.example.app")], in: database)
        #expect(matches.isEmpty)
    }

    @Test func titleSimilarity() {
        let bundle = "br.com.example.passageiro.mobizapsp"
        #expect(AutoFillMatcher.titleLooksLike("car/mobizap", bundleID: bundle, name: "Mobizap SP"))
        #expect(AutoFillMatcher.titleLooksLike("Mobizap", bundleID: bundle, name: nil))
        #expect(AutoFillMatcher.titleLooksLike("Itaú", bundleID: "com.itau.app", name: "Itau"))
        #expect(AutoFillMatcher.titleLooksLike("NuBank", bundleID: "com.nu.production", name: "Nu Bank"))
        // Short and generic words say nothing about the app.
        #expect(!AutoFillMatcher.titleLooksLike("SP", bundleID: bundle, name: "Mobizap SP"))
        #expect(!AutoFillMatcher.titleLooksLike("Work email", bundleID: "com.example.email", name: "Email"))
        #expect(!AutoFillMatcher.titleLooksLike("Spotify", bundleID: bundle, name: "Mobizap SP"))
    }
}
