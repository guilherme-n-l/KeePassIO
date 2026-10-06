import KPMerge
import SwiftUI

/// Lists what a merge changed, after the database file was changed
/// elsewhere and merged into this copy.
struct MergeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let report: MergeReport

    var body: some View {
        NavigationStack {
            List {
                if !report.conflicts.isEmpty {
                    Section {
                        ForEach(report.conflicts, id: \.self) { conflict in
                            VStack(alignment: .leading) {
                                Text(conflict.title).font(.headline)
                                Text(
                                    "Changed on both devices: \(conflict.fields.joined(separator: ", ")). The newer version was kept; the other is in the entry's history."
                                )
                                .font(.caption)
                            }
                        }
                    } header: {
                        Text("Conflicts")
                    }
                }
                Section("Changes") {
                    ForEach(report.changes, id: \.self) { change in
                        Text(change.summary)
                    }
                }
            }
            .navigationTitle("Merged Changes")
            .toolbar {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("merge.done")
            }
        }
    }
}

extension MergeChange {
    var summary: String {
        switch self {
        case .entryAdded(_, let title): String(localized: "Added “\(title)”")
        case .entryUpdated(_, let title): String(localized: "Updated “\(title)”")
        case .entryMoved(_, let title, _): String(localized: "Moved “\(title)”")
        case .entryDeleted(_, let title): String(localized: "Deleted “\(title)”")
        case .entryRestored(_, let title):
            String(localized: "Kept “\(title)”, which was edited after being deleted elsewhere")
        case .groupAdded(_, let name): String(localized: "Added group “\(name)”")
        case .groupUpdated(_, let name): String(localized: "Updated group “\(name)”")
        case .groupMoved(_, let name, _): String(localized: "Moved group “\(name)”")
        case .groupDeleted(_, let name): String(localized: "Deleted group “\(name)”")
        case .groupKept(_, let name): String(localized: "Kept group “\(name)”, which still has entries")
        case .settingsUpdated: String(localized: "Updated database settings")
        }
    }
}
