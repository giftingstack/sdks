import Foundation
import XCTest
@testable import GiftingStack

/// The platform side of rooms: `GiftRoomModel` with a fake socket (join, play into the effect
/// layer, background pause and foreground resume, no `ping` text), and `roomId` on the send path.
@MainActor
final class GiftRoomModelTests: XCTestCase {
    private static let welcome = #"{"t":"welcome","v":1,"viewers":3,"gap":false,"replay":[],"ttl":3600,"now":1000}"#
    private static let rose = #"{"t":"gift","id":101,"at":1000,"tx":"gtx_a","gift":{"id":"rose","name":"Rose","price":10,"icon_url":"https://assets.test/rose/256.webp"},"quantity":2,"sender":{"id":"ayla","name":"Ayla"},"receiver":{"id":"host"}}"#

    #if canImport(SwiftUI) && canImport(ImageIO)
    func testModelJoinsPlaysPausesInBackgroundAndResumes() async throws {
        let clock = FakeGiftClock()
        let script = RoomSessionScript()
        let log = RoomSessionLog()
        let effects = GiftEffectController()
        effects.reducedMotion = false
        let catalog = [
            Gift(
                id: "rose",
                name: "Rose",
                price: 10,
                iconUrl: "https://assets.test/rose/256.webp",
                animationUrl: "https://assets.test/rose/512.webp",
                sortOrder: 1
            ),
        ]
        let client = InstantClient(balance: 100, gifts: catalog)
        let model = GiftRoomModel(
            room: "live_1",
            getToken: { force in
                try await script.token(force)
            },
            client: client,
            effects: effects,
            onEvent: { event in
                log.events.append(event)
            },
            socket: { url, protocols, handlers in
                script.open(url, protocols, handlers)
            },
            clock: clock
        )

        model.join()
        await clock.settle()
        XCTAssertEqual(model.state.status, .connecting)
        XCTAssertEqual(script.tokens, [false])
        try script.resolveToken("tok", "join")
        await clock.settle()
        XCTAssertEqual(script.sockets.count, 1)
        let first = try script.newest("join")
        XCTAssertEqual(first.url, "wss://rt.giftingstack.com/v1/rooms/live_1")
        XCTAssertEqual(first.protocols, ["gs.v1", "tok"])

        first.handlers.onOpen()
        first.handlers.onMessage(GiftRoomModelTests.welcome)
        await clock.settle()
        XCTAssertEqual(model.state.status, .open)
        XCTAssertEqual(model.viewers, 3)
        XCTAssertEqual(first.sent, [.object(["t": .string("hello"), "v": .number(1), "last": .null])])

        first.handlers.onMessage(GiftRoomModelTests.rose)
        await clock.settle()
        XCTAssertEqual(log.events.map { $0.tx }, ["gtx_a"])
        XCTAssertEqual(effects.effects.count, 1, "room gifts play in the effect layer")
        XCTAssertEqual(effects.effects.first?.event.sender, "Ayla")
        XCTAssertEqual(effects.effects.first?.event.quantity, 2)
        XCTAssertEqual(effects.effects.first?.event.gift.image, "https://assets.test/rose/512.webp", "the catalog's big picture")

        // Native sockets use protocol pings: never the `ping` text.
        clock.advance(120_000)
        await clock.settle()
        XCTAssertEqual(first.sent.count, 1)

        model.appDidEnterBackground()
        await clock.settle()
        XCTAssertEqual(model.state.status, .paused)
        XCTAssertEqual(first.closed, .object(["code": .number(1000), "reason": .string("client")]))

        model.appWillEnterForeground()
        await clock.settle()
        XCTAssertEqual(model.state.status, .connecting)
        XCTAssertEqual(script.tokens, [false, false])
        try script.resolveToken("tok", "resume")
        await clock.settle()
        XCTAssertEqual(script.sockets.count, 2)
        let second = try script.newest("resume")
        second.handlers.onOpen()
        XCTAssertEqual(second.sent, [.object(["t": .string("hello"), "v": .number(1), "last": .number(101)])])

        // The app's own pause is not undone by the foreground.
        model.pause()
        model.appWillEnterForeground()
        await clock.settle()
        XCTAssertEqual(model.state.status, .paused)
        XCTAssertEqual(script.sockets.count, 2)

        model.join()
        await clock.settle()
        XCTAssertEqual(model.state.status, .connecting)

        model.leave()
        XCTAssertEqual(model.state.status, .closed)
        XCTAssertEqual(model.state.code, 1000)
        XCTAssertEqual(model.state.reason, "left")
    }
    #endif

    func testTraySendsTheRoomId() async throws {
        let rose = Gift(id: "rose", name: "Rose", price: 10)
        let client = RoomIdRecordingClient()
        let tray = GiftTrayController(client: client, receiver: "host", roomId: "live_1")
        await tray.send(rose)
        tray.roomId = ""
        await tray.send(rose)
        tray.roomId = nil
        await tray.send(rose)
        let sent = await client.roomIds
        XCTAssertEqual(sent, ["live_1", nil, nil], "an empty room id names no room")
    }

    func testClientPutsRoomIdInTheBody() async throws {
        let transport = BodyRecordingTransport()
        let client = GiftingClient(getToken: { _ in "tok" }, transport: transport)
        _ = try await client.sendGift(SendGiftInput(receiver: "host", giftId: "rose", roomId: "live_1"))
        _ = try await client.sendGift(SendGiftInput(receiver: "host", giftId: "rose"))
        let bodies = await transport.bodies
        XCTAssertEqual(bodies.count, 2)
        let withRoom = try JSONValue.parse(try XCTUnwrap(bodies.first ?? nil))
        XCTAssertEqual(withRoom["room_id"], JSONValue.string("live_1"))
        let withoutRoom = try JSONValue.parse(try XCTUnwrap(bodies.last ?? nil))
        XCTAssertNil(withoutRoom["room_id"], "no room: the key is left out")
    }
}

private func roomTestTransaction() -> GiftTransaction {
    GiftTransaction(
        id: "gtx_1",
        sender: "me",
        receiver: "host",
        gift: GiftSummary(id: "rose", name: "Rose"),
        quantity: 1,
        unitPrice: 10,
        total: 10,
        status: "completed",
        createdAt: "2026-10-12T00:00:00.000Z",
        senderBalanceAfter: 90
    )
}

/// Records the `roomId` of every send.
private actor RoomIdRecordingClient: GiftingAPI {
    var roomIds: [String?] = []

    func getGifts() async throws -> [Gift] {
        []
    }

    func getMe() async throws -> Me {
        Me(user: "me", balance: 100)
    }

    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        []
    }

    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        roomIds.append(input.roomId)
        return roomTestTransaction()
    }
}

/// Answers every request with a gift transaction and keeps the request bodies.
private actor BodyRecordingTransport: GiftingTransport {
    var bodies: [Data?] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        bodies.append(request.body)
        return HTTPResponse(status: 201, body: try JSONEncoder().encode(roomTestTransaction()))
    }
}
