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
    }

    enum Completion {
        case password(user: String, password: String)
        case oneTimeCode(String)
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
            let preferred = state.settings.quickCreateDatabaseID
            if let reference = databases.first(where: { $0.id == preferred }) ?? databases.first {
                select(reference)
            }
        } catch {
            loadError = String(localized: "Couldn't read the database list. Open KeePassIOS and try again.")
        }
    }

    func select(_ reference: DatabaseReference) {
        guard reference.id != selected?.id else { return }
        session?.lock()
        selected = reference
        session = DatabaseSession(
            file: BookmarkedFile(bookmark: reference.bookmark, displayName: reference.displayName),
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
        }
    }

    private static func otp(of entry: Entry) -> OTP? {
        try? OTP(fields: entry.fields.mapValues { $0.reveal() })
    }

    func choose(_ entry: Entry) {
        let completion: Completion
        switch mode {
        case .password:
            completion = .password(user: entry.userName, password: entry.password.reveal())
        case .oneTimeCode:
            guard let otp = Self.otp(of: entry) else { return }
            completion = .oneTimeCode(otp.code(at: Date()))
        }
        session?.lock()
        complete(completion)
    }

    func cancel() {
        session?.lock()
        complete(.cancelled)
    }
}
