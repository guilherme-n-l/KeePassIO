import SwiftUI
import UIKit

// The group screen draws its own grouped-list look from stacks instead of
// using List: List handles drag-and-drop for the whole list and never
// delivers drops to individual rows, so dropping an entry on a group (or
// on another entry, to make a group) couldn't work there.

/// A titled, rounded section of rows separated by hairlines.
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                SwiftUI.Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 56)
                        }
                        row
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// A row's content with list padding and, for rows that open something,
/// a disclosure chevron.
struct CardRow<Content: View>: View {
    var showsChevron = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Highlights a row while it's pressed, like a list row.
struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Color(uiColor: .systemFill) : Color.clear)
    }
}
