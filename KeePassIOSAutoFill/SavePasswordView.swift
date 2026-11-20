import KPModel
import KPSession
import SwiftUI

/// A password iOS offers to save, from a website or an app: it replaces
/// the password of an entry that already has this user name there, or
/// goes into a new entry, which is linked to the app it came from.
struct SavePasswordView: View {
    @Environment(AutoFillModel.self) private var model
    let request: AutoFillModel.SaveRequest
    @State private var title = ""
    @State private var groupID: UUID?
    @State private var isPasswordVisible = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                let existing = model.entriesToUpdate
                if !existing.isEmpty {
                    Section {
                        ForEach(existing) { entry in
                            Button {
                                run { try await model.update(entry) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("Update “\(entry.title)”")
                                    Text(entry.userName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("save.update")
                        }
                    } header: {
                        Text("Existing Entry")
                    } footer: {
                        Text("Replaces its password. The old one stays in the entry's history.")
                    }
                }
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("save.title")
                    LabeledContent("User Name", value: request.user)
                    passwordRow
                    groupRow
                } header: {
                    Text("New Entry")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(model.serviceName.map { "Save for \($0)" } ?? String(localized: "Save Password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { run { try await saveNew() } }
                            .accessibilityIdentifier("save.new")
                    }
                }
            }
        }
        .onAppear {
            if title.isEmpty { title = request.title ?? model.newEntryDefaults.title }
            if groupID == nil { groupID = model.defaultGroupID }
        }
    }

    private func saveNew() async throws(SessionError) {
        try await model.addEntry(
            title: title,
            userName: request.user,
            password: request.password,
            url: model.newEntryDefaults.url,
            groupID: groupID
        )
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await action()
            } catch {
                errorMessage = String(localized: "Couldn't save the password.")
                isSaving = false
            }
        }
    }

    /// The password being saved, hidden unless the eye is on.
    private var passwordRow: some View {
        LabeledContent("Password") {
            HStack(spacing: 12) {
                Text(isPasswordVisible ? request.password : String(repeating: "•", count: 10))
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isPasswordVisible ? "Hide Password" : "Show Password")
            }
        }
    }

    /// Where a new entry goes: any group except the recycle bin, the last
    /// one used here to start with.
    @ViewBuilder private var groupRow: some View {
        let choices = model.groupChoices
        if choices.count > 1 {
            Picker("Group", selection: $groupID) {
                ForEach(choices) { choice in
                    Text(choice.path).tag(Optional(choice.id))
                }
            }
            .pickerStyle(.navigationLink)
        }
    }
}
