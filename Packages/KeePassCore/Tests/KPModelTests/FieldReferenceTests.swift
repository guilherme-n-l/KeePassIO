import Foundation
import Testing

@testable import KPModel

struct FieldReferenceTests {
    struct Fixture {
        var database: Database
        let original: Entry
    }

    /// A database with one entry, "Original", that others can refer to.
    func makeFixture() throws -> Fixture {
        var database = Database.empty(name: "Test")
        var original = Entry()
        original.title = "Original"
        original.userName = "alice"
        original.password = "hunter2"
        original.url = "https://example.com"
        original.notes = "Some notes"
        original.fields["Account"] = .plain("12345")
        try database.add(original, to: database.root.id)
        return Fixture(database: database, original: original)
    }

    func addEntry(_ database: inout Database, title: String, _ fields: [String: FieldValue]) throws -> Entry {
        var entry = Entry(fields: fields)
        entry.title = title
        try database.add(entry, to: database.root.id)
        return entry
    }

    @Test func buildsReferencesAsKeePassXCWritesThem() throws {
        let id = try #require(UUID(uuidString: "0123ABCD-4567-89EF-0123-456789ABCDEF"))
        #expect(FieldReference(to: "Password", of: id)?.text == "{REF:P@I:0123ABCD456789EF0123456789ABCDEF}")
        #expect(FieldReference(to: "UserName", of: id)?.text == "{REF:U@I:0123ABCD456789EF0123456789ABCDEF}")
        #expect(FieldReference(to: "URL", of: id)?.text == "{REF:A@I:0123ABCD456789EF0123456789ABCDEF}")
        #expect(FieldReference(to: "Custom", of: id) == nil)
    }

    @Test func resolvesEveryWantedFieldByUUID() throws {
        let fixture = try makeFixture()
        let database = fixture.database
        let id = fixture.original.id
        func resolve(_ letter: String) -> String {
            database.resolveReferences(in: "{REF:\(letter)@I:\(FieldReference.hex(id))}")
        }
        #expect(resolve("T") == "Original")
        #expect(resolve("U") == "alice")
        #expect(resolve("P") == "hunter2")
        #expect(resolve("A") == "https://example.com")
        #expect(resolve("N") == "Some notes")
        #expect(resolve("I") == FieldReference.hex(id))
    }

    @Test func resolvesAnEntrysFieldsAndKeepsProtection() throws {
        var fixture = try makeFixture()
        let id = fixture.original.id
        let clone = try addEntry(
            &fixture.database,
            title: "Clone",
            [
                "UserName": .plain(try #require(FieldReference(to: "UserName", of: id)).text),
                "Password": .protected(SecretString(try #require(FieldReference(to: "Password", of: id)).text)),
            ]
        )

        let resolved = fixture.database.resolvingReferences(in: clone)
        #expect(resolved.userName == "alice")
        #expect(resolved.password.reveal() == "hunter2")
        #expect(resolved.fields["Password"]?.isProtected == true)
        #expect(resolved.title == "Clone")
        #expect(clone.isReference("Password"))
        #expect(!clone.isReference("Title"))
        #expect(!resolved.hasReferences)
    }

    @Test func searchesInEachField() throws {
        let database = try makeFixture().database
        #expect(database.resolveReferences(in: "{REF:P@T:Original}") == "hunter2")
        #expect(database.resolveReferences(in: "{REF:P@U:alice}") == "hunter2")
        #expect(database.resolveReferences(in: "{REF:T@P:hunter2}") == "Original")
        #expect(database.resolveReferences(in: "{REF:T@A:https://example.com}") == "Original")
        #expect(database.resolveReferences(in: "{REF:T@N:Some notes}") == "Original")
        #expect(database.resolveReferences(in: "{REF:T@O:12345}") == "Original")
    }

    @Test func searchTextMatchesExactlyAndCaseSensitively() throws {
        let database = try makeFixture().database
        #expect(database.resolveReferences(in: "{REF:P@T:original}") == "")
        #expect(database.resolveReferences(in: "{REF:P@T:Orig}") == "")
    }

    /// As in KeePassXC: the letters in any case, `{REF:` only in capitals.
    @Test func lettersAreCaseInsensitiveButThePrefixIsNot() throws {
        let database = try makeFixture().database
        #expect(database.resolveReferences(in: "{REF:p@t:Original}") == "hunter2")
        #expect(database.resolveReferences(in: "{ref:p@t:Original}") == "{ref:p@t:Original}")
        #expect(database.resolveReferences(in: "{Ref:P@T:Original}") == "{Ref:P@T:Original}")
    }

    @Test func uuidSearchAcceptsAnyCaseAndDashes() throws {
        let fixture = try makeFixture()
        let id = fixture.original.id
        #expect(fixture.database.resolveReferences(in: "{REF:U@I:\(id.uuidString)}") == "alice")
        #expect(fixture.database.resolveReferences(in: "{REF:U@I:\(FieldReference.hex(id).uppercased())}") == "alice")
        #expect(fixture.database.resolveReferences(in: "{REF:U@I:1234}") == "")
    }

    @Test func replacesReferencesInsideOtherText() throws {
        let database = try makeFixture().database
        #expect(
            database.resolveReferences(in: "user {REF:U@T:Original}, pass {REF:P@T:Original}!")
                == "user alice, pass hunter2!"
        )
    }

    @Test func leavesTextThatIsNotAReferenceAlone() throws {
        let database = try makeFixture().database
        for text in [
            "plain", "{", "}", "{REF:", "{REF:P@T:}", "{REF:X@T:Original}", "{REF:O@T:Original}",
            "{REF:P@T:Original", "{TITLE}", "{S:Account}",
        ] {
            #expect(database.resolveReferences(in: text) == text)
            #expect(!FieldReference.occurs(in: text))
        }
    }

    @Test func missingTargetResolvesToEmpty() throws {
        let database = try makeFixture().database
        #expect(database.resolveReferences(in: "a{REF:P@T:Nobody}b") == "ab")
    }

    @Test func followsChainsOfReferences() throws {
        var fixture = try makeFixture()
        func passwordReference(to id: UUID) throws -> FieldValue {
            .protected(SecretString(try #require(FieldReference(to: "Password", of: id)).text))
        }
        let first = try addEntry(
            &fixture.database,
            title: "First",
            ["Password": try passwordReference(to: fixture.original.id)]
        )
        let second = try addEntry(&fixture.database, title: "Second", ["Password": try passwordReference(to: first.id)])
        #expect(fixture.database.resolvingReferences(in: second).password.reveal() == "hunter2")
    }

    @Test func cyclesStopAtTheDepthLimit() throws {
        var database = Database.empty(name: "Test")
        let a = try addEntry(&database, title: "A", ["UserName": .plain("{REF:U@T:B}")])
        _ = try addEntry(&database, title: "B", ["UserName": .plain("{REF:U@T:A}")])
        let c = try addEntry(&database, title: "C", ["UserName": .plain("{REF:U@T:A}")])
        // Five hops, then the value reached is shown as stored: A, B, A,
        // B, A, B for A. keepassxc-cli shows the same.
        #expect(database.resolvingReferences(in: a).userName == "{REF:U@T:A}")
        #expect(database.resolvingReferences(in: c).userName == "{REF:U@T:B}")
    }

    @Test func searchTextCanItselfBeAReference() throws {
        var fixture = try makeFixture()
        _ = try addEntry(&fixture.database, title: "Pointer", ["UserName": .plain("Original")])
        #expect(fixture.database.resolveReferences(in: "{REF:P@T:{REF:U@T:Pointer}}") == "hunter2")
    }

    @Test func firstEntryInTreeOrderWins() throws {
        var database = Database.empty(name: "Test")
        let sub = Group(name: "Sub")
        try database.add(sub, to: database.root.id)
        var nested = Entry()
        nested.title = "Same"
        nested.userName = "nested"
        try database.add(nested, to: sub.id)
        var top = Entry()
        top.title = "Same"
        top.userName = "top"
        try database.add(top, to: database.root.id)
        // The root group's own entries come before its subgroups'.
        #expect(database.resolveReferences(in: "{REF:U@T:Same}") == "top")
    }

    @Test func entriesInTheRecycleBinCanBeReferenced() throws {
        var fixture = try makeFixture()
        try fixture.database.deleteEntry(fixture.original.id)
        #expect(fixture.database.recycleBin?.entries.contains { $0.id == fixture.original.id } == true)
        #expect(fixture.database.resolveReferences(in: "{REF:P@T:Original}") == "hunter2")
    }
}
