import Foundation
import XCTest
@testable import GiftingStack

/// Battle scores on the session (SPEC 18.6): `RoomClient` keeps the round from `welcome` and
/// `scores` frames, the server clock offset, and survives app callbacks. The wire parsing and
/// `battleView` run in RoomsConformanceTests (rooms-battle.json).
@MainActor
final class RoomBattleSessionTests: XCTestCase {
    private static func battleJSON(_ ava: Int, _ mateo: Int) -> String {
        let avaGifts = ava > 0 ? 1 : 0
        let mateoGifts = mateo > 0 ? 1 : 0
        return #"{"round":"r1","started":1000,"ends":61000,"scores":[{"id":"ava","units":\#(ava),"gifts":\#(avaGifts)},{"id":"mateo","units":\#(mateo),"gifts":\#(mateoGifts)}]}"#
    }

    private static func battleOf(_ ava: Int, _ mateo: Int) -> RoomBattle {
        RoomBattle(
            round: "r1",
            started: 1000,
            ends: 61000,
            scores: [
                RoomScoreEntry(id: "ava", units: ava, gifts: ava > 0 ? 1 : 0),
                RoomScoreEntry(id: "mateo", units: mateo, gifts: mateo > 0 ? 1 : 0),
            ]
        )
    }

    private static func welcome(now: Int = 1000, battle: String? = nil) -> String {
        let extra = battle.map { #","battle":\#($0)"# } ?? ""
        return #"{"t":"welcome","v":1,"viewers":3,"gap":false,"replay":[],"ttl":3600,"now":\#(now)\#(extra)}"#
    }

    private struct Session {
        let clock: FakeGiftClock
        let script: RoomSessionScript
        let room: RoomClient
    }

    private func open() async throws -> Session {
        let clock = FakeGiftClock()
        let script = RoomSessionScript()
        let room = RoomClient(
            room: "live_1",
            getToken: { force in
                try await script.token(force)
            },
            socket: { url, protocols, handlers in
                script.open(url, protocols, handlers)
            },
            heartbeatMs: 0,
            clock: clock
        )
        room.start()
        await clock.settle()
        try script.resolveToken("tok", "start")
        await clock.settle()
        try script.newest("open").handlers.onOpen()
        return Session(clock: clock, script: script, room: room)
    }

    func testTakesTheRoundFromWelcomeThenEachScoresFrameNilWhenRemoved() async throws {
        let s = try await open()
        var seen: [RoomBattle?] = []
        var viaCallback: [RoomBattle?] = []
        s.room.subscribeBattle { seen.append($0) }
        s.room.onBattle = { viaCallback.append($0) }
        let socket = try s.script.newest("socket")
        XCTAssertNil(s.room.battle)
        XCTAssertNil(s.room.serverNow())
        // Local clock 0 at the welcome, server clock 31,000: offset 31,000.
        socket.handlers.onMessage(RoomBattleSessionTests.welcome(now: 31_000, battle: RoomBattleSessionTests.battleJSON(0, 0)))
        XCTAssertEqual(s.room.battle, RoomBattleSessionTests.battleOf(0, 0))
        XCTAssertEqual(s.room.serverNow(), 31_000)
        socket.handlers.onMessage(#"{"t":"scores","battle":\#(RoomBattleSessionTests.battleJSON(300, 100))}"#)
        s.clock.advance(10_000)
        let view = try XCTUnwrap(s.room.battleView())
        XCTAssertTrue(view.open)
        XCTAssertEqual(view.remainingMs, 20_000)
        XCTAssertEqual(view.total, 400)
        XCTAssertEqual(view.leader, "ava")
        socket.handlers.onMessage(#"{"t":"scores","battle":null}"#)
        XCTAssertNil(s.room.battle)
        XCTAssertNil(s.room.battleView())
        let expected: [RoomBattle?] = [RoomBattleSessionTests.battleOf(0, 0), RoomBattleSessionTests.battleOf(300, 100), nil]
        XCTAssertEqual(seen, expected)
        XCTAssertEqual(viaCallback, expected)
    }

    func testIgnoresMalformedScoresAndKeepsTheRoundAcrossAReconnectUntilTheNextWelcome() async throws {
        let s = try await open()
        let socket = try s.script.newest("socket")
        socket.handlers.onMessage(RoomBattleSessionTests.welcome(battle: RoomBattleSessionTests.battleJSON(5, 0)))
        socket.handlers.onMessage(#"{"t":"scores","battle":{"round":""}}"#)
        socket.handlers.onMessage(#"{"t":"scores"}"#)
        XCTAssertEqual(s.room.battle, RoomBattleSessionTests.battleOf(5, 0))
        socket.handlers.onClose(1006, "")
        XCTAssertEqual(s.room.state.status, .reconnecting)
        XCTAssertEqual(s.room.battle, RoomBattleSessionTests.battleOf(5, 0))
        s.room.reconnectNow()
        await s.clock.settle()
        try s.script.resolveToken("tok", "reconnect")
        await s.clock.settle()
        let second = try s.script.newest("second")
        second.handlers.onOpen()
        // The new welcome has no round: it was removed while we were away.
        second.handlers.onMessage(RoomBattleSessionTests.welcome())
        XCTAssertNil(s.room.battle)
    }

    func testAScoresFrameBeforeTheWelcomeIsIgnored() async throws {
        let s = try await open()
        let socket = try s.script.newest("socket")
        socket.handlers.onMessage(#"{"t":"scores","battle":\#(RoomBattleSessionTests.battleJSON(1, 2))}"#)
        XCTAssertNil(s.room.battle)
    }

    #if canImport(SwiftUI) && canImport(ImageIO)
    func testModelPublishesTheBattleAndTheView() async throws {
        let clock = FakeGiftClock()
        let script = RoomSessionScript()
        var seen: [String?] = []
        let model = GiftRoomModel(
            room: "live_1",
            getToken: { force in
                try await script.token(force)
            },
            onBattle: { seen.append($0?.round) },
            socket: { url, protocols, handlers in
                script.open(url, protocols, handlers)
            },
            clock: clock
        )
        model.join()
        await clock.settle()
        try script.resolveToken("tok", "join")
        await clock.settle()
        let socket = try script.newest("socket")
        socket.handlers.onOpen()
        socket.handlers.onMessage(RoomBattleSessionTests.welcome())
        XCTAssertNil(model.battle)
        XCTAssertNil(model.battleView())
        socket.handlers.onMessage(
            #"{"t":"scores","battle":{"round":"r1","started":0,"ends":100000000000000,"scores":[{"id":"ava","units":10,"gifts":1},{"id":"mateo","units":30,"gifts":2}]}}"#
        )
        XCTAssertEqual(model.battle?.round, "r1")
        let view = try XCTUnwrap(model.battleView())
        XCTAssertEqual(view.leader, "mateo")
        XCTAssertEqual(view.sides.map { $0.share }, [0.25, 0.75])
        socket.handlers.onMessage(#"{"t":"scores","battle":null}"#)
        XCTAssertNil(model.battle)
        XCTAssertEqual(seen, ["r1", nil])
        model.leave()
    }
    #endif
}
