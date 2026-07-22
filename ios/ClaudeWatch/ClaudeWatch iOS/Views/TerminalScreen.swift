import SwiftUI
import SwiftTerm
import UIKit

// MARK: - Terminal screen

/// The live Claude Code terminal. Owns the socket's lifetime via a `StateObject`
/// box and hands it to an inner view that observes its connection state.
struct TerminalScreen: View {
    @StateObject private var box: SocketBox

    init(baseURL: URL, token: String) {
        _box = StateObject(wrappedValue: SocketBox(baseURL: baseURL, token: token))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            if let socket = box.socket {
                TerminalContainer(socket: socket)
            } else {
                VStack(spacing: 8) {
                    BlockCursor(mode: .offline, width: 8, height: 16)
                    Text("Terminal unavailable")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Wraps an optional `TerminalSocket` so the parent can hold it as a
/// `StateObject` even when construction (bad URL) fails.
final class SocketBox: ObservableObject {
    let socket: TerminalSocket?
    init(baseURL: URL, token: String) {
        socket = TerminalSocket(baseURL: baseURL, token: token)
    }
}

// MARK: - Terminal container (observes the socket)

private struct TerminalContainer: View {
    @ObservedObject var socket: TerminalSocket
    @State private var ctrlArmed = false

    var body: some View {
        TerminalSurface(socket: socket)
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .top) { stateOverlay(socket.state) }
            .safeAreaInset(edge: .bottom, spacing: 0) { accessoryRow }
            .onAppear { socket.connect() }
            .onDisappear { socket.disconnect() }
    }

    // MARK: Connection-state overlay (never blank)

    @ViewBuilder
    private func stateOverlay(_ state: TerminalSocket.State) -> some View {
        if state != .connected {
            HStack(spacing: 8) {
                if state != .disconnected {
                    ProgressView().tint(Palette.accent).scaleEffect(0.8)
                }
                Text(label(for: state))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(state == .disconnected ? Palette.danger : Palette.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.surface.opacity(0.92))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
            .padding(.top, 8)
            .transition(.opacity)
            .accessibilityLabel("Terminal \(label(for: state))")
        }
    }

    private func label(for state: TerminalSocket.State) -> String {
        switch state {
        case .connecting:   return "connecting…"
        case .reconnecting: return "reconnecting…"
        case .disconnected: return "disconnected"
        case .connected:    return "connected"
        }
    }

    // MARK: Keyboard accessory row

    private var accessoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                keyButton("esc") { send([0x1B]) }
                keyButton("tab") { send([0x09]) }
                keyButton("ctrl", highlighted: ctrlArmed) { ctrlArmed.toggle() }
                keyButton("⌃C") { send([0x03]); ctrlArmed = false }
                keyButton("↑") { send([0x1B, 0x5B, 0x41]) }
                keyButton("↓") { send([0x1B, 0x5B, 0x42]) }
                keyButton("←") { send([0x1B, 0x5B, 0x44]) }
                keyButton("→") { send([0x1B, 0x5B, 0x43]) }
                keyButton("/") { sendChar("/") }
                keyButton("|") { sendChar("|") }
                keyButton("~") { sendChar("~") }
                dismissKeyboardButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 0.5) }
    }

    // Hide the software keyboard. Tapping the terminal again brings it back
    // (SwiftTerm becomes first responder on tap), so the terminal stays usable.
    private var dismissKeyboardButton: some View {
        Button {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 15))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 44, minHeight: 34)
                .background(Palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide keyboard")
    }

    private func keyButton(_ label: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(highlighted ? Color.black : Palette.textPrimary)
                .frame(minWidth: 44, minHeight: 34)
                .padding(.horizontal, 6)
                .background(highlighted ? Palette.accent : Palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(label))
    }

    private func accessibilityName(_ label: String) -> String {
        switch label {
        case "↑": return "up arrow"
        case "↓": return "down arrow"
        case "←": return "left arrow"
        case "→": return "right arrow"
        case "⌃C": return "control C"
        case "/": return "slash"
        case "|": return "pipe"
        case "~": return "tilde"
        default:  return label
        }
    }

    // MARK: Key sending

    private func send(_ bytes: [UInt8]) {
        socket.send(bytes: bytes[...])
    }

    /// Sends a single printable character, applying the armed Ctrl modifier
    /// (control code = char & 0x1f) and then disarming.
    private func sendChar(_ char: String) {
        guard let ascii = char.unicodeScalars.first?.value, ascii < 128 else { return }
        var byte = UInt8(ascii)
        if ctrlArmed {
            byte &= 0x1F
            ctrlArmed = false
        }
        socket.send(bytes: [byte][...])
    }
}

// MARK: - SwiftTerm bridge

/// UIViewRepresentable hosting SwiftTerm's `TerminalView`, wired to a
/// `TerminalSocket`: pty bytes → `feed`, user input → socket, grid size → resize.
struct TerminalSurface: UIViewRepresentable {
    let socket: TerminalSocket

    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        terminal.terminalDelegate = context.coordinator
        terminal.nativeBackgroundColor = UIColor(named: "BgBase") ?? .black
        terminal.nativeForegroundColor = UIColor(named: "TextPrimary") ?? .white
        // Forward touch pans as mouse events so tmux mouse mode (enabled on the
        // phone session by the bridge) handles drag-to-scroll of the live output.
        terminal.allowMouseReporting = true

        // Feed pty bytes from the socket into the emulator.
        socket.onData = { [weak terminal] bytes in
            DispatchQueue.main.async {
                terminal?.feed(byteArray: bytes[...])
            }
        }
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(socket: socket)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let socket: TerminalSocket

        init(socket: TerminalSocket) {
            self.socket = socket
        }

        // User keystrokes from the emulator → bridge.
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            socket.send(bytes: data)
        }

        // Grid geometry changed (layout / rotation / font size) → resize the pty.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            socket.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
