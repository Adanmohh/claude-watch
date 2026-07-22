import SwiftUI
import UIKit

struct ConnectionStatusView: View {

    @EnvironmentObject private var relayService: RelayService
    @EnvironmentObject private var sessionManager: WatchSessionManager

    @State private var showSettings = false
    @State private var activeSessionIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    if relayService.sessions.isEmpty {
                        waitingView
                    } else {
                        sessionPager
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(relayService)
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("ClaudeWatch")
                .font(.ledgerTitle(20))
                .tracking(-0.5)
                .foregroundStyle(Palette.textPrimary)

            Spacer()

            connectionBadge
        }
    }

    private var connectionBadge: some View {
        let (label, color): (String, Color) = {
            switch relayService.connectionState {
            case .connected:        return ("CONNECTED", Palette.success)
            case .connecting:       return ("CONNECTING", Palette.accent)
            case .disconnected:     return ("OFFLINE", Palette.danger)
            case .iPhoneUnreachable:return ("UNREACHABLE", Palette.accent)
            }
        }()
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
                .tracking(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.surface)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection \(label.lowercased())")
    }

    // MARK: - Waiting (empty) state — a dim ledger, never blank.

    private var waitingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            LedgerWaitingRow(text: "waiting for session")
            Text("Connected to \(relayService.machineName ?? "Mac"). Start Claude or Codex.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.textDim.opacity(0.7))
                .padding(.leading, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Session pager

    private var sessionPager: some View {
        TabView(selection: $activeSessionIndex) {
            ForEach(Array(relayService.sessions.enumerated()), id: \.element.id) { index, _ in
                SessionPageView(sessionIndex: index)
                    .environmentObject(relayService)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: relayService.sessions.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }
}

// MARK: - Session Page

private struct SessionPageView: View {
    let sessionIndex: Int
    @EnvironmentObject private var relayService: RelayService

    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    private var session: AgentSession {
        guard relayService.sessions.indices.contains(sessionIndex) else {
            return AgentSession(id: "", agent: .claude, cwd: "", folderName: "", activity: .idle)
        }
        return relayService.sessions[sessionIndex]
    }

    private var cursorMode: BlockCursor.Mode {
        if session.pendingApproval != nil { return .pending }
        let connected = relayService.connectionState == .connected
        return BlockCursor.Mode(activity: session.activity, connected: connected)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if let approval = session.pendingApproval {
                PermissionCard(approval: approval) { label, index in
                    relayService.respondToApprovalWithOption(label, index: index)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            ledger

            promptRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.pendingApproval != nil)
    }

    // MARK: - Status header (with breathing cursor)

    private var statusHeader: some View {
        HStack(spacing: 10) {
            BlockCursor(mode: cursorMode, width: 10, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.folderName.isEmpty ? session.agent.rawValue.capitalized : session.folderName)
                    .font(.ledgerTitle(17))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                if !session.cwd.isEmpty {
                    Text(session.cwd)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button {
                relayService.clearTerminal(sessionId: session.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textDim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear feed")
        }
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }

    // MARK: - Ledger feed

    private var ledger: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if visibleLines.isEmpty {
                        LedgerWaitingRow(text: "waiting for output")
                            .padding(.top, 4)
                    }

                    ForEach(visibleLines) { line in
                        LedgerRow(line: line)
                            .id(line.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if relayService.isThinking {
                        HStack(spacing: 8) {
                            BlockCursor(mode: .working, width: 6, height: 14)
                            Text("working")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Palette.textDim)
                        }
                        .padding(.leading, 4)
                        .id("thinking-cursor")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.15), value: session.terminalLines.count)
            }
            .onChange(of: session.terminalLines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    if relayService.isThinking {
                        proxy.scrollTo("thinking-cursor", anchor: .bottom)
                    } else if let last = visibleLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Prompt row

    private var promptRow: some View {
        HStack(spacing: 8) {
            Text("\u{276F}") // ❯
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(Palette.accent)

            TextField("Send a command…", text: $promptText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.accent)
                .autocorrectionDisabled()
                .focused($isPromptFocused)
                .onSubmit(sendPrompt)

            Button(action: sendPrompt) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSend ? Palette.accent : Palette.textDim)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send command")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isPromptFocused ? Palette.accent : Palette.border,
                        lineWidth: isPromptFocused ? 1.5 : 1)
        )
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        relayService.sendCommand(text: text, sessionId: session.id)
        promptText = ""
        isPromptFocused = false
    }

    private var visibleLines: [TerminalLine] {
        session.terminalLines
            .filter { !$0.text.isEmpty && $0.type != .thinking }
            .suffix(60)
            .map { $0 }
    }
}

// MARK: - Permission card (interrupts the ledger)

private struct PermissionCard: View {
    let approval: ApprovalRequest
    let respond: (_ label: String, _ index: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BlockCursor(mode: .pending, width: 8, height: 16)
                Text(approval.question != nil ? "QUESTION" : "PERMISSION")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .tracking(1)
                Spacer()
            }

            if let question = approval.question {
                Text(question)
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !approval.actionSummary.isEmpty && approval.actionSummary != approval.toolName {
                Text(approval.actionSummary)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Array(approval.options.enumerated()), id: \.element.id) { index, option in
                    optionButton(option, index: index)
                }
            }
        }
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.accent.opacity(0.5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func optionButton(_ option: ApprovalRequest.OptionItem, index: Int) -> some View {
        let role = role(for: index)
        Button {
            let generator = UIImpactFeedbackGenerator(style: role == .allow ? .medium : .heavy)
            generator.impactOccurred()
            respond(option.label, index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(role.textColor)
                if let desc = option.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(.caption))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(role.fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(role.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
    }

    private enum Role {
        case allow, deny, neutral
        var fill: Color {
            switch self {
            case .allow:   return Palette.accent
            case .deny, .neutral: return Palette.bg
            }
        }
        var stroke: Color {
            switch self {
            case .allow:   return .clear
            case .deny:    return Palette.danger.opacity(0.6)
            case .neutral: return Palette.border
            }
        }
        var textColor: Color {
            switch self {
            case .allow:   return .black
            case .deny:    return Palette.danger
            case .neutral: return Palette.textPrimary
            }
        }
    }

    private func role(for index: Int) -> Role {
        if approval.question != nil { return index == 0 ? .allow : .neutral }
        if approval.options.count <= 1 { return .allow }
        if index == 0 { return .allow }
        if index == approval.options.count - 1 { return .deny }
        return .neutral
    }
}

#Preview {
    ConnectionStatusView()
        .environmentObject(WatchSessionManager.shared)
        .environmentObject(RelayService.shared)
}
