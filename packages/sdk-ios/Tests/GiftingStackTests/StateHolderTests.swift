import Foundation
import XCTest
@testable import GiftingStack

/// A client that answers at once, for state holder tests.
actor InstantClient: GiftingAPI {
    var balance: Int
    var failNextSend: GiftingError?
    var livemode: Bool?
    let gifts: [Gift]

    init(balance: Int, gifts: [Gift]) {
        self.balance = balance
        self.gifts = gifts
    }

    func setLivemode(_ value: Bool?) {
        livemode = value
    }

    func setFailNextSend(_ error: GiftingError?) {
        failNextSend = error
    }

    func getGifts() async throws -> [Gift] {
        gifts
    }

    func getMe() async throws -> Me {
        Me(user: "ayla", balance: balance, livemode: livemode)
    }

    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        []
    }

    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        if let error = failNextSend {
            failNextSend = nil
            throw error
        }
        let gift = gifts.first { $0.id == input.giftId }
        let price = gift?.price ?? 0
        balance -= price
        return GiftTransaction(
            id: "gtx_\(input.giftId)",
            sender: "ayla",
            receiver: input.receiver,
            gift: GiftSummary(id: input.giftId, name: gift?.name ?? "?", iconUrl: gift?.iconUrl),
            quantity: 1,
            unitPrice: price,
            total: price,
            status: "completed",
            createdAt: "2026-10-10T00:00:00.000Z",
            senderBalanceAfter: balance
        )
    }
}

let sampleGifts: [Gift] = [
    Gift(id: "rose", name: "Rose", price: 10, iconUrl: nil, animationUrl: nil, sortOrder: 2),
    Gift(id: "hat", name: "Hat", price: 350, iconUrl: nil, animationUrl: nil, sortOrder: 1),
]

@MainActor
final class GiftTrayControllerLogicTests: XCTestCase {
    func testRefreshThenSendKeepsTheBalanceRight() async {
        let client = InstantClient(balance: 1000, gifts: sampleGifts)
        let controller = GiftTrayController(client: client, receiver: "mert")
        var changes = 0
        controller.subscribe { _ in changes += 1 }

        await controller.refresh()
        XCTAssertEqual(controller.state.gifts.map { $0.id }, ["hat", "rose"])
        XCTAssertEqual(controller.state.balance, 1000)
        XCTAssertEqual(controller.state.user, "ayla")
        XCTAssertFalse(controller.state.loading)
        XCTAssertGreaterThan(changes, 0)

        await controller.send(sampleGifts[0])
        XCTAssertEqual(controller.state.balance, 990, "optimistic")
        XCTAssertNil(controller.state.error)
    }

    func testFailedSendRefundsAndReports() async {
        let client = InstantClient(balance: 1000, gifts: sampleGifts)
        await client.setFailNextSend(GiftingError(status: 422, type: "insufficient_balance", message: "No."))
        var reported: [GiftingError] = []
        let controller = GiftTrayController(client: client, receiver: "mert", onError: { reported.append($0) })
        await controller.refresh()
        await controller.send(sampleGifts[1])
        XCTAssertEqual(controller.state.balance, 1000)
        XCTAssertEqual(controller.state.error?.insufficientBalance, true)
        XCTAssertEqual(reported.map { $0.type }, ["insufficient_balance"])
    }

    func testFormatCoinsUsesEnglishGrouping() {
        XCTAssertEqual(formatCoins(0), "0")
        XCTAssertEqual(formatCoins(999), "999")
        XCTAssertEqual(formatCoins(1000), "1,000")
        XCTAssertEqual(formatCoins(60000), "60,000")
        XCTAssertEqual(formatCoins(1234567), "1,234,567")
        XCTAssertEqual(formatCoins(-39000), "-39,000")
    }

    func testAsGiftingErrorKeepsTheMessageOfOtherErrors() {
        let e = asGiftingError(PlainError(message: "boom"))
        XCTAssertEqual(e.status, 0)
        XCTAssertEqual(e.type, "unknown_error")
        XCTAssertEqual(e.message, "boom")
        XCTAssertTrue(e.retryable)
    }
}

#if canImport(SwiftUI) && canImport(ImageIO)
@MainActor
final class SwiftUIStateHolderTests: XCTestCase {
    func testTrayModelMirrorsTheControllerAndPlaysOnTheEffectController() async {
        let client = InstantClient(balance: 1000, gifts: sampleGifts)
        let effects = GiftEffectController()
        effects.reducedMotion = false
        let model = GiftTrayModel(client: client, receiver: "mert", effects: effects)
        XCTAssertTrue(model.loading)

        await model.refreshAndWait()
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.balance, 1000)
        XCTAssertEqual(model.gifts.map { $0.id }, ["hat", "rose"])

        await model.sendAndWait(sampleGifts[1])
        XCTAssertEqual(model.balance, 650)
        // playOn tap: the medium gift entered the layer, sent by the signed-in user.
        XCTAssertEqual(effects.effects.count, 1)
        XCTAssertEqual(effects.effects.first?.event.sender, "ayla")
        XCTAssertEqual(effects.effects.first?.recipe.tier, .medium)
    }

    func testFailedSendTakesTheEffectBack() async {
        let client = InstantClient(balance: 1000, gifts: sampleGifts)
        await client.setFailNextSend(GiftingError(status: 503, type: "temporarily_unavailable", message: "Try again."))
        let effects = GiftEffectController()
        effects.reducedMotion = false
        let model = GiftTrayModel(client: client, receiver: "mert", effects: effects)
        await model.refreshAndWait()
        await model.sendAndWait(sampleGifts[1])
        XCTAssertEqual(model.balance, 1000)
        XCTAssertTrue(effects.effects.isEmpty, "cancelled")
        XCTAssertEqual(model.error?.retryable, true)
    }

    func testEffectControllerPublishesTheSchedulerDecisions() {
        let effects = GiftEffectController()
        effects.reducedMotion = false
        let rose = GiftEffectEvent(gift: GiftEffectEvent.GiftInfo(id: "rose", name: "Rose", price: 10, image: nil, icon: nil), sender: "ayla")
        let first = effects.play(rose)
        let second = effects.play(rose)
        XCTAssertEqual([first, second], [1, 2])
        XCTAssertEqual(effects.effects.map { $0.id }, [1, 2])
        XCTAssertTrue(effects.noticeLines.isEmpty, "the notice waits for the picture gate")

        effects.effectStarted(2)
        XCTAssertEqual(effects.noticeLines.count, 1)
        XCTAssertEqual(effects.noticeLines.last?.data.count, 2)
        XCTAssertEqual(effects.noticeLines.last?.visible, true)

        var ended: [EffectTier] = []
        effects.onEffectEnd = { _, tier in ended.append(tier) }
        effects.effectFinished(1)
        XCTAssertEqual(effects.effects.map { $0.id }, [2])
        XCTAssertEqual(ended, [.small])

        effects.cancel(2)
        XCTAssertTrue(effects.effects.isEmpty)
        XCTAssertEqual(effects.noticeLines.last?.visible, false, "the newest line slides out")

        effects.clear()
        XCTAssertTrue(effects.noticeLines.isEmpty)
        XCTAssertEqual(effects.play(rose), 3, "ids are never reused, not even after clear")
    }

    func testReducedMotionShowsOnlyTheNotice() {
        let effects = GiftEffectController()
        effects.reducedMotion = true
        let dragon = GiftEffectEvent(gift: GiftEffectEvent.GiftInfo(id: "dragon", name: "Dragon", price: 40000, image: nil, icon: nil))
        effects.play(dragon)
        XCTAssertTrue(effects.effects.isEmpty)
        XCTAssertEqual(effects.noticeLines.last?.data.big, true)
        XCTAssertEqual(effects.noticeLines.last?.data.senderName, "Someone")
    }
}
#endif

/// "Test mode" (SPEC 9): `me.livemode == false` turns on the tray badge; absent means live.
@MainActor
final class TestModeTests: XCTestCase {
    func testTrayStateFollowsLivemode() async {
        let cases: [(Bool?, Bool)] = [(false, true), (true, false), (nil, false)]
        for (livemode, expected) in cases {
            let client = InstantClient(balance: 5, gifts: sampleGifts)
            await client.setLivemode(livemode)
            let controller = GiftTrayController(client: client, receiver: "mert")
            XCTAssertFalse(controller.state.testMode)
            await controller.refresh()
            XCTAssertEqual(controller.state.testMode, expected, "livemode: \(String(describing: livemode))")
        }
    }

    func testMeReadsAndWritesLivemode() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Me.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode(#"{"user":"a","balance":1,"livemode":false}"#).livemode, false)
        XCTAssertNil(try decode(#"{"user":"a","balance":1}"#).livemode)
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Me(user: "a", balance: 1)))
        XCTAssertNil((written as? [String: Any])?["livemode"], "absent stays absent")
    }
}

#if canImport(SwiftUI) && canImport(ImageIO)
/// The "Test mode" badge follows the token by itself (SPEC 9): models report `me.livemode == false`
/// to the registry that `GiftTray(testMode: nil)` reads; an explicit value wins.
@MainActor
final class TestModeBadgeTests: XCTestCase {
    private var registry: GiftTrayTestModeRegistry { GiftTrayTestModeRegistry.shared }

    private func tray(testMode: Bool? = nil) -> GiftTray {
        GiftTray(gifts: sampleGifts, balance: 5, onSend: { _ in }, testMode: testMode)
    }

    private func makeModel(livemode: Bool?) async -> GiftTrayModel {
        let client = InstantClient(balance: 5, gifts: sampleGifts)
        await client.setLivemode(livemode)
        return GiftTrayModel(client: client, receiver: "mert")
    }

    func testATestTokenShowsTheBadgeWithoutTheHostPassingAnything() async {
        let model = await makeModel(livemode: false)
        XCTAssertFalse(tray().showsTestMode, "nothing is known before the first load")
        await model.refreshAndWait()
        XCTAssertTrue(model.testMode)
        XCTAssertTrue(tray().showsTestMode)
        model.stop()
        XCTAssertFalse(tray().showsTestMode, "a stopped model takes its report with it")
        model.start()
        XCTAssertTrue(tray().showsTestMode, "start() reports what the model already knows")
        model.stop()
    }

    func testALiveTokenAndAnOlderServerShowNoBadge() async {
        for livemode in [true, nil] as [Bool?] {
            let model = await makeModel(livemode: livemode)
            await model.refreshAndWait()
            XCTAssertFalse(model.testMode)
            XCTAssertFalse(tray().showsTestMode, "livemode: (String(describing: livemode))")
            model.stop()
        }
    }

    func testAnExplicitValueWins() async {
        let model = await makeModel(livemode: false)
        await model.refreshAndWait()
        XCTAssertFalse(tray(testMode: false).showsTestMode, "false forces the badge off")
        model.stop()
        XCTAssertTrue(tray(testMode: true).showsTestMode, "true shows it without any model")
    }

    func testTheTrayParameterTakesEverythingFromTheModel() async {
        let model = await makeModel(livemode: false)
        await model.refreshAndWait()
        let view = GiftTray(tray: model)
        XCTAssertTrue(view.showsTestMode)
        XCTAssertEqual(view.gifts.map { $0.id }, ["hat", "rose"], "the model's gifts, in sort order")
        XCTAssertEqual(view.balance, 5)
        XCTAssertFalse(GiftTray(tray: model, testMode: false).showsTestMode, "false forces it off")
        XCTAssertEqual(GiftTray(tray: model, balance: 99).balance, 99, "what you pass wins")
        model.stop()
        XCTAssertTrue(view.showsTestMode, "the view keeps what the model said when it was made")

        let live = await makeModel(livemode: true)
        await live.refreshAndWait()
        XCTAssertFalse(GiftTray(tray: live).showsTestMode)
        XCTAssertTrue(GiftTray(tray: live, testMode: true).showsTestMode, "true shows it whatever the token says")
        live.stop()
    }

    func testAReleasedModelForgetsItsReport() async {
        do {
            let model = await makeModel(livemode: false)
            await model.refreshAndWait()
            XCTAssertTrue(registry.active)
        }
        XCTAssertFalse(registry.active)
    }

    func testTheCatalogLoadFetchesTheIconsNotTheBigPictures() async {
        let gifts = [
            Gift(id: "a", name: "A", description: nil, price: 1, iconUrl: "https://t/a-icon", animationUrl: "https://t/a-anim", sortOrder: 0),
        ]
        let client = InstantClient(balance: 5, gifts: gifts)
        let controller = GiftTrayController(client: client, receiver: "mert")
        var seen: [String] = []
        controller.prefetch = { seen.append($0) }
        await controller.refresh()
        XCTAssertEqual(seen, ["https://t/a-icon"], "SPEC 8 step 2: icons only")
    }
}
#endif

/// Audit R-29: a server-supplied wait (`retry_after`) can be enormous; the real clock clamps it.
@MainActor
final class ClockLimitTests: XCTestCase {
    func testAnEnormousWaitDoesNotTrap() {
        let clock = SystemGiftClock()
        for ms in [Int.max, Int.max / 1000, 9_007_199_254_740_991 * 1000, Int.min, -1, 0] {
            let handle = clock.schedule(afterMs: ms) {}
            clock.cancel(handle)
        }
    }
}
