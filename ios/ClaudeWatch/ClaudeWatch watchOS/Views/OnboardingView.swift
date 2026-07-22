import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: WatchViewState
    @StateObject private var bridge = WatchBridgeClient.shared

    @State private var code = ""
    @State private var serverAddress = ""
    @State private var isSearching = false
    @State private var isConnecting = false
    @State private var error: String?
    @State private var bridgeURL: URL?
    @State private var manualEntry = false
    @FocusState private var codeFocused: Bool
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Compact header — one line
            HStack(spacing: 4) {
                AppLogo(size: 22)
                Text("Agent Watch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.Text.primary)
            }

            if isSearching {
                Spacer()
                ProgressView()
                    .tint(Theme.Text.secondary)
                Text("Connecting...")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)
                Spacer()

            } else if bridgeURL != nil && !manualEntry {
                // Bridge found (LAN or remote) — code entry
                Text("Enter code from Mac")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)

                TextField("000000", text: $code)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .onChange(of: code) { _, newValue in
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                        if filtered != newValue { code = filtered }
                        if filtered.count == 6 { submitCode(filtered) }
                    }

                if isConnecting {
                    ProgressView()
                        .tint(Theme.Text.primary)
                        .scaleEffect(0.7)
                }

                Button("Use a different server") {
                    bridgeURL = nil
                    manualEntry = true
                    code = ""
                    addressFocused = true
                }
                .font(.system(size: 10))
                .foregroundColor(Theme.Text.secondary)

            } else {
                // Manual entry — LAN IP or full remote URL (first-class)
                Text("Enter server address")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)

                Text("LAN IP or https://host:port")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.Text.dimmed)

                TextField("IP or https://host:port", text: $serverAddress)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)

                Button { connectManual() } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Theme.Text.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(serverAddress.isEmpty)

                Button("Search LAN automatically") { searchForBridge() }
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Text.secondary)
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Accent.error)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Background.primary)
        .onAppear {
            searchForBridge()
        }
    }

    // MARK: - Manual connect (LAN IP or remote URL)

    private func connectManual() {
        let raw = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSearching = true
        error = nil

        Task {
            if BridgeURL.isBareIPv4(raw) {
                await probeLAN(ip: raw)
            } else if let url = BridgeURL.normalize(raw) {
                await verifyRemote(url)
            } else {
                await MainActor.run {
                    isSearching = false
                    error = "Invalid address"
                }
            }
        }
    }

    /// Bare LAN IP → probe the bridge's default port range over http.
    private func probeLAN(ip: String) async {
        for port in 7860...7869 {
            let url = URL(string: "http://\(ip):\(port)/status")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run {
                        isSearching = false
                        bridgeURL = URL(string: "http://\(ip):\(port)")
                        manualEntry = false
                        codeFocused = true
                    }
                    return
                }
            } catch { continue }
        }
        await MainActor.run {
            isSearching = false
            self.error = "Can't reach \(ip)"
        }
    }

    /// Full URL / host:port → verify the bridge is reachable, then move to code entry.
    private func verifyRemote(_ url: URL) async {
        let statusURL = url.appendingPathComponent("status")
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run {
                    isSearching = false
                    bridgeURL = url
                    manualEntry = false
                    codeFocused = true
                }
                return
            }
            await MainActor.run {
                isSearching = false
                self.error = "Server not reachable"
            }
        } catch {
            await MainActor.run {
                isSearching = false
                self.error = "Can't reach \(url.host ?? "server")"
            }
        }
    }

    private func searchForBridge() {
        isSearching = true
        error = nil
        manualEntry = false
        Task {
            let url = await bridge.discover()
            await MainActor.run {
                isSearching = false
                bridgeURL = url
                if url != nil {
                    codeFocused = true
                } else {
                    manualEntry = true
                    addressFocused = true
                }
            }
        }
    }

    private func submitCode(_ code: String) {
        guard let url = bridgeURL, !isConnecting else { return }
        isConnecting = true
        error = nil

        Task {
            do {
                try await bridge.pair(baseURL: url, code: code)
                await MainActor.run {
                    session.isPaired = true
                    session.sessionState = SessionState(
                        connection: .connected, activity: .idle,
                        machineName: url.host ?? "Mac", modelName: nil,
                        workingDirectory: nil,
                        elapsedSeconds: 0, filesChanged: 0, linesAdded: 0,
                        transportMode: .lan
                    )
                    session.appendLine(TerminalLine(text: "Connected to bridge", type: .system))
                    session.startEventStream()
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.error = error.localizedDescription
                    self.code = ""
                }
            }
        }
    }
}

#Preview { OnboardingView().environmentObject(WatchViewState.shared) }
