import Foundation
import KPModel
import KPObservability

/// Merges two copies of a database, KeePass style.
///
/// Items are matched by UUID. When `base` (the last version both copies
/// shared, such as this device's last save) is available the merge is
/// three-way and per field, so independent edits to different fields of
/// the same entry both survive. Without it, the newer version of each item
/// wins. Either way the losing version of an entry is kept in its history,
/// so no data is lost; deletions recorded in `deletedObjects` win only over
/// versions older than the deletion.
///
/// `merge` is a pure function: it never modifies its inputs, which lets the
/// app show the report for review before saving the result.
public enum Merger {
    public static func merge(local: Database, remote: Database, base: Database? = nil) -> MergeResult {
        Trace.span(.mergePlan, argument: UInt64(local.root.allEntries.count)) {
            var merge = MergeState(local: local, remote: remote, base: base)
            merge.run()
            return MergeResult(merged: merge.buildDatabase(), report: merge.report)
        }
    }
}

struct MergeState {
    let local: Database
    let remote: Database
    let base: Database?
    let localIndex: Index
    let remoteIndex: Index
    let baseIndex: Index?

    var groups: [UUID: Index.Node<Group>] = [:]
    var entries: [UUID: Index.Node<Entry>] = [:]
    var deletedObjects: [UUID: Date] = [:]
    /// Groups the other side deleted; removed at the end if they end up
    /// empty, otherwise kept.
    var groupsToDeleteIfEmpty: [UUID: Date] = [:]
    var meta: Meta
    var report = MergeReport()

    init(local: Database, remote: Database, base: Database?) {
        self.local = local
        self.remote = remote
        self.base = base
        localIndex = Index(local)
        // Different copies can have different root UUIDs; roots always
        // correspond, so remote's root is mapped onto local's.
        remoteIndex = Index(remote, mappingRootTo: local.root.id)
        baseIndex = base.map { Index($0, mappingRootTo: local.root.id) }
        meta = local.meta
    }

    mutating func run() {
        mergeDeletedObjects()
        mergeMeta()
        mergeGroups()
        mergeEntries()
        resolveGroupDeletions()
    }

    // MARK: Deleted objects and settings

    mutating func mergeDeletedObjects() {
        deletedObjects = local.deletedObjects.merging(remote.deletedObjects, uniquingKeysWith: max)
    }

    mutating func mergeMeta() {
        guard remote.meta.settingsChanged > local.meta.settingsChanged else {
            meta.customIcons.merge(remote.meta.customIcons) { localIcon, _ in localIcon }
            return
        }
        var merged = remote.meta
        merged.customIcons = remote.meta.customIcons.merging(local.meta.customIcons) { remoteIcon, _ in remoteIcon }
        if merged != local.meta {
            report.changes.append(.settingsUpdated)
        }
        meta = merged
    }

    // MARK: Groups

    mutating func mergeGroups() {
        let ids = Set(localIndex.groups.keys).union(remoteIndex.groups.keys)
        for id in ids {
            let localNode = localIndex.groups[id]
            let remoteNode = remoteIndex.groups[id]
            switch (localNode, remoteNode) {
            case (let localNode?, let remoteNode?):
                groups[id] = mergedGroup(local: localNode, remote: remoteNode)
            case (let localNode?, nil):
                groups[id] = localNode
                if let deletion = deletionTime(of: id, onSide: .remote, lastModified: localNode.item.times) {
                    groupsToDeleteIfEmpty[id] = deletion
                }
            case (nil, let remoteNode?):
                if deletionTime(of: id, onSide: .local, lastModified: remoteNode.item.times) != nil {
                    continue
                }
                var node = remoteNode
                node.order += Self.remoteOrderOffset
                groups[id] = node
                report.changes.append(.groupAdded(id: id, name: remoteNode.item.name))
            case (nil, nil):
                break
            }
        }
    }

    mutating func mergedGroup(local: Index.Node<Group>, remote: Index.Node<Group>) -> Index.Node<Group> {
        var result = local
        let remoteIsNewer = remote.item.times.lastModification > local.item.times.lastModification
        if remoteIsNewer, !local.item.hasSameProperties(as: remote.item) {
            let localTimes = local.item.times
            result.item = remote.item
            result.item.times.creation = min(localTimes.creation, remote.item.times.creation)
            report.changes.append(.groupUpdated(id: local.item.id, name: remote.item.name))
        }
        let remoteMovedLater = remote.item.times.locationChanged > local.item.times.locationChanged
        if remoteMovedLater, remote.parent != local.parent, let parent = remote.parent {
            result.parent = parent
            result.item.times.locationChanged = remote.item.times.locationChanged
            result.item.previousParentGroup = remote.item.previousParentGroup
            report.changes.append(.groupMoved(id: local.item.id, name: result.item.name, toGroup: parent))
        }
        return result
    }

    // MARK: Deletions

    /// When the item was deleted on `side`, if that deletion should win
    /// over a version last modified at `times.lastModification`.
    func deletionTime(of id: UUID, onSide side: MergeSide, lastModified times: Times) -> Date? {
        let database = side == .local ? local : remote
        if let deleted = database.deletedObjects[id] {
            return deleted >= times.lastModification ? deleted : nil
        }
        // A client that doesn't record deletions: the item existed in the
        // base and is now missing. Treat it as deleted unless it changed
        // since the base.
        if let baseIndex, let baseTimes = baseIndex.entries[id]?.item.times ?? baseIndex.groups[id]?.item.times {
            return times.lastModification <= baseTimes.lastModification ? baseTimes.lastModification : nil
        }
        return nil
    }

    mutating func resolveGroupDeletions() {
        // Deepest groups first, so a parent sees its children's outcome.
        let ordered = groupsToDeleteIfEmpty.keys.sorted { depth(of: $0) > depth(of: $1) }
        for id in ordered {
            guard let node = groups[id], let deletion = groupsToDeleteIfEmpty[id] else { continue }
            let hasEntries = entries.values.contains { $0.parent == id }
            let hasGroups = groups.values.contains { $0.parent == id }
            if hasEntries || hasGroups {
                report.changes.append(.groupKept(id: id, name: node.item.name))
            } else {
                groups[id] = nil
                deletedObjects[id] = deletion
                report.changes.append(.groupDeleted(id: id, name: node.item.name))
            }
        }
    }

    func depth(of id: UUID) -> Int {
        var depth = 0
        var current = groups[id]?.parent
        while let parent = current, depth < 10_000 {
            depth += 1
            current = groups[parent]?.parent
        }
        return depth
    }
}
