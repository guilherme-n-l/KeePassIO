import KPAppState
import KPModel
import KPSession
import SwiftUI

extension GroupView {
    /// The icon picker for an entry or group shown in this group, applying
    /// the choice straight to the database.
    @ViewBuilder
    func iconPicker(for target: IconTarget) -> some View {
        let database = session.database
        switch target {
        case .entry(let id):
            let entry = database?.entry(withID: id)
            IconPickerView(
                database: database,
                current: IconChoice(iconID: entry?.iconID ?? 0, customIconID: entry?.customIconID),
                websiteURL: model.settings.mayDownloadFavicons && entry?.url.isEmpty == false ? entry?.url : nil
            ) { choice in
                try? session.setIcon(choice, forEntry: id)
            }
        case .group(let id):
            let group = database?.group(withID: id)
            IconPickerView(
                database: database,
                current: IconChoice(iconID: group?.iconID ?? 48, customIconID: group?.customIconID)
            ) { choice in
                try? session.setIcon(choice, forGroup: id)
            }
        }
    }

}
