import SwiftUI

// MARK: - Phosphor Ledger palette
//
// Single source of truth for color. All values live as named color sets in
// Assets.xcassets (present in both the iOS and watchOS asset catalogs), so no
// raw hex is used in views. Accessors below resolve those named colors.

enum Palette {
    static let bg          = Color("BgBase")      // #0C0D0F
    static let surface     = Color("Surface")     // #16181C
    static let textPrimary = Color("TextPrimary") // #E8E6E1
    static let border      = Color("Border")      // #2A2D33
    static let accent      = Color("Accent")      // #FFB454 phosphor amber
    static let success     = Color("Success")     // #7FD962
    static let danger      = Color("Danger")      // #F26D78

    /// Dimmed metadata / secondary text. Derived from the primary text color.
    static let textDim = Color("TextPrimary").opacity(0.45)
    /// Slightly brighter secondary text for labels.
    static let textSecondary = Color("TextPrimary").opacity(0.62)

    /// watchOS uses pure black backgrounds (OLED + HIG).
    static let watchBg = Color.black
}

// MARK: - Ledger event classification
//
// Maps a TerminalLine to a semantic event kind that drives the gutter glyph
// tint, the row's text color, and the VoiceOver description. Prefixes are the
// terse formats produced by the relay/view-state layers (e.g. "$ cmd",
// "Read file.swift", "  + added", "> user prompt").

enum EventKind {
    case read, edit, bash, search, output, addition, deletion, user, system, error, thinking

    var glyphColor: Color {
        switch self {
        case .read, .search: return Palette.textDim
        case .edit:          return Palette.accent
        case .bash:          return Palette.success
        case .addition:      return Palette.success
        case .deletion:      return Palette.danger
        case .error:         return Palette.danger
        case .user:          return Palette.accent
        case .thinking:      return Palette.accent
        case .output:        return Palette.textDim
        case .system:        return Palette.border
        }
    }

    var textColor: Color {
        switch self {
        case .addition:      return Palette.success
        case .deletion:      return Palette.danger
        case .error:         return Palette.danger
        case .read, .search, .system: return Palette.textSecondary
        case .thinking:      return Palette.accent
        default:             return Palette.textPrimary
        }
    }

    /// Spoken prefix for VoiceOver, e.g. "edit, server.js".
    var voiceOverPrefix: String {
        switch self {
        case .read:     return "read"
        case .edit:     return "edit"
        case .bash:     return "ran command"
        case .search:   return "search"
        case .addition: return "added"
        case .deletion: return "removed"
        case .output:   return "output"
        case .user:     return "you said"
        case .system:   return "status"
        case .error:    return "error"
        case .thinking: return "working"
        }
    }

    static func classify(_ line: TerminalLine) -> EventKind {
        // Strip a leading agent tag such as "[codex] ".
        var text = line.text
        if text.hasPrefix("[codex] ") { text.removeFirst("[codex] ".count) }
        let t = text.trimmingCharacters(in: .whitespaces)

        switch line.type {
        case .error:    return .error
        case .thinking: return .thinking
        case .command:
            if t.hasPrefix("$") { return .bash }
            if t.hasPrefix(">") { return .user }
            if t.hasPrefix("→") { return .user }
            if t.hasPrefix("grep") || t.hasPrefix("find") { return .search }
            return .bash
        case .system:
            if t.hasPrefix("Read") { return .read }
            if t.hasPrefix("Edit") || t.hasPrefix("Write") { return .edit }
            return .system
        case .output:
            if text.hasPrefix("  + ") { return .addition }
            if text.hasPrefix("  - ") { return .deletion }
            return .output
        }
    }
}

// MARK: - Typography

extension Font {
    /// Screen titles: SF Pro Display semibold (system Display optical size is
    /// applied automatically at larger sizes). Pair with `.tracking(-0.5)`.
    static func ledgerTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}
