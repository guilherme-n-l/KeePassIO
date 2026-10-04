import Foundation
import KPModel
import KPObservability

/// An in-memory search index over a database's entries, built after
/// unlock and rebuilt after edits.
///
/// The query language follows KeePassXC's:
///
/// - Words are matched anywhere in a field ("mail" finds "Gmail"),
///   ignoring case and diacritics; every word must match.
/// - `"quoted phrases"` match as one term.
/// - `field:term` limits a term to one field: `title`/`t`,
///   `username`/`user`/`u`, `url`, `notes`/`n`, `tag`/`tags`,
///   `group`/`g`, `attribute`/`attr` (non-protected custom fields),
///   `attachment`/`attach`/`a`, and `is:expired`.
/// - `-term` (or `!term`) excludes entries that match; `+term` must match
///   a whole field exactly; `*term` is a regular expression; `*` and `?`
///   inside a term are wildcards.
///
/// On top of that, a term with slashes is a path: `mail/acc` finds the
/// entry "acc" in group "gmail", each part matching a group or the title
/// in order, as `g:personal/gmail` does for groups.
///
/// Protected fields (passwords, protected custom fields) are never
/// indexed, so they can't be searched.
public struct SearchIndex: Sendable {
    public struct Hit: Sendable, Equatable, Identifiable {
        public let entryID: UUID
        public let title: String
        public let userName: String
        public let groupName: String
        public var id: UUID { entryID }
    }

    private struct Document: Sendable {
        let hit: Hit
        /// Normalized field values.
        let title: String
        let user: String
        let url: String
        let notes: String
        let tags: [String]
        let attributes: [String]
        let attachments: [String]
        /// Normalized group names from the top-level group down to the
        /// entry's group (the root group is left out).
        let groupPath: [String]
        /// The entry's group and all groups above it, for scoped searches.
        let groupIDs: Set<UUID>
        let expiry: Date?
        let modified: Date
    }

    enum Field: Sendable, Equatable {
        case title, user, url, notes, tag, group, attribute, attachment, isFlag

        init?(name: String) {
            switch name {
            case "title", "t": self = .title
            case "username", "user", "u": self = .user
            case "url": self = .url
            case "notes", "n": self = .notes
            case "tag", "tags": self = .tag
            case "group", "g": self = .group
            case "attribute", "attr": self = .attribute
            case "attachment", "attach", "a": self = .attachment
            case "is": self = .isFlag
            default: return nil
            }
        }
    }

    private let documents: [Document]

    public init(_ database: Database) {
        var documents: [Document] = []
        Trace.span(.indexBuild, argument: UInt64(database.root.allEntries.count)) {
            var names: [UUID: String] = [:]
            database.root.forEachGroup { group, _ in names[group.id] = group.name }
            database.root.forEachGroup { group, path in
                if let bin = database.meta.recycleBinID, path.contains(bin) { return }
                // `path` starts at the root group, which isn't part of any
                // name the user sees.
                let groupPath = path.dropFirst().map { Self.normalize(names[$0] ?? "") }
                for entry in group.entries {
                    documents.append(
                        Self.document(for: entry, group: group, groupPath: groupPath, groupIDs: Set(path))
                    )
                }
            }
        }
        self.documents = documents
    }

    public var count: Int { documents.count }

    /// Entries matching `query`, best matches first. An empty query returns
    /// every entry, most recently modified first. With `groupID`, only
    /// entries in that group or its subgroups are searched.
    public func search(_ query: String, in groupID: UUID? = nil, limit: Int = .max, at date: Date = Date()) -> [Hit] {
        Trace.span(.searchQuery, argument: UInt64(documents.count)) {
            let terms = Self.parse(query)
            let candidates = documents.filter { document in
                groupID.map { document.groupIDs.contains($0) } ?? true
            }
            guard !terms.isEmpty else {
                return candidates.sorted { $0.modified > $1.modified }.prefix(limit).map(\.hit)
            }
            var scored: [(score: Int, document: Document)] = []
            for document in candidates {
                if let score = Self.score(terms, in: document, at: date) {
                    scored.append((score, document))
                }
            }
            return
                scored
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.document.modified > $1.document.modified }
                .prefix(limit)
                .map(\.document.hit)
        }
    }

    // MARK: Building

    private static func document(for entry: Entry, group: Group, groupPath: [String], groupIDs: Set<UUID>)
        -> Document
    {
        let attributes = entry.customFieldNames.compactMap { name -> String? in
            guard case .plain(let value)? = entry.fields[name] else { return nil }
            return normalize("\(name) \(value)")
        }
        return Document(
            hit: Hit(entryID: entry.id, title: entry.title, userName: entry.userName, groupName: group.name),
            title: normalize(entry.title),
            user: normalize(entry.userName),
            url: normalize(entry.url),
            notes: normalize(entry.notes),
            tags: entry.tags.map(normalize),
            attributes: attributes,
            attachments: entry.attachments.keys.map(normalize),
            groupPath: groupPath,
            groupIDs: groupIDs,
            expiry: entry.times.expiry,
            modified: entry.times.lastModification
        )
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Parsing

    enum MatchMode: Equatable {
        /// The text appears anywhere in the field.
        case contains
        /// The whole field equals the text.
        case exact
        /// The field matches a `*`/`?` pattern somewhere.
        case wildcard
        /// The field matches a regular expression somewhere.
        case regex
    }

    struct Term: Equatable {
        var field: Field?
        var text: String
        var mode: MatchMode = .contains
        var excluded = false

        /// Slash-separated parts, for path matching; nil without a slash.
        var pathParts: [String]? {
            guard text.contains("/") else { return nil }
            let parts = text.split(separator: "/").map(String.init)
            return parts.isEmpty ? nil : parts
        }
    }

    /// `[modifiers][field:]term`, where the term may be quoted.
    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"([-!+*]*)(?:([A-Za-z]+):)?(?:"([^"]*)"?|'([^']*)'?|([^\s"']+))"#
    )

    static func parse(_ query: String) -> [Term] {
        guard let tokenPattern else { return [] }
        let range = NSRange(query.startIndex..., in: query)
        return tokenPattern.matches(in: query, range: range).compactMap { match in
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: query).map { String(query[$0]) }
            }
            var term = Term(field: nil, text: "")
            for modifier in group(1) ?? "" {
                switch modifier {
                case "-", "!": term.excluded = true
                case "+": term.mode = .exact
                default: term.mode = .regex
                }
            }
            let value = group(3) ?? group(4) ?? group(5) ?? ""
            if let name = group(2) {
                if let field = Field(name: name.lowercased()) {
                    term.field = field
                    term.text = value
                } else {
                    // Not a field ("https://..."): the colon is part of the text.
                    term.text = "\(name):\(value)"
                }
            } else {
                term.text = value
            }
            if term.mode != .regex {
                term.text = normalize(term.text)
            }
            guard !term.text.isEmpty else { return nil }
            if term.mode == .contains, term.text.contains("*") || term.text.contains("?") {
                term.mode = .wildcard
            }
            return term
        }
    }

    // MARK: Matching

    /// The total score, or nil when the entry doesn't match every term.
    private static func score(_ terms: [Term], in document: Document, at date: Date) -> Int? {
        var total = 0
        for term in terms {
            let score = self.score(term, in: document, at: date)
            if term.excluded {
                if score != nil { return nil }
            } else {
                guard let score else { return nil }
                total += score
            }
        }
        return total
    }

    /// Higher is better; nil means the term doesn't match.
    private static func score(_ term: Term, in document: Document, at date: Date) -> Int? {
        if term.field == .isFlag {
            guard term.text == "expired" else { return nil }
            return document.expiry.map { $0 <= date } == true ? 1 : nil
        }
        let fieldScore = self.fieldScore(term, in: document)
        // A term with slashes may be a path, or literal text such as a URL.
        if let parts = term.pathParts, term.mode != .exact, term.field == nil || term.field == .group {
            let components = term.field == .group ? document.groupPath : document.groupPath + [document.title]
            if matchesInOrder(parts, components, mode: term.mode) {
                return max(50, fieldScore ?? 0)
            }
        }
        return fieldScore
    }

    /// The best weighted match of a term against the fields it applies to.
    private static func fieldScore(_ term: Term, in document: Document) -> Int? {
        var best: Int?
        func consider(_ value: String, weight: Int) {
            guard let quality = match(term, value) else { return }
            best = max(best ?? 0, weight * quality)
        }
        let all = term.field == nil
        if all || term.field == .title { consider(document.title, weight: 8) }
        if all || term.field == .user { consider(document.user, weight: 4) }
        if all || term.field == .url { consider(document.url, weight: 4) }
        if all || term.field == .tag { document.tags.forEach { consider($0, weight: 3) } }
        if all || term.field == .group { document.groupPath.forEach { consider($0, weight: 2) } }
        if all || term.field == .attribute { document.attributes.forEach { consider($0, weight: 2) } }
        if all || term.field == .notes { consider(document.notes, weight: 1) }
        if term.field == .attachment { document.attachments.forEach { consider($0, weight: 1) } }
        return best
    }

    /// 3 for the whole field, 2 for the start of a word, 1 elsewhere;
    /// nil for no match.
    private static func match(_ term: Term, _ value: String) -> Int? {
        switch term.mode {
        case .exact:
            return value == term.text ? 3 : nil
        case .wildcard:
            return regexMatches(wildcardPattern(term.text), value) ? 1 : nil
        case .regex:
            return regexMatches(term.text, value) ? 1 : nil
        case .contains:
            guard let range = value.range(of: term.text) else { return nil }
            if range == value.startIndex..<value.endIndex { return 3 }
            if range.lowerBound == value.startIndex { return 2 }
            let before = value[value.index(before: range.lowerBound)]
            return before.isLetter || before.isNumber ? 1 : 2
        }
    }

    /// Whether each part matches a component, in order (not necessarily
    /// adjacent components).
    private static func matchesInOrder(_ parts: [String], _ components: [String], mode: MatchMode) -> Bool {
        var index = components.startIndex
        for part in parts {
            let partMode: MatchMode =
                mode == .regex ? .regex : part.contains("*") || part.contains("?") ? .wildcard : .contains
            let pattern = Term(field: nil, text: part, mode: partMode)
            guard let found = components[index...].firstIndex(where: { match(pattern, $0) != nil }) else {
                return false
            }
            index = components.index(after: found)
        }
        return true
    }

    /// `*` matches any run of characters and `?` one character.
    private static func wildcardPattern(_ pattern: String) -> String {
        NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
    }

    /// Whether `pattern` matches somewhere in `value`, ignoring case and
    /// diacritics. An invalid pattern matches nothing.
    private static func regexMatches(_ pattern: String, _ value: String) -> Bool {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
