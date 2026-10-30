import Foundation
import KPAppState
import KPKDBX
import KPModel
import KPOTP
import KPPlatform
import KPSearch
import KPSession
import Observation

/// State of one AutoFill request: which database is open and which entries
/// fit the website being filled.
@MainActor
@Observable
final class AutoFillModel {
    enum Mode {
        case password
        case oneTimeCode
        /// Any field, from the AutoFill menu of a text field iOS doesn't
        /// recognize as a login (a confirm-password or an unlabeled code
        /// field): the user picks an entry, then which of its values to type.
        case text
    }

    enum Completion {
        case password(user: String, password: String)
        case oneTimeCode(String)
        case text(String)
        case cancelled
    }

    /// Extensions get far less memory than apps (about 120 MB); databases
    /// whose key derivation needs more than this are refused up front
    /// instead of being killed by the system half way.
    static let memoryLimit: UInt64 = 80 << 20

    private(set) var mode: Mode = .password
    private(set) var serviceIdentifiers: [String] = []
    private(set) var databases: [DatabaseReference] = []
    private(set) var selected: DatabaseReference?
    private(set) var session: DatabaseSession?
    private(set) var isLoaded = false
    /// The generator settings shared with the app.
    private(set) var generatorSettings = GeneratorSettings()
    /// The accent color chosen in the app.
    private(set) var accentColor: String?
    /// How long a Face ID key stays valid after the master password is
    /// entered, as set in the app.
    private(set) var quickUnlockValiditySeconds = KPAppState.Settings().quickUnlockValiditySeconds
    /// Set once the request is answered, so the sheet doesn't show the
    /// unlock screen (and offer Face ID) while it closes.
    private(set) var isFinished = false
    private(set) var loadError: String?

    private let codec = KDBXCodec()
    private let complete: (Completion) -> Void

    init(complete: @escaping (Completion) -> Void) {
        self.complete = complete
    }

    func start(_ mode: Mode, serviceIdentifiers: [String]) {
        self.mode = mode
        self.serviceIdentifiers = serviceIdentifiers
        Task { await load() }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let store = AppStateStore.shared() else {
            loadError = String(localized: "The app's shared storage isn't available.")
            return
        }
        do {
            let state = try await store.load()
            databases = state.databases
            generatorSettings = state.settings.generator
            accentColor = state.settings.accentColor
            quickUnlockValiditySeconds = state.settings.quickUnlockValiditySeconds
            let preferred = state.settings.quickCreateDatabaseID
            if let reference = databases.first(where: { $0.id == preferred }) ?? databases.first {
                select(reference)
            }
        } catch {
            loadError = String(localized: "Couldn't read the database list. Open KeePassIO and try again.")
        }
    }

    func select(_ reference: DatabaseReference) {
        guard reference.id != selected?.id else { return }
        session?.lock()
        selected = reference
        let original = BookmarkedFile(bookmark: reference.bookmark, displayName: reference.displayName)
        // Extensions often can't reach files held by other apps' File
        // Providers: reads fall back to copies in the App Group, and saves
        // to a pending copy the app merges later.
        let file: any DatabaseFile =
            if let cache = SharedFiles.databaseCache(for: reference.id),
                let pending = SharedFiles.pendingChanges(for: reference.id)
            {
                ExtensionDatabaseFile(original: original, cache: cache, pending: pending)
            } else {
                original
            }
        session = DatabaseSession(
            file: file,
            codec: codec,
            memoryLimit: Self.memoryLimit
        )
    }

    /// The domain shown as "Suggestions for …".
    var serviceName: String? {
        serviceIdentifiers.first.map { identifier in
            URL(string: identifier)?.host() ?? identifier
        }
    }

    /// Entries for the website being filled, best match first.
    var suggestions: [Entry] {
        guard let database = session?.database else { return [] }
        var seen = Set<UUID>()
        var result: [Entry] = []
        for identifier in serviceIdentifiers {
            for match in URLMatcher.matches(for: identifier, in: database) where seen.insert(match.entryID).inserted {
                if let entry = database.entry(withID: match.entryID), fits(entry) {
                    result.append(entry)
                }
            }
        }
        return result
    }

    /// Every usable entry, or the search results for `query`.
    func entries(matching query: String) -> [Entry] {
        guard let session, let database = session.database else { return [] }
        if query.isEmpty {
            return database.activeEntries.filter(fits).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        let hits = session.searchIndex?.search(query, limit: 200) ?? []
        return hits.compactMap { database.entry(withID: $0.entryID) }.filter(fits)
    }

    private func fits(_ entry: Entry) -> Bool {
        switch mode {
        case .password: !entry.password.isEmpty || !entry.userName.isEmpty
        case .oneTimeCode: Self.otp(of: entry) != nil
        case .text: !insertableFields(of: entry).isEmpty
        }
    }

    /// A value of an entry the user can insert as text.
    struct InsertableField: Identifiable {
        let name: String
        let value: String
        let isSecret: Bool
        var id: String { name }
    }

    /// The entry's non-empty values, standard fields first, with the
    /// current one-time code after the password.
    func insertableFields(of entry: Entry) -> [InsertableField] {
        var result: [InsertableField] = []
        func add(_ name: String, _ value: String, secret: Bool) {
            if !value.isEmpty { result.append(InsertableField(name: name, value: value, isSecret: secret)) }
        }
        add(String(localized: "User Name"), entry.userName, secret: false)
        add(String(localized: "Password"), entry.password.reveal(), secret: true)
        if let otp = Self.otp(of: entry) {
            add(String(localized: "One-Time Code"), otp.code(at: Date()), secret: false)
        }
        add(String(localized: "Website"), entry.url, secret: false)
        // The one-time code's secret fields are offered as the code above.
        for name in entry.customFieldNames where name != "otp" && !name.hasPrefix("TOTP ") {
            if let field = entry.fields[name] {
                add(name, field.reveal(), secret: field.isProtected)
            }
        }
        return result
    }

    /// Answers a text insertion request with one of an entry's values.
    func insert(_ field: InsertableField) {
        finish(.text(field.value))
    }

    /// How long after a password fill its entry is offered first for a
    /// text insertion.
    private static let justFilledWindow: TimeInterval = 5 * 60
    private static let justFilledKey = "justFilled"

    /// iOS fills a password into one field only, so a sign-up form's
    /// confirm-password field stays empty. The user then opens the field's
    /// AutoFill > Passwords menu; remembering which entry was just filled
    /// (its ID, never its values) lets the picker offer that password first.
    private func rememberFilled(_ entry: Entry) {
        guard let databaseID = selected?.id else { return }
        UserDefaults.standard.set(
            [databaseID.uuidString, entry.id.uuidString, String(Date().timeIntervalSince1970)],
            forKey: Self.justFilledKey
        )
    }

    /// The entry whose password was filled in the last few minutes, from
    /// the open database.
    var justFilled: Entry? {
        guard mode == .text, let database = session?.database,
            let saved = UserDefaults.standard.stringArray(forKey: Self.justFilledKey), saved.count == 3,
            saved[0] == selected?.id.uuidString,
            let entryID = UUID(uuidString: saved[1]),
            let time = TimeInterval(saved[2]),
            Date().timeIntervalSince1970 - time < Self.justFilledWindow
        else { return nil }
        return database.entry(withID: entryID).flatMap { $0.password.isEmpty ? nil : $0 }
    }

    /// Inserts the password of the entry just filled, for its
    /// confirm-password field.
    func insertPassword(of entry: Entry) {
        finish(.text(entry.password.reveal()))
    }

    private static func otp(of entry: Entry) -> OTP? {
        try? OTP(fields: entry.fields.mapValues { $0.reveal() })
    }

    func choose(_ entry: Entry) {
        let completion: Completion
        switch mode {
        case .password:
            rememberFilled(entry)
            completion = .password(user: entry.userName, password: entry.password.reveal())
        case .oneTimeCode:
            guard let otp = Self.otp(of: entry) else { return }
            completion = .oneTimeCode(otp.code(at: Date()))
        case .text:
            // Text requests pick a field first; see `insert(_:)`.
            return
        }
        finish(completion)
    }

    func cancel() {
        finish(.cancelled)
    }

    private func finish(_ completion: Completion) {
        isFinished = true
        session?.lock()
        complete(completion)
    }

    /// The site being filled, for a new entry's title and URL. The URL
    /// keeps the page but drops its query and fragment (sign-in tokens,
    /// redirect parameters and the like).
    var newEntryDefaults: (title: String, url: String) {
        let identifier = serviceIdentifiers.first ?? ""
        guard !identifier.isEmpty else { return ("", "") }
        let full = identifier.contains("://") ? identifier : "https://\(identifier)"
        var components = URLComponents(string: full)
        components?.query = nil
        components?.fragment = nil
        let host = components?.host ?? identifier
        let title = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return (title, components?.string ?? full)
    }

    /// User names already in the database, most used first.
    var knownUserNames: [String] {
        guard let database = session?.database else { return [] }
        var counts: [String: Int] = [:]
        for entry in database.activeEntries where !entry.userName.isEmpty {
            counts[entry.userName, default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Remembers generator settings changed here, for the app too.
    func saveGeneratorSettings(_ settings: GeneratorSettings) {
        generatorSettings = settings
        Task {
            _ = try? await AppStateStore.shared()?.update { $0.settings.generator = settings }
        }
    }

    /// A group a new entry can go to, named by its path.
    struct GroupChoice: Identifiable, Hashable {
        let id: UUID
        let path: String
    }

    /// Every group of the open database except the recycle bin, in tree
    /// order, named by path; the top level goes by the database's name.
    var groupChoices: [GroupChoice] {
        guard let database = session?.database else { return [] }
        let top = database.meta.name.isEmpty ? database.root.name : database.meta.name
        return database.activeGroupPaths.map { group in
            GroupChoice(id: group.id, path: group.names.isEmpty ? top : group.names.joined(separator: " / "))
        }
    }

    private static let lastGroupKey = "lastNewEntryGroup"

    /// The group the last entry made here for this database went to, if
    /// it still exists, otherwise the top level.
    var defaultGroupID: UUID? {
        guard let database = session?.database, let databaseID = selected?.id else { return nil }
        let saved = UserDefaults.standard.dictionary(forKey: Self.lastGroupKey)?[databaseID.uuidString] as? String
        if let id = saved.flatMap(UUID.init(uuidString:)), groupChoices.contains(where: { $0.id == id }) {
            return id
        }
        return database.root.id
    }

    private func rememberGroup(_ groupID: UUID) {
        guard let databaseID = selected?.id else { return }
        var saved = UserDefaults.standard.dictionary(forKey: Self.lastGroupKey) ?? [:]
        saved[databaseID.uuidString] = groupID.uuidString
        UserDefaults.standard.set(saved, forKey: Self.lastGroupKey)
    }

    /// Adds an entry to `groupID` (the top level when nil) and saves the
    /// database. When filling a password, the new entry is filled right
    /// away.
    func addEntry(
        title: String,
        userName: String,
        password: String,
        url: String,
        groupID: UUID?
    ) async throws(SessionError) {
        guard let session else { throw .locked }
        var entry = session.newEntry(title: title, userName: userName, password: SecretString(password))
        entry.url = url
        try session.addEntry(entry, to: groupID)
        try await session.save()
        if let groupID {
            rememberGroup(groupID)
        }
        if mode == .password {
            choose(entry)
        }
    }

}
