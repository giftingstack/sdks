import Foundation

/// The real room transport: one `URLSessionWebSocketTask` with the WebSocket protocols
/// `["gs.v1", token]` (the token rides only in `Sec-WebSocket-Protocol`, never in the URL).
/// Text frames only. Callbacks reach `RoomClient` on the main actor, in order. Instead of the
/// app-level `ping` text it sends a protocol ping every 30 s; no pong within 10 s cancels the
/// task (a close 1006), so `RoomClient` runs with `heartbeatMs: 0` (design 5.2).
@MainActor
public final class URLSessionRoomSocket: RoomSocket {
    /// Protocol ping interval.
    public static let pingIntervalMs = 30_000
    /// No pong within this after a ping: the socket is dead.
    public static let pongTimeoutMs = 10_000

    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private let delegate: RoomSocketSessionDelegate
    private var handlers: RoomSocketHandlers?
    private var receiving: Task<Void, Never>?
    private var pinging: Task<Void, Never>?
    private var pongDeadline: Task<Void, Never>?
    private var opened = false
    private var finished = false

    public init(
        url: URL,
        protocols: [String],
        handlers: RoomSocketHandlers,
        configuration: URLSessionConfiguration = URLSessionConfiguration.default
    ) {
        let delegate = RoomSocketSessionDelegate()
        self.delegate = delegate
        self.handlers = handlers
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        self.task = session.webSocketTask(with: url, protocols: protocols)
        delegate.owner = self
        task.resume()
        startReceiving()
    }

    /// Released without `close` (its `RoomClient` went away): the session keeps the task and
    /// the delegate alive, so end the connection here instead of leaving it open.
    deinit {
        task.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    public func send(_ text: String) {
        if finished {
            return
        }
        // A failed send surfaces as the task's close.
        task.send(URLSessionWebSocketTask.Message.string(text)) { _ in }
    }

    public func close(code: Int, reason: String) {
        if finished {
            return
        }
        finished = true
        handlers = nil
        stopLoops()
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? URLSessionWebSocketTask.CloseCode.normalClosure
        task.cancel(with: closeCode, reason: reason.data(using: .utf8))
        session.finishTasksAndInvalidate()
    }

    // MARK: - Internals

    private func startReceiving() {
        let task = self.task
        receiving = Task { [weak self] in
            while !Task.isCancelled {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await task.receive()
                } catch {
                    // The session delegate reports the close (with its code).
                    return
                }
                guard let socket = self else {
                    return
                }
                socket.received(message)
            }
        }
    }

    private func received(_ message: URLSessionWebSocketTask.Message) {
        if finished {
            return
        }
        switch message {
        case .string(let text):
            handlers?.onMessage(text)
        case .data:
            break // text frames only
        @unknown default:
            break
        }
    }

    private func startPinging() {
        let nanos = UInt64(URLSessionRoomSocket.pingIntervalMs) * 1_000_000
        pinging = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled {
                    return
                }
                guard let socket = self else {
                    return
                }
                socket.ping()
            }
        }
    }

    private func ping() {
        if finished || pongDeadline != nil {
            return
        }
        let nanos = UInt64(URLSessionRoomSocket.pongTimeoutMs) * 1_000_000
        let task = self.task
        pongDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled {
                return
            }
            guard let socket = self, !socket.finished else {
                return
            }
            // Dead: cancelling ends the task, the delegate reports a close 1006.
            task.cancel()
        }
        let owner = self
        task.sendPing { error in
            let failed = error != nil
            Task { @MainActor in
                owner.pong(failed: failed)
            }
        }
    }

    private func pong(failed: Bool) {
        if failed {
            return // the deadline (or the delegate) ends the socket
        }
        pongDeadline?.cancel()
        pongDeadline = nil
    }

    private func stopLoops() {
        receiving?.cancel()
        receiving = nil
        pinging?.cancel()
        pinging = nil
        pongDeadline?.cancel()
        pongDeadline = nil
    }

    fileprivate func didOpen() {
        if finished || opened {
            return
        }
        opened = true
        startPinging()
        handlers?.onOpen()
    }

    fileprivate func didClose(code: Int, reason: String) {
        if finished {
            return
        }
        finished = true
        let h = handlers
        handlers = nil
        stopLoops()
        session.finishTasksAndInvalidate()
        h?.onClose(code, reason)
    }
}

/// The session delegate: open and close events, hopped to the main actor.
final class RoomSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    weak var owner: URLSessionRoomSocket?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let owner = self.owner
        Task { @MainActor in
            owner?.didOpen()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let code = closeCode.rawValue
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let owner = self.owner
        Task { @MainActor in
            owner?.didClose(code: code, reason: text)
        }
    }

    /// Always called last. A close frame seen before wins; otherwise (network error, refused
    /// handshake, cancelled) it is a close 1006.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var code = 1006
        var text = ""
        if let ws = task as? URLSessionWebSocketTask, ws.closeCode != URLSessionWebSocketTask.CloseCode.invalid {
            code = ws.closeCode.rawValue
            text = ws.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        let owner = self.owner
        Task { @MainActor in
            owner?.didClose(code: code, reason: text)
        }
    }
}

/// The socket factory `GiftRoomModel` uses: `URLSessionRoomSocket`. A URL that does not parse
/// counts as a close 1006 (`socket_failed`), and so does a plain `ws://` (or `http://`) URL to a host that
/// is not on this device (localhost, 127.0.0.1, ::1, 10.0.2.2) unless `allowInsecure` is true: the room
/// token is a subprotocol, so a clear-text connection would show it to the network.
@MainActor
public func urlSessionRoomSocketFactory(
    configuration: URLSessionConfiguration = URLSessionConfiguration.default,
    allowInsecure: Bool = false
) -> RoomSocketFactory {
    return { url, protocols, handlers in
        guard let target = URL(string: url) else {
            throw URLError(.badURL)
        }
        if SecureURL.isRefusedPlain(url, allowInsecure: allowInsecure) {
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }
        return URLSessionRoomSocket(url: target, protocols: protocols, handlers: handlers, configuration: configuration)
    }
}
