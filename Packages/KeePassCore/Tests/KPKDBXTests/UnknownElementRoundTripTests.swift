import Foundation
import KDBXKit
import KPModel
import KPSession
import Testing

@testable import KPKDBX

/// XML elements KeePassIOS doesn't understand (written by other clients
/// or plugins) must survive opening, editing and saving in the app.
struct UnknownElementRoundTripTests {
    let codec = KDBXCodec()
    let key = CompositeKey(password: "unknown elements")

    @Test func unknownElementsSurviveAnEditAndSave() async throws {
        // A file whose entry, group, root and top level carry elements
        // from some other client.
        let marker = KDBX.UnknownElement(
            name: "XPluginData",
            attributes: [.init(name: "version", value: "2")],
            children: [.text("payload"), .element(.init(name: "Nested", children: [.text("inner")]))]
        )
        var content = KDBXContent.makeEmpty(databaseName: "Foreign", kdf: fastSettings.kdfParameters())
        var entry = KDBX.Entry(uuid: UUID(), strings: [.init(key: "Title", value: .regular("Mail"))])
        entry.unknownElements = [marker]
        var group = KDBX.Group(uuid: UUID(), name: "Work", entries: [entry])
        group.unknownElements = [marker]
        content.database.root.group.groups = [group]
        content.database.root.unknownElements = [marker]
        content.database.unknownElements = [marker]
        let output = OutputStream(toMemory: ())
        output.open()
        try KDBXWriter(to: output).write(content, unlockData: KDBXCodec.unlockData(for: key))
        output.close()
        let original = try #require(output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)

        // Open in the app's codec, edit the entry, save.
        var decoded = try await codec.decode(original, key: key, memoryLimit: nil)
        var mapped = try #require(decoded.database.root.groups.first?.entries.first)
        mapped.userName = "alice"
        decoded.database.root.groups[0].entries[0] = mapped
        let saved = try await codec.encode(
            decoded.database,
            settings: decoded.settings,
            key: key,
            context: decoded.context
        )

        // Every unknown element is still there.
        let reread = try KDBXReader.parse(saved, unlockData: KDBXCodec.unlockData(for: key))
        let savedGroup = try #require(reread.database.root.group.groups.first)
        let savedEntry = try #require(savedGroup.entries.first)
        #expect(savedEntry.strings.contains { $0.key == "UserName" && $0.value.revealedString == "alice" })
        #expect(savedEntry.unknownElements == [marker])
        #expect(savedGroup.unknownElements == [marker])
        #expect(reread.database.root.unknownElements == [marker])
        #expect(reread.database.unknownElements == [marker])
    }
}
