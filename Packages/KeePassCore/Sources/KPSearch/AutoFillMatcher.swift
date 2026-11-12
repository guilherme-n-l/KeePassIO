import Foundation
import KPModel

/// What iOS says is asking, from its service identifiers.
public struct AutoFillService: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case domain
        case url
        case app
    }

    public let kind: Kind
    public let identifier: String
    /// The app's or site's name for display, when iOS gives one.
    public let displayName: String?

    public init(kind: Kind, identifier: String, displayName: String? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
    }
}

/// Finds the entries AutoFill should suggest for what iOS is filling: a
/// website, or an app. Each match carries the reason it was found, best
/// first, so the picker can say why an entry is there.
public enum AutoFillMatcher {
    /// Why an entry matched, strongest last so they compare naturally.
    public enum Reason: Int, Comparable, Sendable {
        /// The entry's title looks like the app's name.
        case similarName = 1
        /// The entry's `AndroidApp` package name is the app's bundle ID.
        case androidApp = 2
        case sameDomain = 3
        case sameHost = 4
        case exactURL = 5
        /// The entry has an `iOSApp` field for this app.
        case linkedApp = 6

        public static func < (lhs: Reason, rhs: Reason) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Match: Sendable, Equatable {
        public let entryID: UUID
        public let reason: Reason
    }

    /// Entries for `services`, best reason first, then by title. An entry
    /// appears once, with its best reason. Entries in the recycle bin and
    /// expired entries are skipped.
    public static func matches(for services: [AutoFillService], in database: Database, at date: Date = Date())
        -> [Match]
    {
        var best: [UUID: Reason] = [:]
        func note(_ id: UUID, _ reason: Reason) {
            if best[id].map({ reason > $0 }) ?? true { best[id] = reason }
        }
        for service in services {
            switch service.kind {
            case .domain, .url:
                for match in URLMatcher.matches(for: service.identifier, in: database, at: date) {
                    note(match.entryID, Reason(match.quality))
                }
            case .app:
                for entry in database.activeEntries where !entry.times.isExpired(at: date) {
                    if let reason = appReason(entry, for: service) { note(entry.id, reason) }
                }
            }
        }
        let titles = Dictionary(uniqueKeysWithValues: database.activeEntries.map { ($0.id, $0.title) })
        return best.map { Match(entryID: $0.key, reason: $0.value) }.sorted {
            if $0.reason != $1.reason { return $0.reason > $1.reason }
            let order = (titles[$0.entryID] ?? "").localizedStandardCompare(titles[$1.entryID] ?? "")
            return order == .orderedSame ? $0.entryID.uuidString < $1.entryID.uuidString : order == .orderedAscending
        }
    }

    private static func appReason(_ entry: Entry, for service: AutoFillService) -> Reason? {
        if entry.iOSAppIDs.contains(where: { AppID.same($0, service.identifier) }) { return .linkedApp }
        let bundleID = AppID.bundleID(of: service.identifier).lowercased()
        if entry.androidAppIDs.contains(where: { $0.lowercased() == bundleID }) { return .androidApp }
        return titleLooksLike(entry.title, bundleID: bundleID, name: service.displayName) ? .similarName : nil
    }

    /// Words too common in titles to say which app an entry is for.
    private static let genericWords: Set<String> = [
        "account", "accounts", "admin", "email", "login", "mail", "password", "user", "work", "home",
    ]

    /// Whether a word of the title (four letters or more, not a generic
    /// one) is a word of the app's name, or starts the last part of its
    /// bundle ID: "car/mobizap" for Mobizap SP, br.com.example.mobizapsp.
    static func titleLooksLike(_ title: String, bundleID: String, name: String?) -> Bool {
        let titleWords = words(in: title).filter { $0.count >= 4 && !genericWords.contains($0) }
        guard !titleWords.isEmpty else { return false }
        let nameWords = Set(words(in: name ?? ""))
        let joinedName = words(in: name ?? "").joined()
        let lastPart = bundleID.split(separator: ".").last.map(String.init) ?? ""
        return titleWords.contains { word in
            nameWords.contains(word) || word == joinedName || (!lastPart.isEmpty && lastPart.hasPrefix(word))
        }
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

extension AutoFillMatcher.Reason {
    init(_ quality: URLMatcher.Quality) {
        switch quality {
        case .exact: self = .exactURL
        case .sameHost: self = .sameHost
        case .sameDomain: self = .sameDomain
        }
    }
}
