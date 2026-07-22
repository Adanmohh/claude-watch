import SwiftUI

// MARK: - VoiceInputView

/// Full-screen voice capture. Uses watchOS system dictation (a dictation-enabled
/// TextField) since the Speech framework is unavailable on watchOS. Styled as a
/// ❯-prefixed prompt line consistent with the ledger.
struct VoiceInputView: View {
    var sessionId: String? = nil
    @EnvironmentObject private var session: WatchViewState
    @Environment(\.dismiss) private var dismiss

    @State private var commandText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    BlockCursor(mode: .working, width: 8, height: 15)
                    Text("Command")
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                }

                // Prompt input row.
                HStack(spacing: 6) {
                    Text("\u{276F}") // ❯
                        .font(.system(.footnote, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.accent)

                    TextField("tap mic or type", text: $commandText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .tint(Palette.accent)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onSubmit { sendCommand() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isTextFieldFocused ? Palette.accent : Palette.border,
                                lineWidth: isTextFieldFocused ? 1.5 : 1)
                )

                if !commandText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { sendCommand() } label: {
                        Text("Send")
                            .font(.system(.footnote, design: .default).weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(.caption))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Palette.watchBg.ignoresSafeArea())
        .onAppear { isTextFieldFocused = true }
    }

    private func sendCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        HapticManager.commandSent()
        session.sendVoiceCommand(text, sessionId: sessionId)
        dismiss()
    }
}

#Preview {
    VoiceInputView()
        .environmentObject(WatchViewState.shared)
}
