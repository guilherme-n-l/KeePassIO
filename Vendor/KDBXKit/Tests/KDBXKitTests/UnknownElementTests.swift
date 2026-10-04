//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import KDBXKit

/// Elements this library doesn't model (written by other clients, plugins
/// or newer format revisions) must survive a read → write cycle instead of
/// being dropped on save.
@Suite("Unknown XML elements are preserved")
struct UnknownElementTests {
    private static let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <KeePassFile>
            <Meta>
                <Generator>OtherClient</Generator>
                <FutureMetaSetting Mode="strict">42</FutureMetaSetting>
            </Meta>
            <Root>
                <Group>
                    <UUID>AAAAAAAAAAAAAAAAAAAAAA==</UUID>
                    <Name>Root</Name>
                    <Entry>
                        <UUID>BBBBBBBBBBBBBBBBBBBBBA==</UUID>
                        <String>
                            <Key>Title</Key>
                            <Value>Example</Value>
                        </String>
                        <PluginData Version="2" Vendor="Acme">
                            <Field Name="a">one &amp; two</Field>
                            <Field Name="b"/>
                            <Nested><Deeper>x</Deeper></Nested>
                        </PluginData>
                        <History>
                            <Entry>
                                <UUID>BBBBBBBBBBBBBBBBBBBBBA==</UUID>
                                <HistoryExtra>old</HistoryExtra>
                            </Entry>
                        </History>
                    </Entry>
                    <GroupExtra/>
                </Group>
                <RootExtra>r</RootExtra>
            </Root>
            <TopLevelExtra Kind="test"><Item>1</Item><Item>2</Item></TopLevelExtra>
        </KeePassFile>
        """

    private static func mockKeystream() -> KeystreamSource {
        KeystreamSource(
            algorithm: .chacha20,
            key: SecureBytes(Data(repeating: 0, count: 32)),
            nonce: Data(repeating: 0, count: 12)
        )
    }

    private static func write(_ database: KDBX) throws -> String {
        let innerHeader = InnerHeader(
            encryptionAlgorithm: .ChaCha20,
            encryptionKey: Data(repeating: 0x42, count: 64),
            binaryContent: []
        )
        let outputStream = OutputStream(toMemory: ())
        outputStream.open()
        try XMLDocumentWriter(to: outputStream, encryptor: try innerHeader.makeEncryptor()).write(database)
        let data = try #require(outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
        return try #require(String(validating: data, as: UTF8.self))
    }

    private static let pluginData = KDBX.UnknownElement(
        name: "PluginData",
        attributes: [
            .init(name: "Vendor", value: "Acme"),
            .init(name: "Version", value: "2"),
        ],
        children: [
            .element(.init(
                name: "Field",
                attributes: [.init(name: "Name", value: "a")],
                children: [.text("one & two")]
            )),
            .element(.init(name: "Field", attributes: [.init(name: "Name", value: "b")])),
            .element(.init(
                name: "Nested",
                children: [.element(.init(name: "Deeper", children: [.text("x")]))]
            )),
        ]
    )

    @Test("Reader keeps unknown children of KeePassFile, Meta, Root, Group and Entry")
    func readerPreservesUnknownElements() throws {
        let reader = try XMLDocumentReader(xmlDocument: Self.xml, keystreamSource: Self.mockKeystream())
        let database = try reader.parse()

        #expect(database.unknownElements == [
            .init(
                name: "TopLevelExtra",
                attributes: [.init(name: "Kind", value: "test")],
                children: [
                    .element(.init(name: "Item", children: [.text("1")])),
                    .element(.init(name: "Item", children: [.text("2")])),
                ]
            ),
        ])
        #expect(database.meta.generator == "OtherClient")
        #expect(database.meta.unknownElements == [
            .init(
                name: "FutureMetaSetting",
                attributes: [.init(name: "Mode", value: "strict")],
                children: [.text("42")]
            ),
        ])
        #expect(database.root.unknownElements == [.init(name: "RootExtra", children: [.text("r")])])
        #expect(database.root.group.unknownElements == [.init(name: "GroupExtra")])

        let entry = try #require(database.root.group.entries.first)
        #expect(entry.unknownElements == [Self.pluginData])
        #expect(entry.history.first?.unknownElements == [.init(name: "HistoryExtra", children: [.text("old")])])

        // Preserved elements are still reported, so a caller can tell the
        // file uses something this library doesn't model.
        let warnings = reader.collectedWarnings
        #expect(warnings.count == 6)
        #expect(warnings.allSatisfy { $0.hasPrefix("Preserved unknown element") })
        #expect(warnings.contains { $0.hasSuffix("PluginData") })
    }

    @Test("Writer emits preserved elements after the known children, and they read back unchanged")
    func writerEmitsUnknownElements() throws {
        let reader = try XMLDocumentReader(xmlDocument: Self.xml, keystreamSource: Self.mockKeystream())
        let database = try reader.parse()

        let written = try Self.write(database)
        #expect(written.contains(#"<PluginData Vendor="Acme" Version="2">"#))
        #expect(written.contains(#"<Field Name="a">one &amp; two</Field>"#))
        #expect(written.contains(#"<Field Name="b"/>"#))
        #expect(written.contains(#"<FutureMetaSetting Mode="strict">42</FutureMetaSetting>"#))

        // Each one goes after the known children of its parent.
        func offset(of needle: String) throws -> String.Index {
            try #require(written.range(of: needle)).lowerBound
        }
        #expect(try offset(of: "<Generator>") < offset(of: "<FutureMetaSetting"))
        #expect(try offset(of: "</History>") < offset(of: "<PluginData"))
        #expect(try offset(of: "</Entry>\n\t\t\t<GroupExtra/>") > offset(of: "<PluginData"))
        #expect(try offset(of: "</Group>\n\t\t<RootExtra>r</RootExtra>\n\t</Root>") > offset(of: "<GroupExtra/>"))
        #expect(try offset(of: "</Root>\n\t<TopLevelExtra") > offset(of: "<RootExtra>"))

        let reparsed = try XMLDocumentReader(xmlDocument: written, keystreamSource: Self.mockKeystream()).parse()
        #expect(reparsed == database)
    }

    @Test("Unknown elements survive a full KDBX save through both writer paths")
    func kdbxRoundTrip() throws {
        let unlock = UnlockData(masterPassword: "123")
        var content = KDBXContent.makeEmpty(
            databaseName: "Unknowns",
            kdf: .aes(.init(salt: Data(repeating: 7, count: 32), rounds: 1), additional: [:])
        )
        content.database.unknownElements = [.init(name: "TopLevelExtra", children: [.text("t")])]
        content.database.meta.unknownElements = [.init(name: "FutureMetaSetting", children: [.text("42")])]
        content.database.root.unknownElements = [.init(name: "RootExtra")]
        content.database.root.group.unknownElements = [.init(name: "GroupExtra")]
        content.database.root.group.entries = [
            KDBX.Entry(
                uuid: UUID(),
                strings: [
                    .init(key: "Title", value: .regular("First")),
                    .init(key: "Password", value: .unprotected("one")),
                ],
                unknownElements: [Self.pluginData]
            ),
            // A protected value after the unknown subtree checks that the
            // inner-stream keystream stays in step.
            KDBX.Entry(
                uuid: UUID(),
                strings: [
                    .init(key: "Title", value: .regular("Second")),
                    .init(key: "Password", value: .unprotected("two")),
                ]
            ),
        ]

        // Eager writer.
        let outputStream = OutputStream(toMemory: ())
        outputStream.open()
        try KDBXWriter(to: outputStream).write(content, unlockData: unlock)
        let eagerData = try #require(outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)

        // Streaming writer.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdbxkit-unknown-\(UUID().uuidString).kdbx")
        defer { try? FileManager.default.removeItem(at: url) }
        try KDBXWriter.streamingWrite(to: url, content: content, binaries: [], unlockData: unlock)
        let streamedData = try Data(contentsOf: url)

        for data in [eagerData, streamedData] {
            let reread = try KDBXReader.parse(data, unlockData: unlock).database
            #expect(reread.unknownElements == content.database.unknownElements)
            #expect(reread.meta.unknownElements == content.database.meta.unknownElements)
            #expect(reread.root.unknownElements == content.database.root.unknownElements)
            #expect(reread.root.group.unknownElements == content.database.root.group.unknownElements)
            #expect(reread.root.group.entries.map(\.unknownElements) == [[Self.pluginData], []])

            let passwords = reread.root.group.entries.map { entry in
                entry.strings.first { $0.key == "Password" }?.value.bytes.withRevealedString { $0 }
            }
            #expect(passwords == ["one", "two"])
        }
    }
}
