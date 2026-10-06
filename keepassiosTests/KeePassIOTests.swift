import Foundation
import Testing

@testable import keepassios

struct KeePassIOTests {
    @Test func displayNameIsKeePassIO() {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(displayName == "KeePassIO")
    }
}
