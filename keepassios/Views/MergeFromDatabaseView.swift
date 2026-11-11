import KPMerge
import KPModel
import KPPlatform
import KPSession
import SwiftUI
import UniformTypeIdentifiers

/// A database file picked to merge into the open one.
struct MergeSource: Identifiable {
    let id = UUID()
    let file: BookmarkedFile
}

extension View {
    /// Lets the user pick another database file and merge it into the
    /// session's database after reviewing what would change.
    func mergeFromDatabase(isPickingFile: Binding<Bool>, session: DatabaseSession) -> some View {
        modifier(MergeFromDatabase(isPickingFile: isPickingFile, session: session))
    }
}

private struct MergeFromDatabase: ViewModifier {
    @Binding var isPickingFile: Bool
    let session: DatabaseSession
    @State private var source: MergeSource?
    @State private var pickError: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.keepassDatabase, .data]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let bookmark = try BookmarkedFile.makeBookmark(for: url)
                    let name = url.deletingPathExtension().lastPathComponent
                    source = MergeSource(file: BookmarkedFile(bookmark: bookmark, displayName: name))
                } catch {
                    pickError = error.localizedDescription
                }
            }
            .sheet(item: $source) { source in
                MergeFromDatabaseView(session: session, source: source)
            }
            .alert(
                "Couldn't Open the File",
                isPresented: Binding(get: { pickError != nil }, set: { if !$0 { pickError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pickError ?? "")
            }
    }
}

/// Opens the picked file, asking for its key when it differs from the
/// open database's, then shows what merging it would change. Nothing is
/// changed until the user confirms.
struct MergeFromDatabaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: DatabaseSession
    let source: MergeSource

    private enum Stage {
        case opening
        case needsKey
        case review(MergePreview)
        case failed(String)
    }

    @State private var stage = Stage.opening
    @State private var choices = MergeChoices()
    @State private var password = ""
    @State private var keyFileData: Data?
    @State private var keyFileName: String?
    @State private var isPickingKeyFile = false
    @State private var keyError: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Merge from Database")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(hasNothingToDo ? "Done" : "Cancel") { dismiss() }
                            .accessibilityIdentifier("mergeFrom.cancel")
                    }
                    if case .review(let preview) = stage, !preview.report.isEmpty {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Merge") { apply(preview) }
                                .disabled(isWorking)
                                .accessibilityIdentifier("mergeFrom.apply")
                        }
                    }
                }
        }
        .task { await open(with: nil) }
        .interactiveDismissDisabled(isWorking)
    }

    /// Whether the sheet has only a result to show, so leaving it is not
    /// cancelling anything.
    private var hasNothingToDo: Bool {
        switch stage {
        case .opening, .needsKey: false
        case .review(let preview): preview.report.isEmpty
        case .failed: true
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .opening:
            ProgressView("Opening \(source.file.displayName)…")
        case .needsKey:
            keyForm
        case .review(let preview):
            if preview.report.isEmpty {
                ContentUnavailableView(
                    "Nothing to Merge",
                    systemImage: "checkmark.circle",
                    description: Text("This database already has everything in “\(preview.sourceName)”.")
                )
                .accessibilityIdentifier("mergeFrom.nothing")
            } else {
                MergePreviewList(preview: preview, choices: $choices)
            }
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't Open the File",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .accessibilityIdentifier("mergeFrom.failed")
        }
    }

    private var keyForm: some View {
        Form {
            Section {
                SecureField("Master Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(openWithEnteredKey)
                    .accessibilityIdentifier("mergeFrom.password")
                Button {
                    isPickingKeyFile = true
                } label: {
                    LabeledContent("Key File") {
                        Text(keyFileName ?? String(localized: "Choose…"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("mergeFrom.keyFile")
            } header: {
                Text(source.file.displayName)
            } footer: {
                if let keyError {
                    Text(keyError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("mergeFrom.keyError")
                } else {
                    Text("This file is locked with a different key than the open database. Enter its key to merge it.")
                }
            }
            Section {
                Button(action: openWithEnteredKey) {
                    HStack {
                        Spacer()
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Open").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(isWorking || (password.isEmpty && keyFileData == nil))
                .accessibilityIdentifier("mergeFrom.open")
            }
        }
        .fileImporter(isPresented: $isPickingKeyFile, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            Task {
                guard let data = await KeyFile.read(url) else {
                    keyError = String(
                        localized: "The key file couldn't be read. If it's in iCloud Drive, make sure it's downloaded."
                    )
                    return
                }
                keyFileData = data
                keyFileName = url.lastPathComponent
                keyError = nil
            }
        }
    }

    private func openWithEnteredKey() {
        guard !password.isEmpty || keyFileData != nil else { return }
        let key = CompositeKey(
            password: password.isEmpty ? nil : SecretString(password),
            keyFileData: keyFileData
        )
        Task { await open(with: key) }
    }

    /// Reads the file with the given key, or the open database's own key
    /// when there is none yet.
    private func open(with key: CompositeKey?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let preview = try await session.previewMerge(from: source.file, key: key)
            password = ""
            keyFileData = nil
            stage = .review(preview)
        } catch .invalidKey {
            if key != nil {
                keyError = String(localized: "That key doesn't open this file.")
            }
            stage = .needsKey
        } catch {
            stage = .failed(error.userMessage)
        }
    }

    private func apply(_ preview: MergePreview) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do throws(SessionError) {
                try session.applyMerge(preview, choices: choices)
                await model.save(session)
                dismiss()
            } catch {
                stage = .failed(error.userMessage)
            }
        }
    }
}

/// What a merge would change: conflicts first, each field with a choice
/// of which side to keep, then everything else.
private struct MergePreviewList: View {
    let preview: MergePreview
    @Binding var choices: MergeChoices

    var body: some View {
        List {
            ForEach(preview.report.conflicts, id: \.self) { conflict in
                Section {
                    ForEach(conflict.fields, id: \.self) { field in
                        MergeConflictFieldRow(
                            field: field,
                            local: preview.local.entry(withID: conflict.entryID),
                            remote: preview.remote.entry(withID: conflict.entryID),
                            sourceName: preview.sourceName,
                            side: Binding(
                                get: { choices[conflict.entryID, field] ?? conflict.winner },
                                set: { choices[conflict.entryID, field] = $0 }
                            )
                        )
                    }
                } header: {
                    Text("Conflict in “\(conflict.title)”")
                } footer: {
                    Text("Changed in both files. The version you don't keep stays in the entry's history.")
                }
            }
            Section("Changes") {
                ForEach(preview.report.changes, id: \.self) { change in
                    Text(change.summary)
                }
            }
        }
        .accessibilityIdentifier("mergeFrom.review")
    }
}

/// One conflicting field: both values and which one is kept.
private struct MergeConflictFieldRow: View {
    let field: String
    let local: Entry?
    let remote: Entry?
    let sourceName: String
    @Binding var side: MergeSide

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MergeConflict.attachmentName(ofField: field).map { String(localized: "Attachment “\($0)”") } ?? label)
                .font(.subheadline.weight(.semibold))
            option(.local, name: String(localized: "This database"), entry: local)
            option(.remote, name: sourceName, entry: remote)
        }
        .padding(.vertical, 4)
    }

    private var label: String {
        switch field {
        case Entry.StandardField.userName: String(localized: "User Name")
        case Entry.StandardField.title: String(localized: "Title")
        case Entry.StandardField.password: String(localized: "Password")
        case Entry.StandardField.notes: String(localized: "Notes")
        default: field
        }
    }

    private func option(_ option: MergeSide, name: String, entry: Entry?) -> some View {
        Button {
            side = option
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: side == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(side == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.primary)
                    Text(description(of: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(side == option ? .isSelected : [])
        .accessibilityIdentifier("mergeFrom.\(field).\(option == .local ? "local" : "remote")")
    }

    /// The side's value and when that side was last changed. Protected
    /// values and attachments aren't shown, only described.
    private func description(of entry: Entry?) -> String {
        guard let entry else { return String(localized: "Not in this file") }
        let changed = entry.times.lastModification.formatted(date: .abbreviated, time: .shortened)
        let value: String
        if let attachment = MergeConflict.attachmentName(ofField: field) {
            value =
                entry.attachments[attachment].map {
                    $0.count.formatted(.byteCount(style: .file))
                } ?? String(localized: "Removed")
        } else {
            switch entry.fields[field] {
            case nil: value = String(localized: "Removed")
            case .some(let field) where field.isEmpty: value = String(localized: "Empty")
            case .some(.protected): value = String(localized: "Hidden")
            case .some(.plain(let text)): value = text
            }
        }
        return String(localized: "\(value) · changed \(changed)")
    }
}
