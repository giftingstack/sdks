import Foundation
import XCTest
@testable import GiftingStack

/// A transport that answers every request with the same scripted response (or fails).
final class RecipesHTTP: GiftingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var response: HTTPResponse?
    private var delayNanos: UInt64 = 0
    private var urls: [String] = []

    init(status: Int = 200, body: String) {
        response = HTTPResponse(status: status, body: Data(body.utf8))
    }

    /// No response at all (offline).
    init(failing: Bool) {
        response = nil
    }

    var requested: [String] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func setDelay(nanos: UInt64) {
        lock.lock()
        delayNanos = nanos
        lock.unlock()
    }

    func setResponse(status: Int, body: String) {
        lock.lock()
        response = HTTPResponse(status: status, body: Data(body.utf8))
        lock.unlock()
    }

    private func record(_ url: String) -> (HTTPResponse?, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
        return (response, delayNanos)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (answer, delay) = record(request.url)
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        guard let answer = answer else {
            throw URLError(.notConnectedToInternet)
        }
        return answer
    }
}

struct StorageFull: Error {}

/// Storage that is full or blocked: every call throws.
final class BrokenRecipesStorage: RecipesStorage {
    func readValue(_ key: String) throws -> String? {
        throw StorageFull()
    }

    func writeValue(_ key: String, _ value: String) throws {
        throw StorageFull()
    }
}

/// The loader of spec 13.5 (not fixture-driven; the web has the same checks in
/// `remote-recipes.test.ts`).
@MainActor
final class RecipesLoaderTests: XCTestCase {
    private static let url = "https://cdn.example.test/recipes.json"
    private static let goodDoc = "{\"specVersion\":\"1.2.0\",\"comboWindowMs\":3000}"

    private func loader(_ http: RecipesHTTP?, storage: RecipesStorage? = InMemoryRecipesStorage(), clock: @escaping () -> Double) -> RemoteRecipesLoader {
        RemoteRecipesLoader(url: RecipesLoaderTests.url, transport: http, storage: storage, now: clock, timeoutMs: 200)
    }

    func testRemoteRecipesFalseMeansNoLoaderAndNoNetwork() {
        RemoteRecipesLoader.resetShared()
        XCTAssertNil(RemoteRecipesLoader.start(remoteRecipes: false))
        XCTAssertNil(RemoteRecipesLoader.start(recipesVersion: "1/../x"), "an unpinnable version turns it off")
        XCTAssertNil(RemoteRecipesLoader.start(recipesVersion: "1.0.0", recipesUrl: "https://x.test/recipes"))
    }

    func testRecipesVersionPinsTheSharedLoaderUrl() {
        RemoteRecipesLoader.resetShared()
        let pinned = RemoteRecipesLoader.sharedLoader(url: remoteRecipesUrl(nil, version: "1.0.0") ?? "")
        XCTAssertEqual(pinned.url, "https://assets.giftingstack.com/recipes.1.0.0.json")
        XCTAssertTrue(pinned === RemoteRecipesLoader.sharedLoader(url: pinned.url), "one loader per URL")
        RemoteRecipesLoader.resetShared()
    }

    func testFetchParsesCachesAndIsUsedAtOnceByTheNextLoader() async {
        let http = RecipesHTTP(body: RecipesLoaderTests.goodDoc)
        let storage = InMemoryRecipesStorage()
        var now: Double = 1_000
        let first = loader(http, storage: storage, clock: { now })
        XCTAssertNil(first.current(), "nothing before the first fetch: embedded numbers")
        await first.refresh()
        XCTAssertEqual(first.current()?.recipeSet.comboWindowMs, 3000)
        XCTAssertEqual(http.requested, [RecipesLoaderTests.url])

        // A new process with the same storage uses the cached copy at once and does not refetch
        // before 6 hours.
        let offline = RecipesHTTP(failing: true)
        let second = loader(offline, storage: storage, clock: { now })
        XCTAssertEqual(second.current()?.recipeSet.comboWindowMs, 3000)
        now += RecipesLoaderDefaults.refreshMs - 1
        await second.refresh()
        XCTAssertEqual(offline.requested.count, 0)
        now += 1
        await second.refresh()
        XCTAssertEqual(offline.requested.count, 1, "due after 6 hours")
        XCTAssertEqual(second.current()?.recipeSet.comboWindowMs, 3000, "a failure keeps the copy")
    }

    func testFailuresBackOffAndDoublesCappedAtSixHours() async {
        let http = RecipesHTTP(status: 404, body: "not found")
        var now: Double = 0
        let l = loader(http, clock: { now })
        await l.refresh()
        XCTAssertEqual(l.requestCount, 1)
        await l.refresh()
        XCTAssertEqual(l.requestCount, 1, "backing off for 1 minute")
        now += 60_000
        await l.refresh()
        XCTAssertEqual(l.requestCount, 2)
        now += 60_000
        await l.refresh()
        XCTAssertEqual(l.requestCount, 2, "second failure: 2 minutes")
        now += 60_000
        await l.refresh()
        XCTAssertEqual(l.requestCount, 3)
        XCTAssertNil(l.current())

        // A success resets the backoff.
        http.setResponse(status: 200, body: RecipesLoaderTests.goodDoc)
        now += 4 * 60_000
        await l.refresh()
        XCTAssertEqual(l.requestCount, 4)
        XCTAssertEqual(l.current()?.recipeSet.comboWindowMs, 3000)
    }

    func testDocumentsTheSdkIgnoresAreFailures() async {
        let http = RecipesHTTP(body: "{\"specVersion\":\"2.0.0\"}")
        let l = loader(http, clock: { 0 })
        await l.refresh()
        XCTAssertNil(l.current())
        let broken = RecipesHTTP(body: "not json")
        let m = loader(broken, clock: { 0 })
        await m.refresh()
        XCTAssertNil(m.current())
    }

    func testConcurrentRefreshesShareOneRequest() async {
        let http = RecipesHTTP(body: RecipesLoaderTests.goodDoc)
        http.setDelay(nanos: 50_000_000)
        let l = loader(http, clock: { 0 })
        async let a: Void = l.refresh()
        async let b: Void = l.refresh()
        _ = await (a, b)
        XCTAssertEqual(http.requested.count, 1)
        XCTAssertEqual(l.current()?.recipeSet.comboWindowMs, 3000)
    }

    func testGivesUpAfterTheTimeout() async {
        let http = RecipesHTTP(body: RecipesLoaderTests.goodDoc)
        http.setDelay(nanos: 5_000_000_000)
        let l = loader(http, clock: { 0 })
        let started = Date()
        await l.refresh()
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "the 200 ms test timeout ended the wait")
        XCTAssertNil(l.current())
    }

    func testStorageThatThrowsMeansMemoryOnly() async {
        let http = RecipesHTTP(body: RecipesLoaderTests.goodDoc)
        let l = loader(http, storage: BrokenRecipesStorage(), clock: { 0 })
        await l.refresh()
        XCTAssertEqual(l.current()?.recipeSet.comboWindowMs, 3000)
    }

    /// Spec 13.4: effects already playing or waiting keep the recipe they were scheduled with;
    /// later ones use the new set; app thresholds and an app combo window beat the remote set.
    func testSchedulerFixesTheRecipeAtPlay() throws {
        let scheduler = EffectScheduler(now: { 0 })
        let large = GiftEffectEvent(gift: GiftEffectEvent.GiftInfo(id: "dragon", name: "Dragon", price: 40_000, image: nil))
        let first = scheduler.play(large)
        let doc = RemoteJSON.object([
            "specVersion": .string("1.0.0"),
            "recipes": .object(["high": .object(["large": .object(["sparks": .number(99)])])]),
            "thresholds": .object(["mediumFrom": .number(50), "largeFrom": .number(500)]),
        ])
        scheduler.recipes = try XCTUnwrap(parseRemoteRecipes(doc)).recipeSet
        let second = scheduler.play(large)
        XCTAssertEqual(scheduler.active.first?.id, first)
        XCTAssertEqual(scheduler.active.first?.recipe.sparks, 50, "the running effect keeps its recipe")
        XCTAssertEqual(scheduler.queued.first?.id, second)
        XCTAssertEqual(scheduler.queued.first?.recipe.sparks, 99, "a new play uses the remote set")

        // Remote thresholds apply (600 is large with largeFrom 500) unless the app gives its own.
        let mid = GiftEffectEvent(gift: GiftEffectEvent.GiftInfo(id: "hat", name: "Hat", price: 600, image: nil))
        scheduler.clear()
        scheduler.play(mid)
        XCTAssertEqual(scheduler.active.last?.recipe.tier, .large)
        scheduler.clear()
        scheduler.thresholds = TierThresholds()
        scheduler.play(mid)
        XCTAssertEqual(scheduler.active.last?.recipe.tier, .medium)
    }

    func testRemoteComboWindowAppliesUnlessTheAppGaveOne() throws {
        var clock: Double = 0
        let doc = RemoteJSON.object(["specVersion": .string("1.0.0"), "comboWindowMs": .number(5000)])
        let remote = try XCTUnwrap(parseRemoteRecipes(doc)).recipeSet
        let rose = GiftEffectEvent(gift: GiftEffectEvent.GiftInfo(id: "rose", name: "Rose", price: 10, image: nil), sender: "ayla")

        let follows = EffectScheduler(now: { clock })
        follows.reducedMotion = true // the notice shows at play, so its count is readable
        follows.recipes = remote
        follows.play(rose)
        clock = 4000
        follows.play(rose)
        XCTAssertEqual(follows.noticeData?.count, 2, "4 s is inside the remote 5 s window")

        clock = 0
        let pinned = EffectScheduler(comboWindowMs: 2500, now: { clock })
        pinned.reducedMotion = true
        pinned.recipes = remote
        pinned.play(rose)
        clock = 4000
        pinned.play(rose)
        XCTAssertEqual(pinned.noticeData?.count, 1, "the app's 2.5 s window wins")
    }
}
