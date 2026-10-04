import KPAppState
import KPMerge
import KPModel
import KPOTP
import KPSearch
import KPSession
import SwiftUI

/// Where a search looks: the group on screen (with its subgroups) or the
/// whole database.
enum SearchScope: Hashable {
    case group
    case database
}

/// The contents of one group, with search, drag-and-drop moves and
/// long-press actions.
struct GroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let session: DatabaseSession
    let databaseID: UUID
    let groupID: UUID
    var isRoot = false

    @State private var query = ""
    @State private var scope = SearchScope.group
    @State private var editingEntry: Entry?
    @State private var editingExistingEntry: Entry?
    @State private var moving: DraggedItem?
    @State private var isDownloadingIcons = false
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var saveError: String?
    @State private var copyCount = 0
    @State private var moveCount = 0
    /// Entries waiting for a name for the group they'll be put in.
    @State private var grouping: [UUID]?
    @State private var groupingName = ""

    private var group: KPModel.Group? { session.database?.group(withID: groupID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !query.isEmpty {
                    searchResults
                } else if let group {
                    if !isRoot {
                        Breadcrumbs(session: session, groupID: groupID) { items, target in
                            move(items, into: target)
                        }
                    }
                    if !group.groups.isEmpty {
                        CardSection("Groups") {
                            ForEach(group.groups) { child in
                                groupRow(child)
                            }
                        }
                    }
                    CardSection("Entries") {
                        if group.entries.isEmpty {
                            CardRow(showsChevron: false) {
                                Text("No entries")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(group.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            GroupSearchBar(query: $query, scope: $scope, showsScope: !isRoot)
        }
        .navigationTitle(group?.name ?? "")
        .toolbar { toolbar }
        .sensoryFeedback(.success, trigger: copyCount)
        .sensoryFeedback(.impact, trigger: moveCount)
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
        .sheet(item: $moving) { item in
            NavigationStack {
                MoveToView(session: session, item: item)
            }
        }
        .alert(
            "New Group",
            isPresented: Binding(get: { grouping != nil }, set: { if !$0 { grouping = nil } })
        ) {
            TextField("Name", text: $groupingName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createGroup() }
        } message: {
            Text("The entries are moved into the new group.")
        }
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
        let searchedGroup = isRoot || scope == .database ? nil : groupID
        let hits = session.searchIndex?.search(query, in: searchedGroup, limit: 200) ?? []
        if hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            CardSection {
                ForEach(hits) { hit in
                    if let entry = session.database?.entry(withID: hit.entryID) {
                        NavigationLink(value: DatabaseRoute.entry(database: databaseID, entry: hit.entryID)) {
                            CardRow {
                                EntryRow(entry: entry, database: session.database, groupName: hit.groupName)
                            }
                        }
                        .buttonStyle(CardRowButtonStyle())
                        .contextMenu { quickActions(for: entry) }
                        .accessibilityIdentifier("search.\(hit.title)")
                    }
                }
            }
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
    /// A subgroup: tap to open, drag to move, drop entries or groups on it
    /// to move them in.
    private func groupRow(_ child: KPModel.Group) -> some View {
        NavigationLink(value: DatabaseRoute.group(database: databaseID, group: child.id)) {
            CardRow {
                HStack(spacing: 12) {
                    ItemIcon(group: child, in: session.database)
                    Text(child.name)
                }
            }
        }
        .buttonStyle(CardRowButtonStyle())
        .draggable(DraggedItem(kind: .group, id: child.id)) {
            DragPreview(title: child.name, systemImage: "folder")
        }
        .modifier(MoveIntoDropTarget { items in move(items, into: child.id) })
        .contextMenu { groupActions(for: child) }
        .accessibilityIdentifier("group.\(child.name)")
    }

    /// An entry: tap to open, drag to move, hold another entry over it to
    /// group the two.
    private func entryRow(_ entry: Entry) -> some View {
        NavigationLink(value: DatabaseRoute.entry(database: databaseID, entry: entry.id)) {
            CardRow {
                EntryRow(entry: entry, database: session.database)
            }
        }
        .buttonStyle(CardRowButtonStyle())
        .draggable(DraggedItem(kind: .entry, id: entry.id)) {
            DragPreview(title: entry.title, systemImage: "key")
        }
        .modifier(GroupingDropTarget { items in proposeGroup(of: items, with: entry) })
        .contextMenu { quickActions(for: entry) }
        .accessibilityIdentifier("entry.\(entry.title)")
    }

    /// Asks for a name for a new group holding `entry` and the dragged
    /// entries. Groups dropped on an entry are ignored.
    private func proposeGroup(of items: [DraggedItem], with entry: Entry) -> Bool {
        let dragged = items.filter { $0.kind == .entry && $0.id != entry.id }.map(\.id)
        guard !dragged.isEmpty else { return false }
        groupingName = String(localized: "New Group")
        grouping = [entry.id] + dragged
        return true
    }

    private func createGroup() {
        guard let entries = grouping else { return }
        let name = groupingName.trimmingCharacters(in: .whitespaces)
        let newGroup = KPModel.Group(name: name.isEmpty ? String(localized: "New Group") : name)
        do {
            try session.addGroup(newGroup, to: groupID)
            for id in entries {
                try session.moveEntry(id, to: newGroup.id)
            }
            moveCount += 1
        } catch {
            saveError = error.userMessage
        }
        grouping = nil
    }

    /// Moves dragged entries and groups into `target`. Groups can't go
    /// into themselves; those drops are ignored.
    private func move(_ items: [DraggedItem], into target: UUID) -> Bool {
        var moved = false
        for item in items {
            switch item.kind {
            case .entry:
                guard session.database?.location(ofEntry: item.id)?.parentID != target else { continue }
                moved = (try? session.moveEntry(item.id, to: target)) != nil || moved
            case .group:
                guard item.id != target, session.database?.location(ofGroup: item.id)?.parentID != target else {
                    continue
                }
                moved = (try? session.moveGroup(item.id, to: target)) != nil || moved
            }
        }
        if moved {
            moveCount += 1
        }
        return moved
    }

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
        Button("Move To…", systemImage: "folder") { moving = DraggedItem(kind: .entry, id: entry.id) }
        if model.settings.mayDownloadFavicons, !entry.url.isEmpty {
            Button("Download Icon", systemImage: "photo.badge.arrow.down") {
                Task { await model.downloadIcons(for: [entry.id], in: session) }
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            try? session.deleteEntry(entry.id)
        }
    }

    /// The long-press menu of a group.
    @ViewBuilder
    func groupActions(for group: KPModel.Group) -> some View {
        Button("Move To…", systemImage: "folder") { moving = DraggedItem(kind: .group, id: group.id) }
        Button("Delete", systemImage: "trash", role: .destructive) {
            try? session.deleteGroup(group.id)
        }
    }

    private func copy(_ value: String, sensitive: Bool) {
        Clipboard.copy(value, sensitive: sensitive, clearAfter: model.settings.clipboardClearSeconds)
        copyCount += 1
    }

    private func downloadMissingIcons() {
        let entries = session.database?.activeEntries ?? []
        let ids = entries.filter { $0.customIconID == nil && !$0.url.isEmpty }.map(\.id)
        isDownloadingIcons = true
        Task {
            await model.downloadIcons(for: ids, in: session)
            isDownloadingIcons = false
        }
    }
}
