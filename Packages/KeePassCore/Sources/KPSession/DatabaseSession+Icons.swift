import Foundation
import KPModel

extension DatabaseSession {
    /// Sets an entry's custom icon (PNG data), reusing an identical icon
    /// already in the database so repeated downloads don't pile up copies.
    public func setCustomIcon(_ imageData: Data, forEntry id: UUID) throws(SessionError) {
        try setIcon(.newCustom(imageData), forEntry: id)
    }

    public func setIcon(_ icon: IconChoice, forEntry id: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in
            guard var entry = database.entry(withID: id) else { throw EditError.entryNotFound(id) }
            (entry.iconID, entry.customIconID) = Self.resolve(icon, current: entry.iconID, in: &database)
            try database.update(entry, at: now)
        }
    }

    public func setIcon(_ icon: IconChoice, forGroup id: UUID) throws(SessionError) {
        let now = clock()
        try edit { database in
            guard var group = database.group(withID: id) else { throw EditError.groupNotFound(id) }
            (group.iconID, group.customIconID) = Self.resolve(icon, current: group.iconID, in: &database)
            try database.updateGroupProperties(group, at: now)
        }
    }

    /// The standard icon ID and custom icon ID an item gets for `icon`,
    /// adding new custom icon data to the database (once).
    private static func resolve(_ icon: IconChoice, current: Int, in database: inout Database) -> (Int, UUID?) {
        switch icon {
        case .standard(let iconID):
            return (iconID, nil)
        case .custom(let customID):
            return (current, customID)
        case .newCustom(let data):
            let customID = database.meta.customIcons.first { $0.value == data }?.key ?? UUID()
            database.meta.customIcons[customID] = data
            return (current, customID)
        }
    }
}
