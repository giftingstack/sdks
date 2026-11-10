import Foundation
import XCTest
@testable import GiftingStack

/// The user's own gift in a battle (SPEC 18.4): the tray puts `receiverOf(receiver)` on the effect event it
/// plays at the tap. The tray.json scenarios do not know `receiverOf`.
@MainActor
final class TrayReceiverTests: XCTestCase {
    private func playedAtTap(receiverOf: ((String) -> GiftEffectReceiver?)?) async -> GiftEffectEvent? {
        let player = StubEffectPlayer()
        let controller = GiftTrayController(
            client: ScriptedTrayClient(),
            receiver: "bob",
            effects: { player },
            playOn: .tap,
            receiverOf: receiverOf
        )
        let rose = Gift(id: "rose", name: "Rose", price: 100)
        Task { await controller.send(rose) }
        // The effect plays at the tap, before the (never answered) send call.
        for _ in 0..<20 where player.played.isEmpty {
            await Task.yield()
        }
        return player.played.first?.event
    }

    func testTheUsersOwnGiftSaysWhoGotItInABattle() async {
        let event = await playedAtTap(receiverOf: { $0 == "bob" ? GiftEffectReceiver(name: "Bob", side: 1, color: nil) : nil })
        XCTAssertEqual(event?.receiver, GiftEffectReceiver(name: "Bob", side: 1, color: nil))
    }

    func testOutsideABattleTheEventHasNoReceiver() async {
        let event = await playedAtTap(receiverOf: { _ in nil })
        XCTAssertNotNil(event)
        XCTAssertNil(event?.receiver)
        let plain = await playedAtTap(receiverOf: nil)
        XCTAssertNil(plain?.receiver)
    }
}
