import Foundation
import KDBXKit

/// Stores KDBXKit's preserved unknown XML elements in KPModel `extras`
/// as JSON, so they ride along through edits and merges and are written
/// back on save.
enum UnknownElementCoding {
    private struct Element: Codable {
        let name: String
        let attributes: [[String]]
        let children: [Child]
    }

    private enum Child: Codable {
        case element(Element)
        case text(String)
    }

    static func encode(_ elements: [KDBX.UnknownElement]) -> String? {
        guard !elements.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(elements.map(element))).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    static func decode(_ text: String?) -> [KDBX.UnknownElement] {
        guard let text, let elements = try? JSONDecoder().decode([Element].self, from: Data(text.utf8)) else {
            return []
        }
        return elements.map(unknownElement)
    }

    private static func element(_ element: KDBX.UnknownElement) -> Element {
        Element(
            name: element.name,
            attributes: element.attributes.map { [$0.name, $0.value] },
            children: element.children.map { child in
                switch child {
                case .element(let nested): .element(self.element(nested))
                case .text(let text): .text(text)
                }
            }
        )
    }

    private static func unknownElement(_ element: Element) -> KDBX.UnknownElement {
        KDBX.UnknownElement(
            name: element.name,
            attributes: element.attributes.compactMap { pair in
                pair.count == 2 ? KDBX.UnknownElement.Attribute(name: pair[0], value: pair[1]) : nil
            },
            children: element.children.map { child in
                switch child {
                case .element(let nested): .element(unknownElement(nested))
                case .text(let text): .text(text)
                }
            }
        )
    }
}
