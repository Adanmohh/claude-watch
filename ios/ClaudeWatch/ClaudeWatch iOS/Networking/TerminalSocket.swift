import Foundation

/// WebSocket transport for the live Claude Code terminal.
///
/// Connects a `URLSessionWebSocketTask` to `wss://<host>:<port>/terminal?token=…`
/// on the same authenticated bridge channel used for pairing. Raw pty bytes
/// arrive as binary frames (fed into SwiftTerm); user keystrokes and JSON
/// `{type:"resize",cols,rows}` control frames go back over the socket.
/// Reconnects with exponential backoff on a dropped connection.
final class TerminalSocket: NSObject, ObservableObject {

    enum State: Equatable {
        case connecting
        case connected
        case reconnecting
        case disconnected
    }

    @Published private(set) var state: State = .disconnected

    /// Raw bytes received from the bridge (pty output).
    var onData: (([UInt8]) -> Void)?

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var shouldRun = false
    private var reconnectAttempts = 0
    private var reconnectScheduled = false
    private var lastCols = 0
    private var lastRows = 0

    init?(baseURL: URL, token: String) {
        guard let wsURL = Self.terminalURL(base: baseURL, token: token) else { return nil }
        self.url = wsURL
        super.init()
    }

    /// Builds the terminal WS URL from the paired base URL: https→wss, http→ws.
    static func terminalURL(base: URL, token: String) -> URL? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = (comps.scheme == "http") ? "ws" : "wss"
        comps.path = "/terminal"
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url
    }

    // MARK: - Lifecycle

    func connect() {
        shouldRun = true
        if urlSession == nil {
            urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        }
        openSocket()
    }

    func disconnect() {
        shouldRun = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setState(.disconnected)
    }

    private func openSocket() {
        guard shouldRun, let urlSession else { return }
        setState(reconnectAttempts == 0 ? .connecting : .reconnecting)
        let newTask = urlSession.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        receiveLoop(on: newTask)
    }

    // MARK: - Send

    /// Sends user keystrokes to the pty as a binary frame.
    func send(bytes: ArraySlice<UInt8>) {
        guard state == .connected else { return }
        task?.send(.data(Data(bytes))) { _ in }
    }

    /// Sends a resize control frame so the bridge resizes the pty. The size is
    /// remembered and re-sent whenever the socket (re)connects.
    func sendResize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        lastCols = cols
        lastRows = rows
        guard state == .connected else { return }
        let json = "{\"type\":\"resize\",\"cols\":\(cols),\"rows\":\(rows)}"
        task?.send(.string(json)) { _ in }
    }

    private func flushResize() {
        guard lastCols > 0, lastRows > 0 else { return }
        let json = "{\"type\":\"resize\",\"cols\":\(lastCols),\"rows\":\(lastRows)}"
        task?.send(.string(json)) { _ in }
    }

    // MARK: - Receive

    private func receiveLoop(on socketTask: URLSessionWebSocketTask) {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            // Ignore callbacks from a stale task after a reconnect.
            guard socketTask === self.task else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.onData?([UInt8](data))
                case .string(let text):
                    self.onData?([UInt8](Data(text.utf8)))
                @unknown default:
                    break
                }
                self.receiveLoop(on: socketTask)
            case .failure:
                self.handleDrop()
            }
        }
    }

    // MARK: - Reconnect

    private func handleDrop() {
        guard shouldRun, !reconnectScheduled else { return }
        reconnectScheduled = true
        task = nil
        reconnectAttempts += 1
        setState(.reconnecting)

        // Exponential backoff capped at 30s (2s, 4s, 8s, 16s, 30s…).
        let delay = min(pow(2.0, Double(min(reconnectAttempts, 5))), 30.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            self.openSocket()
        }
    }

    private func setState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension TerminalSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        reconnectAttempts = 0
        setState(.connected)
        // Re-send the current dimensions now that the socket is open.
        flushResize()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        guard webSocketTask === task else { return }
        handleDrop()
    }
}
