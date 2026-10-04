import SwiftUI

/// Creates a new database and asks where in Files to keep it, like
/// KeePassium: the file is an ordinary document there, to share, move or
/// replace like any other.
struct NewDatabaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Passwords"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isCreating = false
    /// The new database, written to a temporary file while the user picks
    /// where it goes.
    @State private var pending: AppModel.PendingDatabase?
    let onCreated: (UUID) -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8 && password == confirmation
            && !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("newDatabase.name")
                }
                Section {
                    SecureField("Master Password", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("newDatabase.password")
                    SecureField("Confirm Password", text: $confirmation)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("newDatabase.confirm")
                } footer: {
                    if model.picksLocationForNewDatabases, password.isEmpty {
                        Text("After this you choose where to save it in Files, for example iCloud Drive.")
                    } else if !password.isEmpty, password.count < 8 {
                        Text("Use at least 8 characters. A passphrase of several random words is easiest to remember.")
                    } else if !confirmation.isEmpty, password != confirmation {
                        Text("The passwords don't match.")
                    } else {
                        Text("There is no way to recover a forgotten master password.")
                    }
                }
            }
            .fileMover(
                isPresented: Binding(get: { pending != nil }, set: { _ in }),
                file: pending?.url
            ) { result in
                guard let pending else { return }
                self.pending = nil
                switch result {
                case .success(let url):
                    Task {
                        if let id = await model.adopt(pending, movedTo: url) {
                            dismiss()
                            onCreated(id)
                        }
                    }
                case .failure:
                    model.discard(pending)
                }
            } onCancellation: {
                if let pending {
                    model.discard(pending)
                }
                pending = nil
            }
            .navigationTitle("New Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(!canCreate)
                        .accessibilityIdentifier("newDatabase.create")
                }
            }
        }
    }

    private func create() {
        isCreating = true
        Task {
            defer { isCreating = false }
            if model.picksLocationForNewDatabases {
                // Written to a temporary file first; the file mover then
                // asks where it goes.
                pending = await model.prepareDatabase(name: name, password: password)
            } else if let id = await model.createDatabase(name: name, password: password) {
                dismiss()
                onCreated(id)
            }
        }
    }
}
