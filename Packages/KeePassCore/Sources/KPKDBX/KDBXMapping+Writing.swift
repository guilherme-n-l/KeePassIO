import Foundation
import KDBXKit
import KPModel

extension KDBXMapping {
    // MARK: KPModel to KDBXKit

    struct Output {
        var database: KDBX
        var binaries: [InnerHeader.BinaryContent]
    }

    /// Builds the KDBX tree for `database`, keeping metadata from
    /// `previous` (the last file read) that KPModel doesn't model.
    static func kdbx(from database: Database, previous: KDBX) -> Output {
        var pool = BinaryPool()
        let meta = self.meta(from: database.meta, previous: previous.meta)
        let root = group(from: database.root, pool: &pool)
        let deleted = database.deletedObjects
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { KDBX.DeletedObject(uuid: $0.key, deletionTime: $0.value) }
        return Output(
            database: KDBX(meta: meta, root: KDBX.Root(group: root, deletedObjects: deleted)),
            binaries: pool.contents
        )
    }

    /// Applies KPModel's metadata onto the previous file's, updating the
    /// per-setting change times KeePass keeps.
    static func meta(from model: Meta, previous: KDBX.Meta) -> KDBX.Meta {
        var meta = previous
        let now = Date()
        if meta.databaseName != model.name {
            meta.databaseName = model.name
            meta.databaseNameChanged = now
        }
        if (meta.databaseDescription ?? "") != model.description {
            meta.databaseDescription = model.description
            meta.databaseDescriptionChanged = now
        }
        if (meta.defaultUserName ?? "") != model.defaultUserName {
            meta.defaultUserName = model.defaultUserName
            meta.defaultUserNameChanged = now
        }
        let recycleBin = model.recycleBinID ?? zeroUUID
        if meta.recycleBinUUID != recycleBin {
            meta.recycleBinUUID = recycleBin
            meta.recycleBinChanged = now
        }
        meta.recycleBinEnabled = model.recycleBinEnabled
        meta.historyMaxItems = model.historyMaxItems < 0 ? .unlimited : .value(UInt32(clamping: model.historyMaxItems))
        meta.historyMaxSize = model.historyMaxSize < 0 ? .unlimited : .value(UInt64(model.historyMaxSize))
        meta.settingsChanged = model.settingsChanged
        let previousIcons = Dictionary(meta.customIcons.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        meta.customIcons = model.customIcons.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            let data = model.customIcons[id] ?? Data()
            let old = previousIcons[id]
            return KDBX.CustomIcon(
                uuid: id,
                data: data,
                name: old?.name,
                lastModificationTime: old?.data == data ? old?.lastModificationTime : now
            )
        }
        let previousCustomData = Dictionary(
            meta.customData.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        meta.customData = model.customData.keys.sorted().map { key in
            let value = model.customData[key] ?? ""
            let old = previousCustomData[key]
            return KDBX.CustomDataWithTimes(
                key: key,
                value: value,
                lastModificationTime: old?.value == value ? old?.lastModificationTime : now
            )
        }

        return meta
    }

    static func group(from group: KPModel.Group, pool: inout BinaryPool) -> KDBX.Group {
        KDBX.Group(
            uuid: group.id,
            name: group.name,
            notes: group.notes.isEmpty ? nil : group.notes,
            iconID: UInt32(clamping: group.iconID),
            customIconUUID: group.customIconID,
            times: times(from: group.times),
            isExpanded: group.isExpanded,
            defaultAutoTypeSequence: group.extras[ExtraKey.defaultAutoTypeSequence],
            enableAutoType: group.extras[ExtraKey.enableAutoType].map(decodeNullableBool),
            enableSearching: group.extras[ExtraKey.enableSearching].map(decodeNullableBool),
            lastTopVisibleEntry: group.extras[ExtraKey.lastTopVisibleEntry].flatMap(UUID.init(uuidString:)),
            previousParentGroup: group.previousParentGroup,
            tags: group.tags,
            customData: group.customData.keys.sorted().map {
                KDBX.CustomDataItem(key: $0, value: group.customData[$0] ?? "")
            },
            entries: group.entries.map { entry(from: $0, pool: &pool) },
            groups: group.groups.map { self.group(from: $0, pool: &pool) }
        )
    }

    static func entry(from entry: Entry, pool: inout BinaryPool) -> KDBX.Entry {
        let strings = entry.fields.keys.sorted(by: fieldOrder).map { key in
            let value: KDBX.ProtectedString.Value =
                switch entry.fields[key] ?? .plain("") {
                case .plain(let text): .regular(text)
                case .protected(let secret): .protectedInMemory(secret.withBytes { SecureBytes($0) })
                }
            return KDBX.ProtectedString(key: key, value: value)
        }
        let protectedNames = Set(
            (entry.extras[ExtraKey.protectedAttachments] ?? "").split(separator: "\n").map(String.init)
        )
        let binaries = entry.attachments.keys.sorted().map { name in
            let index = pool.index(for: entry.attachments[name] ?? Data(), protected: protectedNames.contains(name))
            return KDBX.ProtectedBinary(key: name, value: .ref(index))
        }
        return KDBX.Entry(
            uuid: entry.id,
            iconID: UInt32(clamping: entry.iconID),
            customIconUUID: entry.customIconID,
            foregroundColor: entry.foregroundColor.flatMap(color),
            backgroundColor: entry.backgroundColor.flatMap(color),
            overrideURL: entry.overrideURL,
            qualityCheck: entry.extras[ExtraKey.qualityCheck].map { $0 == "true" },
            tags: entry.tags,
            previousParentGroup: entry.previousParentGroup,
            times: times(from: entry.times),
            strings: strings,
            binaries: binaries,
            autoType: entry.extras[ExtraKey.autoType].flatMap(decodeAutoType),
            customData: entry.customData.keys.sorted().map {
                KDBX.CustomDataItem(key: $0, value: entry.customData[$0] ?? "")
            },
            history: entry.history.map { self.entry(from: $0, pool: &pool) }
        )
    }

    static func times(from times: Times) -> KDBX.Times {
        KDBX.Times(
            creationTime: times.creation,
            lastModificationTime: times.lastModification,
            lastAccessTime: times.lastAccess,
            expiryTime: times.expiry ?? times.creation,
            expires: times.expiry != nil,
            usageCount: UInt64(max(0, times.usageCount)),
            locationChanged: times.locationChanged
        )
    }

    /// Standard fields first in KeePass's order, then custom fields by name.
    static func fieldOrder(_ lhs: String, _ rhs: String) -> Bool {
        let standard = Entry.StandardField.all
        switch (standard.firstIndex(of: lhs), standard.firstIndex(of: rhs)) {
        case (let left?, let right?): return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs < rhs
        }
    }

    /// The inner header's attachment pool; identical attachments are stored
    /// once.
    struct BinaryPool {
        private(set) var contents: [InnerHeader.BinaryContent] = []
        private var indexByData: [Data: UInt32] = [:]

        mutating func index(for data: Data, protected: Bool) -> UInt32 {
            if let index = indexByData[data] { return index }
            let index = UInt32(contents.count)
            contents.append(InnerHeader.BinaryContent(shouldBeProtected: protected, data: data))
            indexByData[data] = index
            return index
        }
    }
}
