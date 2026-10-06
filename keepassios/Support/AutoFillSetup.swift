import AuthenticationServices
import Observation

/// Whether KeePassIO is turned on as an AutoFill provider, and the ways
/// to turn it on.
///
/// iOS 18 can ask the user directly (a system prompt with an "Allow"
/// button), so there's no need to walk them through Settings; opening
/// the AutoFill settings page is the fallback when they decline.
@MainActor
@Observable
final class AutoFillSetup {
    enum Status {
        case unknown
        case on
        case off
    }

    private(set) var status = Status.unknown

    func refresh() async {
        let isEnabled = await withCheckedContinuation { continuation in
            ASCredentialIdentityStore.shared.getState { state in
                continuation.resume(returning: state.isEnabled)
            }
        }
        status = isEnabled ? .on : .off
    }

    /// Shows the system prompt to turn KeePassIO on. Returns whether
    /// it's on afterwards.
    @discardableResult
    func turnOn() async -> Bool {
        let accepted = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
        await refresh()
        return accepted || status == .on
    }

    /// Opens Settings at the page listing AutoFill providers.
    func openSettings() async {
        try? await ASSettingsHelper.openCredentialProviderAppSettings()
    }
}
