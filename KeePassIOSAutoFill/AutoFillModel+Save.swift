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
    /// user name.
    var entriesToUpdate: [Entry] {
        guard case .save(let request) = mode, let database = session?.database else { return [] }
        return AutoFillMatcher.matches(for: services, in: database)
            .filter { $0.reason != .similarName }
            .compactMap { database.entry(withID: $0.entryID) }
            .filter { $0.userName == request.user }
    }

    /// Gives `entry` the password being saved, keeping the old one in its
    /// history, links it to the app being saved from, and saves.
    func update(_ entry: Entry) async throws(SessionError) {
        guard case .save(let request) = mode, let session else { throw .locked }
        var entry = entry
        entry.password = SecretString(request.password)
        if let app {
            entry.linkApp(app.identifier)
        }
        try session.updateEntry(entry)
        try await session.save()
        finish(.saved)
    }
}
