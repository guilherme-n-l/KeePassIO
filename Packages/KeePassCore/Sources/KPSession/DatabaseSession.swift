import Foundation
import KPMerge
import KPModel
import KPObservability
import KPSearch
import Observation

/// One open database: unlocking, reading, editing, saving and merging.
///
/// Views observe `state`, `database` and `searchIndex`. Every edit goes
/// through a method here so history, search and the unsaved-changes flag
/// stay consistent. Saving checks that the file hasn't changed since it
/// was read; if it has, the other version is merged in first (three-way,
/// using the last version this session read or wrote as the base) and the
/// report is kept in `lastMergeReport` for the review screen.
@MainActor
@Observable
public final class DatabaseSession {
    public enum State: Equatable, Sendable {
        case locked
        case unlocking
        case unlocked
        case failed(SessionError)
    }

    public private(set) var state: State = .locked
    public private(set) var database: Database?
    public private(set) var settings: EncryptionSettings?
    public private(set) var searchIndex: SearchIndex?
    public private(set) var hasUnsavedChanges = false
    public private(set) var isSaving = false
    public private(set) var lastMergeReport: MergeReport?
    public private(set) var lastSaved: Date?

    public let file: any DatabaseFile
    private let codec: any DatabaseCodec
    private let memoryLimit: UInt64?
    private let clock: @Sendable () -> Date
    private var key: CompositeKey?
    /// The content as last read from or written to the file: the common
    /// base for three-way merges.
    private var base: Database?
    private var fileVersion: FileVersion?
    private var formatContext: FormatContext?

    /// - Parameters:
    ///   - memoryLimit: Upper bound for key derivation memory; extensions
    ///     pass their budget, the app passes nil.
    ///   - clock: Source of edit timestamps, injectable for tests.
    public init(
        file: any DatabaseFile,
        codec: any DatabaseCodec,
        memoryLimit: UInt64? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.file = file
        self.codec = codec
        self.memoryLimit = memoryLimit
        self.clock = clock
    }

    // MARK: Unlocking

    public func unlock(with key: CompositeKey) async {
        guard state != .unlocking else { return }
        state = .unlocking
        do {
            let opened = try await Trace.span(.unlockTotal) {
                let (data, version) = try await file.read()
                let decoded = try await codec.decode(data, key: key, memoryLimit: memoryLimit)
                return (decoded, version)
            }
            self.key = key
            settings = opened.0.settings
            formatContext = opened.0.context
            fileVersion = opened.1
            base = opened.0.database
            hasUnsavedChanges = false
            install(opened.0.database)
            state = .unlocked
        } catch {
            state = .failed(SessionError(error))
        }
    }

    /// Forgets the key and every decrypted value.
    public func lock() {
        key = nil
        database = nil
        base = nil
        settings = nil
        searchIndex = nil
        fileVersion = nil
        formatContext = nil
        lastMergeReport = nil
        hasUnsavedChanges = false
        state = .locked
    }

    // MARK: Creating

    /// Creates a new database at this session's file.
    public func create(
        name: String,
        key: CompositeKey,
        settings: EncryptionSettings = .recommended
    ) async throws(SessionError) {
        guard !key.isEmpty else { throw .emptyKey }
        var database = Database.empty(name: name)
        database.meta.settingsChanged = clock()
        do {
            let data = try await codec.encode(database, settings: settings, key: key, context: nil)
            fileVersion = try await file.write(data, expecting: nil)
        } catch {
            throw SessionError(error)
        }
        database.root.times = Times(creation: clock())
        self.key = key
        self.settings = settings
        base = database
        install(database)
        hasUnsavedChanges = false
        state = .unlocked
    }

    // MARK: Editing

    public func addEntry(_ entry: Entry, to groupID: UUID? = nil) throws(SessionError) {
        try edit { database in
            try database.add(entry, to: groupID ?? database.root.id)
        }
    }

    public func updateEntry(_ entry: Entry) throws(SessionError) {
        let now = clock()
        try edit { database in try database.update(entry, at: now) }
    }

    public func deleteEntry(_ id: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in try database.deleteEntry(id, at: now) }
    }

    public func moveEntry(_ id: UUID, to groupID: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in try database.moveEntry(id, to: groupID, at: now) }
    }

    public func addGroup(_ group: Group, to parentID: UUID? = nil) throws(SessionError) {
        try edit { database in try database.add(group, to: parentID ?? database.root.id) }
    }

    public func updateGroup(_ group: Group) throws(SessionError) {
        let now = clock()
        try edit { database in try database.updateGroupProperties(group, at: now) }
    }

    public func deleteGroup(_ id: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in try database.deleteGroup(id, at: now) }
    }

    public func emptyRecycleBin() throws(SessionError) {
        let now = clock()
        try edit { database in database.emptyRecycleBin(at: now) }
    }

    /// Sets an entry's custom icon (PNG data), reusing an identical icon
    /// already in the database so repeated downloads don't pile up copies.
    public func setCustomIcon(_ imageData: Data, forEntry id: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in
            guard var entry = database.entry(withID: id) else { throw EditError.entryNotFound(id) }
            let iconID =
                database.meta.customIcons.first { $0.value == imageData }?.key ?? UUID()
            database.meta.customIcons[iconID] = imageData
            entry.customIconID = iconID
            try database.update(entry, at: now)
        }
    }

    /// Creates an entry stamped with the current time.
    public func newEntry(title: String = "", userName: String = "", password: SecretString = .empty) -> Entry {
        var entry = Entry(times: Times(creation: clock()))
        entry.title = title
        entry.userName = userName
        entry.password = password
        return entry
    }

    private func edit(_ change: (inout Database) throws -> Void) throws(SessionError) {
        guard var database else { throw .locked }
        do {
            try change(&database)
        } catch {
            throw SessionError(error)
        }
        install(database)
        hasUnsavedChanges = true
    }

    // MARK: Saving

    /// Encrypts and writes the database. If the file changed on disk since
    /// it was read, merges that version in and retries once.
    public func save() async throws(SessionError) {
        guard let database, let key, let settings else { throw .locked }
        isSaving = true
        defer { isSaving = false }
        do {
            try await write(database, key: key, settings: settings)
        } catch .changedOnDisk {
            try await mergeFromDisk(key: key)
            guard let merged = self.database else { throw .locked }
            try await write(merged, key: key, settings: settings)
        } catch {
            throw error
        }
    }

    /// Reads the file and merges it into the open database without saving.
    /// Used when the app learns the file changed (or an extension left a
    /// pending working copy).
    public func mergeFromDisk() async throws(SessionError) {
        guard let key else { throw .locked }
        try await mergeFromDisk(key: key)
    }

    /// Merges another copy of the database (for example an extension's
    /// working copy or a "conflicted copy" file) into this one.
    public func merge(_ other: Database) throws(SessionError) {
        guard let database else { throw .locked }
        let result = Merger.merge(local: database, remote: other, base: base)
        lastMergeReport = result.report
        guard !result.report.isEmpty else { return }
        install(result.merged)
        hasUnsavedChanges = true
    }

    private func mergeFromDisk(key: CompositeKey) async throws(SessionError) {
        do {
            let (data, version) = try await file.read()
            let decoded = try await codec.decode(data, key: key, memoryLimit: memoryLimit)
            try merge(decoded.database)
            base = decoded.database
            fileVersion = version
            hasUnsavedChanges = true
        } catch let error as SessionError {
            throw error
        } catch {
            throw SessionError(error)
        }
    }

    private func write(_ database: Database, key: CompositeKey, settings: EncryptionSettings) async throws(SessionError)
    {
        do {
            let data = try await Trace.span(.saveEncrypt) {
                try await codec.encode(database, settings: settings, key: key, context: formatContext)
            }
            let version = try await Trace.span(.saveReplace, argument: UInt64(data.count)) {
                try await file.write(data, expecting: fileVersion)
            }
            fileVersion = version
            base = database
            hasUnsavedChanges = false
            lastSaved = clock()
        } catch let FileError.changedOnDisk(current) {
            throw .changedOnDisk(current)
        } catch {
            throw SessionError(error)
        }
    }

    private func install(_ database: Database) {
        self.database = database
        searchIndex = SearchIndex(database)
    }
}

public enum SessionError: Error, Equatable, Sendable {
    case locked
    case emptyKey
    case invalidKey
    case unsupportedFormat(String)
    case corrupted(String)
    case keyDerivationTooExpensive(memoryBytes: UInt64)
    case changedOnDisk(FileVersion)
    case file(FileError)
    case edit(EditError)
    case other(String)

    init(_ error: any Error) {
        switch error {
        case let error as SessionError: self = error
        case let error as FileError: self = .file(error)
        case let error as EditError: self = .edit(error)
        case let error as CodecError:
            switch error {
            case .invalidKey: self = .invalidKey
            case .unsupportedFormat(let detail): self = .unsupportedFormat(detail)
            case .corrupted(let detail): self = .corrupted(detail)
            case .keyDerivationTooExpensive(let memory): self = .keyDerivationTooExpensive(memoryBytes: memory)
            }
        default: self = .other(String(describing: type(of: error)))
        }
    }
}
