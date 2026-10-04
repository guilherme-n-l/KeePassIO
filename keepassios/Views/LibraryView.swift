import KPAppState
import SwiftUI
import UniformTypeIdentifiers

/// The list of databases the user has added.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var isCreating = false
    @State private var isShowingSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
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
                                DatabaseRow(reference: reference)
                            }
                            .accessibilityIdentifier("library.database.\(reference.displayName)")
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

private struct DatabaseRow: View {
    let reference: DatabaseReference

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(reference.displayName, systemImage: "lock.shield")
                .font(.headline)
            if let lastOpened = reference.lastOpened {
                Text("Opened \(lastOpened, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension UTType {
    /// KeePass 2 database files, declared as an imported type in
    /// Config/keepassios-Info.plist.
    static let keepassDatabase = UTType(importedAs: "org.keepass.kdbx", conformingTo: .data)
}
