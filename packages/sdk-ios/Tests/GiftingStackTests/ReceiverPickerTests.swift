#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI
import XCTest
@testable import GiftingStack

/// Spec 21: one gift button for a battle. The receiver picker of `GiftTrayModel` (`receivers`, `selectReceiver`,
/// `receiver`, `onReceiverChange`, the side of the last send) and the tray's "Send to" row.
@MainActor
final class ReceiverPickerTests: XCTestCase {
    private let sides = [
        TrayReceiver(id: "mia", name: "Mia", color: "#ff5d8f"),
        TrayReceiver(id: "theo", name: "Theo"),
    ]

    private func makeModel(
        client: InstantClient = InstantClient(balance: 1000, gifts: sampleGifts),
        receiver: String = "host",
        receivers: [TrayReceiver] = [],
        onReceiverChange: ((String) -> Void)? = nil
    ) -> GiftTrayModel {
        GiftTrayModel(client: client, receiver: receiver, receivers: receivers, onReceiverChange: onReceiverChange)
    }

    func testWithoutReceiversTheTrayIsAsBefore() async {
        let client = RecordingReceiverClient()
        let model = GiftTrayModel(client: client, receiver: "host")
        XCTAssertEqual(model.receivers, [])
        XCTAssertEqual(model.receiver, "host")
        model.selectReceiver("mia")
        XCTAssertEqual(model.receiver, "host", "no receivers: a pick is ignored")
        await model.sendAndWait(sampleGifts[0])
        let sent = await client.receivers
        XCTAssertEqual(sent, ["host"])
        XCTAssertNil(model.lastReceiver)
    }

    func testTheFirstSideByDefault() {
        let model = makeModel(receivers: sides)
        XCTAssertEqual(model.receiver, "mia")
        XCTAssertNil(model.selectedReceiver)
    }

    func testThePlainReceiverIsTheFallbackWhenItIsASide() {
        let model = makeModel(receiver: "theo", receivers: sides)
        XCTAssertEqual(model.receiver, "theo")
    }

    func testSelectReceiverPicksASideAndIgnoresOthers() {
        var changes: [String] = []
        let model = makeModel(receivers: sides, onReceiverChange: { changes.append($0) })
        model.selectReceiver("theo")
        XCTAssertEqual(model.receiver, "theo")
        XCTAssertEqual(model.selectedReceiver, "theo")
        model.selectReceiver("zoe")
        XCTAssertEqual(model.receiver, "theo", "an id that is not a side is ignored")
        XCTAssertEqual(model.selectedReceiver, "theo")
        model.selectReceiver("theo")
        XCTAssertEqual(changes, ["theo"], "onReceiverChange only when the side changed")
    }

    func testEverySendGoesToThePickedSideAndSetsLast() async {
        let client = RecordingReceiverClient()
        let model = GiftTrayModel(client: client, receiver: "host", receivers: sides)
        await model.sendAndWait(sampleGifts[0])
        model.selectReceiver("theo")
        await model.sendAndWait(sampleGifts[0])
        let sent = await client.receivers
        XCTAssertEqual(sent, ["mia", "theo"])
        XCTAssertEqual(model.lastReceiver, "theo")
    }

    func testAFailedSendDoesNotSetLast() async {
        let client = InstantClient(balance: 1000, gifts: sampleGifts)
        await client.setFailNextSend(GiftingError(status: 402, type: "insufficient_balance", message: "no"))
        let model = makeModel(client: client, receivers: sides)
        model.selectReceiver("theo")
        await model.sendAndWait(sampleGifts[0])
        XCTAssertNil(model.lastReceiver)
    }

    func testANewListKeepsThePickWhenItIsStillThere() {
        let model = makeModel(receivers: sides)
        model.selectReceiver("theo")
        model.receivers = sides + [TrayReceiver(id: "ava", name: "Ava")]
        XCTAssertEqual(model.receiver, "theo")
    }

    func testANewRoundStartsAtTheSideGiftedLast() async {
        var changes: [String] = []
        let model = makeModel(receivers: sides, onReceiverChange: { changes.append($0) })
        model.selectReceiver("theo")
        await model.sendAndWait(sampleGifts[0])
        model.selectReceiver("mia")
        // The next round: Mia is gone, the pick is dropped; Theo got the last gift.
        model.receivers = [TrayReceiver(id: "ava", name: "Ava"), TrayReceiver(id: "theo", name: "Theo")]
        XCTAssertNil(model.selectedReceiver)
        XCTAssertEqual(model.receiver, "theo")
        XCTAssertEqual(changes, ["theo", "mia", "theo"])
        // And without a side gifted: the first.
        model.receivers = [TrayReceiver(id: "zoe", name: "Zoe"), TrayReceiver(id: "kai", name: "Kai")]
        XCTAssertEqual(model.receiver, "zoe")
    }

    func testEmptyingTheListGoesBackToThePlainReceiver() async {
        let client = RecordingReceiverClient()
        let model = GiftTrayModel(client: client, receiver: "host", receivers: sides)
        model.selectReceiver("theo")
        model.receivers = []
        XCTAssertEqual(model.receiver, "host")
        await model.sendAndWait(sampleGifts[0])
        let sent = await client.receivers
        XCTAssertEqual(sent, ["host"])
    }

    func testOneSideTakesTheSend() async {
        let client = RecordingReceiverClient()
        let model = GiftTrayModel(client: client, receiver: "host", receivers: [TrayReceiver(id: "mia", name: "Mia")])
        XCTAssertEqual(model.receiver, "mia")
        await model.sendAndWait(sampleGifts[0])
        let sent = await client.receivers
        XCTAssertEqual(sent, ["mia"])
    }

    func testTheEffectSaysWhichSideGotIt() async {
        let player = StubEffectPlayer()
        let model = makeModel(receivers: sides)
        model.controller.effects = { player }
        model.controller.receiverOf = { GiftEffectReceiver(name: $0.capitalized, side: $0 == "mia" ? 0 : 1) }
        model.selectReceiver("theo")
        await model.sendAndWait(sampleGifts[0])
        XCTAssertEqual(player.played.first?.event.receiver, GiftEffectReceiver(name: "Theo", side: 1))
    }

    // MARK: - The tray view

    func testTheRowNeedsTwoSides() {
        let none = GiftTray(gifts: sampleGifts, balance: 100, onSend: { _ in })
        XCTAssertFalse(none.showsReceiverRow)
        let one = GiftTray(gifts: sampleGifts, balance: 100, onSend: { _ in }, receivers: [sides[0]])
        XCTAssertFalse(one.showsReceiverRow)
        let two = GiftTray(gifts: sampleGifts, balance: 100, onSend: { _ in }, receivers: sides)
        XCTAssertTrue(two.showsReceiverRow)
        XCTAssertEqual(two.sendToLabel, "Send to")
        XCTAssertEqual(two.shownReceiver, "mia")
    }

    func testTheTrayFollowsTheModel() {
        let model = makeModel(receivers: sides)
        model.selectReceiver("theo")
        let tray = GiftTray(tray: model, sendToLabel: "Gift to")
        XCTAssertEqual(tray.receivers, sides)
        XCTAssertEqual(tray.shownReceiver, "theo")
        XCTAssertEqual(tray.sendToLabel, "Gift to")
        tray.onSelectReceiver?("mia")
        XCTAssertEqual(model.receiver, "mia")
    }

    func testSideColoursAreTheOwnColourElseTheBattlePalette() {
        let tray = GiftTray(gifts: sampleGifts, balance: 100, onSend: { _ in }, theme: .dark, receivers: sides)
        XCTAssertEqual(tray.receiverSideColor(sides[0], index: 0).color, Color(giftingCSS: "#ff5d8f"))
        XCTAssertEqual(tray.receiverSideColor(sides[1], index: 1).color, GiftingTheme.dark.coin)
        XCTAssertEqual(tray.receiverSideColor(TrayReceiver(id: "a", name: "A"), index: 0).color, GiftingTheme.dark.accent)
        XCTAssertEqual(tray.receiverSideColor(TrayReceiver(id: "c", name: "C"), index: 2).color, Color(giftingCSS: "#2ec4b6"))
        XCTAssertEqual(tray.receiverSideColor(TrayReceiver(id: "e", name: "E"), index: 4).color, GiftingTheme.dark.accent)
    }
}

/// Records the receiver of every send.
private actor RecordingReceiverClient: GiftingAPI {
    var receivers: [String] = []

    func getGifts() async throws -> [Gift] {
        sampleGifts
    }

    func getMe() async throws -> Me {
        Me(user: "me", balance: 1000)
    }

    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        []
    }

    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        receivers.append(input.receiver)
        return GiftTransaction(
            id: "gtx_\(receivers.count)",
            sender: "me",
            receiver: input.receiver,
            gift: GiftSummary(id: input.giftId, name: "Rose"),
            quantity: 1,
            unitPrice: 10,
            total: 10,
            status: "completed",
            createdAt: "2026-11-13T00:00:00.000Z",
            senderBalanceAfter: 990
        )
    }
}
#endif
