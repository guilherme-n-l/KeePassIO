import Foundation

/// Timestamps KeePass keeps for every group and entry. Merging relies on
/// `lastModification` and `locationChanged`.
public struct Times: Sendable, Equatable, Hashable {
    public var creation: Date
    public var lastModification: Date
    public var lastAccess: Date
    public var locationChanged: Date
    public var expiry: Date?
    public var usageCount: Int

    public init(
        creation: Date = Date(),
        lastModification: Date? = nil,
        lastAccess: Date? = nil,
        locationChanged: Date? = nil,
        expiry: Date? = nil,
        usageCount: Int = 0
    ) {
        self.creation = creation
        self.lastModification = lastModification ?? creation
        self.lastAccess = lastAccess ?? creation
        self.locationChanged = locationChanged ?? creation
        self.expiry = expiry
        self.usageCount = usageCount
    }

    public static func now() -> Times { Times(creation: Date()) }

    public func isExpired(at date: Date) -> Bool {
        guard let expiry else { return false }
        return expiry <= date
    }
}

/// A field value; protected fields are kept as `SecretString`.
public enum FieldValue: Sendable, Equatable, Hashable {
    case plain(String)
    case protected(SecretString)

    public var isProtected: Bool {
        if case .protected = self { return true }
        return false
    }

    /// The value in clear text. Use only where it's shown or used.
    public func reveal() -> String {
        switch self {
        case .plain(let text): text
        case .protected(let secret): secret.reveal()
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .plain(let text): text.isEmpty
        case .protected(let secret): secret.isEmpty
        }
    }
}

/// An entry: a set of named fields plus attachments, tags and history.
public struct Entry: Sendable, Equatable, Hashable, Identifiable {
    /// Names of the fields every KeePass client knows.
    public enum StandardField {
        public static let title = "Title"
        public static let userName = "UserName"
        public static let password = "Password"
        public static let url = "URL"
        public static let notes = "Notes"
        public static let all = [title, userName, password, url, notes]
    }

    public var id: UUID
    public var fields: [String: FieldValue]
    public var attachments: [String: Data]
    public var tags: [String]
    public var iconID: Int
    public var customIconID: UUID?
    public var times: Times
    /// Earlier versions, oldest first. History entries have no history.
    public var history: [Entry]
    public var customData: [String: String]
    /// Group the entry was in before its last move (KDBX 4.1).
    public var previousParentGroup: UUID?
    public var foregroundColor: String?
    public var backgroundColor: String?
    public var overrideURL: String?
    /// File-format properties this model doesn't interpret (auto-type
    /// settings, unknown XML written by other clients, ...), keyed by the
    /// codec and carried through edits and merges so saving keeps them.
    public var extras: [String: String]

    public init(
        id: UUID = UUID(),
        fields: [String: FieldValue] = [:],
        attachments: [String: Data] = [:],
        tags: [String] = [],
        iconID: Int = 0,
        customIconID: UUID? = nil,
        times: Times = .now(),
        history: [Entry] = [],
        customData: [String: String] = [:],
        previousParentGroup: UUID? = nil,
        foregroundColor: String? = nil,
        backgroundColor: String? = nil,
        overrideURL: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.id = id
        self.fields = fields
        self.attachments = attachments
        self.tags = tags
        self.iconID = iconID
        self.customIconID = customIconID
        self.times = times
        self.history = history
        self.customData = customData
        self.previousParentGroup = previousParentGroup
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.overrideURL = overrideURL
        self.extras = extras
    }

    public var title: String {
        get { fields[StandardField.title]?.reveal() ?? "" }
        set { fields[StandardField.title] = .plain(newValue) }
    }

    public var userName: String {
        get { fields[StandardField.userName]?.reveal() ?? "" }
        set { fields[StandardField.userName] = .plain(newValue) }
    }

    public var password: SecretString {
        get {
            switch fields[StandardField.password] {
            case .protected(let secret): secret
            case .plain(let text): SecretString(text)
            case nil: .empty
            }
        }
        set { fields[StandardField.password] = .protected(newValue) }
    }

    public var url: String {
        get { fields[StandardField.url]?.reveal() ?? "" }
        set { fields[StandardField.url] = .plain(newValue) }
    }

    public var notes: String {
        get { fields[StandardField.notes]?.reveal() ?? "" }
        set { fields[StandardField.notes] = .plain(newValue) }
    }

    /// Custom (non-standard) field names, sorted.
    public var customFieldNames: [String] {
        fields.keys.filter { !StandardField.all.contains($0) }.sorted()
    }

    /// True when the content (everything except history and access
    /// statistics) is the same. Used to avoid recording no-op history.
    public func hasSameContent(as other: Entry) -> Bool {
        fields == other.fields && attachments == other.attachments && tags == other.tags
            && iconID == other.iconID && customIconID == other.customIconID
            && times.expiry == other.times.expiry && customData == other.customData
            && foregroundColor == other.foregroundColor && backgroundColor == other.backgroundColor
            && overrideURL == other.overrideURL && extras == other.extras
    }

    /// A copy suitable for storing in history: same content, no nested
    /// history.
    public var historySnapshot: Entry {
        var copy = self
        copy.history = []
        return copy
    }
}

/// A group (folder) of entries and subgroups.
public struct Group: Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var iconID: Int
    public var customIconID: UUID?
    public var times: Times
    public var isExpanded: Bool
    public var groups: [Group]
    public var entries: [Entry]
    public var customData: [String: String]
    public var tags: [String]
    public var previousParentGroup: UUID?
    /// Format-specific properties this model doesn't interpret; see
    /// `Entry.extras`.
    public var extras: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        iconID: Int = 48,
        customIconID: UUID? = nil,
        times: Times = .now(),
        isExpanded: Bool = true,
        groups: [Group] = [],
        entries: [Entry] = [],
        customData: [String: String] = [:],
        tags: [String] = [],
        previousParentGroup: UUID? = nil,
        extras: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.iconID = iconID
        self.customIconID = customIconID
        self.times = times
        self.isExpanded = isExpanded
        self.groups = groups
        self.entries = entries
        self.customData = customData
        self.tags = tags
        self.previousParentGroup = previousParentGroup
        self.extras = extras
    }

    /// Group properties excluding children, for comparing two versions.
    public func hasSameProperties(as other: Group) -> Bool {
        name == other.name && notes == other.notes && iconID == other.iconID
            && customIconID == other.customIconID && customData == other.customData && tags == other.tags
            && times.expiry == other.times.expiry && extras == other.extras
    }
}

/// Database-wide settings and metadata.
public struct Meta: Sendable, Equatable, Hashable {
    public var name: String
    public var description: String
    public var defaultUserName: String
    public var recycleBinEnabled: Bool
    public var recycleBinID: UUID?
    /// Maximum history items per entry; negative means unlimited.
    public var historyMaxItems: Int
    /// Maximum history size per entry in bytes; negative means unlimited.
    public var historyMaxSize: Int
    public var customIcons: [UUID: Data]
    public var customData: [String: String]
    /// When any of the settings above last changed.
    public var settingsChanged: Date
    /// Format-specific properties this model doesn't interpret; see
    /// `Entry.extras`.
    public var extras: [String: String]

    public init(
        name: String = "",
        description: String = "",
        defaultUserName: String = "",
        recycleBinEnabled: Bool = true,
        recycleBinID: UUID? = nil,
        historyMaxItems: Int = 10,
        historyMaxSize: Int = 6 * 1024 * 1024,
        customIcons: [UUID: Data] = [:],
        customData: [String: String] = [:],
        settingsChanged: Date = Date(),
        extras: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.defaultUserName = defaultUserName
        self.recycleBinEnabled = recycleBinEnabled
        self.recycleBinID = recycleBinID
        self.historyMaxItems = historyMaxItems
        self.historyMaxSize = historyMaxSize
        self.customIcons = customIcons
        self.customData = customData
        self.settingsChanged = settingsChanged
        self.extras = extras
    }
}

/// A whole database's content, independent of the file format.
public struct Database: Sendable, Equatable, Hashable {
    public var meta: Meta
    public var root: Group
    /// Items deleted permanently, with the time of deletion, so merging
    /// with an older copy doesn't bring them back.
    public var deletedObjects: [UUID: Date]

    public init(meta: Meta = Meta(), root: Group, deletedObjects: [UUID: Date] = [:]) {
        self.meta = meta
        self.root = root
        self.deletedObjects = deletedObjects
    }

    /// A new, empty database with a root group named after the database.
    public static func empty(name: String) -> Database {
        Database(meta: Meta(name: name), root: Group(name: name))
    }
}
