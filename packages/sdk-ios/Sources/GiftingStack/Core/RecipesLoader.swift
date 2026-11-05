import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Fetches and caches the remote recipes document (spec 13.5). The cached copy is used at once; a
// refresh runs in the background at most once per 6 hours. Nothing here throws to the app or
// delays an effect: on any failure the layer keeps the cached or embedded numbers. Ported from
// `packages/sdk-js/src/web/recipes-loader.ts`.

/// A small key-value store for the cached document. Throwing (full, blocked) means memory only.
public protocol RecipesStorage: AnyObject {
    func readValue(_ key: String) throws -> String?
    func writeValue(_ key: String, _ value: String) throws
}

/// The default store: memory only, for the life of the process.
public final class InMemoryRecipesStorage: RecipesStorage {
    private var values: [String: String] = [:]

    public init() {}

    public func readValue(_ key: String) throws -> String? {
        values[key]
    }

    public func writeValue(_ key: String, _ value: String) throws {
        values[key] = value
    }
}

/// The loader's numbers (spec 13.5).
public enum RecipesLoaderDefaults {
    /// Whole-response timeout, ms.
    public static let fetchTimeoutMs: Double = 3_000
    /// A successful fetch is reused this long, ms.
    public static let refreshMs: Double = 6 * 60 * 60 * 1000
    /// First wait after a failure; doubles per failure, capped at `refreshMs`.
    public static let backoffMs: Double = 60_000
    public static let storagePrefix = "giftingstack:recipes:"

    /// `URLSession` without cookies, 3 s for the whole response.
    public static func transport() -> GiftingTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = fetchTimeoutMs / 1000
        configuration.timeoutIntervalForRequest = fetchTimeoutMs / 1000
        configuration.httpShouldSetCookies = false
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    /// Wall clock in ms (the cache time must survive app restarts).
    public static func wallClockMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}

private struct RecipesCacheEntry: Codable {
    var fetchedAt: Double
    /// The raw document text, parsed again on read so new limits apply to old copies.
    var doc: String
}

/// Resumes a continuation once, from whichever task gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPResponse?, Never>?

    init(_ continuation: CheckedContinuation<HTTPResponse?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: HTTPResponse?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

@MainActor
public final class RemoteRecipesLoader {
    public let url: String
    private let transport: GiftingTransport?
    private let storage: RecipesStorage?
    private let now: () -> Double
    private let timeoutMs: Double
    private var loaded = false
    private var value: RemoteRecipeSet?
    private var fetchedAt: Double?
    private var failures = 0
    private var backoffUntil: Double = 0
    private var inflight: Task<Void, Never>?
    /// Requests started so far (for tests).
    public private(set) var requestCount = 0

    /// - Parameters:
    ///   - transport: nil = no network at all.
    ///   - storage: nil = memory only.
    ///   - now: milliseconds (`RecipesLoaderDefaults.wallClockMs` in the shared loaders).
    public init(
        url: String,
        transport: GiftingTransport?,
        storage: RecipesStorage?,
        now: @escaping () -> Double,
        timeoutMs: Double = RecipesLoaderDefaults.fetchTimeoutMs
    ) {
        self.url = url
        self.transport = transport
        self.storage = storage
        self.now = now
        self.timeoutMs = timeoutMs
    }

    private var key: String {
        RecipesLoaderDefaults.storagePrefix + url
    }

    /// The best document known now (cached or fetched), or nil: use the embedded set.
    public func current() -> RemoteRecipeSet? {
        load()
        return value
    }

    /// Fetches a fresh document when one is due and no attempt is backing off. Concurrent callers
    /// share one request. Never throws.
    public func refresh() async {
        load()
        if let running = inflight {
            await running.value
            return
        }
        guard let transport = transport, due(now()) else {
            return
        }
        let task = Task { [weak self] () -> Void in
            guard let self = self else {
                return
            }
            await self.attempt(transport)
        }
        inflight = task
        await task.value
        inflight = nil
    }

    // MARK: - Private

    private func load() {
        if loaded {
            return
        }
        loaded = true
        var stored: String?
        if let storage = storage {
            stored = (try? storage.readValue(key)) ?? nil
        }
        guard let raw = stored,
              let entry = try? JSONDecoder().decode(RecipesCacheEntry.self, from: Data(raw.utf8)),
              let json = RemoteJSON.parse(Data(entry.doc.utf8)),
              let parsed = parseRemoteRecipes(json) else {
            return
        }
        value = parsed
        fetchedAt = entry.fetchedAt
    }

    private func due(_ t: Double) -> Bool {
        if t < backoffUntil {
            return false
        }
        guard let at = fetchedAt else {
            return true
        }
        // A clock that went back counts as due, so a wrong clock cannot pin an old copy.
        return t < at || t - at >= RecipesLoaderDefaults.refreshMs
    }

    private func attempt(_ transport: GiftingTransport) async {
        requestCount += 1
        let request = HTTPRequest(method: "GET", url: url, headers: [:], body: nil)
        let response = await fetch(transport, request)
        guard let res = response,
              (200...299).contains(res.status),
              let json = RemoteJSON.parse(res.body),
              let parsed = parseRemoteRecipes(json) else {
            failures += 1
            let wait = min(
                RecipesLoaderDefaults.refreshMs,
                RecipesLoaderDefaults.backoffMs * pow(2, Double(failures - 1))
            )
            backoffUntil = now() + wait
            return
        }
        let t = now()
        value = parsed
        fetchedAt = t
        failures = 0
        backoffUntil = 0
        if let text = String(data: res.body, encoding: .utf8),
           let encoded = try? JSONEncoder().encode(RecipesCacheEntry(fetchedAt: t, doc: text)),
           let entry = String(data: encoded, encoding: .utf8) {
            // Full or blocked storage: keep the copy in memory only.
            try? storage?.writeValue(key, entry)
        }
    }

    /// The response, or nil after `timeoutMs` or on any transport error.
    private func fetch(_ transport: GiftingTransport, _ request: HTTPRequest) async -> HTTPResponse? {
        let nanos = UInt64(max(0, timeoutMs) * 1_000_000)
        return await withCheckedContinuation { (continuation: CheckedContinuation<HTTPResponse?, Never>) in
            let once = ResumeOnce(continuation)
            let work = Task.detached {
                let answer = try? await transport.send(request)
                once.resume(answer)
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: nanos)
                work.cancel()
                once.resume(nil)
            }
        }
    }

    // MARK: - One loader per URL

    private static var registry: [String: RemoteRecipesLoader] = [:]

    /// The process-wide loader for `url` (wall clock, in-memory cache, `URLSession`).
    public static func sharedLoader(url: String) -> RemoteRecipesLoader {
        if let existing = registry[url] {
            return existing
        }
        let loader = RemoteRecipesLoader(
            url: url,
            transport: RecipesLoaderDefaults.transport(),
            storage: InMemoryRecipesStorage(),
            now: { RecipesLoaderDefaults.wallClockMs() }
        )
        registry[url] = loader
        return loader
    }

    /// The shared loader with its background refresh started, or nil when remote recipes are
    /// off (`remoteRecipes == false`, or a version that cannot be pinned): no network then.
    public static func start(
        remoteRecipes: Bool = true,
        recipesVersion: String? = nil,
        recipesUrl: String? = nil
    ) -> RemoteRecipesLoader? {
        if !remoteRecipes {
            return nil
        }
        guard let url = remoteRecipesUrl(recipesUrl, version: recipesVersion) else {
            return nil
        }
        let loader = sharedLoader(url: url)
        Task {
            await loader.refresh()
        }
        return loader
    }

    /// Forgets the shared loaders (tests).
    public static func resetShared() {
        registry = [:]
    }
}
