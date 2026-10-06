import AppIntents

/// "New KeePass Entry": available in Shortcuts, Siri, Spotlight, the
/// Action Button and Control Center. It opens the app, which asks to
/// unlock the default database before showing the new-entry form; nothing
/// is written without unlocking.
nonisolated struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New KeePass Entry"
    static let description = IntentDescription("Creates a new entry in your default KeePass database.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCreateCenter.shared.request()
        return .result()
    }
}

nonisolated struct KeePassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewEntryIntent(),
            phrases: [
                "New entry in \(.applicationName)",
                "Add a password to \(.applicationName)",
            ],
            shortTitle: "New Entry",
            systemImageName: "key.badge.plus"
        )
    }
}

/// Hands quick-create requests from intents to the running app.
@MainActor
final class QuickCreateCenter {
    static let shared = QuickCreateCenter()
    weak var model: AppModel?
    private var pending = false

    func request() {
        if let model {
            model.quickCreateRequested = true
        } else {
            pending = true
        }
    }

    func attach(_ model: AppModel) {
        self.model = model
        if pending {
            pending = false
            model.quickCreateRequested = true
        }
    }
}
