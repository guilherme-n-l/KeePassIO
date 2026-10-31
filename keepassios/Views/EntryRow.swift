import KPModel
import SwiftUI

/// The entry or group whose icon is being chosen.
enum IconTarget: Identifiable {
    case entry(UUID)
    case group(UUID)

    var id: UUID {
        switch self {
        case .entry(let id), .group(let id): id
        }
    }
}

/// Where a search looks: the group on screen (with its subgroups) or the
/// whole database.
enum SearchScope: Hashable {
    case group
    case database
}

/// The search field at the top of every group screen, with the
/// "This Group / All Groups" switch in subgroups.
///
/// It's the first thing on the page rather than the system search bar:
/// the system bar sat at the bottom on the database's top level and at
/// the top in subgroups (scopes move it), and could vanish after going
/// back. It's drawn like the system field.
struct GroupSearchBar: View {
    @Binding var query: String
    @Binding var scope: SearchScope
    let showsScope: Bool
    @FocusState private var isFocused: Bool

    /// Searching shows Cancel and, in subgroups, the scope switch. One
    /// value drives both so they animate together with the field.
    private var isActive: Bool { isFocused || !query.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search", text: $query)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("group.search")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                // Always in the row, at zero width while not searching. Its
                // width animates with the field's, so its leading edge
                // follows the field's trailing edge as the field shrinks,
                // like the system search bar, instead of appearing on top.
                Button("Cancel") {
                    query = ""
                    isFocused = false
                }
                .fixedSize()
                .padding(.leading, 8)
                .frame(width: isActive ? nil : 0, alignment: .leading)
                .clipped()
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
            }
            if showsScope, isActive {
                Picker("Search In", selection: $scope) {
                    Text("This Group").tag(SearchScope.group)
                    Text("All Groups").tag(SearchScope.database)
                }
                .pickerStyle(.segmented)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: isActive)
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
