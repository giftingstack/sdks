import Foundation
import XCTest
@testable import GiftingStack

/// A malformed 2xx (SPEC 3.5, audit R-05) and the request timeout (SPEC 3.4, audit R-04), in the
/// places the fixtures do not look. (Swift closures cannot throw into the tray, so audit R-14 has
/// no case here; Swift `Int` is 64-bit, so R-06 has none either.)
final class ClientRobustnessTests: XCTestCase {
    private struct FixedTransport: GiftingTransport {
        var response: HTTPResponse
        var counter: Counter

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            counter.bump()
            return response
        }
    }

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

    private struct TimedOutTransport: GiftingTransport {
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            throw URLError(.timedOut)
        }
    }

    private func failure(_ block: () async throws -> Void) async -> GiftingError? {
        do {
            try await block()
        } catch let error as GiftingError {
            return error
        } catch {
            XCTFail("expected a GiftingError, got \(error)")
        }
        return nil
    }

    func testANonJsonTwoXxIsInvalidResponseWithoutItsText() async {
        let counter = Counter()
        let transport = FixedTransport(
            response: HTTPResponse(
                status: 200,
                headers: ["X-Request-Id": "req_9"],
                body: Data("<html>Captive portal secret-text</html>".utf8)
            ),
            counter: counter
        )
        let client = GiftingClient(getToken: { _ in "t" }, transport: transport)
        let error = await failure { _ = try await client.getMe() }
        XCTAssertEqual(error?.status, 200)
        XCTAssertEqual(error?.type, "invalid_response")
        XCTAssertEqual(error?.message, "Invalid response (200).")
        XCTAssertEqual(error?.requestId, "req_9")
        XCTAssertEqual(error?.retryable, false)
        XCTAssertFalse(String(describing: error).contains("secret-text"))
        XCTAssertEqual(counter.count, 1, "a 2xx is never retried")
    }

    func testJsonOfTheWrongShapeIsInvalidResponseToo() async {
        let transport = FixedTransport(response: HTTPResponse(status: 200, body: Data("[1,2]".utf8)), counter: Counter())
        let client = GiftingClient(getToken: { _ in "t" }, transport: transport)
        let error = await failure { _ = try await client.getMe() }
        XCTAssertEqual(error?.type, "invalid_response")
        XCTAssertNil(error?.requestId)
    }

    func testATimeoutIsTheNetworkError() async {
        let client = GiftingClient(getToken: { _ in "t" }, transport: TimedOutTransport())
        let error = await failure { _ = try await client.getMe() }
        XCTAssertEqual(error?.status, 0)
        XCTAssertEqual(error?.type, "network_error")
        XCTAssertEqual(error?.retryable, true)
    }

    func testTheDefaultTransportBoundsTheWholeAttempt() {
        XCTAssertEqual(defaultRequestTimeout, 20)
        let standard = URLSessionTransport()
        XCTAssertEqual(standard.session.configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(standard.session.configuration.timeoutIntervalForResource, 20)
        let short = URLSessionTransport(timeout: 5)
        XCTAssertEqual(short.session.configuration.timeoutIntervalForRequest, 5)
        XCTAssertEqual(short.session.configuration.timeoutIntervalForResource, 5)
    }
}
