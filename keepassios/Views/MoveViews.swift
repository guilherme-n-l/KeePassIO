import KPModel
import KPSession
import SwiftUI

/// The path from the top of the database to the group on screen. Every
/// part is a drop target, so an entry or group can be dragged up and out
/// of the group, like the path bar in the Files app.
struct Breadcrumbs: View {
    let session: DatabaseSession
    let groupID: UUID
    let onDrop: ([DraggedItem], UUID) -> Bool

    private var groups: [KPModel.Group] {
        guard let database = session.database else { return [] }
        let above = database.location(ofGroup: groupID)?.path ?? []
        return (above + [groupID]).compactMap { database.group(withID: $0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Crumb(
                        name: index == 0 ? session.database?.meta.name ?? group.name : group.name,
                        isCurrent: group.id == groupID
                    ) { items in
                        onDrop(items, group.id)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }
}

private struct Crumb: View {
    let name: String
    let isCurrent: Bool
    let onDrop: ([DraggedItem]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Text(name.isEmpty ? String(localized: "Database") : name)
            .font(.subheadline)
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isTargeted ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
            .dropDestination(for: DraggedItem.self) { items, _ in
                onDrop(items)
            } isTargeted: {
                isTargeted = $0
            }
    }
}

/// Picks a group to move an entry or group to: the long-press alternative
/// to dragging.
struct MoveToView: View {
    @Environment(\.dismiss) private var dismiss
    let session: DatabaseSession
    let item: DraggedItem
    @State private var errorMessage: String?

    private struct Row: Identifiable {
        let group: KPModel.Group
        let depth: Int
        var id: UUID { group.id }
    }

    /// Every group, indented by depth, leaving out the recycle bin and,
    /// when moving a group, the group itself and everything under it.
    private var rows: [Row] {
        guard let database = session.database else { return [] }
        var rows: [Row] = []
        database.root.forEachGroup { group, path in
            if let bin = database.meta.recycleBinID, path.contains(bin) { return }
            if item.kind == .group, path.contains(item.id) { return }
            rows.append(Row(group: group, depth: path.count - 1))
        }
        return rows
    }

    private var currentParent: UUID? {
        switch item.kind {
        case .entry: session.database?.location(ofEntry: item.id)?.parentID
        case .group: session.database?.location(ofGroup: item.id)?.parentID
        }
    }

    var body: some View {
        List(rows) { row in
            Button {
                move(to: row.group.id)
            } label: {
                HStack {
                    Label {
                        Text(row.depth == 0 ? session.database?.meta.name ?? row.group.name : row.group.name)
                    } icon: {
                        ItemIcon(group: row.group, in: session.database)
                    }
                    .padding(.leading, CGFloat(row.depth) * 16)
                    Spacer()
                    if row.group.id == currentParent {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Move To")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert(
            "Couldn't Move",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func move(to target: UUID) {
        do {
            switch item.kind {
            case .entry: try session.moveEntry(item.id, to: target)
            case .group: try session.moveGroup(item.id, to: target)
            }
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}

/// Makes a group row a drop target: entries and groups dropped on it move
/// inside. The row is highlighted while something is held over it.
struct MoveIntoDropTarget: ViewModifier {
    let onDrop: ([DraggedItem]) -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
            .dropDestination(for: DraggedItem.self) { items, _ in
                onDrop(items)
            } isTargeted: { targeted in
                withAnimation(.snappy) { isTargeted = targeted }
            }
    }
}

/// Makes an entry row a drop target for grouping: an entry held over it
/// for a moment arms the row ("New Group"), and dropping then offers to
/// put both entries in a new group, like making a folder on the Home
/// Screen. A quick drop over a row does nothing.
struct GroupingDropTarget: ViewModifier {
    static let holdDelay = Duration.milliseconds(700)

    let onGroup: ([DraggedItem]) -> Bool
    @State private var isArmed = false
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isArmed {
                    Label("New Group", systemImage: "folder.badge.plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background(isArmed ? Color.accentColor.opacity(0.2) : Color.clear)
            .sensoryFeedback(.selection, trigger: isArmed) { _, armed in armed }
            .dropDestination(for: DraggedItem.self) { items, _ in
                let armed = isArmed
                disarm()
                return armed && onGroup(items)
            } isTargeted: { targeted in
                timer?.cancel()
                timer = Task {
                    // Arm after holding still over the row; when the drag
                    // leaves, wait a little so a drop that reports leaving
                    // first still sees the armed state.
                    try? await Task.sleep(for: targeted ? Self.holdDelay : .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { isArmed = targeted }
                }
            }
    }

    private func disarm() {
        timer?.cancel()
        withAnimation(.snappy) { isArmed = false }
    }
}

/// What follows the finger while dragging an entry or group.
struct DragPreview: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .padding(8)
            .background(.regularMaterial, in: Capsule())
    }
}
