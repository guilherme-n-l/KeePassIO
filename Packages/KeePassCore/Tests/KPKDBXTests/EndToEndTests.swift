import Foundation
import KPMerge
import KPModel
import KPOTP
import KPSearch
import KPSession
import Testing

@testable import KPKDBX

/// Whole-app flows below the UI: real KDBX files on disk, the real codec
/// and DatabaseSession, and (when installed) KeePassXC editing the same
/// file in between, the way a desktop client on a synced folder would.
@MainActor
struct EndToEndTests {
    let directory: URL
    let key = CompositeKey(password: "end to end password")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("E2E-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func session(_ name: String = "vault") -> DatabaseSession {
        DatabaseSession(
            file: LocalDatabaseFile(url: directory.appendingPathComponent("\(name).kdbx")),
            codec: KDBXCodec()
        )
    }

    @Test func createUseLockAndReopen() async throws {
        // Create a database and fill it the way a user would.
        let app = session()
        try await app.create(name: "Personal", key: key, settings: fastSettings)
        let work = Group(name: "Work")
        try app.addGroup(work)

        var mail = app.newEntry(title: "Mail", userName: "alice@example.com", password: "first password")
        mail.url = "https://mail.example.com"
        mail.fields["otp"] = .protected("otpauth://totp/Mail:alice?secret=JBSWY3DPEHPK3PXP")
        try app.addEntry(mail, to: work.id)
        try app.addEntry(app.newEntry(title: "Bank", userName: "alice", password: "bank password"))
        try await app.save()

        // Edit: the old password goes to history.
        var edited = try #require(app.database?.entry(withID: mail.id))
        edited.password = "second password"
        try app.updateEntry(edited)
        try await app.save()

        // Delete goes to the recycle bin and out of search.
        let bank = try #require(app.searchIndex?.search("bank").first)
        try app.deleteEntry(bank.entryID)
        try await app.save()
        #expect(app.searchIndex?.search("bank").isEmpty == true)

        app.lock()
        #expect(app.database == nil)

        // Reopen from disk with a fresh session.
        let reopened = session()
        await reopened.unlock(with: CompositeKey(password: "wrong"))
        #expect(reopened.state == .failed(.invalidKey))
        await reopened.unlock(with: key)
        #expect(reopened.state == .unlocked)

        let database = try #require(reopened.database)
        let stored = try #require(database.entry(withID: mail.id))
        #expect(stored.password.reveal() == "second password")
        #expect(stored.history.map { $0.password.reveal() } == ["first password"])
        #expect(database.location(ofEntry: mail.id)?.parentID == work.id)
        #expect(database.recycleBin?.entries.map(\.title) == ["Bank"])
        #expect(reopened.searchIndex?.search("mail").map(\.title) == ["Mail"])
        #expect(URLMatcher.matches(for: "https://mail.example.com/inbox", in: database).first?.entryID == mail.id)

        let otp = try #require(try OTP(fields: stored.fields.mapValues { $0.reveal() }))
        #expect(otp.code(at: Date(timeIntervalSince1970: 0)) == "282760")
    }

    @Test func twoDevicesEditingTheSameFileMerge() async throws {
        let phone = session()
        try await phone.create(name: "Shared", key: key, settings: fastSettings)
        let shared = phone.newEntry(title: "Wi-Fi", userName: "home", password: "router-1")
        try phone.addEntry(shared)
        try await phone.save()

        let tablet = session()
        await tablet.unlock(with: key)

        // Both edit different fields of the same entry, and each adds one.
        var onPhone = try #require(phone.database?.entry(withID: shared.id))
        onPhone.notes = "Edited on phone"
        try phone.updateEntry(onPhone)
        try phone.addEntry(phone.newEntry(title: "Phone only"))

        var onTablet = try #require(tablet.database?.entry(withID: shared.id))
        onTablet.password = "router-2"
        try tablet.updateEntry(onTablet)
        try tablet.addEntry(tablet.newEntry(title: "Tablet only"))

        try await tablet.save()
        try await phone.save()  // file changed underneath: merges first

        let report = try #require(phone.lastMergeReport)
        #expect(report.conflicts.isEmpty)

        let check = session()
        await check.unlock(with: key)
        let database = try #require(check.database)
        let merged = try #require(database.entry(withID: shared.id))
        #expect(merged.notes == "Edited on phone")
        #expect(merged.password.reveal() == "router-2")
        #expect(Set(database.activeEntries.map(\.title)) == ["Wi-Fi", "Phone only", "Tablet only"])
    }

    @Test(.enabled(if: KeePassXC.path != nil, "keepassxc-cli is not installed"))
    func keePassXCEditsWhileTheAppHasTheFileOpen() async throws {
        let app = session()
        try await app.create(name: "Synced", key: key, settings: fastSettings)
        try app.addEntry(app.newEntry(title: "Mail", userName: "alice", password: "one"))
        try await app.save()
        let file = directory.appendingPathComponent("vault.kdbx").path
        let password = key.password?.reveal() ?? ""

        // While the app has the database open, KeePassXC (say, on a laptop
        // syncing the same file) adds an entry and changes a password.
        _ = try KeePassXC.run(["add", "-u", "bob", "-p", file, "Laptop entry"], input: "\(password)\nlaptop secret")
        _ = try KeePassXC.run(["edit", "-p", file, "Mail"], input: "\(password)\nchanged on laptop")

        // Meanwhile the app adds its own entry, then saves.
        try app.addEntry(app.newEntry(title: "Phone entry", userName: "carol", password: "phone secret"))
        try await app.save()

        // Everything is in the file, and KeePassXC can still read it.
        let titles = try KeePassXC.run(["ls", "-R", "-f", file], input: password)
            .split(separator: "\n").map { String($0) }
        #expect(Set(titles).isSuperset(of: ["Mail", "Laptop entry", "Phone entry"]))
        let mailPassword = try KeePassXC.run(["show", "-s", "-a", "Password", file, "Mail"], input: password)
        #expect(mailPassword == "changed on laptop")
        let phonePassword = try KeePassXC.run(["show", "-s", "-a", "Password", file, "Phone entry"], input: password)
        #expect(phonePassword == "phone secret")
    }
}
