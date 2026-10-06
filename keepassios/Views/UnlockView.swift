import KPAppState
import KPModel
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// Asks for the master password (and optional key file) of a locked
/// database.
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let session: DatabaseSession
    let reference: DatabaseReference
    private var name: String { reference.name }
    @State private var rememberWithBiometrics = false
    @State private var password = ""
    @State private var keyFileData: Data?
    @State private var keyFileName: String?
    /// The key file picked on this screen; nil when it came from the
    /// remembered bookmark.
    @State private var keyFileURL: URL?
    @State private var rememberKeyFile = true
    @State private var isPickingKeyFile = false
    @State private var keyFileError: String?
    @FocusState private var passwordFocused: Bool
    /// Whether a biometric quick-unlock key is stored for this database.
    @State private var canQuickUnlock = false
    /// Set once Face ID was offered automatically, so cancelling it (which
    /// makes the app inactive and active again) doesn't ask again until
    /// the app has been in the background.
    @State private var didOfferQuickUnlock = false
    @State private var isQuickUnlocking = false

    var body: some View {
        Form {
            if canQuickUnlock {
                Section {
                    Button {
                        Task { await quickUnlock() }
                    } label: {
                        Label("Unlock with \(QuickUnlock.biometryName)", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isQuickUnlocking || session.state == .unlocking)
                    .accessibilityIdentifier("unlock.biometrics")
                }
            }
            Section {
                SecureField("Master Password", text: $password)
                    .textContentType(.password)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(unlock)
                    .accessibilityIdentifier("unlock.password")
                HStack(spacing: 12) {
                    Button {
                        isPickingKeyFile = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("Key File")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Text(keyFileName ?? String(localized: "Choose…"))
                                .foregroundStyle(keyFileName == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("unlock.keyFile")
                    if keyFileData != nil {
                        Button {
                            clearKeyFile()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear Key File")
                        .accessibilityIdentifier("unlock.clearKeyFile")
                    }
                }
                if keyFileData != nil {
                    Toggle("Remember Key File", isOn: $rememberKeyFile)
                        .accessibilityIdentifier("unlock.rememberKeyFile")
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
            canQuickUnlock = reference.quickUnlockEnabled && QuickUnlock.hasKey(for: reference.id)
            // With Face ID about to be offered, raising the keyboard first
            // would only flash it on screen.
            passwordFocused = !canQuickUnlock || model.lockedByUser.contains(reference.id)
        }
        .onDisappear {
            model.lockedByUser.remove(reference.id)
        }
        .task {
            // Face ID doesn't need the key file (the stored key includes
            // it), so don't make it wait for the file to be read.
            async let keyFile: Void = loadRememberedKeyFile()
            await offerQuickUnlock()
            await keyFile
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                didOfferQuickUnlock = false
                // Coming back after the app locked counts as a fresh visit.
                model.lockedByUser.remove(reference.id)
            case .active:
                Task { await offerQuickUnlock() }
            default:
                break
            }
        }
        .fileImporter(isPresented: $isPickingKeyFile, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task { await loadKeyFile(from: url) }
        }
    }

    /// Reads the chosen key file. It is shown as selected only once its
    /// contents were actually read.
    private func loadKeyFile(from url: URL) async {
        keyFileData = nil
        keyFileName = nil
        keyFileURL = nil
        keyFileError = nil
        guard let data = await KeyFile.read(url) else {
            keyFileError = String(
                localized: "The key file couldn't be read. If it's in iCloud Drive, make sure it's downloaded."
            )
            return
        }
        keyFileData = data
        keyFileName = url.lastPathComponent
        keyFileURL = url
    }

    /// Fills in the key file remembered for this database, if any.
    private func loadRememberedKeyFile() async {
        guard keyFileData == nil, let bookmark = reference.keyFileBookmark else { return }
        if let (name, data) = await KeyFile.read(bookmark: bookmark) {
            keyFileData = data
            keyFileName = name
            rememberKeyFile = true
        } else {
            keyFileError = String(
                localized: "The remembered key file couldn't be read. Choose it again, or check that it's downloaded."
            )
        }
    }

    private func clearKeyFile() {
        keyFileData = nil
        keyFileName = nil
        keyFileURL = nil
        keyFileError = nil
        Task { await model.setKeyFileBookmark(nil, for: reference.id) }
    }

    private func unlock() {
        let key = CompositeKey(
            password: password.isEmpty ? nil : SecretString(password),
            keyFileData: keyFileData
        )
        // Read the choices now: once unlocked, this view goes away.
        let withBiometrics = rememberWithBiometrics
        let keyFileBookmark: Data?? =
            keyFileData == nil || !rememberKeyFile
            ? .some(nil)  // forget
            : keyFileURL.flatMap { KeyFile.bookmark(for: $0) }.map { Optional($0) }  // nil: keep as is
        let (model, session, id) = (model, session, reference.id)
        Task {
            await session.unlock(with: key)
            guard session.state == .unlocked else { return }
            password = ""
            if withBiometrics {
                try? QuickUnlock.store(key, for: id, validFor: model.settings.quickUnlockValiditySeconds)
            } else {
                QuickUnlock.remove(for: id)
            }
            await model.setQuickUnlock(withBiometrics, for: id)
            if let keyFileBookmark {
                await model.setKeyFileBookmark(keyFileBookmark, for: id)
            }
        }
    }

    /// Asks for biometrics on its own when the database is opened, but
    /// not right after the user locked it: then the user taps the button.
    private func offerQuickUnlock() async {
        guard canQuickUnlock, !didOfferQuickUnlock, scenePhase == .active,
            !model.lockedByUser.contains(reference.id)
        else { return }
        didOfferQuickUnlock = true
        await quickUnlock()
    }

    /// Unlocks with the key stored behind biometrics.
    private func quickUnlock() async {
        guard canQuickUnlock, !isQuickUnlocking, session.state != .unlocked, session.state != .unlocking else {
            return
        }
        isQuickUnlocking = true
        defer { isQuickUnlocking = false }
        let reason = String(localized: "Unlock \(name)")
        do {
            let key = try await QuickUnlock.retrieve(for: reference.id, reason: reason)
            await session.unlock(with: key)
            if case .failed = session.state {
                // The stored key no longer works (the master key changed).
                QuickUnlock.remove(for: reference.id)
                canQuickUnlock = false
                passwordFocused = true
            }
        } catch QuickUnlock.Failure.cancelled {
            passwordFocused = true
        } catch {
            // Expired or removed: the password is needed again.
            canQuickUnlock = false
            passwordFocused = true
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
