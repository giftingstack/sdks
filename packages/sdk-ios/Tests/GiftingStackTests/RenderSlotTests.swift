#if canImport(SwiftUI) && canImport(ImageIO)
import SwiftUI
import XCTest
@testable import GiftingStack

/// The render slots (`renderChip`, `renderRow`, `renderSummary`): the contexts carry the computed
/// data and a slot answering nil means "draw the default". Drawing itself needs a device.
@MainActor
final class RenderSlotTests: XCTestCase {
    private let rose = GiftSummary(id: "rose", name: "Rose")

    func testSlotsAreOptionalSoCurrentCallSitesStillCompile() {
        let loader = GiftWallLoader(query: { _, _ in })
        _ = GiftWall(loader: loader, user: "mert", data: [ReceivedGift(gift: rose, count: 12)])
        _ = GiftWall(
            loader: loader,
            user: "mert",
            data: [ReceivedGift(gift: rose, count: 12)],
            renderChip: { chip in AnyView(Text(verbatim: "mine \(chip.countText)")) }
        )
        _ = GiftWall(loader: loader, user: "mert", data: [], renderChip: { _ in nil })
    }

    func testChipContextCarriesTheCountAndTheTheme() {
        let theme = GiftingTheme()
        let chip = WallChipContext(gift: rose, count: 1200, countText: "1.2K", theme: theme)
        XCTAssertEqual(chip.gift.id, "rose")
        XCTAssertEqual(chip.count, 1200)
        XCTAssertEqual(chip.countText, "1.2K")
        let answer: ((WallChipContext) -> AnyView?) = { _ in nil }
        XCTAssertNil(answer(chip), "nil means the default chip")
    }

    func testRowContextCarriesTheScoreAndWhetherItIsMe() {
        let entry = LeaderboardEntry(rank: 1, user: "ayla", gifts: 120, units: 54000)
        let row = LeaderboardRowContext(
            entry: entry,
            rank: entry.rank,
            name: "Ayla K",
            avatarUrl: nil,
            metric: .units,
            score: entry.units,
            scoreText: "54K",
            isMe: true,
            theme: GiftingTheme()
        )
        XCTAssertEqual(row.rank, 1)
        XCTAssertEqual(row.score, 54000)
        XCTAssertEqual(row.scoreText, "54K")
        XCTAssertTrue(row.isMe)
    }

    func testSummaryContextCallbacksAreTheCardsActions() {
        var dismissed = 0
        var acked = 0
        let summary = AwaySummary(
            user: "me", since: "s", until: "e", cursor: "c", truncated: false,
            totalGifts: 74, totalUnits: 0, senderCount: 9, groups: [], topSenders: []
        )
        let context = AwaySummaryContext(
            summary: summary,
            title: "While you were away",
            headline: "74 gifts from 9 people",
            gifts: "74 gifts",
            people: "9 people",
            senders: [AwaySenderInfo(user: "ayla", name: "Ayla K", avatarUrl: nil, count: 3)],
            dismiss: { dismissed += 1 },
            ack: { acked += 1 },
            theme: GiftingTheme()
        )
        context.dismiss()
        context.ack()
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(acked, 1)
        XCTAssertEqual(context.senders.first?.name, "Ayla K")
    }
}
#endif
