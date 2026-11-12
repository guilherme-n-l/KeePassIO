import Foundation
import Testing

@testable import KPModel

struct AppLinksTests {
    @Test func appIDsComeFromNumberedFieldsInOrder() {
        var entry = Entry()
        entry.fields["iOSApp_2"] = .plain("com.example.third")
        entry.fields["iOSApp"] = .plain("ABCDE12345.com.example.first")
        entry.fields["iOSApp_1"] = .plain(" com.example.second ")
        entry.fields["iOSApp_10"] = .plain("com.example.eleventh")
        entry.fields["iOSApp_x"] = .plain("not an app field")
        entry.fields["iOSApp_3"] = .plain("  ")
        #expect(
            entry.iOSAppIDs == [
                "ABCDE12345.com.example.first", "com.example.second", "com.example.third", "com.example.eleventh",
            ]
        )
    }

    @Test func androidPackagesComeFromFieldsAndAndroidAppURLs() {
        var entry = Entry()
        entry.fields["AndroidApp"] = .plain("br.com.example.passageiro")
        entry.url = "androidapp://com.example.fromurl"
        entry.fields["KP2A_URL_1"] = .plain("androidapp://com.example.fromextra")
        entry.fields["KP2A_URL_2"] = .plain("https://example.com")
        #expect(
            Set(entry.androidAppIDs) == ["br.com.example.passageiro", "com.example.fromurl", "com.example.fromextra"]
        )
    }

    @Test func linkingAddsTheNextFreeFieldOnce() {
        var entry = Entry()
        let first = entry.linkApp("ABCDE12345.com.example.one")
        #expect(first)
        #expect(entry.fields["iOSApp"] == .plain("ABCDE12345.com.example.one"))
        // The same app, with or without the team ID, isn't linked twice.
        let again = entry.linkApp("com.example.one")
        let blank = entry.linkApp("  ")
        #expect(!again && !blank)
        let second = entry.linkApp("com.example.two")
        #expect(second)
        #expect(entry.fields["iOSApp_1"] == .plain("com.example.two"))
        #expect(entry.iOSAppIDs == ["ABCDE12345.com.example.one", "com.example.two"])
    }

    @Test func bundleIDDropsOnlyATeamID() {
        #expect(AppID.bundleID(of: "ABCDE12345.com.example.app") == "com.example.app")
        #expect(AppID.bundleID(of: "com.example.app") == "com.example.app")
        // Ten characters, but not a team ID (lowercase).
        #expect(AppID.bundleID(of: "abcdefghij.example.app") == "abcdefghij.example.app")
        #expect(AppID.same("ABCDE12345.com.Example.App", "com.example.app"))
        #expect(!AppID.same("com.example.app", "com.example.other"))
    }

    @Test func appFieldNames() {
        for name in ["iOSApp", "iosapp", "iOSApp_1", "iOSApp_12", "AndroidApp", "ANDROIDAPP_2"] {
            #expect(Entry.isAppField(name), "\(name)")
        }
        for name in ["iOSApp_", "iOSApp_x", "iOSApps", "AndroidAppName", "URL", "KP2A_URL_1"] {
            #expect(!Entry.isAppField(name), "\(name)")
        }
    }
}
