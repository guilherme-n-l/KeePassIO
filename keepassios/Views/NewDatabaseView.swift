import SwiftUI

/// Creates a new database in the app's Documents folder.
struct NewDatabaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Passwords"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isCreating = false
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
                    if !password.isEmpty, password.count < 8 {
                        Text("Use at least 8 characters. A passphrase of several random words is easiest to remember.")
                    } else if !confirmation.isEmpty, password != confirmation {
                        Text("The passwords don't match.")
                    } else {
                        Text("There is no way to recover a forgotten master password.")
                    }
                }
            }
            .navigationTitle("New Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        Task {
                            let id = await model.createDatabase(name: name, password: password)
                            isCreating = false
                            if let id {
                                dismiss()
                                onCreated(id)
                            }
                        }
                    }
                    .disabled(!canCreate)
                    .accessibilityIdentifier("newDatabase.create")
                }
            }
        }
    }
}
