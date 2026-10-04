import KPAppState
import KPModel
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// The AutoFill sheet: unlock a database, then pick an entry.
struct AutoFillView: View {
    @Environment(AutoFillModel.self) private var model

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                }
        }
        .tint(AccentColors.color(model.accentColor))
    }

    @ViewBuilder private var content: some View {
        if model.isFinished {
            Color.clear
        } else if let loadError = model.loadError {
            ContentUnavailableView(
                "Can't Open Databases",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if !model.isLoaded {
            ProgressView()
        } else if model.databases.isEmpty {
            ContentUnavailableView(
                "No Databases",
                systemImage: "lock.rectangle.stack",
                description: Text("Open or create a database in KeePassIOS first.")
            )
        } else if let session = model.session, let reference = model.selected {
            if session.state == .unlocked {
                EntryPickerView()
            } else {
                AutoFillUnlockView(session: session, reference: reference)
                    .id(reference.id)
            }
        }
    }
}

/// Lists the entries for the website first, then all of them, searchable.
private struct EntryPickerView: View {
    @Environment(AutoFillModel.self) private var model
    @State private var query = ""
    @State private var isAdding = false

    var body: some View {
        List {
            let suggestions = model.suggestions
            if query.isEmpty, !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { entry in
                        row(entry)
                    }
                } header: {
                    if let serviceName = model.serviceName {
                        Text("Suggestions for \(serviceName)")
                    } else {
                        Text("Suggestions")
                    }
                }
            }
            Section(query.isEmpty ? "All Entries" : "Results") {
                let entries = model.entries(matching: query)
                if entries.isEmpty {
                    Text(model.mode == .oneTimeCode ? "No entries with one-time codes" : "No entries")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle(model.selected?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            // Tap the title to switch to another database.
            if model.databases.count > 1 {
                ForEach(model.databases) { database in
                    Button {
                        model.select(database)
                    } label: {
                        if database.id == model.selected?.id {
                            Label(database.name, systemImage: "checkmark")
                        } else {
                            Text(database.name)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("New Entry", systemImage: "plus")
                }
                .accessibilityIdentifier("autofill.newEntry")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                NewAutoFillEntryView()
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        Button {
            model.choose(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? String(localized: "Untitled") : entry.title)
                    .foregroundStyle(.primary)
                if !entry.userName.isEmpty {
                    Text(entry.userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Password, key file and Face ID unlock, like the app's unlock screen.
private struct AutoFillUnlockView: View {
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
        .navigationTitle("KeePassIOS")
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
        Task {
            await session.unlock(with: key)
            if case .failed(let error) = session.state {
                message = Self.message(for: error)
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
                message = Self.message(for: error)
                passwordFocused = true
            }
        } catch {
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

    private static func message(for error: SessionError) -> String {
        switch error {
        case .invalidKey:
            String(localized: "The master password or key file is wrong.")
        case .keyDerivationTooExpensive:
            String(
                localized:
                    "This database needs more memory to unlock than AutoFill is allowed. Lower the key derivation memory in KeePassXC (Database Settings → Security), or copy the password from the app."
            )
        case .file(.notFound), .file(.accessDenied):
            String(localized: "The database file can't be reached. Open it once in KeePassIOS, then try again.")
        default:
            String(localized: "The database couldn't be opened.")
        }
    }
}
