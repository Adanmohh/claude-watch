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
        ScrollView {
            VStack(spacing: 8) {
                header

                if isSearching {
                    searching
                } else if bridgeURL != nil && !manualEntry {
                    codeEntry
                } else {
                    manualEntryView
                }

                if let error {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Palette.watchBg.ignoresSafeArea())
        .onAppear { searchForBridge() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            BlockCursor(mode: isSearching ? .working : (bridgeURL != nil ? .idle : .pending),
                        width: 8, height: 15)
            Text("Apuri Go")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private var searching: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 12)
            ProgressView().tint(Palette.accent)
            Text("connecting")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.textDim)
            Spacer(minLength: 12)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 8) {
            Text("Enter code from Mac")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("000000", text: $code)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(codeFocused ? Palette.accent : Palette.border,
                                lineWidth: codeFocused ? 1.5 : 1)
                )
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                    if filtered != newValue { code = filtered }
                    if filtered.count == 6 { submitCode(filtered) }
                }

            if isConnecting {
                ProgressView().tint(Palette.accent).scaleEffect(0.7)
            }

            Button("Use a different server") {
                bridgeURL = nil
                manualEntry = true
                code = ""
                addressFocused = true
            }
            .font(.system(.caption2))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var manualEntryView: some View {
        VStack(spacing: 8) {
            Text("Server address")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("IP or https://host:port", text: $serverAddress)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.accent)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($addressFocused)
                .padding(.vertical, 9)
                .padding(.horizontal, 8)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(addressFocused ? Palette.accent : Palette.border,
                                lineWidth: addressFocused ? 1.5 : 1)
                )

            Button { connectManual() } label: {
                Text("Connect")
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(serverAddress.isEmpty)
            .opacity(serverAddress.isEmpty ? 0.5 : 1)

            Button("Search LAN automatically") { searchForBridge() }
                .font(.system(.caption2))
                .foregroundStyle(Palette.textSecondary)
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
