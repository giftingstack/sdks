#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import ImageIO
import SwiftUI

/// The limits of `GiftImageCache` (outside the main actor type so the download can read them).
enum GiftImageLimits {
    /// Most bytes a picture download may have (SPEC 7.6).
    static let maxBytes = pictureMaxBytes
    /// A decoded picture is at most this many pixels on its long side.
    static let maxPixelSize = 1024
}

/// Downloads and decodes gift pictures once and keeps the decoded bitmaps in memory, so an effect
/// never waits for a decode when the person taps Send (spec 7.2, 9: prefetch and decode ahead).
/// WebP is decoded by ImageIO (iOS 14+). Downloads go through `URLSession` and its URL cache,
/// which keeps the files the asset host serves with a one-year cache header.
///
/// Safety limits (SPEC 7.6, audit R-08): only `isPictureUrl` URLs (`https`, `http` to localhost, 127.0.0.1,
/// ::1 and 10.0.2.2 for a local server, `data:image`); a download stops at 5 MiB; a picture is decoded as a
/// thumbnail of at most 1024 px on its long side (ImageIO downsamples while decoding, so a huge file never
/// becomes a huge bitmap); a picture that failed is not requested again for 60 s (`PictureFailures`).
/// `cancelAll()` stops the downloads in flight.
@MainActor
public final class GiftImageCache {
    public static let shared = GiftImageCache()

    /// How many decoded pictures stay in memory (oldest dropped first). Default 80.
    public var capacity = 80
    public var session: URLSession
    /// A clock that only moves forward, in seconds. Tests replace it.
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private var waiting: [String: [(CGImage?) -> Void]] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var failures = PictureFailures()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The decoded picture, if it is already in memory.
    public func cached(_ url: String) -> CGImage? {
        images[url]
    }

    /// Starts downloading and decoding a picture. Never fails; nil and empty URLs are ignored.
    public func prefetch(_ url: String?) {
        guard let url = url, !url.isEmpty else {
            return
        }
        load(url) { _ in }
    }

    /// Calls `completion` on the main actor with the decoded picture, or nil when it could not
    /// be loaded. Calls it synchronously when the picture is already in memory, or when it is not
    /// allowed or failed within the last 60 seconds.
    public func load(_ url: String, completion: @escaping (CGImage?) -> Void) {
        if let image = images[url] {
            completion(image)
            return
        }
        if waiting[url] != nil {
            waiting[url]?.append(completion)
            return
        }
        guard isPictureUrl(url), !recentlyFailed(url) else {
            completion(nil)
            return
        }
        if url.prefix(5).lowercased() == "data:" {
            guard let bytes = GiftImageCache.dataURLBytes(url) else {
                failures.fail(url, atMs: uptimeMs)
                completion(nil)
                return
            }
            // data:image/...;base64,...: nothing to download; decode now (kept like any other picture).
            waiting[url] = [completion]
            finish(url, image: bytes.count <= GiftImageLimits.maxBytes ? GiftImageCache.decode(bytes) : nil)
            return
        }
        guard let target = URL(string: url) else {
            completion(nil)
            return
        }
        waiting[url] = [completion]
        let session = self.session
        running[url] = Task.detached(priority: .userInitiated) { [weak self] in
            let image = await GiftImageCache.download(target, session: session)
            // A cancelled download (cancelAll) is not a failure to remember.
            let cancelled = Task.isCancelled
            await self?.finish(url, image: image, remember: !cancelled)
        }
    }

    /// Drops every decoded picture (for example on a memory warning).
    public func removeAll() {
        images = [:]
        order = []
    }

    /// Cancels every download in flight; their callbacks get nil. Pictures already decoded stay.
    public func cancelAll() {
        for task in running.values {
            task.cancel()
        }
    }

    private var uptimeMs: Int {
        Int(uptime() * 1000)
    }

    private func recentlyFailed(_ url: String) -> Bool {
        failures.has(url, atMs: uptimeMs)
    }

    private func finish(_ url: String, image: CGImage?, remember: Bool = true) {
        running[url] = nil
        if let image = image {
            images[url] = image
            order.removeAll { $0 == url }
            order.append(url)
            while order.count > max(1, capacity) {
                let dropped = order.removeFirst()
                images[dropped] = nil
            }
        } else if remember {
            failures.fail(url, atMs: uptimeMs)
        }
        let callbacks = waiting[url] ?? []
        waiting[url] = nil
        for callback in callbacks {
            callback(image)
        }
    }

    /// The bytes of a `data:image/...;base64,...` URL, or nil when it is not base64 or not valid.
    nonisolated static func dataURLBytes(_ url: String) -> Data? {
        guard url.prefix(5).lowercased() == "data:", let comma = url.firstIndex(of: ",") else {
            return nil
        }
        guard url[..<comma].lowercased().hasSuffix(";base64") else {
            return nil
        }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }

    /// One download, at most 5 MB (a bigger file, declared or streamed, is a failure) and decoded
    /// as a thumbnail. Any error, and a cancelled task, give nil.
    nonisolated static func download(_ url: URL, session: URLSession) async -> CGImage? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            if response.expectedContentLength > Int64(GiftImageLimits.maxBytes) {
                return nil
            }
            var data = Data()
            var chunk = [UInt8]()
            chunk.reserveCapacity(16 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 16 * 1024 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if data.count > GiftImageLimits.maxBytes {
                        return nil
                    }
                }
            }
            data.append(contentsOf: chunk)
            if data.count > GiftImageLimits.maxBytes {
                return nil
            }
            return decode(data)
        } catch {
            return nil
        }
    }

    /// Decodes at once (not lazily at first draw), downsampled so the long side is at most
    /// `GiftImageLimits.maxPixelSize` (`kCGImageSourceThumbnailMaxPixelSize`; a smaller picture keeps its size).
    nonisolated static func decode(_ data: Data, maxPixelSize: Int = GiftImageLimits.maxPixelSize) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Starts loading pictures so they are ready when needed (spec 9). Safe to call with nil.
@MainActor
public func prefetchGiftPicture(_ url: String?) {
    GiftImageCache.shared.prefetch(url)
}
#endif
