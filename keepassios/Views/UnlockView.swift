import KPAppState
import KPModel
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// Asks for the master password (and optional key file) of a locked
/// database.
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    let session: DatabaseSession
    let reference: DatabaseReference
    private var name: String { reference.displayName }
    @State private var rememberWithBiometrics = false
    @State private var password = ""
    @State private var keyFileData: Data?
    @State private var keyFileName: String?
    @State private var isPickingKeyFile = false
    @State private var keyFileError: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        Form {
            Section {
                SecureField("Master Password", text: $password)
                    .textContentType(.password)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(unlock)
                    .accessibilityIdentifier("unlock.password")
                Button {
                    isPickingKeyFile = true
                } label: {
                    LabeledContent("Key File", value: keyFileName ?? String(localized: "None"))
                }
                if keyFileData != nil {
                    Button("Remove Key File", role: .destructive) {
                        keyFileData = nil
                        keyFileName = nil
                    }
                }
                if QuickUnlock.isAvailable {
                    Toggle("Unlock with \(QuickUnlock.biometryName) Next Time", isOn: $rememberWithBiometrics)
                        .accessibilityIdentifier("unlock.rememberBiometrics")
                }
            } header: {
                Text(name)
            } footer: {
                if let keyFileError {
                    Text(keyFileError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("unlock.keyFileError")
                } else if case .failed(let error) = session.state {
                    Text(error.userMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("unlock.error")
                }
            }
            Section {
                Button(action: unlock) {
                    HStack {
                        Spacer()
                        if session.state == .unlocking {
                            ProgressView()
                        } else {
                            Text("Unlock").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(session.state == .unlocking || (password.isEmpty && keyFileData == nil))
                .accessibilityIdentifier("unlock.submit")
            }
        }
        .navigationTitle(name)
        .onAppear {
            rememberWithBiometrics = reference.quickUnlockEnabled
            passwordFocused = true
        }
        .task { await tryQuickUnlock() }
        .fileImporter(isPresented: $isPickingKeyFile, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task { await loadKeyFile(from: url) }
        }
    }

    /// Reads the chosen key file through file coordination, so a file in
    /// iCloud Drive or another provider is downloaded first. The file is
    /// shown as selected only once its contents were actually read.
    private func loadKeyFile(from url: URL) async {
        keyFileData = nil
        keyFileName = nil
        keyFileError = nil
        let data = await Task.detached { () -> Data? in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var data: Data?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                data = try? Data(contentsOf: readURL)
            }
            return data
        }.value
        guard let data, !data.isEmpty else {
            keyFileError = String(
                localized: "The key file couldn't be read. If it's in iCloud Drive, make sure it's downloaded."
            )
            return
        }
        keyFileData = data
        keyFileName = url.lastPathComponent
    }

    private func unlock() {
        let key = CompositeKey(
            password: password.isEmpty ? nil : SecretString(password),
            keyFileData: keyFileData
        )
        Task {
            await session.unlock(with: key)
            guard session.state == .unlocked else { return }
            password = ""
            if rememberWithBiometrics {
                try? QuickUnlock.store(key, for: reference.id, validFor: model.settings.quickUnlockValiditySeconds)
            } else {
                QuickUnlock.remove(for: reference.id)
            }
            await model.setQuickUnlock(rememberWithBiometrics, for: reference.id)
        }
    }

    /// Unlocks with biometrics when a quick-unlock key is stored.
    private func tryQuickUnlock() async {
        guard reference.quickUnlockEnabled, session.state == .locked, QuickUnlock.hasKey(for: reference.id) else {
            return
        }
        let reason = String(localized: "Unlock \(name)")
        guard let key = try? await QuickUnlock.retrieve(for: reference.id, reason: reason) else { return }
        await session.unlock(with: key)
        if case .failed = session.state {
            // The stored key no longer works (the master key changed).
            QuickUnlock.remove(for: reference.id)
        }
    }
}

extension SessionError {
    var userMessage: String {
        switch self {
        case .invalidKey:
            String(localized: "The master password or key file is wrong.")
        case .unsupportedFormat(let detail):
            String(
                localized:
                    "This database format isn't supported (\(detail)). Open it in KeePassXC and change Database Settings → Security → Encryption → Database format to KDBX 4."
            )
        case .corrupted:
            String(localized: "The file is damaged or isn't a KeePass database.")
        case .keyDerivationTooExpensive:
            String(localized: "This database needs more memory to unlock than is available here. Open it in the app.")
        case .file(.notFound):
            String(localized: "The file can't be found. It may have been moved or deleted.")
        case .file(.accessDenied):
            String(localized: "The app no longer has permission to open this file. Remove it and add it again.")
        case .file, .other, .changedOnDisk:
            String(localized: "The file couldn't be read.")
        case .locked, .emptyKey, .edit:
            String(localized: "Something went wrong. Try again.")
        }
    }
}
