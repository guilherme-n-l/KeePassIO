import KPModel
import KPSession
import PhotosUI
import SwiftUI
import UIKit

/// Chooses an icon for an entry or group: a standard KeePass icon, one
/// already in the database, a photo, or (for entries) the website's icon.
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let database: Database?
    /// The icon the item has now, marked in the grid.
    let current: IconChoice
    /// The entry's URL when its website icon may be downloaded.
    var websiteURL: String?
    let onPick: (IconChoice) -> Void

    @State private var photo: PhotosPickerItem?
    @State private var isWorking = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 12)]

    private var customIcons: [(id: UUID, data: Data)] {
        (database?.meta.customIcons ?? [:])
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { (id: $0.key, data: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sources
                if !customIcons.isEmpty {
                    gridSection("In This Database") {
                        ForEach(customIcons, id: \.id) { icon in
                            cell(.custom(icon.id), icon: ItemIcon(iconID: 0, customIcon: icon.data))
                        }
                    }
                }
                gridSection("Standard") {
                    ForEach(0..<StandardIcon.count, id: \.self) { id in
                        cell(.standard(id), icon: ItemIcon(iconID: id, customIcon: nil))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
    }

    /// Photo library and website icon buttons.
    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if let websiteURL {
                    Button {
                        Task { await useWebsiteIcon(websiteURL) }
                    } label: {
                        Label("Website Icon", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(isWorking)
            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gridSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                content()
            }
            .padding(12)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private func cell(_ choice: IconChoice, icon: ItemIcon) -> some View {
        Button {
            pick(choice)
        } label: {
            icon
                .frame(width: 52, height: 52)
                .background(
                    choice == current ? Color.accentColor.opacity(0.25) : Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func pick(_ choice: IconChoice) {
        onPick(choice)
        dismiss()
    }

    private func usePhoto(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let png = IconImage.png(from: image)
        else {
            message = String(localized: "That photo couldn't be used.")
            return
        }
        pick(.newCustom(png))
    }

    private func useWebsiteIcon(_ url: String) async {
        isWorking = true
        defer { isWorking = false }
        guard let png = await WebsiteIcon.fetch(for: url) else {
            message = String(localized: "The website has no icon, or couldn't be reached.")
            return
        }
        pick(.newCustom(png))
    }
}

extension IconChoice {
    /// The choice that describes an item's current icon.
    init(iconID: Int, customIconID: UUID?) {
        self = customIconID.map { .custom($0) } ?? .standard(iconID)
    }
}
