import SwiftUI

struct MultiSessionPager: View {
    @EnvironmentObject private var state: WatchViewState
    @State private var showNewSession = false

    var body: some View {
        if state.sessions.isEmpty {
            waitingView
        } else {
            TabView(selection: $state.activeSessionIndex) {
                ForEach(Array(state.sessions.enumerated()), id: \.element.id) { index, _ in
                    SessionView(sessionIndex: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
        }
    }

    // Empty state — a dim ledger, never a blank screen.
    private var waitingView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                BlockCursor(mode: state.sessionState.connection == .connected ? .idle : .offline,
                            width: 8, height: 15)
                Text(state.sessionState.connection == .connected ? "Connected" : "Offline")
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 0.5) }

            VStack(alignment: .leading, spacing: 8) {
                LedgerWaitingRow(text: "waiting for session", compact: true)
                Text("Start on your Mac, or spawn one here")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.textDim.opacity(0.7))
                    .padding(.leading, 17)

                Button { showNewSession = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Session")
                            .font(.system(.footnote, design: .default).weight(.semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.watchBg.ignoresSafeArea())
        .sheet(isPresented: $showNewSession) {
            NewSessionView()
        }
    }
}

#Preview("Waiting") {
    MultiSessionPager()
        .environmentObject(WatchViewState.shared)
}
