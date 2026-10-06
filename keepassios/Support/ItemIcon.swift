import KPModel
import KPSession
import SwiftUI
import UIKit

/// The icon of an entry or group: the database's custom icon (a website
/// icon downloaded here or by KeePassXC) when there is one, otherwise the
/// standard KeePass icon the entry or group has.
struct ItemIcon: View {
    let iconID: Int
    let customIcon: Data?

    init(iconID: Int, customIcon: Data?) {
        self.iconID = iconID
        self.customIcon = customIcon
    }

    /// How an item would look with `choice` (for previews before saving).
    init(choice: IconChoice, in database: Database?) {
        switch choice {
        case .standard(let id): self.init(iconID: id, customIcon: nil)
        case .custom(let id): self.init(iconID: 0, customIcon: database?.meta.customIcons[id])
        case .newCustom(let data): self.init(iconID: 0, customIcon: data)
        }
    }

    init(entry: Entry, in database: Database?) {
        iconID = entry.iconID
        customIcon = entry.customIconID.flatMap { database?.meta.customIcons[$0] }
    }

    init(group: KPModel.Group, in database: Database?) {
        iconID = group.iconID
        customIcon = group.customIconID.flatMap { database?.meta.customIcons[$0] }
    }

    var body: some View {
        SwiftUI.Group {
            if let customIcon, let image = UIImage(data: customIcon) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                StandardIcon.image(for: iconID)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

/// The 69 standard KeePass icons (`PwIcon` in KeePass 2), drawn with
/// KeePassXC's artwork so entries look the same as on the desktop. The
/// SVGs live in Assets.xcassets/DatabaseIcons (MIT and CC0, see
/// THIRD_PARTY_NOTICES.md). KeePassXC's Apple logo is GPL, so icon 64
/// uses the SF Symbol instead.
enum StandardIcon {
    static let count = 69
    static let appleIconID = 64

    static func image(for iconID: Int) -> Image {
        let id = (0..<count).contains(iconID) ? iconID : 0
        if id == appleIconID {
            return Image(systemName: "applelogo")
        }
        return Image(String(format: "KeePassIcon%02d", id))
    }
}
