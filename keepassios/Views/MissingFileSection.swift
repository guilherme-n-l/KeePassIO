import KPAppState
import SwiftUI
import UniformTypeIdentifiers

/// Ways forward on the unlock screen when a database's file is gone:
/// point the app at where it is now, put the copy kept on this device
/// back in Files, or remove the database from the library.
struct MissingFileSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reference: DatabaseReference

    @State private var isLocating = false
    @State private var restored: RestoredFile?
    @State private var isConfirmingRemoval = false

    private struct RestoredFile {
        let url: URL
    }

    private var hasKeptCopy: Bool { model.hasKeptCopy(of: reference.id) }

    var body: some View {
        Section {
            Button("Locate File…", systemImage: "folder") {
                isLocating = true
            }
            .accessibilityIdentifier("missingFile.locate")
            if hasKeptCopy {
                Button("Restore Copy from This Device…", systemImage: "arrow.counterclockwise") {
                    restored = model.restoredFile(for: reference).map(RestoredFile.init)
                }
                .accessibilityIdentifier("missingFile.restore")
            }
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                isConfirmingRemoval = true
            }
            .accessibilityIdentifier("missingFile.remove")
        } header: {
            Text("File Not Found")
        } footer: {
            if hasKeptCopy {
                Text(
                    "The file was moved or deleted. If it was moved, locate it. Otherwise restore the copy this device kept from the last time the database was open: you choose where to save it."
                )
            } else {
                Text("The file was moved or deleted. If it was moved, locate it.")
            }
        }
        .fileImporter(isPresented: $isLocating, allowedContentTypes: [.keepassDatabase, .data]) { result in
            guard case .success(let url) = result else { return }
            relocate(to: url)
        }
        .fileMover(
            isPresented: Binding(get: { restored != nil }, set: { _ in }),
            file: restored?.url
        ) { result in
            let folder = restored?.url.deletingLastPathComponent()
            restored = nil
            if case .success(let url) = result {
                relocate(to: url)
            }
            if let folder {
                try? FileManager.default.removeItem(at: folder)
            }
        } onCancellation: {
            if let folder = restored?.url.deletingLastPathComponent() {
                try? FileManager.default.removeItem(at: folder)
            }
            restored = nil
        }
        .confirmationDialog("Remove from Library?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove \(reference.name)", role: .destructive) {
                Task {
                    await model.removeDatabase(reference.id)
                    dismiss()
                }
            }
        } message: {
            if hasKeptCopy {
                Text("The copy kept on this device is deleted too. This can't be undone.")
            } else {
                Text("The database is only removed from this list.")
            }
        }
    }

    private func relocate(to url: URL) {
        Task { await model.relocateDatabase(reference.id, to: url) }
    }
}
