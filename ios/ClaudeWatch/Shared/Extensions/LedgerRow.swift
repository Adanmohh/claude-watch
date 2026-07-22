import SwiftUI

/// A single row in the ledger feed:
/// `[glyph gutter][monospaced event text][dim metadata]`.
///
/// The gutter holds a small block glyph tinted by the event kind. Text is
/// always monospaced and scales with Dynamic Type. On compact (watchOS)
/// layouts the trailing timestamp metadata is hidden to save width.
struct LedgerRow: View {
    let line: TerminalLine
    var compact: Bool = false

    private var kind: EventKind { EventKind.classify(line) }

    private var gutterWidth: CGFloat { compact ? 12 : 20 }
    private var blockSize: CGFloat { 6 }

    private var monoFont: Font {
        .system(compact ? .caption2 : .footnote, design: .monospaced)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 8) {
            // Gutter glyph — 6pt block tinted by event type.
            ZStack(alignment: .top) {
                Color.clear.frame(width: gutterWidth, height: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(kind.glyphColor)
                    .frame(width: blockSize, height: blockSize)
                    .padding(.top, 2)
            }
            .frame(width: gutterWidth, alignment: .center)

            Text(line.text)
                .font(monoFont)
                .foregroundStyle(kind.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !compact {
                Text(Self.timeString(line.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.voiceOverPrefix), \(line.text)")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func timeString(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

/// The dim placeholder row shown when there is no session/activity yet —
/// the ledger is never a blank screen.
struct LedgerWaitingRow: View {
    var text: String = "waiting for session"
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            BlockCursor(mode: .idle,
                        width: compact ? 5 : 6,
                        height: compact ? 12 : 16)
                .opacity(0.5)
            Text(text)
                .font(.system(compact ? .caption2 : .footnote, design: .monospaced))
                .foregroundStyle(Palette.textDim)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
