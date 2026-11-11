import Foundation
import KPModel

extension MergeState {
    // MARK: Entries

    mutating func mergeEntries() {
        let ids = Set(localIndex.entries.keys).union(remoteIndex.entries.keys)
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            switch (localIndex.entries[id], remoteIndex.entries[id]) {
            case (let localNode?, let remoteNode?):
                entries[id] = mergedEntry(local: localNode, remote: remoteNode)
            case (let localNode?, nil):
                mergeOneSidedEntry(localNode, presentOn: .local)
            case (nil, let remoteNode?):
                mergeOneSidedEntry(remoteNode, presentOn: .remote)
            case (nil, nil):
                break
            }
        }
    }

    /// An entry present on only one side: either new there, or deleted on
    /// the other side.
    mutating func mergeOneSidedEntry(_ node: Index.Node<Entry>, presentOn side: MergeSide) {
        let entry = node.item
        let otherSide: MergeSide = side == .local ? .remote : .local
        if let deletion = deletionTime(of: entry.id, onSide: otherSide, lastModified: entry.times) {
            if side == .local {
                report.changes.append(.entryDeleted(id: entry.id, title: entry.title))
            }
            deletedObjects[entry.id] = max(deletedObjects[entry.id] ?? deletion, deletion)
            return
        }
        var node = node
        if side == .remote {
            node.order += Self.remoteOrderOffset
        }
        entries[entry.id] = node
        let wasDeletedOnOtherSide =
            (otherSide == .local ? local : remote).deletedObjects[entry.id] != nil
            || baseIndex?.entries[entry.id] != nil
        if wasDeletedOnOtherSide {
            deletedObjects[entry.id] = nil
            report.changes.append(.entryRestored(id: entry.id, title: entry.title))
        } else if side == .remote {
            report.changes.append(.entryAdded(id: entry.id, title: entry.title))
        }
    }

    mutating func mergedEntry(local: Index.Node<Entry>, remote: Index.Node<Entry>) -> Index.Node<Entry> {
        var result = local
        let localEntry = local.item
        let remoteEntry = remote.item
        let remoteIsNewer = remoteEntry.times.lastModification > localEntry.times.lastModification

        if !localEntry.hasSameContent(as: remoteEntry) {
            var merged: Entry
            let baseEntry = baseIndex?.entries[localEntry.id]?.item ?? sharedVersion(of: localEntry, and: remoteEntry)
            if let baseEntry {
                merged = threeWayContent(local: localEntry, remote: remoteEntry, base: baseEntry)
            } else {
                merged = remoteIsNewer ? remoteEntry : localEntry
            }
            merged.times = mergedTimes(localEntry.times, remoteEntry.times)
            merged.history = mergedHistory(
                localEntry.history + remoteEntry.history + [localEntry.historySnapshot, remoteEntry.historySnapshot],
                current: merged
            )
            result.item = merged
            if !merged.hasSameContent(as: localEntry) {
                report.changes.append(.entryUpdated(id: localEntry.id, title: merged.title))
            }
        } else {
            var merged = localEntry
            merged.times = mergedTimes(localEntry.times, remoteEntry.times)
            merged.history = mergedHistory(localEntry.history + remoteEntry.history, current: merged)
            if merged.history.count != localEntry.history.count {
                report.changes.append(.entryUpdated(id: localEntry.id, title: merged.title))
            }
            result.item = merged
        }

        let remoteMovedLater = remoteEntry.times.locationChanged > localEntry.times.locationChanged
        if remoteMovedLater, remote.parent != local.parent, let parent = remote.parent {
            result.parent = parent
            result.item.previousParentGroup = remoteEntry.previousParentGroup
            report.changes.append(.entryMoved(id: localEntry.id, title: result.item.title, toGroup: parent))
        }
        return result
    }

    /// The newest version of an entry that both copies have, as the
    /// current version or in history: what they looked like before they
    /// diverged. Nil when their histories share nothing, for example after
    /// one of them was trimmed.
    func sharedVersion(of local: Entry, and remote: Entry) -> Entry? {
        let remoteVersions = remote.history + [remote]
        let localVersions = (local.history + [local]).sorted {
            $0.times.lastModification > $1.times.lastModification
        }
        return localVersions.first { candidate in
            remoteVersions.contains {
                $0.times.lastModification == candidate.times.lastModification && $0.hasSameContent(as: candidate)
            }
        }
    }

    /// Per-field merge against the common base: a field changed on only one
    /// side takes that side's value; a field changed differently on both is
    /// a conflict, won by the side the user chose or else the newer side.
    mutating func threeWayContent(local: Entry, remote: Entry, base: Entry) -> Entry {
        let remoteIsNewer = remote.times.lastModification > local.times.lastModification
        let newerSide: MergeSide = remoteIsNewer ? .remote : .local
        var result = remoteIsNewer ? remote : local
        var conflictingFields: [String] = []

        /// The value for one field or attachment, noting a conflict.
        func resolve<Value: Equatable>(_ local: Value, _ remote: Value, base: Value, reportedAs field: String) -> Value
        {
            if let value = pick(local, remote, base: base) {
                return value
            }
            conflictingFields.append(field)
            return (choices[result.id, field] ?? newerSide) == .remote ? remote : local
        }

        let fieldNames = Set(local.fields.keys).union(remote.fields.keys).union(base.fields.keys)
        for name in fieldNames.sorted() {
            result.fields[name] = resolve(
                local.fields[name],
                remote.fields[name],
                base: base.fields[name],
                reportedAs: name
            )
        }

        let attachmentNames = Set(local.attachments.keys).union(remote.attachments.keys)
            .union(base.attachments.keys)
        for name in attachmentNames.sorted() {
            result.attachments[name] = resolve(
                local.attachments[name],
                remote.attachments[name],
                base: base.attachments[name],
                reportedAs: MergeConflict.attachmentField(name)
            )
        }

        mergeUnreportedProperties(into: &result, local: local, remote: remote, base: base)

        if !conflictingFields.isEmpty {
            report.conflicts.append(
                MergeConflict(
                    entryID: local.id,
                    title: result.title,
                    fields: conflictingFields,
                    winner: newerSide
                )
            )
        }
        return result
    }

    /// Tags, icons and custom data: changed on both sides, these follow the
    /// newer side without being reported.
    func mergeUnreportedProperties(into result: inout Entry, local: Entry, remote: Entry, base: Entry) {
        let remoteIsNewer = remote.times.lastModification > local.times.lastModification
        func newer<Value>(_ local: Value, _ remote: Value) -> Value { remoteIsNewer ? remote : local }
        result.tags = pick(local.tags, remote.tags, base: base.tags) ?? newer(local.tags, remote.tags)
        result.customData =
            pick(local.customData, remote.customData, base: base.customData)
            ?? newer(local.customData, remote.customData)
        result.iconID = pick(local.iconID, remote.iconID, base: base.iconID) ?? newer(local.iconID, remote.iconID)
        result.extras = pick(local.extras, remote.extras, base: base.extras) ?? newer(local.extras, remote.extras)
        result.customIconID =
            pick(local.customIconID, remote.customIconID, base: base.customIconID)
            ?? newer(local.customIconID, remote.customIconID)
    }

    /// The value both sides agree on or that only one side changed since
    /// `base`; nil when they changed it differently.
    func pick<Value: Equatable>(_ local: Value, _ remote: Value, base: Value) -> Value? {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }
        return nil
    }

    func mergedTimes(_ local: Times, _ remote: Times) -> Times {
        var times = remote.lastModification > local.lastModification ? remote : local
        times.creation = min(local.creation, remote.creation)
        times.lastModification = max(local.lastModification, remote.lastModification)
        times.lastAccess = max(local.lastAccess, remote.lastAccess)
        times.usageCount = max(local.usageCount, remote.usageCount)
        times.locationChanged = max(local.locationChanged, remote.locationChanged)
        return times
    }

    /// Union of history versions, without duplicates or the current
    /// version, oldest first, trimmed to the database limits.
    func mergedHistory(_ candidates: [Entry], current: Entry) -> [Entry] {
        var kept: [Entry] = []
        for candidate in candidates.sorted(by: { $0.times.lastModification < $1.times.lastModification }) {
            let snapshot = candidate.historySnapshot
            if snapshot.hasSameContent(as: current), snapshot.times.lastModification == current.times.lastModification {
                continue
            }
            let duplicate = kept.contains {
                $0.times.lastModification == snapshot.times.lastModification && $0.hasSameContent(as: snapshot)
            }
            if !duplicate {
                kept.append(snapshot)
            }
        }
        return trimmed(kept)
    }

    func trimmed(_ history: [Entry]) -> [Entry] {
        var result = history
        if meta.historyMaxItems >= 0, result.count > meta.historyMaxItems {
            result.removeFirst(result.count - meta.historyMaxItems)
        }
        return result
    }
}
