import KPModel
import KPSearch
import KPSession
import SwiftUI

/// The contents of one group, with search over the whole database.
struct GroupView: View {
    @Environment(AppModel.self) private var model
    let session: DatabaseSession
    let groupID: UUID
    var isRoot = false

    @State private var query = ""
    @State private var editingEntry: Entry?
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var saveError: String?

    private var group: Group? { session.database?.group(withID: groupID) }

    var body: some View {
        List {
            if !query.isEmpty {
                searchResults
            } else if let group {
                if !group.groups.isEmpty {
                    Section("Groups") {
                        ForEach(group.groups) { child in
                            NavigationLink {
                                GroupView(session: session, groupID: child.id)
                            } label: {
                                Label(
                                    child.name,
                                    systemImage: child.id == session.database?.meta.recycleBinID ? "trash" : "folder"
                                )
                            }
                            .accessibilityIdentifier("group.\(child.name)")
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                try? session.deleteGroup(group.groups[index].id)
                            }
                        }
                    }
                }
                Section("Entries") {
                    if group.entries.isEmpty {
                        Text("No entries")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.entries) { entry in
                        NavigationLink {
                            EntryDetailView(session: session, entryID: entry.id)
                        } label: {
                            EntryRow(title: entry.title, userName: entry.userName)
                        }
                        .accessibilityIdentifier("entry.\(entry.title)")
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            try? session.deleteEntry(group.entries[index].id)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle(group?.name ?? "")
        .toolbar { toolbar }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                EntryEditorView(session: session, entry: entry, isNew: true, groupID: groupID)
            }
        }
        .alert("New Group", isPresented: $isAddingGroup) {
            TextField("Name", text: $newGroupName)
                .accessibilityIdentifier("newGroup.name")
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Add") {
                try? session.addGroup(Group(name: newGroupName), to: groupID)
                newGroupName = ""
            }
        }
        .alert(
            "Couldn't Save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { session.lastMergeReport.map { !$0.isEmpty } ?? false && isRoot },
                set: { _ in }
            )
        ) {
            if let report = session.lastMergeReport {
                MergeReviewView(report: report)
            }
        }
        .onChange(of: model.quickCreateRequested) { _, requested in
            if requested, isRoot {
                model.quickCreateRequested = false
                editingEntry = session.newEntry()
            }
        }
        .onAppear {
            if model.quickCreateRequested, isRoot {
                model.quickCreateRequested = false
                editingEntry = session.newEntry()
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let hits = session.searchIndex?.search(query, limit: 200) ?? []
        if hits.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        ForEach(hits) { hit in
            NavigationLink {
                EntryDetailView(session: session, entryID: hit.entryID)
            } label: {
                EntryRow(title: hit.title, userName: hit.userName, groupName: hit.groupName)
            }
            .accessibilityIdentifier("search.\(hit.title)")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Entry", systemImage: "key") {
                    editingEntry = session.newEntry()
                }
                .accessibilityIdentifier("group.newEntry")
                Button("New Group", systemImage: "folder.badge.plus") {
                    isAddingGroup = true
                }
                .accessibilityIdentifier("group.newGroup")
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityIdentifier("group.add")
        }
        if isRoot {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        do {
                            try await session.save()
                        } catch {
                            saveError = (error as? SessionError)?.userMessage ?? error.localizedDescription
                        }
                    }
                } label: {
                    if session.isSaving {
                        ProgressView()
                    } else {
                        Label(
                            "Save",
                            systemImage: session.hasUnsavedChanges
                                ? "square.and.arrow.down.badge.clock" : "checkmark.circle"
                        )
                    }
                }
                .disabled(!session.hasUnsavedChanges || session.isSaving)
                .accessibilityIdentifier("database.save")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.lock()
                } label: {
                    Label("Lock", systemImage: "lock")
                }
                .accessibilityIdentifier("database.lock")
            }
        }
    }
}

struct EntryRow: View {
    let title: String
    let userName: String
    var groupName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.isEmpty ? String(localized: "Untitled") : title)
                .font(.body)
            HStack(spacing: 4) {
                if !userName.isEmpty {
                    Text(userName)
                }
                if let groupName {
                    Text("· \(groupName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
