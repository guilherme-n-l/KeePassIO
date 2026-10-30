import KPAppState
import KPModel
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// Password, key file and Face ID unlock, like the app's unlock screen.
struct AutoFillUnlockView: View {
    @Environment(AutoFillModel.self) private var model
    let session: DatabaseSession
    let reference: DatabaseReference

    @State private var password = ""
    @State private var keyFileData: Data?
    @State private var keyFileName: String?
    @State private var isPickingKeyFile = false
    @State private var canQuickUnlock = false
    @State private var message: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        Form {
            if model.databases.count > 1 {
                Section {
                    Picker(
                        "Database",
                        selection: Binding(
                            get: { reference.id },
                            set: { id in
                                if let chosen = model.databases.first(where: { $0.id == id }) {
                                    model.select(chosen)
                                }
                            }
                        )
                    ) {
                        ForEach(model.databases) { database in
                            Text(database.name).tag(database.id)
                        }
                    }
                }
            }
            if canQuickUnlock {
                Section {
                    Button {
                        Task { await quickUnlock() }
                    } label: {
                        Label("Unlock with \(QuickUnlock.biometryName)", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(session.state == .unlocking)
                }
            }
            Section {
                SecureField("Master Password", text: $password)
                    .textContentType(.password)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(unlock)
                Button {
                    isPickingKeyFile = true
                } label: {
                    LabeledContent("Key File", value: keyFileName ?? String(localized: "None"))
                }
            } header: {
                Text(reference.name)
            } footer: {
                if let message {
                    Text(message).foregroundStyle(.red)
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
            }
        }
        .navigationTitle("KeePassIO")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPickingKeyFile, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task { await loadKeyFile(from: url) }
        }
        .task {
            canQuickUnlock = reference.quickUnlockEnabled && QuickUnlock.hasKey(for: reference.id)
            async let keyFile: Void = loadRememberedKeyFile()
            if canQuickUnlock {
                await quickUnlock()
            } else {
                passwordFocused = true
            }
            await keyFile
        }
    }

    private func unlock() {
        message = nil
        let key = CompositeKey(password: password.isEmpty ? nil : SecretString(password), keyFileData: keyFileData)
        let (reference, validity) = (reference, model.quickUnlockValiditySeconds)
        Task {
            await session.unlock(with: key)
            if case .failed(let error) = session.state {
                message = Self.message(for: error)
            } else if session.state == .unlocked, reference.quickUnlockEnabled {
                // Face ID is on for this database but its key expired or
                // was removed: store it again, as the app does, so Face ID
                // works again here and in the app without a trip to the app.
                try? QuickUnlock.store(key, for: reference.id, validFor: validity)
            }
        }
    }

    private func quickUnlock() async {
        do {
            let key = try await QuickUnlock.retrieve(
                for: reference.id,
                reason: String(localized: "Unlock \(reference.name)")
            )
            await session.unlock(with: key)
            if case .failed(let error) = session.state {
                if error == .invalidKey {
                    // The master key changed since Face ID was set up.
                    QuickUnlock.remove(for: reference.id)
                    canQuickUnlock = false
                }
                message = Self.message(for: error)
                passwordFocused = true
            }
        } catch QuickUnlock.Failure.cancelled {
            passwordFocused = true
        } catch {
            // Expired or removed. Unlocking with the password stores the
            // key again (see `unlock()`).
            canQuickUnlock = false
            message = String(localized: "Enter the master password to use \(QuickUnlock.biometryName) again.")
            passwordFocused = true
        }
    }

    /// The key file remembered in the app for this database, if any.
    private func loadRememberedKeyFile() async {
        guard keyFileData == nil, let bookmark = reference.keyFileBookmark,
            let (name, data) = await KeyFile.read(bookmark: bookmark)
        else { return }
        keyFileData = data
        keyFileName = name
    }

    private func loadKeyFile(from url: URL) async {
        keyFileData = nil
        keyFileName = nil
        guard let data = await KeyFile.read(url) else {
            message = String(localized: "The key file couldn't be read.")
            return
        }
        keyFileData = data
        keyFileName = url.lastPathComponent
    }

    /// The app's messages, except where AutoFill's limits call for
    /// different advice.
    private static func message(for error: SessionError) -> String {
        switch error {
        case .keyDerivationTooExpensive:
            String(
                localized:
                    "This database needs more memory to unlock than AutoFill is allowed. Lower the key derivation memory in KeePassXC (Database Settings → Security), or copy the password from the app."
            )
        case .file(.notFound), .file(.accessDenied):
            String(localized: "The database file can't be reached. Open it once in KeePassIO, then try again.")
        default:
            error.userMessage
        }
    }
}
