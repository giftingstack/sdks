import Foundation
import XCTest
@testable import GiftingStack

/// SPEC 3.1, audit R-07: plain `http://` and `ws://` only for loopback, unless `allowInsecure`.
/// (A refused URL is a `precondition` failure, which a test cannot catch: the rule is tested through
/// `SecureURL`, and the accepted cases through the real initialisers.)
final class SecureURLTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func bump() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct EmptyListTransport: GiftingTransport {
        let counter: Counter

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            counter.bump()
            return HTTPResponse(status: 200, body: Data(#"{"data":[]}"#.utf8))
        }
    }

    private func refused(_ url: String, allow: Bool = false) -> Bool {
        SecureURL.isRefusedPlain(url, allowInsecure: allow)
    }

    func testSecureSchemesAndOddOnesAreNotRefusedHere() {
        XCTAssertFalse(refused("https://api.giftingstack.com"))
        XCTAssertFalse(refused("wss://rt.giftingstack.com"))
        XCTAssertFalse(refused("HTTPS://api.example.test///"))
        XCTAssertFalse(refused("ftp://x.test"), "the transport fails another scheme later")
        XCTAssertFalse(refused("api.giftingstack.com"))
        XCTAssertFalse(refused(""))
    }

    func testPlainSchemesPassForLoopbackOnly() {
        for host in ["localhost", "127.0.0.1", "[::1]", "10.0.2.2"] {
            XCTAssertFalse(refused("http://\(host):8787/proxy"), "http \(host)")
            XCTAssertFalse(refused("ws://\(host):8788"), "ws \(host)")
        }
        XCTAssertTrue(refused("http://api.example.test"))
        XCTAssertTrue(refused("HTTP://api.example.test"), "any case")
        XCTAssertTrue(refused("ws://rt.example.test"))
        XCTAssertTrue(refused("WS://rt.example.test"))
        XCTAssertTrue(refused("http://192.168.1.10:8787"))
        XCTAssertTrue(refused("http://127.0.0.2"), "only 127.0.0.1 is loopback here")
        XCTAssertTrue(refused("http://localhost@evil.example/x"), "userinfo does not make a host local")
        XCTAssertTrue(refused("http://localhost.evil.example/"))
    }

    func testAllowInsecureLetsAPlainURLThrough() {
        XCTAssertFalse(refused("http://192.168.1.10:8787", allow: true))
        XCTAssertFalse(refused("ws://rt.example.test", allow: true))
    }

    func testTheMessageNamesTheOptionAndShowsOnlySchemeAndHost() {
        let message = SecureURL.refusalMessage("http://user:secret@api.example.test:8080/path?token=abc", what: "The base URL")
        XCTAssertTrue(message.contains("allowInsecure"), message)
        XCTAssertTrue(message.contains("http://api.example.test"), message)
        XCTAssertFalse(message.contains("secret"), message)
        XCTAssertFalse(message.contains("token=abc"), message)
        XCTAssertFalse(message.contains("/path"), message)
        XCTAssertTrue(SecureURL.refusalMessage("ws://rt.example.test", what: "The rooms url").contains("wss"))
    }

    func testHostParsing() {
        XCTAssertEqual(SecureURL.host(of: "http://LocalHost:80/a?b#c"), "localhost")
        XCTAssertEqual(SecureURL.host(of: "ws://[::1]:8788//"), "::1")
        XCTAssertEqual(SecureURL.host(of: "http://localhost@evil.example/"), "evil.example")
        XCTAssertNil(SecureURL.host(of: "not a url"))
        XCTAssertNil(SecureURL.host(of: "http://[::1"))
    }

    func testLoopbackHttpsAndTheOptInAllConstructAndWork() async throws {
        for (base, allow) in [("http://10.0.2.2:8787", false), ("https://api.example.test/", false), ("http://staging.lan", true)] {
            let counter = Counter()
            let client = GiftingClient(
                getToken: { _ in "t" },
                baseURL: base,
                transport: EmptyListTransport(counter: counter),
                allowInsecure: allow
            )
            let gifts = try await client.getGifts()
            XCTAssertEqual(gifts.count, 0, base)
            XCTAssertEqual(counter.count, 1, base)
        }
    }

    #if canImport(SwiftUI) && canImport(ImageIO)
    @MainActor
    func testTheRoomSocketRefusesPlainWsToAnotherHost() {
        let handlers = RoomSocketHandlers(onOpen: {}, onMessage: { _ in }, onClose: { _, _ in })
        let factory = urlSessionRoomSocketFactory()
        XCTAssertThrowsError(try factory("ws://rooms.example.test/v1/rooms/a", ["gs.v1", "t"], handlers))
        XCTAssertThrowsError(try factory("http://10.1.2.3/v1/rooms/a", ["gs.v1", "t"], handlers))
    }
    #endif

    @MainActor
    func testTheRoomClientAcceptsTheAllowedURLs() {
        let factory: RoomSocketFactory = { _, _, _ in throw URLError(.badURL) }
        let getToken: GiftingTokenProvider = { _ in "t" }
        _ = RoomClient(room: "live_1", getToken: getToken, socket: factory, url: "ws://localhost:8788//")
        _ = RoomClient(room: "live_1", getToken: getToken, socket: factory, url: "wss://rt.giftingstack.com")
        _ = RoomClient(room: "live_1", getToken: getToken, socket: factory, url: "ws://rt.example.test", allowInsecure: true)
        let client = RoomClient(room: "live_1", getToken: getToken, socket: factory)
        client.url = "ws://127.0.0.1:8788"
        client.allowInsecure = true
        client.url = "ws://rt.example.test"
    }
}
