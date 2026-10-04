import Foundation
import Testing

@testable import keepassios

struct KeePassIOSTests {
    @Test func displayNameIsKeePassIOS() {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(displayName == "KeePassIOS")
    }
}
