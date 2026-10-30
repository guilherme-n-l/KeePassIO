import Foundation
import KPAppState
import KPModel
import KPOTP
import KPSession

/// The demo database the screenshot UI test starts from (-UITest
/// -UITestDemoData). Made-up names only: no real services or brands.
extension AppModel {
    static let demoPassword = "correct horse battery"

    private struct DemoEntry {
        let title: String
        let userName: String
        let url: String
        let icon: Int
        var hasCode = false
    }

    private struct DemoGroup {
        let name: String
        let icon: Int
        let entries: [DemoEntry]
    }

    // Standard KeePass icon IDs, drawn with KeePassXC's artwork.
    private static let demoGroups = [
        DemoGroup(
            name: "Email",
            icon: 19,
            entries: [
                DemoEntry(
                    title: "Personal Email",
                    userName: "alex@example.com",
                    url: "https://mail.example.com",
                    icon: 19
                ),
                DemoEntry(
                    title: "Work Email",
                    userName: "alex.rivera@work.example",
                    url: "https://outlook.work.example",
                    icon: 25
                ),
            ]
        ),
        DemoGroup(
            name: "Banking",
            icon: 37,
            entries: [
                DemoEntry(
                    title: "Checking Account",
                    userName: "alex.rivera",
                    url: "https://bank.example.com",
                    icon: 66
                ),
                DemoEntry(title: "Credit Card", userName: "4111 •••• 1111", url: "https://card.example.com", icon: 37),
            ]
        ),
        DemoGroup(
            name: "Home",
            icon: 60,
            entries: [
                DemoEntry(title: "Wi-Fi", userName: "HomeNetwork", url: "", icon: 12),
                DemoEntry(title: "Router", userName: "admin", url: "http://192.168.1.1", icon: 3),
            ]
        ),
        DemoGroup(
            name: "Work",
            icon: 59,
            entries: [
                DemoEntry(title: "VPN", userName: "arivera", url: "https://vpn.work.example", icon: 29),
                DemoEntry(title: "Code Hosting", userName: "arivera", url: "https://code.work.example", icon: 58),
            ]
        ),
    ]

    private static let demoRootEntries = [
        DemoEntry(
            title: "Cloud Storage",
            userName: "alex@example.com",
            url: "https://cloud.example.com",
            icon: 27,
            hasCode: true
        ),
        DemoEntry(title: "Streaming", userName: "alex@example.com", url: "https://watch.example.com", icon: 18),
        DemoEntry(
            title: "Online Store",
            userName: "alex.rivera",
            url: "https://shop.example.com",
            icon: 47,
            hasCode: true
        ),
        DemoEntry(title: "Social Network", userName: "@alexrivera", url: "https://social.example.com", icon: 5),
    ]

    func seedDemoDatabase() async {
        guard let id = await createDatabase(name: "Personal", password: Self.demoPassword),
            let reference = databases.first(where: { $0.id == id })
        else { return }
        let session = session(for: reference)
        guard let rootID = session.database?.root.id else { return }
        do {
            for (index, demo) in Self.demoGroups.enumerated() {
                let group = KPModel.Group(name: demo.name, iconID: demo.icon)
                try session.addGroup(group, to: rootID)
                for entry in demo.entries {
                    try session.addEntry(
                        makeEntry(entry, seed: index * 10 + entry.title.count, in: session),
                        to: group.id
                    )
                }
            }
            for entry in Self.demoRootEntries {
                try session.addEntry(makeEntry(entry, seed: entry.title.count, in: session), to: rootID)
            }
            await save(session)
        } catch {
            errorMessage = String(localized: "Couldn't create the demo database.")
        }
    }

    private func makeEntry(_ demo: DemoEntry, seed: Int, in session: DatabaseSession) throws -> Entry {
        var entry = session.newEntry(
            title: demo.title,
            userName: demo.userName,
            password: SecretString(demoPassword(seed: seed))
        )
        entry.url = demo.url
        entry.iconID = demo.icon
        if demo.hasCode {
            let otp = try OTP(base32Secret: "JBSWY3DPEHPK3PXP", issuer: demo.title, account: demo.userName)
            entry.fields[OTP.FieldName.uri] = .protected(SecretString(otp.uri))
        }
        return entry
    }

    /// Plausible-looking passwords that are the same on every run.
    private func demoPassword(seed: Int) -> String {
        let words = ["Maple", "Orbit", "Quartz", "Harbor", "Lumen", "Cobalt", "Tundra", "Willow"]
        let symbols = Array("!#%&*+?@")
        let word = words[seed % words.count]
        let suffix = words[(seed + 3) % words.count].lowercased()
        return "\(word)\(seed * 37 % 90 + 10)\(symbols[seed % symbols.count])\(suffix)"
    }
}
