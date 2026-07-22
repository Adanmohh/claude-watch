import SwiftUI

struct PairingView: View {

    @EnvironmentObject private var relayService: RelayService

    // MARK: - State

    @State private var code: String = ""
    @State private var ipAddress: String = ""
    @State private var showManualIP: Bool = false
    @FocusState private var isCodeFocused: Bool
    @FocusState private var isIPFocused: Bool
    @State private var shakeOffset: CGFloat = 0
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isConnecting: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                header
                titleSection

                if showManualIP {
                    ipEntrySection
                }

                digitFields
                statusSection
                bottomSection

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            BlockCursor(mode: isConnecting ? .working : .idle, width: 12, height: 22)
            Text("ClaudeWatch")
                .font(.ledgerTitle(28))
                .tracking(-0.5)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var titleSection: some View {
        Text(showManualIP
             ? "Enter your server address and the pairing code"
             : "Enter the pairing code from your Mac")
            .font(.system(.subheadline))
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
    }

    private var ipEntrySection: some View {
        TextField("IP or https://host:port", text: $ipAddress)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
            .tint(Palette.accent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isIPFocused ? Palette.accent : Palette.border,
                            lineWidth: isIPFocused ? 1.5 : 1)
            )
            .focused($isIPFocused)
    }

    private var digitFields: some View {
        ZStack {
            // Hidden single TextField that captures all input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accentColor(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    handleCodeChange(newValue)
                }

            // Visual digit boxes
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    DigitBox(
                        character: digitAt(index),
                        isActive: index == code.count && isCodeFocused && !isConnecting,
                        isError: showError,
                        isDisabled: isConnecting
                    )
                }
            }
            .offset(x: shakeOffset)
            .contentShape(Rectangle())
            .onTapGesture {
                isCodeFocused = true
            }
        }
        .onAppear {
            if !showManualIP {
                isCodeFocused = true
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isConnecting {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Palette.accent)
                Text("Connecting…")
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 4)
        } else if showError {
            Text(errorMessage)
                .font(.system(.footnote))
                .foregroundStyle(errorMessage.contains("expired") ? Palette.accent : Palette.danger)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .padding(.top, 4)
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 12) {
            if !showManualIP {
                Button {
                    withAnimation {
                        showManualIP = true
                        isIPFocused = true
                    }
                } label: {
                    Text("Enter IP or remote server URL")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.accent)
                }
            }

            Text("Run `node server.js` in the bridge folder to start")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Logic

    private func digitAt(_ index: Int) -> Character? {
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }

    private func handleCodeChange(_ newValue: String) {
        let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
        if filtered != code {
            code = filtered
        }

        if showError {
            withAnimation(.easeOut(duration: 0.2)) {
                showError = false
                errorMessage = ""
            }
        }

        if code.count == 6 && !isConnecting {
            submitCode(code)
        }
    }

    private func submitCode(_ code: String) {
        isConnecting = true
        isCodeFocused = false
        isIPFocused = false

        Task {
            do {
                if showManualIP {
                    let address = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !address.isEmpty else {
                        await MainActor.run {
                            showPairingError("Please enter an IP address or server URL.")
                        }
                        return
                    }
                    if BridgeURL.isBareIPv4(address) {
                        // Bare LAN IP → probe the bridge's default port range over http.
                        try await relayService.pairWithIP(address, code: code)
                    } else {
                        // Full URL / host:port → connect directly (remote, https by default).
                        try await relayService.pairWithURL(address, code: code)
                    }
                } else {
                    try await relayService.pair(code: code)
                }
            } catch let error as BridgeClient.BridgeError {
                await MainActor.run { handlePairingError(error) }
            } catch {
                await MainActor.run {
                    let msg = error.localizedDescription
                    if msg.contains("noServiceFound") || msg.contains("timed out") || msg.contains("not found") {
                        showManualIP = true
                        showPairingError("Bridge not found automatically. Enter your Mac's IP address.")
                        isIPFocused = true
                    } else {
                        showPairingError("Connection failed: \(msg)")
                    }
                }
            }
        }
    }

    private func handlePairingError(_ error: BridgeClient.BridgeError) {
        switch error {
        case .invalidCode:
            showPairingError("Incorrect code. Please try again.")
            shakeFields()
        case .expired:
            showPairingError("Code expired. A new code has been generated on your Mac.")
        case .rateLimited:
            showPairingError("Too many attempts. Please wait a few minutes.")
        case .networkError:
            if !showManualIP {
                showManualIP = true
                showPairingError("Can't reach bridge. Enter your Mac's IP address.")
                isIPFocused = true
            } else {
                showPairingError("Cannot reach the bridge server. Check the address and network.")
            }
        case .serverError(let msg):
            showPairingError(msg)
        }
    }

    private func showPairingError(_ message: String) {
        isConnecting = false
        errorMessage = message
        withAnimation(.easeInOut(duration: 0.3)) {
            showError = true
        }
        code = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if showManualIP && ipAddress.isEmpty {
                isIPFocused = true
            } else {
                isCodeFocused = true
            }
        }
    }

    private func shakeFields() {
        withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            shakeOffset = 0
        }
    }
}

// MARK: - Digit Box (display only)

private struct DigitBox: View {

    let character: Character?
    let isActive: Bool
    let isError: Bool
    let isDisabled: Bool

    var body: some View {
        Text(character.map(String.init) ?? "")
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundStyle(isError ? Palette.danger : Palette.accent)
            .frame(width: 46, height: 56)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isError ? Palette.danger : (isActive ? Palette.accent : Palette.border),
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .opacity(isDisabled ? 0.4 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    PairingView()
        .environmentObject(RelayService.shared)
}
