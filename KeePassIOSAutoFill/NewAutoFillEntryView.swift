import KPPlatform
import SwiftUI

/// A new entry for the site being filled, saved to the database and, when
/// filling a password, filled right away.
struct NewAutoFillEntryView: View {
    @Environment(AutoFillModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var userName = ""
    @State private var password = ""
    @State private var url = ""
    @State private var isPasswordVisible = false
    @State private var isGenerating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case userName
    }

    /// Known user names matching what's typed, while typing.
    private var userNameSuggestions: [String] {
        guard focusedField == .userName, !userName.isEmpty else { return [] }
        return model.knownUserNames
            .filter { $0.localizedCaseInsensitiveContains(userName) && $0 != userName }
            .prefix(4)
            .map(\.self)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                userNameRow
                ForEach(userNameSuggestions, id: \.self) { suggestion in
                    Button {
                        userName = suggestion
                        focusedField = nil
                    } label: {
                        Label(suggestion, systemImage: "person")
                            .foregroundStyle(.primary)
                    }
                }
                passwordRow
                TextField("Website", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if model.mode == .password {
                    Text("Saved to \(model.selected?.name ?? "the database") and filled in.")
                }
            }
        }
        .animation(.snappy, value: userNameSuggestions)
        .navigationTitle("New Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(model.mode == .password ? "Save and Fill" : "Save", action: save)
                        .disabled(title.isEmpty && userName.isEmpty)
                }
            }
        }
        .sheet(isPresented: $isGenerating) {
            NavigationStack {
                GeneratorView(settings: model.generatorSettings) { settings in
                    model.saveGeneratorSettings(settings)
                } onUse: { generated in
                    password = generated
                }
            }
        }
        .onAppear {
            let defaults = model.newEntryDefaults
            if title.isEmpty { title = defaults.title }
            if url.isEmpty { url = defaults.url }
        }
    }

    /// The user name, with a menu of the ones already in the database.
    private var userNameRow: some View {
        HStack(spacing: 12) {
            TextField("User Name", text: $userName)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .userName)
            if !model.knownUserNames.isEmpty {
                Menu {
                    ForEach(model.knownUserNames.prefix(30), id: \.self) { name in
                        Button(name) { userName = name }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Choose User Name")
            }
        }
    }

    /// The password: empty at first, hidden unless the eye is on, with the
    /// dice opening the generator.
    private var passwordRow: some View {
        HStack(spacing: 12) {
            SwiftUI.Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPasswordVisible ? "Hide Password" : "Show Password")
            Button {
                isGenerating = true
            } label: {
                Image(systemName: "dice")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Generate Password")
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.addEntry(title: title, userName: userName, password: password, url: url)
                dismiss()
            } catch {
                errorMessage = String(localized: "Couldn't save the entry.")
            }
            isSaving = false
        }
    }
}
