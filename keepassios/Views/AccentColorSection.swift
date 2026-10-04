import KPAppState
import KPPlatform
import SwiftUI

/// Settings > Appearance: the accent color, from presets or any color.
struct AccentColorSection: View {
    @Environment(AppModel.self) private var model

    private var selected: String? { model.settings.accentColor }

    var body: some View {
        Section("Appearance") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(AccentColors.presets) { preset in
                    swatch(preset)
                }
            }
            .padding(.vertical, 4)
            ColorPicker(
                "Custom Color",
                selection: Binding(
                    get: { AccentColors.color(selected) },
                    set: { set(AccentColors.hex($0)) }
                ),
                supportsOpacity: false
            )
        }
    }

    private func swatch(_ preset: AccentColors.Preset) -> some View {
        let isSelected = preset.hex?.uppercased() == selected?.uppercased()
        return Button {
            set(preset.hex)
        } label: {
            Circle()
                .fill(AccentColors.color(preset.hex))
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? AccentColors.color(preset.hex) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(preset.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func set(_ hex: String?) {
        var settings = model.settings
        settings.accentColor = hex
        Task { await model.updateSettings(settings) }
    }
}
