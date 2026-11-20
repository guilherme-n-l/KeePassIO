import Foundation
import KPModel
import KPSearch
import KPSession

/// Suggestions for the app or site being filled, with why each matched,
/// and remembering which entry belongs to an app.
extension AutoFillModel {
    struct Suggestion: Identifiable {
        let entry: Entry
        let reason: AutoFillMatcher.Reason
        var id: UUID { entry.id }
    }

    /// Entries for the app or website being filled, best match first.
    var suggestions: [Suggestion] {
        guard let database = session?.database else { return [] }
        return AutoFillMatcher.matches(for: services, in: database).compactMap { match in
            guard let entry = database.entry(withID: match.entryID), fits(entry) else { return nil }
            return Suggestion(entry: entry, reason: match.reason)
        }
    }

    /// The app being filled, when iOS names it, for "Remember for …".
    var rememberableApp: AutoFillService? {
        mode == .password || mode == .oneTimeCode ? app : nil
    }

    /// Links `entry` to `app` and saves, before it is filled. Filling
    /// goes ahead even if saving fails: the user asked for the password.
    func link(_ entry: Entry, to app: AutoFillService) async {
        guard let session else { return }
        var linked = entry
        guard linked.linkApp(app.identifier) else { return }
        try? session.updateEntry(linked)
        try? await session.save()
    }
}
