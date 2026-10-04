import KPModel
import KPSession
import SwiftUI

/// Creates or edits an entry. Changes are applied to the session (and
/// recorded in history) when the user taps Done.
struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let session: DatabaseSession
    @State var entry: Entry
    let isNew: Bool
    let groupID: UUID?

    @State private var password = ""
    @State private var isShowingGenerator = false
    @State private var newFieldName = ""
    @State private var errorMessage: String?

    init(session: DatabaseSession, entry: Entry, isNew: Bool, groupID: UUID?) {
        self.session = session
        _entry = State(initialValue: entry)
        _password = State(initialValue: entry.password.reveal())
        self.isNew = isNew
        self.groupID = groupID
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $entry.title)
                    .accessibilityIdentifier("editor.title")
                TextField("User Name", text: $entry.userName)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editor.userName")
                HStack {
                    TextField("Password", text: $password)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editor.password")
                    Button {
                        isShowingGenerator = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Generate Password")
                    .accessibilityIdentifier("editor.generate")
                }
                TextField("Website", text: $entry.url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editor.url")
            }
            Section("Notes") {
                TextEditor(text: $entry.notes)
                    .frame(minHeight: 80)
                    .accessibilityIdentifier("editor.notes")
            }
            Section("Fields") {
                ForEach(entry.customFieldNames, id: \.self) { name in
                    LabeledContent(name) {
                        TextField(name, text: binding(forField: name))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .onDelete { offsets in
                    let names = entry.customFieldNames
                    for index in offsets {
                        entry.fields[names[index]] = nil
                    }
                }
                HStack {
                    TextField("New Field Name", text: $newFieldName)
                    Button("Add") {
                        let name = newFieldName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, entry.fields[name] == nil else { return }
                        entry.fields[name] = .plain("")
                        newFieldName = ""
                    }
                    .disabled(newFieldName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Tags") {
                TextField(
                    "Comma-separated",
                    text: Binding(
                        get: { entry.tags.joined(separator: ", ") },
                        set: {
                            entry.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter
                            { !$0.isEmpty }
                        }
                    )
                )
            }
        }
        .navigationTitle(isNew ? "New Entry" : "Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: commit)
                    .accessibilityIdentifier("editor.done")
            }
        }
        .sheet(isPresented: $isShowingGenerator) {
            NavigationStack {
                GeneratorView { generated in
                    password = generated
                }
            }
        }
        .alert(
            "Couldn't Save Entry",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func binding(forField name: String) -> Binding<String> {
        Binding(
            get: { entry.fields[name]?.reveal() ?? "" },
            set: { newValue in
                let wasProtected = entry.fields[name]?.isProtected ?? false
                entry.fields[name] = wasProtected ? .protected(SecretString(newValue)) : .plain(newValue)
            }
        )
    }

    private func commit() {
        entry.password = SecretString(password)
        do {
            let previousURL = session.database?.entry(withID: entry.id)?.url
            if isNew {
                try session.addEntry(entry, to: groupID)
            } else {
                try session.updateEntry(entry)
            }
            if entry.customIconID == nil || (previousURL != nil && previousURL != entry.url), !entry.url.isEmpty {
                // Runs after the sheet closes; does nothing unless website
                // icons are turned on in Settings.
                let (model, session, id) = (model, session, entry.id)
                Task { await model.downloadIcons(for: [id], in: session) }
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
