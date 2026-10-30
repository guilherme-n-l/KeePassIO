import Foundation
import KPModel
import PublicSuffixList

/// Finds entries for a website, as AutoFill does.
public enum URLMatcher {
    public enum Quality: Int, Comparable, Sendable {
        case sameDomain = 1
        case sameHost = 2
        case exact = 3

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Match: Sendable, Equatable {
        public let entryID: UUID
        public let quality: Quality
    }

    /// Entries whose URL belongs to the same site as `url`, best first.
    /// Entries in the recycle bin and expired entries are skipped.
    public static func matches(for url: String, in database: Database, at date: Date = Date()) -> [Match] {
        guard let target = host(of: url) else { return [] }
        let targetDomain = registrableDomain(target)
        var results: [Match] = []
        for entry in database.activeEntries where !entry.times.isExpired(at: date) {
            for candidate in [entry.url, entry.overrideURL ?? ""] + entry.additionalURLs {
                guard let host = host(of: candidate) else { continue }
                let quality: Quality? =
                    if normalizedURL(candidate) == normalizedURL(url) {
                        .exact
                    } else if host == target {
                        .sameHost
                    } else if registrableDomain(host) == targetDomain {
                        .sameDomain
                    } else {
                        nil
                    }
                if let quality {
                    results.append(Match(entryID: entry.id, quality: quality))
                    break
                }
            }
        }
        return results.sorted { $0.quality > $1.quality }
    }

    static func host(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: withScheme)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalizedURL(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// The part of the host one owner registered, from the Public Suffix
    /// List: example.co.uk for shop.example.co.uk, and alice.github.io for
    /// itself, since every github.io site belongs to someone else. IP
    /// addresses and hosts that are themselves a public suffix stand alone.
    static func registrableDomain(_ host: String) -> String {
        if isIPAddress(host) { return host }
        return PublicSuffixList.effectiveTLDPlusOne(host) ?? host
    }

    private static func isIPAddress(_ host: String) -> Bool {
        host.contains(":") || host.split(separator: ".").allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

extension Entry {
    /// Extra URLs in KeePassXC's `KP2A_URL` / `KP2A_URL_n` custom fields.
    var additionalURLs: [String] {
        fields.filter { $0.key.hasPrefix("KP2A_URL") }.map { $0.value.reveal() }
    }
}
