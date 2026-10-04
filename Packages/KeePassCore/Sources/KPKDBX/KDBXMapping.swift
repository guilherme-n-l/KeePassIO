import Foundation
import KDBXKit
import KPModel

/// Converts between KDBXKit's file model and KPModel.
///
/// KDBX properties KPModel doesn't model are carried in `extras` under
/// `kdbx.*` keys, so they survive edits and merges and are written back.
enum KDBXMapping {
    enum ExtraKey {
        static let autoType = "kdbx.autoType"
        static let qualityCheck = "kdbx.qualityCheck"
        static let protectedAttachments = "kdbx.protectedAttachments"
        static let defaultAutoTypeSequence = "kdbx.defaultAutoTypeSequence"
        static let enableAutoType = "kdbx.enableAutoType"
        static let enableSearching = "kdbx.enableSearching"
        static let lastTopVisibleEntry = "kdbx.lastTopVisibleEntry"
        static let unknownElements = "kdbx.unknownElements"
    }

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    // MARK: KDBXKit to KPModel

    static func model(from content: KDBXContent) -> Database {
        let kdbx = content.database
        let pool = content.innerHeader.binaryContent
        let meta = kdbx.meta
        let recycleBin = meta.recycleBinUUID.flatMap { $0 == zeroUUID ? nil : $0 }
        let model = Meta(
            name: meta.databaseName ?? "",
            description: meta.databaseDescription ?? "",
            defaultUserName: meta.defaultUserName ?? "",
            recycleBinEnabled: meta.recycleBinEnabled ?? true,
            recycleBinID: recycleBin,
            historyMaxItems: meta.historyMaxItems.map { limit in
                if case .value(let value) = limit { Int(value) } else { -1 }
            } ?? 10,
            historyMaxSize: meta.historyMaxSize.map { limit in
                if case .value(let value) = limit { Int(clamping: value) } else { -1 }
            } ?? 6 * 1024 * 1024,
            customIcons: Dictionary(
                meta.customIcons.map { ($0.uuid, $0.data) },
                uniquingKeysWith: { first, _ in first }
            ),
            customData: Dictionary(meta.customData.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }),
            settingsChanged: meta.settingsChanged ?? Date(timeIntervalSince1970: 0)
        )
        let deleted = Dictionary(
            kdbx.root.deletedObjects.map { ($0.uuid, $0.deletionTime) },
            uniquingKeysWith: { first, second in max(first, second) }
        )
        return Database(meta: model, root: group(from: kdbx.root.group, pool: pool), deletedObjects: deleted)
    }

    static func group(from group: KDBX.Group, pool: [InnerHeader.BinaryContent]) -> KPModel.Group {
        var extras: [String: String] = [:]
        extras[ExtraKey.defaultAutoTypeSequence] = group.defaultAutoTypeSequence
        extras[ExtraKey.enableAutoType] = group.enableAutoType.map(encode)
        extras[ExtraKey.enableSearching] = group.enableSearching.map(encode)
        extras[ExtraKey.lastTopVisibleEntry] = group.lastTopVisibleEntry?.uuidString
        extras[ExtraKey.unknownElements] = UnknownElementCoding.encode(group.unknownElements)
        return KPModel.Group(
            id: group.uuid,
            name: group.name ?? "",
            notes: group.notes ?? "",
            iconID: Int(group.iconID),
            customIconID: group.customIconUUID,
            times: times(from: group.times),
            isExpanded: group.isExpanded ?? true,
            groups: group.groups.map { self.group(from: $0, pool: pool) },
            entries: group.entries.map { entry(from: $0, pool: pool) },
            customData: Dictionary(
                group.customData.map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            ),
            tags: group.tags,
            previousParentGroup: group.previousParentGroup,
            extras: extras
        )
    }

    static func entry(from entry: KDBX.Entry, pool: [InnerHeader.BinaryContent]) -> Entry {
        var fields: [String: FieldValue] = [:]
        for string in entry.strings {
            switch string.value {
            case .regular(let bytes):
                fields[string.key] = .plain(bytes.revealedString)
            case .unprotected, .protectedInMemory, .lazyInnerCipher:
                // All three are protected in the file ("unprotected" means
                // not protected in memory, still protected on disk).
                fields[string.key] = .protected(SecretString(bytes: Array(string.value.bytes.toData())))
            }
        }
        var attachments: [String: Data] = [:]
        var protectedAttachments: [String] = []
        for binary in entry.binaries {
            switch binary.value {
            case .inline(let data, let isProtected):
                attachments[binary.key] = data
                if isProtected { protectedAttachments.append(binary.key) }
            case .ref(let index):
                guard Int(index) < pool.count else { continue }
                attachments[binary.key] = pool[Int(index)].data
                if pool[Int(index)].shouldBeProtected { protectedAttachments.append(binary.key) }
            }
        }
        var extras: [String: String] = [:]
        extras[ExtraKey.autoType] = entry.autoType.flatMap(encode)
        extras[ExtraKey.qualityCheck] = entry.qualityCheck.map { $0 ? "true" : "false" }
        extras[ExtraKey.unknownElements] = UnknownElementCoding.encode(entry.unknownElements)
        if !protectedAttachments.isEmpty {
            extras[ExtraKey.protectedAttachments] = protectedAttachments.sorted().joined(separator: "\n")
        }
        return Entry(
            id: entry.uuid,
            fields: fields,
            attachments: attachments,
            tags: entry.tags,
            iconID: Int(entry.iconID),
            customIconID: entry.customIconUUID,
            times: times(from: entry.times),
            history: entry.history.map { self.entry(from: $0, pool: pool) },
            customData: Dictionary(
                entry.customData.map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            ),
            previousParentGroup: entry.previousParentGroup,
            foregroundColor: entry.foregroundColor.flatMap(colorString),
            backgroundColor: entry.backgroundColor.flatMap(colorString),
            overrideURL: entry.overrideURL,
            extras: extras
        )
    }

    static func times(from times: KDBX.Times?) -> Times {
        let creation = times?.creationTime ?? times?.lastModificationTime ?? Date(timeIntervalSince1970: 0)
        return Times(
            creation: creation,
            lastModification: times?.lastModificationTime,
            lastAccess: times?.lastAccessTime,
            locationChanged: times?.locationChanged,
            expiry: times?.expires == true ? times?.expiryTime : nil,
            usageCount: Int(clamping: times?.usageCount ?? 0)
        )
    }

    // MARK: Small conversions

    static func colorString(_ color: KDBX.Color) -> String? {
        let text = color.description
        return text.isEmpty ? nil : text
    }

    static func color(_ text: String) -> KDBX.Color? {
        guard text.hasPrefix("#"), text.count == 7, let value = UInt32(text.dropFirst(), radix: 16) else {
            return nil
        }
        return .color(red: UInt8((value >> 16) & 0xff), green: UInt8((value >> 8) & 0xff), blue: UInt8(value & 0xff))
    }

    static func encode(_ value: KDBX.NullableBoolEx) -> String {
        switch value {
        case .value(let flag): flag ? "true" : "false"
        case .null: "null"
        }
    }

    static func decodeNullableBool(_ text: String) -> KDBX.NullableBoolEx {
        switch text {
        case "true": .value(true)
        case "false": .value(false)
        default: .null
        }
    }

    private struct AutoTypeAssociationJSON: Codable {
        let window: String
        let sequence: String
    }

    private struct AutoTypeJSON: Codable {
        // Optional like the file format's own field: absent, true or false.
        let enabled: Bool?  // swiftlint:disable:this discouraged_optional_boolean
        let obfuscation: Int32?
        let defaultSequence: String?
        let associations: [AutoTypeAssociationJSON]
    }

    static func encode(_ autoType: KDBX.AutoType) -> String? {
        let json = AutoTypeJSON(
            enabled: autoType.enabled,
            obfuscation: autoType.dataTransferObfuscation?.rawValue,
            defaultSequence: autoType.defaultSequence,
            associations: autoType.association.map { .init(window: $0.window, sequence: $0.keystrokeSequence) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(json)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    static func decodeAutoType(_ text: String) -> KDBX.AutoType? {
        guard let json = try? JSONDecoder().decode(AutoTypeJSON.self, from: Data(text.utf8)) else { return nil }
        return KDBX.AutoType(
            enabled: json.enabled,
            dataTransferObfuscation: json.obfuscation.flatMap(KDBX.AutoType.DataTransferObfuscation.init(rawValue:)),
            defaultSequence: json.defaultSequence,
            association: json.associations.map { .init(window: $0.window, keystrokeSequence: $0.sequence) }
        )
    }
}
