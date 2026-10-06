import Foundation
import Testing

@testable import KPModel
@testable import KPSearch

struct SearchIndexTests {
    static func database() throws -> Database {
        var database = Database.empty(name: "Test")
        let work = Group(name: "Work")
        try database.add(work, to: database.root.id)

        var mail = Entry(times: Times(creation: Date(timeIntervalSince1970: 100)))
        mail.title = "Gmail"
        mail.userName = "alice@example.com"
        mail.url = "https://mail.google.com"
        mail.tags = ["personal"]
        try database.add(mail, to: database.root.id)

        var bank = Entry(times: Times(creation: Date(timeIntervalSince1970: 200)))
        bank.title = "Banco Café"
        bank.userName = "alice"
        bank.notes = "Branch 1234"
        bank.password = "gmail-is-not-here"
        bank.fields["PIN"] = .protected("9999")
        bank.fields["Account"] = .plain("Checking")
        try database.add(bank, to: work.id)

        var deleted = Entry()
        deleted.title = "Gmail old"
        try database.add(deleted, to: database.root.id)
        try database.deleteEntry(deleted.id)
        return database
    }

    @Test func substringMatchingAcrossFields() throws {
        let index = SearchIndex(try Self.database())
        #expect(index.search("gma").map(\.title) == ["Gmail"])
        #expect(index.search("alice").count == 2)
        #expect(index.search("alice gma").map(\.title) == ["Gmail"])
        #expect(index.search("checking").map(\.title) == ["Banco Café"])
        #expect(index.search("work").map(\.title) == ["Banco Café"])
        // Anywhere in a word, as in KeePassXC.
        #expect(index.search("mail").map(\.title) == ["Gmail"])
        #expect(index.search("anco").map(\.title) == ["Banco Café"])
    }

    @Test func pathQueriesMatchGroupsAndTitleInOrder() throws {
        var database = Database.empty(name: "Test")
        let personal = Group(name: "Personal")
        let gmail = Group(name: "gmail")
        try database.add(personal, to: database.root.id)
        try database.add(gmail, to: personal.id)
        var account = Entry()
        account.title = "acc"
        try database.add(account, to: gmail.id)
        var other = Entry()
        other.title = "account"
        try database.add(other, to: personal.id)
        let index = SearchIndex(database)

        #expect(index.search("mail/acc").map(\.title) == ["acc"])
        #expect(index.search("personal/acc").count == 2)
        #expect(index.search("acc/mail").isEmpty)
        #expect(index.search("g:pers/gma").map(\.title) == ["acc"])
        #expect(index.search("group:gmail").map(\.title) == ["acc"])
    }

    @Test func keePassXCModifiers() throws {
        let index = SearchIndex(try Self.database())
        #expect(index.search("alice -gmail").map(\.title) == ["Banco Café"])
        #expect(index.search("alice !gmail").map(\.title) == ["Banco Café"])
        #expect(index.search("+u:alice").map(\.title) == ["Banco Café"])
        #expect(index.search("u:alice").count == 2)
        #expect(index.search("t:g*l").map(\.title) == ["Gmail"])
        #expect(index.search("t:b?nco").map(\.title) == ["Banco Café"])
        #expect(index.search("*^gm").map(\.title) == ["Gmail"])
        #expect(index.search(#""banco café""#).map(\.title) == ["Banco Café"])
        #expect(index.search(#"title:"banco caf""#).map(\.title) == ["Banco Café"])
        #expect(index.search("https://mail.google").map(\.title) == ["Gmail"])
        #expect(index.search("attr:checking").map(\.title) == ["Banco Café"])
    }

    @Test func searchCanBeLimitedToAGroup() throws {
        let database = try Self.database()
        let work = try #require(database.root.groups.first { $0.name == "Work" })
        let index = SearchIndex(database)
        #expect(index.search("alice").count == 2)
        #expect(index.search("alice", in: work.id).map(\.title) == ["Banco Café"])
        #expect(index.search("", in: work.id).map(\.title) == ["Banco Café"])
        #expect(index.search("alice", in: database.root.id).count == 2)
    }

    @Test func expiredEntriesCanBeFound() throws {
        var database = try Self.database()
        var old = Entry(times: Times(expiry: Date(timeIntervalSince1970: 50)))
        old.title = "Old VPN"
        try database.add(old, to: database.root.id)
        let index = SearchIndex(database)
        #expect(index.search("is:expired", at: Date(timeIntervalSince1970: 1000)).map(\.title) == ["Old VPN"])
    }

    @Test func caseAndDiacriticInsensitive() throws {
        let index = SearchIndex(try Self.database())
        #expect(index.search("CAFE").map(\.title) == ["Banco Café"])
        #expect(index.search("café").map(\.title) == ["Banco Café"])
    }

    @Test func protectedFieldsAndRecycleBinAreNotSearchable() throws {
        let index = SearchIndex(try Self.database())
        #expect(index.count == 2)
        #expect(index.search("9999").isEmpty)
        #expect(!index.search("gmail").contains { $0.title == "Banco Café" })
        #expect(!index.search("old").contains { $0.title == "Gmail old" })
    }

    @Test func fieldFilters() throws {
        let index = SearchIndex(try Self.database())
        #expect(index.search("tag:personal").map(\.title) == ["Gmail"])
        #expect(index.search("user:alice").count == 2)
        #expect(index.search("title:alice").isEmpty)
        #expect(index.search("url:google").map(\.title) == ["Gmail"])
    }

    @Test func titleMatchesRankFirstAndEmptyQueryListsNewestFirst() throws {
        var database = try Self.database()
        var note = Entry(times: Times(creation: Date(timeIntervalSince1970: 300)))
        note.title = "Notes"
        note.notes = "Gmail recovery codes"
        try database.add(note, to: database.root.id)
        let index = SearchIndex(database)

        #expect(index.search("gmail").first?.title == "Gmail")
        #expect(index.search("").map(\.title) == ["Notes", "Banco Café", "Gmail"])
        #expect(index.search("", limit: 1).count == 1)
    }
}

struct URLMatcherTests {
    static func database() throws -> (Database, [String: UUID]) {
        var database = Database.empty(name: "Test")
        var ids: [String: UUID] = [:]
        for (title, url) in [
            ("exact", "https://login.example.com/signin"),
            ("host", "login.example.com"),
            ("domain", "https://www.example.com"),
            ("other", "https://example.org"),
            ("uk", "https://shop.example.co.uk"),
        ] {
            var entry = Entry()
            entry.title = title
            entry.url = url
            try database.add(entry, to: database.root.id)
            ids[title] = entry.id
        }
        var expired = Entry(times: Times(expiry: Date(timeIntervalSince1970: 0)))
        expired.url = "https://login.example.com"
        try database.add(expired, to: database.root.id)
        var extra = Entry()
        extra.title = "extra"
        extra.fields["KP2A_URL_1"] = .plain("https://accounts.example.net")
        try database.add(extra, to: database.root.id)
        ids["extra"] = extra.id
        return (database, ids)
    }

    @Test func ranksExactThenHostThenDomain() throws {
        let (database, ids) = try Self.database()
        let matches = URLMatcher.matches(for: "https://login.example.com/signin", in: database)
        #expect(matches.map(\.entryID) == [ids["exact"], ids["host"], ids["domain"]])
        #expect(matches.map(\.quality) == [.exact, .sameHost, .sameDomain])
    }

    @Test func secondLevelSuffixesAndExtraURLs() throws {
        let (database, ids) = try Self.database()
        #expect(URLMatcher.matches(for: "https://www.example.co.uk", in: database).map(\.entryID) == [ids["uk"]])
        #expect(URLMatcher.matches(for: "https://example.net", in: database).map(\.entryID) == [ids["extra"]])
        #expect(URLMatcher.matches(for: "not a url", in: database).isEmpty)
        #expect(URLMatcher.registrableDomain("a.b.example.com") == "example.com")
    }
}

struct PasswordAuditTests {
    @Test func flagsWeakReusedOldAndExpired() throws {
        let now = Date(timeIntervalSince1970: 100_000_000)
        var database = Database.empty(name: "Test")
        func add(_ title: String, _ password: String, modified: Date = now, expiry: Date? = nil) throws -> UUID {
            var entry = Entry(times: Times(creation: modified, expiry: expiry))
            entry.title = title
            entry.password = SecretString(password)
            try database.add(entry, to: database.root.id)
            return entry.id
        }
        let weak = try add("weak", "password")
        let reusedA = try add("a", "Tr0ub4dor&3-horse-staple")
        let reusedB = try add("b", "Tr0ub4dor&3-horse-staple")
        let old = try add("old", "j8#Kd!2mQz@9vLp$Xw4", modified: now.addingTimeInterval(-400 * 86_400))
        let expired = try add("expired", "j8#Kd!2mQz@9vLp$Xw5", expiry: now.addingTimeInterval(-1))
        _ = try add("fine", "j8#Kd!2mQz@9vLp$Xw6")

        let results = PasswordAudit.run(on: database, at: now)
        let findings = Dictionary(uniqueKeysWithValues: results.map { ($0.entryID, $0) })
        #expect(findings.count == 5)
        #expect(findings[weak]?.issues == [.weak(bits: 0)])
        #expect(findings[reusedA]?.issues == [.reused(count: 2)])
        #expect(findings[reusedB]?.issues == [.reused(count: 2)])
        #expect(findings[old]?.issues == [.old(days: 400)])
        #expect(findings[expired]?.issues == [.expired])
    }

    @Test func strengthEstimates() {
        #expect(PasswordAudit.estimatedBits("") == 0)
        #expect(PasswordAudit.estimatedBits("aaaaaaaaaaaa") < 30)
        #expect(PasswordAudit.estimatedBits("abcdefgh") < PasswordAudit.estimatedBits("axkqpmwz"))
        #expect(PasswordAudit.estimatedBits("correct-horse-battery-staple") > 100)
    }
}
