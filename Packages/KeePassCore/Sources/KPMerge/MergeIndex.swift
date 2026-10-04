import Foundation
import KPModel

/// Flattened view of a database: every group and entry with its parent
/// and position.
struct Index {
    struct Node<Item> {
        var item: Item
        var parent: UUID?
        var order: Int
    }

    var groups: [UUID: Node<Group>] = [:]
    var entries: [UUID: Node<Entry>] = [:]
    let rootID: UUID

    init(_ database: Database, mappingRootTo mappedRoot: UUID? = nil) {
        let rootID = mappedRoot ?? database.root.id
        self.rootID = rootID
        var order = 0
        func visit(_ group: Group, id: UUID, parent: UUID?) {
            var stripped = group
            stripped.id = id
            stripped.groups = []
            stripped.entries = []
            groups[id] = Node(item: stripped, parent: parent, order: order)
            order += 1
            for entry in group.entries {
                entries[entry.id] = Node(item: entry, parent: id, order: order)
                order += 1
            }
            for child in group.groups {
                visit(child, id: child.id, parent: id)
            }
        }
        visit(database.root, id: rootID, parent: nil)
    }
}
