import Foundation

/// Everything the app remembers outside the database files themselves.
///
/// Nothing here is secret: database contents, passwords and keys never go
/// in this file. It lives in the App Group container so the app and its
/// extensions share it.
public struct AppState: Codable, Equatable, Sendable {
    /// Bumped when the format changes in a way older builds can't read.
    public static let currentVersion = 1

    public var version: Int
    public var databases: [DatabaseReference]
    public var settings: Settings

    public init(databases: [DatabaseReference] = [], settings: Settings = Settings()) {
        version = Self.currentVersion
        self.databases = databases
        self.settings = settings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        databases = try container.decodeIfPresent([DatabaseReference].self, forKey: .databases) ?? []
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    }

    public func database(withID id: UUID) -> DatabaseReference? {
        databases.first { $0.id == id }
    }
}

/// A database file the user has added, remembered through a
/// security-scoped bookmark.
public struct DatabaseReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// The file name without extension.
    public var displayName: String
    /// A name the user chose for the library instead of the file name.
    public var alias: String?
    /// Security-scoped bookmark to the original file (opaque outside Apple
    /// platforms).
    public var bookmark: Data
    public var lastOpened: Date?
    /// Set when an extension saved to the App Group working copy because
    /// it couldn't reach the original; the app merges and clears it.
    public var pendingSync: Bool
    public var quickUnlockEnabled: Bool
    /// Path of the key file's bookmark, if the user chose to remember which
    /// key file this database uses. The key file itself is never copied.
    public var keyFileBookmark: Data?

    public init(
        id: UUID = UUID(),
        displayName: String,
        bookmark: Data,
        lastOpened: Date? = nil,
        pendingSync: Bool = false,
        quickUnlockEnabled: Bool = false,
        keyFileBookmark: Data? = nil,
        alias: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.alias = alias
        self.bookmark = bookmark
        self.lastOpened = lastOpened
        self.pendingSync = pendingSync
        self.quickUnlockEnabled = quickUnlockEnabled
        self.keyFileBookmark = keyFileBookmark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened)
        pendingSync = try container.decodeIfPresent(Bool.self, forKey: .pendingSync) ?? false
        quickUnlockEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickUnlockEnabled) ?? false
        keyFileBookmark = try container.decodeIfPresent(Data.self, forKey: .keyFileBookmark)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
    }

    /// The name shown to the user: the alias if set, else the file name.
    public var name: String {
        guard let alias, !alias.trimmingCharacters(in: .whitespaces).isEmpty else { return displayName }
        return alias
    }
}

/// User preferences. Every field has a default, and decoding fills in
/// defaults for fields a file doesn't have, so adding a setting never
/// needs a version bump.
public struct Settings: Codable, Equatable, Sendable {
    /// Seconds in the background or idle before the database locks; 0
    /// locks as soon as the app leaves the screen.
    public var autoLockSeconds: Int = 0
    /// Seconds before a copied password or code is cleared from the
    /// clipboard.
    public var clipboardClearSeconds: Int = 30
    /// How long biometric quick unlock stays valid after a full unlock.
    public var quickUnlockValiditySeconds: Int = 7 * 24 * 3600
    /// Global switch: when false, no feature may use the network.
    public var networkAllowed: Bool = false
    public var faviconDownloadEnabled: Bool = false
    public var breachCheckEnabled: Bool = false
    /// Database that quick create and AutoFill saves go to.
    public var quickCreateDatabaseID: UUID?
    public var generator: GeneratorSettings = GeneratorSettings()

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        autoLockSeconds = try container.decodeIfPresent(Int.self, forKey: .autoLockSeconds) ?? defaults.autoLockSeconds
        clipboardClearSeconds =
            try container.decodeIfPresent(Int.self, forKey: .clipboardClearSeconds) ?? defaults.clipboardClearSeconds
        quickUnlockValiditySeconds =
            try container.decodeIfPresent(Int.self, forKey: .quickUnlockValiditySeconds)
            ?? defaults.quickUnlockValiditySeconds
        networkAllowed = try container.decodeIfPresent(Bool.self, forKey: .networkAllowed) ?? defaults.networkAllowed
        faviconDownloadEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .faviconDownloadEnabled)
            ?? defaults.faviconDownloadEnabled
        breachCheckEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .breachCheckEnabled) ?? defaults.breachCheckEnabled
        quickCreateDatabaseID = try container.decodeIfPresent(UUID.self, forKey: .quickCreateDatabaseID)
        generator = try container.decodeIfPresent(GeneratorSettings.self, forKey: .generator) ?? defaults.generator
    }

    /// Favicons may be fetched only when both the feature and the network
    /// master switch are on.
    public var mayDownloadFavicons: Bool { networkAllowed && faviconDownloadEnabled }
    public var mayCheckBreaches: Bool { networkAllowed && breachCheckEnabled }
}

/// The password generator's last-used configuration.
public struct GeneratorSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case password
        case passphrase
    }

    public var mode: Mode = .password
    public var length: Int = 20
    public var includeLowercase = true
    public var includeUppercase = true
    public var includeDigits = true
    public var includeSymbols = true
    public var excludeLookalikes = false
    public var wordCount: Int = 6
    public var wordSeparator: String = "-"
    public var capitalizeWords = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneratorSettings()
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode
        length = try container.decodeIfPresent(Int.self, forKey: .length) ?? defaults.length
        includeLowercase =
            try container.decodeIfPresent(Bool.self, forKey: .includeLowercase) ?? defaults.includeLowercase
        includeUppercase =
            try container.decodeIfPresent(Bool.self, forKey: .includeUppercase) ?? defaults.includeUppercase
        includeDigits = try container.decodeIfPresent(Bool.self, forKey: .includeDigits) ?? defaults.includeDigits
        includeSymbols = try container.decodeIfPresent(Bool.self, forKey: .includeSymbols) ?? defaults.includeSymbols
        excludeLookalikes =
            try container.decodeIfPresent(Bool.self, forKey: .excludeLookalikes) ?? defaults.excludeLookalikes
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? defaults.wordCount
        wordSeparator = try container.decodeIfPresent(String.self, forKey: .wordSeparator) ?? defaults.wordSeparator
        capitalizeWords =
            try container.decodeIfPresent(Bool.self, forKey: .capitalizeWords) ?? defaults.capitalizeWords
    }
}
