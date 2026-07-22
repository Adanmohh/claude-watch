import SwiftUI

extension Color {

    /// Creates a `Color` from a hex string.
    ///
    /// Supported formats: `"#RRGGBB"`, `"RRGGBB"`, `"#RRGGBBAA"`, `"RRGGBBAA"`.
    /// Returns `Color.clear` for malformed input.
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)

        let r, g, b, a: Double
        switch sanitized.count {
        case 6: // RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255.0
            g = Double((rgb >> 8) & 0xFF) / 255.0
            b = Double(rgb & 0xFF) / 255.0
            a = 1.0
        case 8: // RRGGBBAA
            r = Double((rgb >> 24) & 0xFF) / 255.0
            g = Double((rgb >> 16) & 0xFF) / 255.0
            b = Double((rgb >> 8) & 0xFF) / 255.0
            a = Double(rgb & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0; a = 0
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // MARK: - Brand colors (Phosphor Ledger)
    //
    // These legacy names are kept as aliases onto the centralized `Palette`
    // (named colors in Assets.xcassets) so older references stay on-brand.
    // New code should reference `Palette` directly.

    static let claudeOrange = Palette.accent
    static let claudeAmber = Palette.accent
    static let subtleText = Palette.textSecondary
    static let cardBackground = Palette.surface
    static let fieldBorder = Palette.border
    static let statusGreen = Palette.success
    static let connectedPillBackground = Palette.surface
}
