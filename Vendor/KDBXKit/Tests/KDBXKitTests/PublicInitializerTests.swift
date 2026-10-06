//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing

import KDBXKit

/// Not `@testable`: the initializer must be usable by library clients.
struct PublicInitializerTests {
    @Test func publicInitializer() {
        let item = KDBX.CustomDataItem(key: "KeePassIOS_Example", value: "1")
        #expect(item.key == "KeePassIOS_Example")
        #expect(item.value == "1")
    }

    @Test func autoTypeAssociationInitializer() {
        let association = KDBX.AutoType.Association(window: "*Firefox*", keystrokeSequence: "{USERNAME}{TAB}")
        #expect(association.window == "*Firefox*")
        #expect(association.keystrokeSequence == "{USERNAME}{TAB}")
    }
}
