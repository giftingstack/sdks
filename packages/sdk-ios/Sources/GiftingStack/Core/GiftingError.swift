import Foundation

/// Any error from the API, or a network failure (`status` 0).
public struct GiftingError: Error, Sendable, Equatable, Hashable, LocalizedError {
    /// The HTTP status, or 0 when no response arrived.
    public let status: Int
    /// `body.error.type`, else `"unknown_error"`; `"network_error"` for status 0.
    public let type: String
    public let message: String
    /// `body.error.request_id`, else the `X-Request-Id` response header, else nil.
    public let requestId: String?

    public init(status: Int, type: String, message: String, requestId: String? = nil) {
        self.status = status
        self.type = type
        self.message = message
        self.requestId = requestId
    }

    /// Worth showing as "try again" rather than as a hard failure.
    public var retryable: Bool {
        status == 0 || status == 429 || status >= 500
    }

    /// `insufficient_balance`: show your coin store.
    public var insufficientBalance: Bool {
        type == "insufficient_balance"
    }

    public var errorDescription: String? {
        message
    }

    static let networkMessage = "Could not reach GiftingStack. Check your connection."

    static var network: GiftingError {
        GiftingError(status: 0, type: "network_error", message: networkMessage, requestId: nil)
    }
}

/// Any failure as a `GiftingError`. Anything else becomes status 0, `unknown_error`, with the
/// error's localized description as the message (spec section 8, `asError`).
public func asGiftingError(_ error: Error) -> GiftingError {
    if let e = error as? GiftingError {
        return e
    }
    let text = error.localizedDescription
    return GiftingError(
        status: 0,
        type: "unknown_error",
        message: text.isEmpty ? "Something went wrong." : text,
        requestId: nil
    )
}
