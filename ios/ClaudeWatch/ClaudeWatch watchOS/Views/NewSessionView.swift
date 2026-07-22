import SwiftUI

/// Spawns a new agent session from the watch. Agent picker only — the working
/// directory defaults to `WatchBridgeClient.defaultCwd` to keep watch input
/// minimal. On success the bridge emits a "session" running event over SSE and
/// WatchViewState auto-switches to the new session.
struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isSpawning = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    BlockCursor(mode: isSpawning ? .working : .idle, width: 8, height: 15)
                    Text("New Session")
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                }

                Text("Choose an agent")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.textDim)

                agentButton(.claude, label: "Claude")
                agentButton(.codex, label: "Codex")

                Text(WatchBridgeClient.defaultCwd)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.textDim.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let error {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Palette.watchBg.ignoresSafeArea())
    }

    @ViewBuilder
    private func agentButton(_ agent: AgentType, label: String) -> some View {
        Button { spawn(agent) } label: {
            HStack(spacing: 8) {
                AgentIcon(agent: agent, size: 18)
                Text(label)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSpawning)
        .opacity(isSpawning ? 0.5 : 1)
        .accessibilityLabel("Start \(label) session")
    }

    private func spawn(_ agent: AgentType) {
        guard !isSpawning else { return }
        isSpawning = true
        error = nil
        Task {
            do {
                _ = try await WatchBridgeClient.shared.spawnSession(agent: agent.rawValue)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSpawning = false
                    self.error = "Couldn't start: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NewSessionView()
}
