#if os(iOS)
    import SwiftUI
    import UIKit

    /// The accent colors the user can pick, stored in Settings as "#RRGGBB".
    public enum AccentColors {
        public struct Preset: Identifiable, Sendable {
            public let name: LocalizedStringResource
            /// nil is the default (the icon's green).
            public let hex: String?
            public var id: String { hex ?? "default" }
        }

        public static let presets: [Preset] = [
            Preset(name: "Green", hex: nil),
            Preset(name: "Blue", hex: "#007AFF"),
            Preset(name: "Teal", hex: "#30B0C7"),
            Preset(name: "Indigo", hex: "#5856D6"),
            Preset(name: "Purple", hex: "#AF52DE"),
            Preset(name: "Pink", hex: "#FF2D55"),
            Preset(name: "Red", hex: "#FF3B30"),
            Preset(name: "Orange", hex: "#FF9500"),
            Preset(name: "Yellow", hex: "#FFCC00"),
            Preset(name: "Graphite", hex: "#8E8E93"),
        ]

        /// The app icon's green, the default accent (also the AccentColor
        /// asset, used before settings load).
        public static let defaultHex = "#4FA34F"

        /// The color for a stored value; nil (or anything unreadable) is the
        /// default green. Not `Color.accentColor`: that follows the current
        /// tint, so the default swatch would show whichever color is chosen.
        public static func color(_ hex: String?) -> Color {
            guard
                let value = UInt32(
                    (hex ?? defaultHex).trimmingCharacters(in: CharacterSet(charactersIn: "#")),
                    radix: 16
                )
            else { return color(defaultHex) }
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }

        /// "#RRGGBB" for a color picked in a color picker.
        public static func hex(_ color: Color) -> String {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
            func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }
    }
#endif
