import Foundation

/// Where an item sits in the tree.
public struct Location: Sendable, Equatable, Hashable {
    /// Group IDs from the root (inclusive) to the item's parent (inclusive).
    public var path: [UUID]
    public var parentID: UUID { path[path.count - 1] }
}

public enum EditError: Error, Equatable, Sendable {
    case entryNotFound(UUID)
    case groupNotFound(UUID)
    case cannotMoveGroupIntoItself
    case cannotDeleteRoot
}

extension Group {
    /// Depth-first visit of this group and every group below it, with the
    /// path of group IDs from this group to the visited group.
    public func forEachGroup(path: [UUID] = [], _ body: (Group, [UUID]) throws -> Void) rethrows {
        let here = path + [id]
        try body(self, here)
        for child in groups {
            try child.forEachGroup(path: here, body)
        }
    }

    /// Every entry in this group and its subgroups.
    public var allEntries: [Entry] {
        var result: [Entry] = []
        forEachGroup { group, _ in result.append(contentsOf: group.entries) }
        return result
    }

    /// Applies `change` to the group with `id` anywhere below (or at) this
    /// group. Returns false if it doesn't exist.
    @discardableResult
    mutating func modifyGroup(_ id: UUID, _ change: (inout Group) throws -> Void) rethrows -> Bool {
        if self.id == id {
            try change(&self)
            return true
        }
        for index in groups.indices where try groups[index].modifyGroup(id, change) {
            return true
        }
        return false
    }
}

extension Database {
    // MARK: Lookup

    public func entry(withID id: UUID) -> Entry? {
        var found: Entry?
        root.forEachGroup { group, _ in
            if found == nil, let entry = group.entries.first(where: { $0.id == id }) {
                found = entry
            }
        }
        return found
    }

    public func group(withID id: UUID) -> Group? {
        var found: Group?
        root.forEachGroup { group, _ in
            if found == nil, group.id == id { found = group }
        }
        return found
    }

    public func location(ofEntry id: UUID) -> Location? {
        var found: Location?
        root.forEachGroup { group, path in
            if found == nil, group.entries.contains(where: { $0.id == id }) {
                found = Location(path: path)
            }
        }
        return found
    }

    public func location(ofGroup id: UUID) -> Location? {
        var found: Location?
        root.forEachGroup { group, path in
            if found == nil, group.groups.contains(where: { $0.id == id }) {
                found = Location(path: path)
            }
        }
        return found
    }

    /// All entries except those in the recycle bin.
    public var activeEntries: [Entry] {
        var result: [Entry] = []
        root.forEachGroup { group, path in
            if let bin = meta.recycleBinID, path.contains(bin) { return }
            result.append(contentsOf: group.entries)
        }
        return result
    }

    public var recycleBin: Group? {
        meta.recycleBinID.flatMap { group(withID: $0) }
    }

    // MARK: Entries

    /// Adds `entry` to the group with `groupID`.
    public mutating func add(_ entry: Entry, to groupID: UUID) throws(EditError) {
        let added = root.modifyGroup(groupID) { $0.entries.append(entry) }
        guard added else { throw .groupNotFound(groupID) }
    }

    /// Replaces an entry's content, saving the previous version to its
    /// history and updating its modification time. Does nothing when the
    /// content is unchanged.
    public mutating func update(_ entry: Entry, at date: Date = Date()) throws(EditError) {
        guard let location = location(ofEntry: entry.id) else { throw .entryNotFound(entry.id) }
        let maxItems = meta.historyMaxItems
        let maxSize = meta.historyMaxSize
        root.modifyGroup(location.parentID) { group in
            guard let index = group.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            let old = group.entries[index]
            guard !old.hasSameContent(as: entry) else { return }
            var updated = entry
            updated.history = old.history + [old.historySnapshot]
            updated.times.lastModification = date
            updated.times.lastAccess = date
            updated.history = Self.trimmedHistory(updated.history, maxItems: maxItems, maxSize: maxSize)
            group.entries[index] = updated
        }
    }

    /// Moves an entry to another group, recording where it came from.
    public mutating func moveEntry(_ id: UUID, to groupID: UUID, at date: Date = Date()) throws(EditError) {
        guard let location = location(ofEntry: id), var entry = entry(withID: id) else {
            throw .entryNotFound(id)
        }
        guard group(withID: groupID) != nil else { throw .groupNotFound(groupID) }
        guard location.parentID != groupID else { return }
        root.modifyGroup(location.parentID) { $0.entries.removeAll { $0.id == id } }
        entry.previousParentGroup = location.parentID
        entry.times.locationChanged = date
        root.modifyGroup(groupID) { $0.entries.append(entry) }
    }

    /// Deletes an entry: moves it to the recycle bin when that's enabled
    /// and it isn't already there, otherwise removes it for good and
    /// records the deletion so merges don't resurrect it.
    public mutating func deleteEntry(_ id: UUID, at date: Date = Date()) throws(EditError) {
        guard let location = location(ofEntry: id) else { throw .entryNotFound(id) }
        if meta.recycleBinEnabled {
            let binID = ensureRecycleBin(at: date)
            if !location.path.contains(binID) {
                try moveEntry(id, to: binID, at: date)
                return
            }
        }
        root.modifyGroup(location.parentID) { $0.entries.removeAll { $0.id == id } }
        deletedObjects[id] = date
    }

    // MARK: Groups

    public mutating func add(_ group: Group, to parentID: UUID) throws(EditError) {
        let added = root.modifyGroup(parentID) { $0.groups.append(group) }
        guard added else { throw .groupNotFound(parentID) }
    }

    /// Renames or otherwise edits a group's own properties (not its
    /// children).
    public mutating func updateGroupProperties(_ group: Group, at date: Date = Date()) throws(EditError) {
        let found = root.modifyGroup(group.id) { existing in
            guard !existing.hasSameProperties(as: group) else { return }
            existing.name = group.name
            existing.notes = group.notes
            existing.iconID = group.iconID
            existing.customIconID = group.customIconID
            existing.customData = group.customData
            existing.tags = group.tags
            existing.times.expiry = group.times.expiry
            existing.times.lastModification = date
        }
        guard found else { throw .groupNotFound(group.id) }
    }

    public mutating func moveGroup(_ id: UUID, to parentID: UUID, at date: Date = Date()) throws(EditError) {
        guard let location = location(ofGroup: id), var moving = group(withID: id) else {
            throw .groupNotFound(id)
        }
        guard group(withID: parentID) != nil else { throw .groupNotFound(parentID) }
        guard moving.group(withIDInSubtree: parentID) == nil else { throw .cannotMoveGroupIntoItself }
        guard location.parentID != parentID else { return }
        root.modifyGroup(location.parentID) { $0.groups.removeAll { $0.id == id } }
        moving.previousParentGroup = location.parentID
        moving.times.locationChanged = date
        root.modifyGroup(parentID) { $0.groups.append(moving) }
    }

    /// Deletes a group with everything in it, through the recycle bin
    /// like `deleteEntry`.
    public mutating func deleteGroup(_ id: UUID, at date: Date = Date()) throws(EditError) {
        guard id != root.id else { throw .cannotDeleteRoot }
        guard let location = location(ofGroup: id), let doomed = group(withID: id) else {
            throw .groupNotFound(id)
        }
        if meta.recycleBinEnabled, id != meta.recycleBinID {
            let binID = ensureRecycleBin(at: date)
            if !location.path.contains(binID) {
                try moveGroup(id, to: binID, at: date)
                return
            }
        }
        root.modifyGroup(location.parentID) { $0.groups.removeAll { $0.id == id } }
        doomed.forEachGroup { group, _ in
            deletedObjects[group.id] = date
            for entry in group.entries {
                deletedObjects[entry.id] = date
            }
        }
        if id == meta.recycleBinID {
            meta.recycleBinID = nil
            meta.settingsChanged = date
        }
    }

    /// Permanently deletes everything in the recycle bin.
    public mutating func emptyRecycleBin(at date: Date = Date()) {
        guard let bin = recycleBin else { return }
        for child in bin.groups {
            try? deleteGroup(child.id, at: date)
        }
        for entry in bin.entries {
            try? deleteEntry(entry.id, at: date)
        }
    }

    /// The recycle bin's ID, creating the bin under the root if needed.
    @discardableResult
    public mutating func ensureRecycleBin(at date: Date = Date()) -> UUID {
        if let id = meta.recycleBinID, group(withID: id) != nil {
            return id
        }
        let bin = Group(name: "Recycle Bin", iconID: 43, times: Times(creation: date), isExpanded: false)
        root.groups.append(bin)
        meta.recycleBinID = bin.id
        meta.settingsChanged = date
        return bin.id
    }

    // MARK: History

    /// Keeps the newest history items within the database's limits.
    static func trimmedHistory(_ history: [Entry], maxItems: Int, maxSize: Int) -> [Entry] {
        var result = history
        if maxItems >= 0, result.count > maxItems {
            result.removeFirst(result.count - maxItems)
        }
        if maxSize >= 0 {
            while !result.isEmpty, result.reduce(0, { $0 + $1.approximateSize }) > maxSize {
                result.removeFirst()
            }
        }
        return result
    }
}

extension Group {
    func group(withIDInSubtree id: UUID) -> Group? {
        var found: Group?
        forEachGroup { group, _ in
            if found == nil, group.id == id { found = group }
        }
        return found
    }
}

extension Entry {
    /// Rough size in bytes for history limits: field and attachment bytes.
    var approximateSize: Int {
        fields.reduce(0) { total, field in
            let valueSize =
                switch field.value {
                case .plain(let text): text.utf8.count
                case .protected(let secret): secret.byteCount
                }
            return total + field.key.utf8.count + valueSize
        } + attachments.values.reduce(0) { $0 + $1.count }
    }
}
