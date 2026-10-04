import KPAppState
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// The list of databases the user has added.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var isCreating = false
    @State private var isShowingSettings = false
    @State private var path = NavigationPath()
    @State private var renaming: DatabaseReference?
    @State private var aliasText = ""
    @State private var removing: DatabaseReference?

    var body: some View {
        NavigationStack(path: $path) {
            SwiftUI.Group {
                if model.databases.isEmpty {
                    ContentUnavailableView {
                        Label("No Databases", systemImage: "lock.rectangle.stack")
                    } description: {
                        Text("Open a KeePass database (.kdbx) from the Files app to get started.")
                    } actions: {
                        Button("Open Database") { isImporting = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("library.open")
                        Button("New Database") { isCreating = true }
                            .accessibilityIdentifier("library.new")
                    }
                } else {
                    List {
                        ForEach(model.databases) { reference in
                            NavigationLink(value: reference.id) {
                                DatabaseRow(
                                    reference: reference,
                                    isUnlocked: model.isUnlocked(reference.id),
                                    isQuickCreateTarget: model.settings.quickCreateDatabaseID == reference.id
                                )
                            }
                            .contextMenu { quickActions(for: reference) }
                            .accessibilityIdentifier("library.database.\(reference.name)")
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.databases[$0].id }
                            Task {
                                for id in ids {
                                    await model.removeDatabase(id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("KeePassIOS")
            .navigationDestination(for: UUID.self) { id in
                if let reference = model.databases.first(where: { $0.id == id }) {
                    DatabaseContainerView(reference: reference)
                }
            }
            .navigationDestination(for: DatabaseRoute.self) { route in
                destination(for: route)
            }
            .onChange(of: path) { _, newPath in
                // Going back to the library closes the database, as in
                // KeePassium; opening it again asks for Face ID or the
                // password.
                if newPath.isEmpty {
                    model.lockAll()
                }
            }
            .onChange(of: model.lockCount) {
                // Screens inside a database can't show anything once it's
                // locked: go back to its unlock screen.
                if path.count > 1 {
                    path.removeLast(path.count - 1)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("library.settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Open Database", systemImage: "folder") { isImporting = true }
                        Button("New Database", systemImage: "plus.rectangle.on.folder") { isCreating = true }
                    } label: {
                        Label("Add Database", systemImage: "plus")
                    }
                    .accessibilityIdentifier("library.add")
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.keepassDatabase, .data]) { result in
                if case .success(let url) = result {
                    Task { await model.addDatabase(at: url) }
                }
            }
            .sheet(isPresented: $isCreating) {
                NewDatabaseView { id in
                    path.append(id)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .alert(
                "Rename",
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                presenting: renaming
            ) { reference in
                TextField(reference.displayName, text: $aliasText)
                    .accessibilityIdentifier("library.rename.field")
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    Task { await model.rename(reference.id, to: aliasText) }
                }
                .accessibilityIdentifier("library.rename.confirm")
            } message: { reference in
                Text(
                    "Shown in the library instead of the file name, \(reference.displayName). Leave empty to use the file name."
                )
            }
            .confirmationDialog(
                "Remove from Library?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { reference in
                Button("Remove \(reference.name)", role: .destructive) {
                    Task { await model.removeDatabase(reference.id) }
                }
            } message: { _ in
                Text("The file itself stays where it is in the Files app.")
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: model.quickCreateRequested) { _, requested in
                guard requested else { return }
                let target = model.settings.quickCreateDatabaseID ?? model.databases.first?.id
                if let target, path.isEmpty {
                    path.append(target)
                }
            }
        }
    }
}

extension LibraryView {
    @ViewBuilder
    private func destination(for route: DatabaseRoute) -> some View {
        switch route {
        case .group(let databaseID, let groupID):
            if let session = unlockedSession(databaseID) {
                GroupView(session: session, databaseID: databaseID, groupID: groupID)
            }
        case .entry(let databaseID, let entryID):
            if let session = unlockedSession(databaseID) {
                EntryDetailView(session: session, databaseID: databaseID, entryID: entryID)
            }
        case .history(let databaseID, let entryID):
            if let session = unlockedSession(databaseID) {
                EntryHistoryView(session: session, entryID: entryID)
            }
        }
    }

    private func unlockedSession(_ databaseID: UUID) -> DatabaseSession? {
        guard let reference = model.databases.first(where: { $0.id == databaseID }) else { return nil }
        let session = model.session(for: reference)
        return session.state == .unlocked ? session : nil
    }

    /// The long-press menu of a database.
    @ViewBuilder
    private func quickActions(for reference: DatabaseReference) -> some View {
        Button("Open", systemImage: "arrow.forward.circle") { path.append(reference.id) }
        if model.isUnlocked(reference.id) {
            Button("Lock", systemImage: "lock") {
                model.lock(model.session(for: reference))
            }
        }
        Button("Quick Create Entry", systemImage: "plus.circle") {
            path = NavigationPath()
            path.append(reference.id)
            model.quickCreateRequested = true
        }
        Button("Rename", systemImage: "pencil") {
            aliasText = reference.alias ?? ""
            renaming = reference
        }
        .accessibilityIdentifier("library.rename")
        if model.settings.quickCreateDatabaseID == reference.id {
            Button("Stop Using for Quick Create", systemImage: "star.slash") {
                Task { await model.setQuickCreateDatabase(nil) }
            }
        } else {
            Button("Use for Quick Create", systemImage: "star") {
                Task { await model.setQuickCreateDatabase(reference.id) }
            }
        }
        if reference.quickUnlockEnabled {
            Button("Forget \(QuickUnlock.biometryName)", systemImage: "faceid") {
                Task { await model.forgetQuickUnlock(for: reference.id) }
            }
        }
        Divider()
        Button("Remove from Library", systemImage: "trash", role: .destructive) {
            removing = reference
        }
    }
}

private struct DatabaseRow: View {
    let reference: DatabaseReference
    let isUnlocked: Bool
    let isQuickCreateTarget: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(reference.name)
                        .font(.headline)
                    if isQuickCreateTarget {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Quick Create database")
                    }
                }
                if reference.name != reference.displayName {
                    Text(reference.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastOpened = reference.lastOpened {
                    Text("Opened \(lastOpened, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension UTType {
    /// KeePass 2 database files, declared as an imported type in
    /// Config/keepassios-Info.plist.
    static let keepassDatabase = UTType(importedAs: "org.keepass.kdbx", conformingTo: .data)
}
