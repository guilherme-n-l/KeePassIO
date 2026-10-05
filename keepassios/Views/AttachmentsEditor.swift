import KPModel
import KPPlatform
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Attachment editing for the entry editor. As with one-time codes, the
/// pickers are presented from the editor itself rather than from inside
/// its Form (see `OTPSetup`).
@MainActor
@Observable
final class AttachmentEditing {
    var isImportingFiles = false
    var isPickingPhotos = false
    var photos: [PhotosPickerItem] = []
    /// The attachment being renamed and the name being typed.
    var renaming: String?
    var newName = ""
    var message: String?

    func add(_ data: Data, named name: String, to entry: Binding<Entry>) {
        let unique = AttachmentFiles.uniqueName(name, existing: entry.wrappedValue.attachments.keys)
        entry.wrappedValue.attachments[unique] = data
    }

    func importFiles(_ urls: [URL], into entry: Binding<Entry>) async {
        message = nil
        for url in urls {
            if let data = await KeyFile.read(url) {
                add(data, named: url.lastPathComponent, to: entry)
            } else {
                message = String(localized: "\(url.lastPathComponent) couldn't be read.")
            }
        }
    }

    func importPhotos(into entry: Binding<Entry>) async {
        message = nil
        let items = photos
        photos = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                message = String(localized: "A photo couldn't be read.")
                continue
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            add(data, named: "Photo \(index + 1).\(ext)", to: entry)
        }
    }

    func rename(in entry: Binding<Entry>) {
        guard let old = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty, name != old, let data = entry.wrappedValue.attachments[old] else { return }
        entry.wrappedValue.attachments[old] = nil
        add(data, named: name, to: entry)
    }
}

/// The editor's attachments section.
struct AttachmentsSection: View {
    @Binding var entry: Entry
    let editing: AttachmentEditing

    var body: some View {
        Section {
            let names = entry.attachments.keys.sorted()
            ForEach(names, id: \.self) { name in
                LabeledContent(name) {
                    Text(Int64(entry.attachments[name]?.count ?? 0), format: .byteCount(style: .file))
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        editing.newName = name
                        editing.renaming = name
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        entry.attachments[name] = nil
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    entry.attachments[names[index]] = nil
                }
            }
            Button("Add File", systemImage: "doc.badge.plus") { editing.isImportingFiles = true }
                .accessibilityIdentifier("editor.attachments.addFile")
            Button("Add Photo", systemImage: "photo.badge.plus") { editing.isPickingPhotos = true }
        } header: {
            Text("Attachments")
        } footer: {
            if let message = editing.message {
                Text(message).foregroundStyle(.red)
            } else if !entry.attachments.isEmpty {
                Text(
                    "Attachments are stored encrypted inside the database, so large ones make it slower to open and sync."
                )
            }
        }
    }
}

/// The file importer, photo picker and rename alert, attached to the
/// editor itself.
struct AttachmentScreens: ViewModifier {
    @Binding var entry: Entry
    @Bindable var editing: AttachmentEditing

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $editing.isImportingFiles,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await editing.importFiles(urls, into: $entry) }
            }
            .photosPicker(
                isPresented: $editing.isPickingPhotos,
                selection: $editing.photos,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: editing.photos) { _, items in
                guard !items.isEmpty else { return }
                Task { await editing.importPhotos(into: $entry) }
            }
            .alert(
                "Rename Attachment",
                isPresented: Binding(
                    get: { editing.renaming != nil },
                    set: { if !$0 { editing.renaming = nil } }
                )
            ) {
                TextField("Name", text: $editing.newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { editing.rename(in: $entry) }
            }
    }
}
