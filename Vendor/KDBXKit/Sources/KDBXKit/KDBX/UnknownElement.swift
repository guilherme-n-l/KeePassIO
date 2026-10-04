//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

public extension KDBX {
    /// An XML element KDBXKit doesn't model, kept verbatim so saving the
    /// vault doesn't lose it.
    ///
    /// Other clients, plugins and newer revisions of the format add
    /// elements this library doesn't know about. The reader keeps every
    /// unrecognized child of `KeePassFile`, `Meta`, `Root`, `Group` and
    /// `Entry` as an `UnknownElement` (and still notes it in
    /// ``KDBXContent/parserWarnings``); the writer emits them again after
    /// the known children of the same parent, in their original order.
    ///
    /// The subtree is stored as plain XML: element names, attributes and
    /// text are carried over unchanged. A value inside an unknown element
    /// that is marked `Protected="True"` is written back as the same
    /// ciphertext; KeePass and KeePassXC skip unknown elements without
    /// touching the inner-stream keystream, and so does this library, so
    /// that ciphertext doesn't affect any other protected value.
    struct UnknownElement: Sendable, Equatable {
        /// An attribute on an ``UnknownElement``.
        public struct Attribute: Sendable, Equatable {
            public var name: String
            public var value: String

            public init(name: String, value: String) {
                self.name = name
                self.value = value
            }
        }

        /// A child node of an ``UnknownElement``: a nested element or a
        /// run of text.
        public enum Child: Sendable, Equatable {
            case element(UnknownElement)
            case text(String)
        }

        /// The element's tag name.
        public var name: String

        /// The element's attributes. The XML parser doesn't report source
        /// order, so a parsed element lists them sorted by name.
        public var attributes: [Attribute]

        /// Nested elements and text, in document order.
        public var children: [Child]

        public init(
            name: String,
            attributes: [Attribute] = [],
            children: [Child] = []
        ) {
            self.name = name
            self.attributes = attributes
            self.children = children
        }
    }
}

extension KDBX.UnknownElement {
    /// Copies an element subtree out of a parsed document.
    init(_ node: Node) {
        self.init(
            name: node.name,
            attributes: node.attributes.map { Attribute(name: $0.name, value: $0.value) },
            children: node.children.map { child in
                switch child.kind {
                case .element:
                    .element(KDBX.UnknownElement(child))
                case .text:
                    .text(child.value)
                }
            }
        )
    }

    /// Appends this element, with its whole subtree, as the last child of
    /// `parent`.
    func append(to parent: Node) {
        let node = parent.addElement(name)
        node.attributes = attributes.map { (name: $0.name, value: $0.value) }
        for child in children {
            switch child {
            case let .element(element):
                element.append(to: node)
            case let .text(text):
                node.addText(text)
            }
        }
    }
}
