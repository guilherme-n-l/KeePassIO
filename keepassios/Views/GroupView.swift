import KPMerge
import KPModel
import KPOTP
import KPSearch
import KPSession
import SwiftUI

/// The contents of one group, with search over the whole database.
struct GroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let session: DatabaseSession
    let groupID: UUID
    var isRoot = false

    @State private var query = ""
    @State private var editingEntry: Entry?
    @State private var editingExistingEntry: Entry?
    @State private var isDownloadingIcons = false
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var saveError: String?
    @State private var copyCount = 0

    private var group: KPModel.Group? { session.database?.group(withID: groupID) }

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
                                Label {
                                    Text(child.name)
                                } icon: {
                                    ItemIcon(group: child, in: session.database)
                                }
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
                            EntryRow(entry: entry, database: session.database)
                        }
                        .contextMenu { quickActions(for: entry) }
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
        .sheet(item: $editingExistingEntry) { entry in
            NavigationStack {
                EntryEditorView(session: session, entry: entry, isNew: false, groupID: nil)
            }
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .alert("New Group", isPresented: $isAddingGroup) {
            TextField("Name", text: $newGroupName)
                .accessibilityIdentifier("newGroup.name")
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Add") {
                try? session.addGroup(KPModel.Group(name: newGroupName), to: groupID)
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
                if let entry = session.database?.entry(withID: hit.entryID) {
                    EntryRow(entry: entry, database: session.database, groupName: hit.groupName)
                }
            }
            .contextMenu {
                if let entry = session.database?.entry(withID: hit.entryID) {
                    quickActions(for: entry)
                }
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
                if model.settings.mayDownloadFavicons {
                    Button("Download Website Icons", systemImage: "photo.badge.arrow.down") {
                        downloadMissingIcons()
                    }
                    .disabled(isDownloadingIcons)
                }
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
                    model.lock(session)
                } label: {
                    Label("Lock", systemImage: "lock")
                }
                .accessibilityIdentifier("database.lock")
            }
        }
    }
}

extension GroupView {
    /// The long-press menu of an entry.
    @ViewBuilder
    func quickActions(for entry: Entry) -> some View {
        if !entry.userName.isEmpty {
            Button("Copy User Name", systemImage: "person") { copy(entry.userName, sensitive: false) }
        }
        if !entry.password.isEmpty {
            Button("Copy Password", systemImage: "key") { copy(entry.password.reveal(), sensitive: true) }
                .accessibilityIdentifier("entryMenu.copyPassword")
        }
        if let otp = try? OTP(fields: entry.fields.mapValues { $0.reveal() }) {
            Button("Copy One-Time Code", systemImage: "clock.badge.checkmark") {
                copy(otp.code(at: Date()), sensitive: true)
            }
        }
        if let url = WebsiteIcon.openableURL(for: entry.url) {
            Button("Open Website", systemImage: "safari") { openURL(url) }
        }
        Divider()
        Button("Edit", systemImage: "pencil") { editingExistingEntry = entry }
        if model.settings.mayDownloadFavicons, !entry.url.isEmpty {
            Button("Download Icon", systemImage: "photo.badge.arrow.down") {
                Task { await model.downloadIcons(for: [entry.id], in: session) }
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            try? session.deleteEntry(entry.id)
        }
    }

    private func copy(_ value: String, sensitive: Bool) {
        Clipboard.copy(value, sensitive: sensitive, clearAfter: model.settings.clipboardClearSeconds)
        copyCount += 1
    }

    private func downloadMissingIcons() {
        let ids = session.database?.allEntries.filter { $0.customIconID == nil && !$0.url.isEmpty }.map(\.id) ?? []
        isDownloadingIcons = true
        Task {
            await model.downloadIcons(for: ids, in: session)
            isDownloadingIcons = false
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let database: Database?
    var groupName: String?

    private var title: String { entry.title }
    private var userName: String { entry.userName }

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(entry: entry, in: database)
            details
        }
    }

    private var details: some View {
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
