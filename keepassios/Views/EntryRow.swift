import KPModel
import SwiftUI

/// The "This Group / All Groups" switch under the search field, shown in
/// subgroups (at the top level both mean the same).
struct SearchScopeBar: ViewModifier {
    let isShown: Bool
    @Binding var scope: SearchScope

    func body(content: Content) -> some View {
        if isShown {
            content.searchScopes($scope, activation: .onSearchPresentation) {
                Text("This Group").tag(SearchScope.group)
                Text("All Groups").tag(SearchScope.database)
            }
        } else {
            content
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
