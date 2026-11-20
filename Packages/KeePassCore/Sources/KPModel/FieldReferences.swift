import Foundation

/// A KeePass field reference, `{REF:<Wanted>@<SearchIn>:<Text>}`: the
/// `Wanted` field of the first entry whose `SearchIn` field is `Text`.
/// KeePassXC writes `{REF:P@I:<uuid>}` when an entry is cloned with
/// references, so the clone's password follows the original's.
///
/// The format is KeePass's (keepass.info/help/base/fieldrefs.html);
/// resolution follows KeePassXC:
///
/// - `{REF:` is matched exactly; the field letters after it in any
///   case: T title, U user name, P
///   password, A URL, N notes, I UUID, and for `SearchIn` only, O any
///   field.
/// - `Text` is compared with the stored (unresolved) value, exactly and
///   case-sensitively; for I it is the UUID as 32 hex digits. Entries are
///   searched in tree order, the recycle bin included.
/// - The value found is resolved in turn, up to `maxDepth` references
///   deep; past that (a cycle, say) the last value is left as written.
/// - A reference no entry matches resolves to an empty string.
public struct FieldReference: Sendable, Equatable, Hashable {
    public enum Field: Character, Sendable, CaseIterable {
        case title = "T"
        case userName = "U"
        case password = "P"
        case url = "A"
        case notes = "N"
        case id = "I"
        /// Any field; only valid as the field searched in.
        case other = "O"

        init?(letter: Character) {
            guard let field = Field(rawValue: Character(letter.uppercased())) else { return nil }
            self = field
        }

        /// The standard field this letter names, if it names one.
        public var fieldName: String? {
            switch self {
            case .title: Entry.StandardField.title
            case .userName: Entry.StandardField.userName
            case .password: Entry.StandardField.password
            case .url: Entry.StandardField.url
            case .notes: Entry.StandardField.notes
            case .id, .other: nil
            }
        }

        init?(fieldName: String) {
            guard let field = Field.allCases.first(where: { $0.fieldName == fieldName }) else { return nil }
            self = field
        }
    }

    public var wanted: Field
    public var searchIn: Field
    public var searchText: String

    /// How many references deep a value is followed. KeePassXC's limit of
    /// 10 counts two levels per reference, so it follows five.
    public static let maxDepth = 5

    /// A reference to the standard field `fieldName` of the entry with
    /// `entryID`, as KeePassXC writes it. Nil for custom fields, which
    /// references can't name.
    public init?(to fieldName: String, of entryID: UUID) {
        guard let wanted = Field(fieldName: fieldName) else { return nil }
        self.wanted = wanted
        searchIn = .id
        searchText = Self.hex(entryID).uppercased()
    }

    /// The reference as it is stored in a field.
    public var text: String { "{REF:\(wanted.rawValue)@\(searchIn.rawValue):\(searchText)}" }

    /// The reference `text` consists of, if it is exactly one.
    public init?(exactly text: String) {
        guard let (reference, end) = Self.parse(text, at: text.startIndex), end == text.endIndex else { return nil }
        self = reference
    }

    /// True when `text` contains a field reference.
    public static func occurs(in text: String) -> Bool {
        var index = text.startIndex
        while let start = nextCandidate(in: text, from: index) {
            if parse(text, at: start) != nil { return true }
            index = text.index(after: start)
        }
        return false
    }

    /// UUIDs as references write them: 32 lowercase hex digits.
    static func hex(_ id: UUID) -> String {
        id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The UUID in a reference's search text. Like KeePassXC, characters
    /// that aren't hex digits (dashes, say) are skipped.
    static func uuid(fromHex text: String) -> UUID? {
        let digits = Array(text.filter(\.isHexDigit))
        guard digits.count == 32 else { return nil }
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }
        return UUID(uuidString: groups.joined(separator: "-"))
    }

    // MARK: Parsing

    private static let prefix = Array("{REF:")
    private static let prefixBytes = Array("{REF:".utf8)

    /// True when the UTF-8 `bytes` contain `{REF:`.
    static func mayStart(in bytes: some Collection<UInt8>) -> Bool {
        var index = bytes.startIndex
        while let brace = bytes[index...].firstIndex(of: prefixBytes[0]) {
            if bytes[brace...].starts(with: prefixBytes) { return true }
            index = bytes.index(after: brace)
        }
        return false
    }

    /// Where the next `{` that could start a reference is.
    static func nextCandidate(in text: String, from index: String.Index) -> String.Index? {
        text[index...].firstIndex(of: "{")
    }

    /// The reference starting at `start`, and the index just past it.
    static func parse(_ text: String, at start: String.Index) -> (FieldReference, end: String.Index)? {
        guard var (reference, textStart) = header(text, at: start),
            let close = searchTextEnd(text, from: textStart), close > textStart
        else { return nil }
        reference.searchText = String(text[textStart..<close])
        return (reference, text.index(after: close))
    }

    /// The fields of `{REF:<Wanted>@<SearchIn>:` at `start`, with no search
    /// text yet, and where the search text begins.
    private static func header(_ text: String, at start: String.Index) -> (FieldReference, String.Index)? {
        let characters = text[start...].prefix(prefix.count + 4)
        guard characters.count == prefix.count + 4, characters.starts(with: prefix) else { return nil }
        let rest = Array(characters.dropFirst(prefix.count))
        guard let wanted = Field(letter: rest[0]), wanted != .other, rest[1] == "@",
            let searchIn = Field(letter: rest[2]), rest[3] == ":"
        else { return nil }
        return (FieldReference(wanted: wanted, searchIn: searchIn, searchText: ""), characters.endIndex)
    }

    /// The `}` that ends a search text starting at `index`. The text may
    /// hold `{…}` groups (another placeholder) but no other closing brace,
    /// as in KeePassXC.
    private static func searchTextEnd(_ text: String, from start: String.Index) -> String.Index? {
        var index = start
        while index < text.endIndex {
            switch text[index] {
            case "}":
                return index
            case "{":
                guard let close = text[text.index(after: index)...].firstIndex(of: "}") else { return nil }
                index = text.index(after: close)
            default:
                index = text.index(after: index)
            }
        }
        return nil
    }

    init(wanted: Field, searchIn: Field, searchText: String) {
        self.wanted = wanted
        self.searchIn = searchIn
        self.searchText = searchText
    }
}

extension FieldValue {
    /// True when the value holds a field reference.
    var holdsReference: Bool {
        // Nearly no value does, so look for the prefix in place before
        // copying the value out to parse it.
        let found =
            switch self {
            case .plain(let text): FieldReference.mayStart(in: text.utf8)
            case .protected(let secret): secret.withBytes(FieldReference.mayStart)
            }
        return found && FieldReference.occurs(in: reveal())
    }
}

extension Entry {
    /// True when the field holds a reference to another entry.
    public func isReference(_ fieldName: String) -> Bool {
        fields[fieldName]?.holdsReference ?? false
    }

    /// True when any field holds a reference.
    public var hasReferences: Bool {
        fields.values.contains(where: \.holdsReference)
    }
}

extension Database {
    /// `entry` with the references in its fields replaced by the values
    /// they point to, for showing, copying and filling. Protected fields
    /// stay protected. Edit the stored entry, not this copy, or the
    /// references are lost.
    public func resolvingReferences(in entry: Entry) -> Entry {
        guard entry.hasReferences else { return entry }
        var resolved = entry
        for (name, value) in entry.fields where value.holdsReference {
            let result = resolveReferences(in: value.reveal(), depth: FieldReference.maxDepth)
            resolved.fields[name] = value.isProtected ? .protected(SecretString(result)) : .plain(result)
        }
        return resolved
    }

    /// `text` with each reference in it resolved.
    public func resolveReferences(in text: String) -> String {
        resolveReferences(in: text, depth: FieldReference.maxDepth)
    }

    private func resolveReferences(in text: String, depth: Int) -> String {
        guard depth > 0 else { return text }
        var result = ""
        var copied = text.startIndex
        var index = text.startIndex
        while let start = FieldReference.nextCandidate(in: text, from: index) {
            guard let (reference, end) = FieldReference.parse(text, at: start) else {
                index = text.index(after: start)
                continue
            }
            result += text[copied..<start]
            result += value(of: reference, depth: depth)
            copied = end
            index = end
        }
        result += text[copied...]
        return result
    }

    /// The entry whose stored password `entryID`'s password comes from.
    /// While an entry's password is exactly one reference to a password
    /// (`{REF:P@…}`), follow it to the entry it finds; stop at the first
    /// entry whose password is its own, at a reference that finds nothing,
    /// or on a cycle. KeePassXC saves a changed password there, so entries
    /// that refer to it keep showing the new one.
    public func passwordSource(of entryID: UUID) -> UUID {
        var current = entryID
        var visited: Set<UUID> = [entryID]
        while let password = entry(withID: current)?.fields[Entry.StandardField.password]?.reveal(),
            let reference = FieldReference(exactly: password), reference.wanted == .password
        {
            let searchText = resolveReferences(in: reference.searchText, depth: FieldReference.maxDepth - 1)
            guard let target = firstEntry(where: reference.searchIn, is: searchText),
                visited.insert(target.id).inserted
            else { break }
            current = target.id
        }
        return current
    }

    private func value(of reference: FieldReference, depth: Int) -> String {
        let searchText = resolveReferences(in: reference.searchText, depth: depth - 1)
        guard let target = firstEntry(where: reference.searchIn, is: searchText) else { return "" }
        switch reference.wanted {
        case .id:
            return FieldReference.hex(target.id)
        case .title, .userName, .password, .url, .notes:
            let raw = reference.wanted.fieldName.flatMap { target.fields[$0]?.reveal() } ?? ""
            return resolveReferences(in: raw, depth: depth - 1)
        case .other:
            return ""
        }
    }

    /// The first entry in tree order whose `field` is exactly `text`.
    private func firstEntry(where field: FieldReference.Field, is text: String) -> Entry? {
        let id: UUID?
        if field == .id {
            guard let parsed = FieldReference.uuid(fromHex: text) else { return nil }
            id = parsed
        } else {
            id = nil
        }
        var found: Entry?
        root.forEachGroup { group, _ in
            guard found == nil else { return }
            found = group.entries.first { entry in
                switch field {
                case .id: entry.id == id
                case .other: entry.fields.values.contains { $0.reveal() == text }
                default: field.fieldName.map { (entry.fields[$0]?.reveal() ?? "") == text } ?? false
                }
            }
        }
        return found
    }
}
