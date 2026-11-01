//
// Copyright (c) 2025, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing

@testable import KDBXKit

@Suite("Large XML documents")
struct LargeXMLDocumentTests {
    /// A vault with a few thousand entries and history produces more than 10 MB
    /// of XML. On Linux the data-backed parser reported a malformed document at
    /// that size even though the input was well-formed, which made large
    /// databases impossible to reopen; this pins the stream-backed path that
    /// parses them.
    @Test func parsesDocumentsLargerThanTenMegabytes() throws {
        let entryCount = 160_000
        var parts: [String] = [
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n",
            "<KeePassFile><Root><Group><Name>Root</Name>\n",
        ]
        parts.reserveCapacity(entryCount + 3)
        for index in 0..<entryCount {
            parts.append("<Entry><String><Key>Title</Key><Value>Entry \(index)</Value></String></Entry>\n")
        }
        parts.append("</Group></Root></KeePassFile>\n")
        let xml = parts.joined()

        #expect(xml.utf8.count > 10 * 1024 * 1024)

        let document = try Document(string: xml)
        let root = try #require(document.root)
        #expect(root.name == "KeePassFile")

        let rootElement = try #require(root.children(ofKind: .element).first)
        let group = try #require(rootElement.children(ofKind: .element).first)
        let entries = group.children(ofKind: .element).filter { $0.name == "Entry" }
        #expect(entries.count == entryCount)
    }

    /// The tree must not hold indentation, but a value that is really just
    /// spaces is content and has to survive a parse.
    @Test(arguments: [
        ("<a>   </a>", ["   "]),
        ("<a>\n\t </a>", ["\n\t "]),
        ("<a> <![CDATA[  ]]> </a>", ["    "]),
        ("<a> <!-- comment --> </a>", ["  "]),
        ("<a></a>", []),
        ("<a> <![CDATA[x]]> </a>", [" x "]),
    ])
    func keepsTextOfElementsWithoutElementChildren(xml: String, expected: [String]) throws {
        let root = try #require(try Document(string: xml).root)
        #expect(root.children.map(\.value) == expected)
    }

    @Test func dropsIndentationAroundElementChildren() throws {
        let root = try #require(try Document(string: "<a>\n  <b>  </b>\n  <c/>\n</a>").root)
        #expect(root.children.map(\.name) == ["b", "c"])
        #expect(root.children[0].children.map(\.value) == ["  "])
        #expect(root.children[1].children.isEmpty)
    }

    @Test func keepsNonWhitespaceTextBesideElementChildren() throws {
        let root = try #require(try Document(string: "<a> x <b/>  <c/> y </a>").root)
        let text = root.children(ofKind: .text).map(\.value)
        #expect(text == [" x ", " y "])
        #expect(root.children(ofKind: .element).map(\.name) == ["b", "c"])
    }
}
