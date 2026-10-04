import Foundation
import KPModel
import KPObservability

/// An in-memory search index over a database's entries, built after
/// unlock and rebuilt after edits.
///
/// Queries are split into words; an entry matches when every word is a
/// prefix of some word in its title, user name, URL, notes, tags, group
/// name or non-protected custom fields (case- and diacritic-insensitive).
/// Words of the form `tag:x`, `user:x`, `url:x` and `title:x` restrict a
/// word to one field. Protected fields are never indexed.
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
        /// Words per field, normalized.
        let fields: [Field: [String]]
        let modified: Date
    }

    enum Field: String, Sendable, CaseIterable {
        case title, user, url, notes, tag, group, other
    }

    private let documents: [Document]

    public init(_ database: Database) {
        var documents: [Document] = []
        Trace.span(.indexBuild, argument: UInt64(database.root.allEntries.count)) {
            database.root.forEachGroup { group, path in
                if let bin = database.meta.recycleBinID, path.contains(bin) { return }
                for entry in group.entries {
                    documents.append(Self.document(for: entry, groupName: group.name))
                }
            }
        }
        self.documents = documents
    }

    public var count: Int { documents.count }

    /// Entries matching `query`, best matches first. An empty query returns
    /// every entry, most recently modified first.
    public func search(_ query: String, limit: Int = .max) -> [Hit] {
        Trace.span(.searchQuery, argument: UInt64(documents.count)) {
            let terms = Self.parse(query)
            guard !terms.isEmpty else {
                return documents.sorted { $0.modified > $1.modified }.prefix(limit).map(\.hit)
            }
            var scored: [(score: Int, document: Document)] = []
            for document in documents {
                var total = 0
                for term in terms {
                    guard let score = Self.score(term, in: document) else {
                        total = -1
                        break
                    }
                    total += score
                }
                if total >= 0 {
                    scored.append((total, document))
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

    private static func document(for entry: Entry, groupName: String) -> Document {
        var fields: [Field: [String]] = [:]
        fields[.title] = words(entry.title)
        fields[.user] = words(entry.userName)
        fields[.url] = words(entry.url)
        fields[.notes] = words(entry.notes)
        fields[.tag] = entry.tags.flatMap(words)
        fields[.group] = words(groupName)
        fields[.other] = entry.customFieldNames.flatMap { name -> [String] in
            guard case .plain(let value)? = entry.fields[name] else { return [] }
            return words(name) + words(value)
        }
        return Document(
            hit: Hit(entryID: entry.id, title: entry.title, userName: entry.userName, groupName: groupName),
            fields: fields,
            modified: entry.times.lastModification
        )
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func words(_ text: String) -> [String] {
        normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    // MARK: Querying

    struct Term: Equatable {
        let field: Field?
        let word: String
    }

    static func parse(_ query: String) -> [Term] {
        query.split(whereSeparator: \.isWhitespace).flatMap { token -> [Term] in
            let parts = token.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let field = Field(rawValue: normalize(String(parts[0]))) {
                return words(String(parts[1])).map { Term(field: field, word: $0) }
            }
            return words(String(token)).map { Term(field: nil, word: $0) }
        }
    }

    /// Higher is better; nil means the term doesn't match.
    private static func score(_ term: Term, in document: Document) -> Int? {
        let weights: [Field: Int] = [.title: 8, .user: 4, .url: 4, .tag: 3, .group: 2, .other: 2, .notes: 1]
        var best: Int?
        for field in Field.allCases where term.field == nil || term.field == field {
            for word in document.fields[field] ?? [] where word.hasPrefix(term.word) {
                let exact = word == term.word ? 2 : 1
                let score = (weights[field] ?? 1) * exact
                best = max(best ?? 0, score)
            }
        }
        return best
    }
}
