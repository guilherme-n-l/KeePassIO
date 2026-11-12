import AuthenticationServices
import KPSearch
import SwiftUI
import UIKit

/// Entry point of the AutoFill extension. iOS shows it when the user picks
/// KeePassIO from the password or one-time code suggestions, or from the
/// AutoFill > Passwords menu of any text field; it hosts the SwiftUI picker
/// and hands the chosen credential or text back to the system.
///
/// New entries saved here go to the original file when the extension can
/// reach it, otherwise to a pending copy the app merges later (see
/// `ExtensionDatabaseFile`).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private lazy var model = AutoFillModel { [weak self] completion in
        self?.finish(completion)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: AutoFillView().environment(model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.start(.password, services: Self.services(serviceIdentifiers))
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.start(.oneTimeCode, services: Self.services(serviceIdentifiers))
    }

    /// Called from the text field menu (AutoFill > Passwords). iOS lists
    /// only extensions that declare `ProvidesTextToInsert` there, and it is
    /// the only way in for fields it doesn't recognize as a login, such as
    /// a confirm-password field or an unlabeled two-factor code.
    override func prepareInterfaceForUserChoosingTextToInsert() {
        model.start(.text, services: [])
    }

    /// Nothing is published to the system's credential identity store, so
    /// every request goes through the picker.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    /// iOS's service identifiers, keeping their kind: an app ID (iOS 26.2
    /// and later) must not be read as a website.
    private static func services(_ identifiers: [ASCredentialServiceIdentifier]) -> [AutoFillService] {
        identifiers.map { identifier in
            var kind: AutoFillService.Kind = identifier.type == .domain ? .domain : .url
            var displayName: String?
            if #available(iOS 26.2, *) {
                displayName = identifier.displayName
                if identifier.type == .app { kind = .app }
            }
            return AutoFillService(kind: kind, identifier: identifier.identifier, displayName: displayName)
        }
    }

    private func finish(_ completion: AutoFillModel.Completion) {
        switch completion {
        case .password(let user, let password):
            extensionContext.completeRequest(
                withSelectedCredential: ASPasswordCredential(user: user, password: password),
                completionHandler: nil
            )
        case .oneTimeCode(let code):
            extensionContext.completeOneTimeCodeRequest(
                using: ASOneTimeCodeCredential(code: code),
                completionHandler: nil
            )
        case .text(let text):
            extensionContext.completeRequest(withTextToInsert: text, completionHandler: nil)
        case .cancelled:
            extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
        }
    }
}
