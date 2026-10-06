import Foundation
import KPModel

extension MergeState {
    // MARK: Output

    static let remoteOrderOffset = 1 << 40

    func buildDatabase() -> Database {
        let rootID = local.root.id
        var childrenGroups: [UUID: [Index.Node<Group>]] = [:]
        for (id, node) in groups where id != rootID {
            // Re-home groups whose parent is gone or would create a cycle.
            let parent = node.parent.flatMap { groups[$0] != nil && !isAncestor(id, of: $0) ? $0 : nil } ?? rootID
            childrenGroups[parent, default: []].append(node)
        }
        var childrenEntries: [UUID: [Index.Node<Entry>]] = [:]
        for node in entries.values {
            let parent = node.parent.flatMap { groups[$0] != nil ? $0 : nil } ?? rootID
            childrenEntries[parent, default: []].append(node)
        }

        func build(_ id: UUID) -> Group {
            var group = groups[id]?.item ?? local.root
            group.id = id
            group.entries = (childrenEntries[id] ?? []).sorted { $0.order < $1.order }.map(\.item)
            group.groups = (childrenGroups[id] ?? []).sorted { $0.order < $1.order }.map { build($0.item.id) }
            return group
        }

        var present = Set(entries.keys).union(groups.keys)
        present.insert(rootID)
        let liveDeletions = deletedObjects.filter { !present.contains($0.key) }
        return Database(meta: meta, root: build(rootID), deletedObjects: liveDeletions)
    }

    func isAncestor(_ candidate: UUID, of id: UUID) -> Bool {
        var current: UUID? = id
        var steps = 0
        while let node = current, steps < 10_000 {
            if node == candidate { return true }
            current = groups[node]?.parent
            steps += 1
        }
        return false
    }
}
