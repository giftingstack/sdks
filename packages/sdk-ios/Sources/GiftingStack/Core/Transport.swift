import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP request as the client builds it. `url` is the full URL string, exactly as sent.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    /// nil: no body (GET requests).
    public var body: Data?

    public init(method: String, url: String, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// One HTTP response.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Header value by name, compared case-insensitively.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        for (key, value) in headers where key.lowercased() == wanted {
            return value
        }
        return nil
    }
}

/// The HTTP layer of `GiftingClient`. Replace it in tests or to use your own networking.
/// Throw any error when no response arrived (offline, DNS, TLS, reset): the client turns it
/// into a `network_error`.
public protocol GiftingTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Same protocol, the name used in the iOS docs.
public typealias HTTPTransport = GiftingTransport

/// Default time allowed for one HTTP attempt, in seconds (SPEC 3.4).
public let defaultRequestTimeout: TimeInterval = 20

/// The default transport, on `URLSession`.
public struct URLSessionTransport: GiftingTransport {
    public let session: URLSession
    /// Time allowed for one attempt, in seconds, when this transport makes its own session (no
    /// `session` given): the whole attempt is bounded (`timeoutIntervalForRequest` and
    /// `timeoutIntervalForResource`). A slower attempt fails with `URLError.timedOut`, which
    /// `GiftingClient` reports as the `network_error`. 0 keeps the URLSession defaults (60 s without
    /// data). A `session` you pass keeps its own configuration.
    public let timeout: TimeInterval

    public init(session: URLSession? = nil, timeout: TimeInterval = defaultRequestTimeout) {
        self.timeout = timeout
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            if timeout > 0 {
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
            }
            self.session = URLSession(configuration: configuration)
        }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            throw URLError(.badURL)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        // The completion-handler API exists on every platform (the async one does not on Linux).
        // A cancelled caller cancels the request too (it used to run on until the timeout).
        let handle = TransportTaskHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    var headers: [String: String] = [:]
                    for (key, value) in http.allHeaderFields {
                        if let name = key as? String, let text = value as? String {
                            headers[name] = text
                        }
                    }
                    continuation.resume(
                        returning: HTTPResponse(status: http.statusCode, headers: headers, body: data ?? Data())
                    )
                }
                handle.set(task)
                task.resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

/// Holds the running `URLSessionDataTask` so `onCancel` (any thread) can cancel it, even when the
/// cancellation arrives before the task exists.
private final class TransportTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func set(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let already = cancelled
        lock.unlock()
        if already {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
