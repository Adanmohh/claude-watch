import SwiftUI

struct SessionView: View {
    let sessionIndex: Int
    @EnvironmentObject private var session: WatchViewState

    @State private var showVoiceInput = false

    private var agentSession: AgentSession {
        guard session.sessions.indices.contains(sessionIndex) else {
            return AgentSession(id: "", agent: .claude, cwd: "", folderName: "", activity: .idle)
        }
        return session.sessions[sessionIndex]
    }

    private var connected: Bool {
        session.sessionState.connection == .connected
    }

    private var cursorMode: BlockCursor.Mode {
        if agentSession.pendingApproval != nil { return .pending }
        return BlockCursor.Mode(activity: agentSession.activity, connected: connected)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            ledger
            promptRow
        }
        .background(Palette.watchBg.ignoresSafeArea())
        .sheet(item: $session.pendingApproval) { request in
            ApprovalView(request: request)
        }
        .fullScreenCover(isPresented: $showVoiceInput) {
            VoiceInputView(sessionId: agentSession.id)
        }
    }

    // MARK: - Status header

    private var statusHeader: some View {
        HStack(spacing: 6) {
            BlockCursor(mode: cursorMode, width: 8, height: 15)

            Text(title)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                session.clearTerminal(sessionId: agentSession.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear feed")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    private var title: String {
        agentSession.folderName.isEmpty
            ? agentSession.agent.rawValue.capitalized
            : agentSession.folderName
    }

    // MARK: - Ledger feed

    private var ledger: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if visibleLines.isEmpty {
                        LedgerWaitingRow(
                            text: connected ? "waiting for output" : "disconnected",
                            compact: true
                        )
                        .padding(.top, 6)
                    }

                    ForEach(visibleLines) { line in
                        LedgerRow(line: line, compact: true)
                            .id(line.id)
                            .transition(.opacity)
                    }

                    if isThinking {
                        HStack(spacing: 5) {
                            BlockCursor(mode: .working, width: 6, height: 12)
                            Text("working")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Palette.textDim)
                        }
                        .padding(.leading, 2)
                        .id("cursor")
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: agentSession.terminalLines.count)
            }
            .onChange(of: agentSession.terminalLines.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    if isThinking {
                        proxy.scrollTo("cursor", anchor: .bottom)
                    } else if let last = visibleLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Prompt row (dictation entry)

    private var promptRow: some View {
        Button { showVoiceInput = true } label: {
            HStack(spacing: 6) {
                Text("\u{276F}") // ❯
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.accent)
                Text("Speak a command")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Palette.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.border).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speak a command")
    }

    // MARK: - Data

    private var visibleLines: [TerminalLine] {
        agentSession.terminalLines
            .filter { !$0.text.isEmpty && $0.type != .thinking }
            .suffix(40)
            .map { $0 }
    }

    private var isThinking: Bool {
        agentSession.terminalLines.last?.type == .thinking
    }
}

#Preview {
    let state = WatchViewState.shared
    return SessionView(sessionIndex: 0)
        .environmentObject(state)
}
