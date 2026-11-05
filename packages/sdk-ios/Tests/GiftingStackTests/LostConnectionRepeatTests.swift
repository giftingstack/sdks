import Foundation
import XCTest
@testable import GiftingStack

/// SPEC 3.4 (audit R-18): `sendGift` repeats one lost connection; nothing else is repeated.
final class LostConnectionRepeatTests: XCTestCase {
    private final class Recorder: GiftingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String?] = []
        let error: Error

        init(error: Error) {
            self.error = error
        }

        var keys: [String?] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.lock()
            seen.append(request.headers["Idempotency-Key"])
            lock.unlock()
            throw error
        }
    }

    private func networkError(_ block: () async throws -> Void) async {
        do {
            try await block()
            XCTFail("expected network_error")
        } catch let error as GiftingError {
            XCTAssertEqual(error.type, "network_error")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testTwoLostConnectionsInARowEndAfterTwoRequestsWithTheSameKey() async {
        let recorder = Recorder(error: URLError(.networkConnectionLost))
        let client = GiftingClient(getToken: { _ in "t" }, transport: recorder)
        await networkError { _ = try await client.sendGift(SendGiftInput(receiver: "bob", giftId: "rose")) }
        XCTAssertEqual(recorder.keys.count, 2)
        XCTAssertFalse((recorder.keys[0] ?? "").isEmpty)
        XCTAssertEqual(recorder.keys[0], recorder.keys[1])
    }

    func testATimeoutIsNotRepeated() async {
        let recorder = Recorder(error: URLError(.timedOut))
        let client = GiftingClient(getToken: { _ in "t" }, transport: recorder)
        await networkError { _ = try await client.sendGift(SendGiftInput(receiver: "bob", giftId: "rose")) }
        XCTAssertEqual(recorder.keys.count, 1)
    }

    func testAGetIsNeverRepeated() async {
        let recorder = Recorder(error: URLError(.networkConnectionLost))
        let client = GiftingClient(getToken: { _ in "t" }, transport: recorder)
        await networkError { _ = try await client.getGifts() }
        XCTAssertEqual(recorder.keys.count, 1)
    }
}
