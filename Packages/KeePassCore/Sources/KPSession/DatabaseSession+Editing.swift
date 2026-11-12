import Foundation
import KPModel

extension DatabaseSession {
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

    /// Moves a group (with everything in it) under another group. Moving
    /// a group into itself or its own subgroups is refused.
    public func moveGroup(_ id: UUID, to parentID: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in try database.moveGroup(id, to: parentID, at: now) }
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

    /// Creates an entry stamped with the current time.
    public func newEntry(title: String = "", userName: String = "", password: SecretString = .empty) -> Entry {
        var entry = Entry(times: Times(creation: clock()))
        entry.title = title
        entry.userName = userName
        entry.password = password
        return entry
    }
}
