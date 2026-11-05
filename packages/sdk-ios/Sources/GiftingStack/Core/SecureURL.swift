import Foundation

/// The transport rule of the SDK (SPEC 3.1, audit R-07): plain `http` and `ws` only for a host on this
/// device (or the Android emulator's name for the dev machine) or with `allowInsecure`.
/// The token travels in the `Authorization` header (HTTP) or as a subprotocol (rooms), so clear text
/// would show it to the network.
enum SecureURL {
    /// Hosts that never leave the device.
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "10.0.2.2"]

    /// The host of a URL (lower case, no port, no brackets), or nil. Parsed by hand so a malformed URL
    /// never fails and `http://localhost@evil.example` reads as `evil.example`.
    static func host(of url: String) -> String? {
        guard let separator = url.range(of: "://") else {
            return nil
        }
        var authority = String(url[separator.upperBound...])
        if let end = authority.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            authority = String(authority[..<end])
        }
        if let at = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: at)...])
        }
        let host: String
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else {
                return nil
            }
            host = String(authority[authority.index(after: authority.startIndex)..<close])
        } else if let colon = authority.firstIndex(of: ":") {
            host = String(authority[..<colon])
        } else {
            host = authority
        }
        let lowered = host.lowercased()
        return lowered.isEmpty ? nil : lowered
    }

    static func scheme(of url: String) -> String {
        guard let separator = url.range(of: "://") else {
            return ""
        }
        return String(url[..<separator.lowerBound]).lowercased()
    }

    static func isLoopback(_ url: String) -> Bool {
        guard let host = host(of: url) else {
            return false
        }
        return loopbackHosts.contains(host)
    }

    /// SPEC 3.1: true for a plain `http` / `ws` URL (any case) that is not on this device while
    /// `allowInsecure` is off. `https`, `wss`, another scheme and a string without one are not refused here
    /// (the transport fails the odd ones later).
    static func isRefusedPlain(_ url: String, allowInsecure: Bool) -> Bool {
        let s = scheme(of: url)
        return (s == "http" || s == "ws") && !allowInsecure && !isLoopback(url)
    }

    /// The message of a refusal: names the option and shows only scheme and host, never userinfo, path or query.
    static func refusalMessage(_ url: String, what: String) -> String {
        let s = scheme(of: url)
        let secure = s == "ws" ? "wss" : "https"
        return "\(what) uses plain \(s)://\(host(of: url) ?? "?"). Use \(secure), or pass allowInsecure: true "
            + "(localhost, 127.0.0.1, ::1 and 10.0.2.2 are always allowed)."
    }
}
