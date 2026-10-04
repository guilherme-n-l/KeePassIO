import KPAppState
import KPModel
import KPOTP
import KPSession
import SwiftUI

/// Shows an entry's fields with copy buttons, its one-time code and its
/// history.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let session: DatabaseSession
    let databaseID: UUID
    let entryID: UUID
    @State private var isEditing = false
    @State private var revealedFields: Set<String> = []
    @State private var copiedField: String?

    private var entry: Entry? { session.database?.entry(withID: entryID) }

    var body: some View {
        if let entry {
            List {
                Section {
                    field(Entry.StandardField.userName, label: "User Name", value: entry.userName, sensitive: false)
                    passwordRow(entry)
                    if !entry.url.isEmpty {
                        field(Entry.StandardField.url, label: "Website", value: entry.url, sensitive: false)
                    }
                    if let otp = try? OTP(fields: entry.fields.mapValues { $0.reveal() }) {
                        OTPRow(otp: otp) { code in
                            copy(code, field: "otp", sensitive: true)
                        }
                    }
                }
                let customFields = Self.displayedCustomFields(of: entry)
                if !customFields.isEmpty {
                    Section("Fields") {
                        ForEach(customFields, id: \.self) { name in
                            let value = entry.fields[name] ?? .plain("")
                            if value.isProtected {
                                protectedRow(name: name, value: value.reveal())
                            } else {
                                field(name, label: LocalizedStringKey(name), value: value.reveal(), sensitive: false)
                            }
                        }
                    }
                }
                if !entry.notes.isEmpty {
                    Section("Notes") {
                        Text(entry.notes)
                            .textSelection(.enabled)
                    }
                }
                if !entry.attachments.isEmpty {
                    Section("Attachments") {
                        ForEach(entry.attachments.keys.sorted(), id: \.self) { name in
                            LabeledContent(name) {
                                Text(Int64(entry.attachments[name]?.count ?? 0), format: .byteCount(style: .file))
                            }
                        }
                    }
                }
                if !entry.tags.isEmpty {
                    Section("Tags") {
                        Text(entry.tags.joined(separator: ", "))
                    }
                }
                Section {
                    LabeledContent("Modified") {
                        Text(entry.times.lastModification, format: .dateTime)
                    }
                    if let expiry = entry.times.expiry {
                        LabeledContent("Expires") {
                            Text(expiry, format: .dateTime)
                        }
                    }
                    if !entry.history.isEmpty {
                        NavigationLink(
                            "History (\(entry.history.count))",
                            value: DatabaseRoute.history(database: databaseID, entry: entry.id)
                        )
                    }
                }
            }
            .navigationTitle(entry.title)
            .toolbar {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("entry.edit")
            }
            .sheet(isPresented: $isEditing) {
                NavigationStack {
                    EntryEditorView(session: session, entry: entry, isNew: false, groupID: nil)
                }
            }
            .overlay(alignment: .bottom) {
                if copiedField != nil {
                    Text("Copied")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("entry.copied")
                }
            }
        } else {
            ContentUnavailableView("Entry Not Found", systemImage: "questionmark.key.filled")
        }
    }

    /// Custom fields shown in the Fields section; OTP settings are shown
    /// as a code instead.
    static func displayedCustomFields(of entry: Entry) -> [String] {
        entry.customFieldNames.filter { $0 != "otp" && !$0.hasPrefix("TOTP ") }
    }

    private func field(_ key: String, label: LocalizedStringKey, value: String, sensitive: Bool) -> some View {
        Button {
            copy(value, field: key, sensitive: sensitive)
        } label: {
            LabeledContent(label) {
                Text(value)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { copy(value, field: key, sensitive: sensitive) }
            if key == Entry.StandardField.url, let url = URL(string: value) {
                Button("Open", systemImage: "safari") { openURL(url) }
            }
        }
        .accessibilityIdentifier("field.\(key)")
    }

    private func passwordRow(_ entry: Entry) -> some View {
        protectedRow(name: Entry.StandardField.password, label: "Password", value: entry.password.reveal())
    }

    private func protectedRow(name: String, label: LocalizedStringKey? = nil, value: String) -> some View {
        HStack {
            Button {
                copy(value, field: name, sensitive: true)
            } label: {
                LabeledContent(label ?? LocalizedStringKey(name)) {
                    Text(
                        revealedFields.contains(name)
                            ? value : String(repeating: "•", count: min(max(value.count, 8), 16))
                    )
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("field.\(name).value")
                }
            }
            .accessibilityIdentifier("field.\(name)")
            Button {
                if revealedFields.contains(name) {
                    revealedFields.remove(name)
                } else {
                    revealedFields.insert(name)
                }
            } label: {
                Image(systemName: revealedFields.contains(name) ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealedFields.contains(name) ? "Hide" : "Show")
            .accessibilityIdentifier("field.\(name).reveal")
        }
    }

    private func copy(_ value: String, field: String, sensitive: Bool) {
        Clipboard.copy(value, sensitive: sensitive, clearAfter: model.settings.clipboardClearSeconds)
        withAnimation { copiedField = field }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { if copiedField == field { copiedField = nil } }
        }
    }
}

/// The current one-time code, refreshed every second.
private struct OTPRow: View {
    let otp: OTP
    let onCopy: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = otp.code(at: context.date)
            Button {
                onCopy(code)
            } label: {
                LabeledContent("One-Time Code") {
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.body.monospaced())
                            .foregroundStyle(.primary)
                        Gauge(value: Double(otp.secondsRemaining(at: context.date)), in: 0...Double(otp.period)) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.5)
                        .frame(width: 24, height: 24)
                    }
                }
            }
            .accessibilityIdentifier("field.otp")
        }
    }
}

/// Earlier versions of an entry.
struct EntryHistoryView: View {
    let session: DatabaseSession
    let entryID: UUID

    private var versions: [Entry] {
        session.database?.entry(withID: entryID).map { Array($0.history.reversed()) } ?? []
    }

    var body: some View {
        List(versions, id: \.times.lastModification) { version in
            VStack(alignment: .leading) {
                Text(version.title)
                Text(version.times.lastModification, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
    }
}
