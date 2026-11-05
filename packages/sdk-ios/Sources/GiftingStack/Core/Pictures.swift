import Foundation

/// Most bytes one picture may have (SPEC 7.6): 5 MiB.
public let pictureMaxBytes = 5_242_880

/// A picture that failed is not requested again for this long (SPEC 7.6).
public let pictureFailureMemoryMs = 60_000

/// At most this many failed URLs are remembered, the oldest forgotten first.
public let pictureFailuresKept = 200

/// A `data:image` URL longer than this many characters is refused: `ceil(pictureMaxBytes x 4 / 3) + 256`.
public let pictureDataUrlMaxChars = (pictureMaxBytes * 4 + 2) / 3 + 256

/// Which picture URLs the SDK draws (SPEC 7.6, audit R-08): `https://` always; `http://` only to a
/// loopback host (`localhost`, `127.0.0.1`, `::1`, `10.0.2.2`); `data:image/...` up to
/// `pictureDataUrlMaxChars` characters; nothing else (`javascript:`, `file:`, `blob:`, `ftp:`, a
/// scheme-less or empty string). A refused URL is never requested: the placeholder is drawn instead.
public func isPictureUrl(_ url: String) -> Bool {
    func starts(_ prefix: String) -> Bool {
        url.utf8.count >= prefix.utf8.count && url.prefix(prefix.count).lowercased() == prefix
    }
    if starts("https://") {
        return true
    }
    if starts("http://") {
        return SecureURL.isLoopback(url)
    }
    if starts("data:image/") {
        return url.utf8.count <= pictureDataUrlMaxChars
    }
    return false
}

/// The URLs whose picture failed, for `pictureFailureMemoryMs` (SPEC 7.6): until then the same URL is not
/// requested again by a prefetch, a rebuilt grid or the next effect. Time is passed in (`atMs`, any clock
/// that only moves forward), so it is pure and testable. At most `pictureFailuresKept` URLs; failing a URL
/// again restarts its minute and makes it the newest.
public struct PictureFailures: Sendable, Equatable {
    private var failedAt: [String: Int] = [:]
    /// Oldest first.
    private var order: [String] = []

    public init() {}

    /// Records that `url` failed at `atMs`.
    public mutating func fail(_ url: String, atMs: Int) {
        if failedAt[url] != nil {
            order.removeAll { $0 == url }
        }
        failedAt[url] = atMs
        order.append(url)
        while order.count > pictureFailuresKept {
            let oldest = order.removeFirst()
            failedAt[oldest] = nil
        }
    }

    /// True while `url` failed less than a minute before `atMs`.
    public func has(_ url: String, atMs: Int) -> Bool {
        guard let at = failedAt[url] else {
            return false
        }
        return atMs - at < pictureFailureMemoryMs
    }
}
