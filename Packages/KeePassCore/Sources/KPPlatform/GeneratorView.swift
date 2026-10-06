#if os(iOS)
    import KPAppState
    import KPGenerator
    import SwiftUI

    extension GeneratorSettings {
        public var passwordOptions: PasswordGenerator.Options {
            var sets: PasswordGenerator.CharacterSets = []
            if includeUppercase { sets.insert(.uppercase) }
            if includeLowercase { sets.insert(.lowercase) }
            if includeDigits { sets.insert(.digits) }
            if includeSymbols { sets.insert(.symbols) }
            if includeExtendedASCII { sets.insert(.extendedASCII) }
            return PasswordGenerator.Options(
                length: length,
                sets: sets,
                excludeLookalikes: excludeLookalikes,
                pickFromEveryGroup: pickFromEveryGroup,
                alsoInclude: alsoInclude,
                exclude: excludeCharacters
            )
        }

        /// A new password or passphrase with these settings; empty when the
        /// settings leave nothing to choose from.
        public func generate() -> String {
            switch mode {
            case .password:
                return (try? PasswordGenerator().password(passwordOptions)) ?? ""
            case .passphrase:
                let wordCase = PassphraseGenerator.WordCase(rawValue: wordCase.rawValue) ?? .lower
                return
                    (try? PassphraseGenerator.english().passphrase(
                        wordCount: wordCount,
                        separator: wordSeparator,
                        wordCase: wordCase
                    )) ?? ""
            }
        }

        public var entropyBits: Double {
            switch mode {
            case .password: passwordOptions.entropyBits
            case .passphrase: (try? PassphraseGenerator.english().entropyBits(wordCount: wordCount)) ?? 0
            }
        }
    }

    /// The password and passphrase generator, with KeePassXC's options.
    /// Used by the app and the AutoFill extension; each stores the
    /// settings itself through `onSettingsChange`.
    public struct GeneratorView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var settings: GeneratorSettings
        @State private var generated = ""
        private let onSettingsChange: (GeneratorSettings) -> Void
        private let onUse: ((String) -> Void)?

        public init(
            settings: GeneratorSettings,
            onSettingsChange: @escaping (GeneratorSettings) -> Void,
            onUse: ((String) -> Void)? = nil
        ) {
            _settings = State(initialValue: settings)
            self.onSettingsChange = onSettingsChange
            self.onUse = onUse
        }

        public var body: some View {
            Form {
                Section {
                    Text(generated.isEmpty ? " " : generated)
                        .font(.title3.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("generator.value")
                    Button("Regenerate", systemImage: "wand.and.stars", action: regenerate)
                        .accessibilityIdentifier("generator.regenerate")
                } footer: {
                    if generated.isEmpty {
                        Text("Nothing to choose from: turn on a character type.")
                            .foregroundStyle(.red)
                    } else {
                        Text("\(strength) · about \(Int(settings.entropyBits)) bits of entropy")
                    }
                }
                Section {
                    Picker("Type", selection: $settings.mode) {
                        Text("Password").tag(GeneratorSettings.Mode.password)
                        Text("Passphrase").tag(GeneratorSettings.Mode.passphrase)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if settings.mode == .password {
                    passwordOptions
                } else {
                    passphraseOptions
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
                        .disabled(generated.isEmpty)
                        .accessibilityIdentifier("generator.use")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear(perform: regenerate)
            .onChange(of: settings) { _, newValue in
                regenerate()
                onSettingsChange(newValue)
            }
        }

        @ViewBuilder private var passwordOptions: some View {
            Section("Length") {
                // A draggable slider with the value beside it, as in
                // KeePassXC.
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { Double(settings.length) },
                            set: { settings.length = Int($0.rounded()) }
                        ),
                        // No step: on iOS 26 a stepped slider draws a tick for
                        // every step, which at 125 steps reads as a second bar.
                        // The binding rounds to whole characters instead.
                        in: 4...128
                    ) {
                        Text("Length")
                    } minimumValueLabel: {
                        Text("4").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("128").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityValue("\(settings.length) characters")
                    Text("\(settings.length)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            Section("Character Types") {
                Toggle("Upper Case (A–Z)", isOn: $settings.includeUppercase)
                Toggle("Lower Case (a–z)", isOn: $settings.includeLowercase)
                Toggle("Numbers (0–9)", isOn: $settings.includeDigits)
                Toggle("Special Characters (/*+&…)", isOn: $settings.includeSymbols)
                Toggle("Extended ASCII (¡¿©±…)", isOn: $settings.includeExtendedASCII)
            }
            Section {
                Toggle("Exclude Look-Alike Characters", isOn: $settings.excludeLookalikes)
                Toggle("Pick Characters from Every Group", isOn: $settings.pickFromEveryGroup)
                LabeledContent("Also Choose From") {
                    TextField("e.g. @#", text: $settings.alsoInclude)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Do Not Include") {
                    TextField("e.g. {}<>", text: $settings.excludeCharacters)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Options")
            }
        }

        @ViewBuilder private var passphraseOptions: some View {
            Section {
                Stepper("Words: \(settings.wordCount)", value: $settings.wordCount, in: 3...20)
                LabeledContent("Separator") {
                    TextField("Separator", text: $settings.wordSeparator)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("Word Case", selection: $settings.wordCase) {
                    Text("lower case").tag(GeneratorSettings.WordCase.lower)
                    Text("UPPER CASE").tag(GeneratorSettings.WordCase.upper)
                    Text("Title Case").tag(GeneratorSettings.WordCase.title)
                }
            }
        }

        /// KeePassXC's strength wording for the entropy.
        private var strength: String {
            switch settings.entropyBits {
            case ..<40: String(localized: "Poor")
            case ..<65: String(localized: "Weak")
            case ..<100: String(localized: "Good")
            default: String(localized: "Excellent")
            }
        }

        private func regenerate() {
            generated = settings.generate()
        }
    }
#endif
