import AuthenticationServices
import SwiftUI
import UIKit

/// Entry point of the AutoFill extension. iOS shows it when the user picks
/// KeePassIOS from the password or one-time code suggestions; it hosts the
/// SwiftUI picker and hands the chosen credential back to the system.
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
        model.start(.password, serviceIdentifiers: serviceIdentifiers.map(\.identifier))
    }

    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.start(.oneTimeCode, serviceIdentifiers: serviceIdentifiers.map(\.identifier))
    }

    /// Nothing is published to the system's credential identity store, so
    /// every request goes through the picker.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
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
        case .cancelled:
            extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
        }
    }
}
