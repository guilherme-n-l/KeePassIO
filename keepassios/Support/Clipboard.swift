import UIKit

/// Copies values for the user to paste.
///
/// Sensitive values are marked local-only (never synced to other devices
/// through Universal Clipboard) and expire after the configured time; iOS
/// removes them itself, so this works even if the app is suspended.
enum Clipboard {
    static func copy(_ text: String, sensitive: Bool, clearAfter seconds: Int) {
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if sensitive {
            options[.localOnly] = true
            if seconds > 0 {
                options[.expirationDate] = Date().addingTimeInterval(TimeInterval(seconds))
            }
        }
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: options)
    }
}
