import SwiftUI

/// The AutoFill section of Settings: whether it's on, a button that asks
/// iOS to turn it on, and the manual steps as a fallback.
struct AutoFillSettingsSection: View {
    @Environment(AutoFillSetup.self) private var setup
    @State private var declined = false

    var body: some View {
        Section {
            LabeledContent("AutoFill") {
                switch setup.status {
                case .on: Text("On")
                case .off: Text("Off")
                case .unknown: ProgressView()
                }
            }
            .accessibilityIdentifier("settings.autoFillStatus")
            if setup.status == .off {
                Button("Turn On AutoFill") {
                    Task { declined = !(await setup.turnOn()) }
                }
                .accessibilityIdentifier("settings.turnOnAutoFill")
                Button("Open AutoFill Settings") {
                    Task { await setup.openSettings() }
                }
            }
        } header: {
            Text("AutoFill")
        } footer: {
            if setup.status == .off {
                Text(
                    "Fill passwords and one-time codes in Safari and other apps. If the prompt doesn't appear, open Settings > General > AutoFill & Passwords and turn on KeePassIO."
                )
                .foregroundStyle(declined ? .orange : .secondary)
            }
        }
    }
}

/// A card at the top of the library offering to turn on AutoFill, until
/// it's on or the user closes the card.
struct AutoFillPromptCard: View {
    @Environment(AutoFillSetup.self) private var setup
    @AppStorage("autoFillPromptDismissed") private var isDismissed = false

    var body: some View {
        if setup.status == .off, !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Use KeePassIO for AutoFill", systemImage: "key.viewfinder")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close")
                }
                Text("Fill passwords and one-time codes in Safari and other apps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Turn On AutoFill") {
                    Task {
                        if !(await setup.turnOn()) {
                            await setup.openSettings()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.turnOnAutoFill")
            }
            .padding(.vertical, 4)
        }
    }
}
