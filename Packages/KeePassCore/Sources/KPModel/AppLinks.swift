import Foundation

/// The apps an entry is used in, stored as plain custom fields so every
/// KeePass app shows them and they survive syncing: `iOSApp` (then
/// `iOSApp_1`, `iOSApp_2`, ...) for iOS app IDs, the way KeePassDX keeps
/// Android package names in `AndroidApp`.
extension Entry {
    public enum AppField {
        public static let iOS = "iOSApp"
        public static let android = "AndroidApp"
    }

    /// iOS app IDs this entry is linked to, as iOS reported them.
    public var iOSAppIDs: [String] {
        Self.values(named: AppField.iOS, in: fields)
    }

    /// Android package names: from `AndroidApp` fields, and from the
    /// `androidapp://` URLs some Android KeePass apps put in URL fields.
    public var androidAppIDs: [String] {
        let fromURLs = ([url] + fields.filter { $0.key.hasPrefix("KP2A_URL") }.map { $0.value.reveal() })
            .compactMap { text -> String? in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("androidapp://") else { return nil }
                let package = trimmed.dropFirst("androidapp://".count)
                return package.isEmpty ? nil : String(package)
            }
        return Self.values(named: AppField.android, in: fields) + fromURLs
    }

    /// Links the entry to an iOS app, in `iOSApp` or the next free
    /// `iOSApp_n` field. Returns false, changing nothing, when it is
    /// already linked to that app.
    @discardableResult
    public mutating func linkApp(_ appID: String) -> Bool {
        let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, !iOSAppIDs.contains(where: { AppID.same($0, appID) }) else { return false }
        var name = AppField.iOS
        var number = 0
        while fields[name] != nil {
            number += 1
            name = "\(AppField.iOS)_\(number)"
        }
        fields[name] = .plain(appID)
        return true
    }

    /// Values of `name` and `name_1`, `name_2`, ... (any case), in that
    /// order, without blanks.
    private static func values(named name: String, in fields: [String: FieldValue]) -> [String] {
        let base = name.lowercased()
        return fields.keys
            .filter { key in
                let lower = key.lowercased()
                return lower == base || (lower.hasPrefix(base + "_") && Int(lower.dropFirst(base.count + 1)) != nil)
            }
            .sorted { ($0.count, $0) < ($1.count, $1) }
            .compactMap { fields[$0]?.reveal().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// iOS app IDs: a team ID and a bundle ID (`ABCDE12345.com.example.app`),
/// or a bundle ID alone.
public enum AppID {
    /// The bundle ID part: `com.example.app` for both forms.
    public static func bundleID(of appID: String) -> String {
        let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = trimmed.firstIndex(of: ".") else { return trimmed }
        let prefix = trimmed[..<dot]
        let isTeamID =
            prefix.count == 10 && prefix.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        return isTeamID ? String(trimmed[trimmed.index(after: dot)...]) : trimmed
    }

    /// Whether two IDs name the same app, with or without a team ID.
    public static func same(_ lhs: String, _ rhs: String) -> Bool {
        bundleID(of: lhs).lowercased() == bundleID(of: rhs).lowercased()
    }
}
