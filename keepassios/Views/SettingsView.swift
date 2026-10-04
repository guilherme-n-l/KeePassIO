import KPAppState
import KPObservability
import SwiftUI

struct SettingsView: View {
    private static let sponsorsURL = URL(string: "https://github.com/sponsors/guilherme-n-l")

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AutoFillSettingsSection()
                AccentColorSection()
                Section {
                    Picker("Auto-Lock", selection: setting(\.autoLockSeconds)) {
                        Text("Immediately").tag(0)
                        Text("After 1 Minute").tag(60)
                        Text("After 2 Minutes").tag(120)
                        Text("After 5 Minutes").tag(300)
                        Text("After 15 Minutes").tag(900)
                    }
                    Picker("Clear Clipboard", selection: setting(\.clipboardClearSeconds)) {
                        Text("After 30 Seconds").tag(30)
                        Text("After 1 Minute").tag(60)
                        Text("After 2 Minutes").tag(120)
                        Text("Never").tag(0)
                    }
                } header: {
                    Text("Security")
                }
                Section {
                    Toggle("Allow Network Access", isOn: setting(\.networkAllowed))
                        .accessibilityIdentifier("settings.network")
                    Toggle("Download Website Icons", isOn: setting(\.faviconDownloadEnabled))
                        .disabled(!model.settings.networkAllowed)
                    Toggle("Check for Breached Passwords", isOn: setting(\.breachCheckEnabled))
                        .disabled(!model.settings.networkAllowed)
                } header: {
                    Text("Network")
                } footer: {
                    Text(
                        "Off by default. With network access off, the app never connects to the internet. Breach checks send only the first five characters of a password's SHA-1 hash."
                    )
                }
                Section {
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                    if let sponsorsURL = Self.sponsorsURL {
                        Link("Support Development", destination: sponsorsURL)
                    }
                    LabeledContent("Version", value: Bundle.main.appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("KeePassIOS is free and open source. There is no paid version.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.settings
                settings[keyPath: keyPath] = newValue
                Task { await model.updateSettings(settings) }
            }
        )
    }
}

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
