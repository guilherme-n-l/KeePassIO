import KPAppState
import KPGenerator
import SwiftUI

/// Password and passphrase generator. Remembers the last settings.
struct GeneratorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = GeneratorSettings()
    @State private var generated = ""
    @State private var loaded = false
    var onUse: ((String) -> Void)?

    var body: some View {
        Form {
            Section {
                Text(generated)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("generator.value")
                Button("Regenerate", systemImage: "arrow.clockwise", action: regenerate)
                    .accessibilityIdentifier("generator.regenerate")
            } footer: {
                Text("About \(Int(entropy)) bits of entropy")
            }
            Section {
                Picker("Type", selection: $settings.mode) {
                    Text("Password").tag(GeneratorSettings.Mode.password)
                    Text("Passphrase").tag(GeneratorSettings.Mode.passphrase)
                }
                .pickerStyle(.segmented)
                if settings.mode == .password {
                    Stepper("Length: \(settings.length)", value: $settings.length, in: 8...128)
                    Toggle("Lowercase (a–z)", isOn: $settings.includeLowercase)
                    Toggle("Uppercase (A–Z)", isOn: $settings.includeUppercase)
                    Toggle("Digits (0–9)", isOn: $settings.includeDigits)
                    Toggle("Symbols (!@#…)", isOn: $settings.includeSymbols)
                    Toggle("Avoid Look-Alikes (l, 1, O, 0)", isOn: $settings.excludeLookalikes)
                } else {
                    Stepper("Words: \(settings.wordCount)", value: $settings.wordCount, in: 3...12)
                    TextField("Separator", text: $settings.wordSeparator)
                    Toggle("Capitalize Words", isOn: $settings.capitalizeWords)
                }
            }
        }
        .navigationTitle("Generator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onUse {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(generated)
                        dismiss()
                    }
                    .accessibilityIdentifier("generator.use")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if !loaded {
                settings = model.settings.generator
                loaded = true
            }
            regenerate()
        }
        .onChange(of: settings) { _, newValue in
            regenerate()
            var updated = model.settings
            updated.generator = newValue
            Task { await model.updateSettings(updated) }
        }
    }

    private var sets: PasswordGenerator.CharacterSets {
        var sets: PasswordGenerator.CharacterSets = []
        if settings.includeLowercase { sets.insert(.lowercase) }
        if settings.includeUppercase { sets.insert(.uppercase) }
        if settings.includeDigits { sets.insert(.digits) }
        if settings.includeSymbols { sets.insert(.symbols) }
        return sets
    }

    private var entropy: Double {
        switch settings.mode {
        case .password:
            PasswordGenerator.entropyBits(
                length: settings.length,
                sets: sets,
                excludingLookalikes: settings.excludeLookalikes
            )
        case .passphrase:
            (try? PassphraseGenerator.english().entropyBits(wordCount: settings.wordCount)) ?? 0
        }
    }

    private func regenerate() {
        switch settings.mode {
        case .password:
            generated =
                (try? PasswordGenerator().password(
                    length: settings.length,
                    sets: sets.isEmpty ? .all : sets,
                    excludingLookalikes: settings.excludeLookalikes
                )) ?? ""
        case .passphrase:
            generated =
                (try? PassphraseGenerator.english().passphrase(
                    wordCount: settings.wordCount,
                    separator: settings.wordSeparator,
                    capitalize: settings.capitalizeWords
                )) ?? ""
        }
    }
}
