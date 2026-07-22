import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var relayService: RelayService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("connectionMode") private var connectionMode: ConnectionMode = .auto

    @State private var showForgetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                pairedMacSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .alert("Forget Mac?", isPresented: $showForgetConfirmation) {
                Button("Forget", role: .destructive) {
                    relayService.unpair()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will need to re-pair with a new code from Claude Code.")
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            Picker("Connection Mode", selection: $connectionMode) {
                Text("Auto").tag(ConnectionMode.auto)
                Text("LAN Only").tag(ConnectionMode.lanOnly)
            }
            .foregroundStyle(Palette.textPrimary)
        } header: {
            Text("Connection")
                .foregroundStyle(Palette.textDim)
        } footer: {
            Text("Auto discovers the bridge via Bonjour on your local network. Remote servers are reached by URL.")
                .foregroundStyle(Palette.textDim)
        }
        .listRowBackground(Palette.surface)
    }

    private var pairedMacSection: some View {
        Section {
            if relayService.isPaired {
                HStack(spacing: 10) {
                    BlockCursor(mode: relayService.connectionState == .connected ? .idle : .offline,
                                width: 6, height: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(relayService.machineName ?? "Unknown Mac")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                        if let lastConnected = relayService.lastConnected {
                            Text("Last connected \(lastConnected, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer()
                }

                Button("Forget This Mac", role: .destructive) {
                    showForgetConfirmation = true
                }
                .foregroundStyle(Palette.danger)
            } else {
                Text("No Mac paired")
                    .foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text("Paired Mac")
                .foregroundStyle(Palette.textDim)
        }
        .listRowBackground(Palette.surface)
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
            }

            Link(destination: URL(string: "https://github.com/anthropics/claude-code")!) {
                HStack {
                    Text("Claude Code")
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        } header: {
            Text("About")
                .foregroundStyle(Palette.textDim)
        }
        .listRowBackground(Palette.surface)
    }
}

// MARK: - Connection Mode

enum ConnectionMode: String {
    case auto
    case lanOnly
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(RelayService.shared)
}
