import Foundation

/// Helpers for turning user-entered server addresses into a normalized base URL.
///
/// Supports three kinds of input:
///  - A full URL with scheme and (optional) port, e.g. `https://cc-bridge.sykli.ai:8443`
///  - A bare host / host:port with no scheme, e.g. `cc-bridge.sykli.ai:8443` (defaults to https)
///  - A bare LAN IPv4 address, e.g. `192.168.1.20` (handled separately via port probing over http)
enum BridgeURL {

    /// Normalizes a user-entered address into a base URL.
    /// If no scheme is present, `https://` is assumed (remote/public servers use TLS).
    /// Returns `nil` if the input can't be turned into a URL with a host.
    static func normalize(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        if !string.contains("://") {
            string = "https://" + string
        }

        // Drop any trailing slashes so appendingPathComponent produces clean paths.
        while string.hasSuffix("/") {
            string.removeLast()
        }

        guard let url = URL(string: string),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// True when the input is a bare IPv4 address with no scheme (LAN case).
    /// These are reached over http on the bridge's default port range, not https.
    static func isBareIPv4(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return false }
        // Reject anything carrying an explicit port or path — those are full addresses.
        guard !trimmed.contains(":"), !trimmed.contains("/") else { return false }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part) ?? 999) <= 255
        }
    }
}
