import Foundation
import KPModel
import KPSearch
import KPSession

/// Saving a password iOS offers to save; see `Mode.save`.
extension AutoFillModel {
    /// Starts a save request for `service`; see `Mode.save`.
    func startSave(_ request: SaveRequest, for service: AutoFillService) {
        start(.save(request), services: [service])
    }

    /// Entries the password being saved probably belongs to: they match
    /// the app or site (by more than a similar title) and have the same
    /// user name. Field references are resolved, as the user sees them.
    var entriesToUpdate: [Entry] {
        guard case .save(let request) = mode, let database = session?.database else { return [] }
        return AutoFillMatcher.matches(for: services, in: database)
            .filter { $0.reason != .similarName }
            .compactMap { database.entry(withID: $0.entryID).map(database.resolvingReferences) }
            .filter { $0.userName == request.user }
    }

    /// Gives `entry` the password being saved, keeping the old one in its
    /// history, links it to the app being saved from, and saves.
    ///
    /// When the entry's password refers to another entry's, as in a
    /// KeePassXC clone with references, the new password goes to that
    /// entry instead, so both keep showing it; KeePassXC does the same.
    func update(_ entry: Entry) async throws(SessionError) {
        guard case .save(let request) = mode, let session, let database = session.database else { throw .locked }
        let source = database.passwordSource(of: entry.id)
        guard var chosen = database.entry(withID: entry.id) else { throw .locked }
        if source == entry.id {
            chosen.password = SecretString(request.password)
        } else if var owner = database.entry(withID: source) {
            owner.password = SecretString(request.password)
            try session.updateEntry(owner)
        }
        // The app goes with the entry the user picked. Updating an entry
        // without changes records nothing.
        if let app {
            chosen.linkApp(app.identifier)
        }
        try session.updateEntry(chosen)
        try await session.save()
        finish(.saved)
    }
}
