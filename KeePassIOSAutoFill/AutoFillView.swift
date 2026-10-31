import KPAppState
import KPModel
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// The AutoFill sheet: unlock a database, then pick an entry.
struct AutoFillView: View {
    @Environment(AutoFillModel.self) private var model
    /// Whether the entry picker's stack is on screen. Decided only while
    /// the request is open: answering it locks the database, and swapping
    /// the whole navigation stack (with a pushed screen and maybe an active
    /// search) at the moment the sheet is handed back could leave the sheet
    /// stuck on screen. It keeps showing what it showed until it closes.
    @State private var isPicking = false

    var body: some View {
        SwiftUI.Group {
            if isPicking {
                EntryPickerStack()
            } else {
                NavigationStack {
                    content
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { model.cancel() }
                            }
                        }
                }
            }
        }
        .tint(AccentColors.color(model.accentColor))
        .onChange(of: isUnlocked, initial: true) { _, unlocked in
            if !model.isFinished {
                isPicking = unlocked
            }
        }
    }

    /// A database is open and unlocked: the picker should show.
    private var isUnlocked: Bool {
        model.loadError == nil && model.selected != nil && model.session?.state == .unlocked
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
                description: Text("Open or create a database in KeePassIO first.")
            )
        } else if let session = model.session, let reference = model.selected {
            AutoFillUnlockView(session: session, reference: reference)
                .id(reference.id)
        }
    }
}

/// The entry picker in a navigation stack of its own, with search attached
/// to the stack.
///
/// `.searchable` belongs on the NavigationStack, not on a view inside it.
/// Applied to the list (or to any screen pushed onto a stack), iOS 26 and
/// later turn it into a toolbar item of that one screen: on iPhone it
/// floats at the bottom, ignoring `.navigationBarDrawer`, with no scroll
/// edge effect, so rows show and take taps around it; and after pushing a
/// screen and going back it isn't put back, so search disappears. On the
/// stack, the drawer sits under the navigation bar and survives pushes.
/// The app's group screens had the same symptoms; see GroupSearchBar.
private struct EntryPickerStack: View {
    @Environment(AutoFillModel.self) private var model
    @State private var query = ""

    var body: some View {
        NavigationStack {
            EntryPickerView(query: query)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
    }
}

/// Lists the entries for the website first, then all of them, or the
/// results for `query`.
private struct EntryPickerView: View {
    @Environment(AutoFillModel.self) private var model
    let query: String
    @State private var isAdding = false

    var body: some View {
        List {
            if query.isEmpty, let entry = model.justFilled {
                Section {
                    Button {
                        model.insertPassword(of: entry)
                    } label: {
                        Label {
                            EntryLabel(entry: entry)
                        } icon: {
                            Image(systemName: "key.fill")
                        }
                    }
                    .accessibilityHint("Inserts this entry's password")
                } header: {
                    Text("Just Filled")
                } footer: {
                    Text("Inserts the same password, for a confirm-password field.")
                }
            }
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

    @ViewBuilder private func row(_ entry: Entry) -> some View {
        if model.mode == .text {
            NavigationLink {
                InsertFieldView(entry: entry)
            } label: {
                EntryLabel(entry: entry)
            }
        } else {
            Button {
                model.choose(entry)
            } label: {
                EntryLabel(entry: entry)
            }
        }
    }
}

private struct EntryLabel: View {
    let entry: Entry

    var body: some View {
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

/// The values of one entry, for a text insertion request: tap one to type
/// it into the field. Secret values stay masked.
private struct InsertFieldView: View {
    @Environment(AutoFillModel.self) private var model
    let entry: Entry

    var body: some View {
        List(model.insertableFields(of: entry)) { field in
            Button {
                model.insert(field)
            } label: {
                // The name keeps the button's accent color; the value is
                // dimmed so it doesn't read as part of the button's title.
                LabeledContent(field.name) {
                    Text(field.isSecret ? String(repeating: "•", count: 8) : field.value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Inserts this value")
        }
        .navigationTitle(entry.title.isEmpty ? String(localized: "Untitled") : entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
