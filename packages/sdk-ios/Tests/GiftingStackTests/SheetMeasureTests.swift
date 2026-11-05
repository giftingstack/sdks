import Foundation
import XCTest
@testable import GiftingStack

/// The sheet's measurement -> SheetLayout step and the grid momentum (pure parts of the SwiftUI
/// sheet, spec 9.1). Numbers are an iPhone-like layout: container 797, handle + header 35,
/// footer 104, row 104, 4 columns.
final class SheetMeasureTests: XCTestCase {
    private func measure(gifts: Int, row: Double = 104, top: Double = 35, footer: Double = 104) -> SheetMeasure {
        SheetMeasure(
            containerHeight: 797,
            topBlockHeight: top,
            footerHeight: footer,
            rowHeight: row,
            giftCount: gifts,
            columns: 4,
            snaps: nil
        )
    }

    func testNinetyGiftsReachNinetyPercent() {
        let m = measure(gifts: 90)
        XCTAssertEqual(m.rows, 23)
        XCTAssertEqual(m.peekMinHeight, 151)
        let h = resolveSheetHeights(m.layout)
        XCTAssertEqual(h.peek, 151)
        XCTAssertEqual(h.default, 359)
        XCTAssertEqual(h.expanded, 717) // round(0.9 * 797), not capped by 2543 of content
    }

    func testTheGiftCountChangesTheCap() {
        // The bug: a layout built from the previous render's 12 gifts capped expanded at 463.
        XCTAssertEqual(resolveSheetHeights(measure(gifts: 12).layout).expanded, 463)
        XCTAssertNotEqual(measure(gifts: 12), measure(gifts: 90))
        XCTAssertEqual(resolveSheetHeights(measure(gifts: 90).layout).expanded, 717)
    }

    func testNoHeightsUntilTheFloorsAreMeasured() {
        let zero = SheetHeights(peek: 0, default: 0, expanded: 0)
        XCTAssertFalse(measure(gifts: 90, row: 0).floorsReady)
        XCTAssertEqual(resolveSheetHeights(measure(gifts: 90, row: 0).layout), zero)
        XCTAssertEqual(resolveSheetHeights(measure(gifts: 90, top: 0).layout), zero)
        XCTAssertEqual(resolveSheetHeights(measure(gifts: 90, footer: 0).layout), zero)
        // No gifts: no row to measure.
        let empty = measure(gifts: 0, row: 0)
        XCTAssertTrue(empty.floorsReady)
        XCTAssertEqual(resolveSheetHeights(empty.layout).expanded, 151)
    }

    func testAnEmptyCatalogIsReadyToShowWithoutAMeasuredRow() {
        // The view shows the sheet when `floorsReady` (it used to wait for a row height of 0 to become
        // positive, so a catalog with no gifts never showed the sheet).
        let empty = measure(gifts: 0, row: 0)
        XCTAssertTrue(empty.floorsReady)
        XCTAssertGreaterThan(resolveSheetHeights(empty.layout).expanded, 0)
        XCTAssertFalse(measure(gifts: 4, row: 0).floorsReady, "gifts need their first row measured")
        XCTAssertEqual(SheetMeasure.emptyFallbackMs, 700, "the fallback when nothing could be measured, like web")
    }

    func testGridViewportAndScrollRange() {
        let m = measure(gifts: 90)
        XCTAssertEqual(m.gridViewport(expanded: 717), 566)
        XCTAssertEqual(m.maxGridScroll(expanded: 717), 23 * 104 - 566)
        // Everything fits: no scrolling.
        let few = measure(gifts: 12)
        XCTAssertEqual(few.maxGridScroll(expanded: 463), 0)
        XCTAssertEqual(m.gridViewport(expanded: 100), 0)
    }

    func testMomentumDecaysToItsTotalDistance() {
        var run = SheetGridMomentum(velocity: 1000)
        XCTAssertEqual(run.totalDistance, 1000 / -log(0.998) / 1000, accuracy: 1e-9)
        var travelled = 0.0
        var frames = 0
        while !run.finished && frames < 10_000 {
            travelled += run.step(dtMs: 16)
            frames += 1
        }
        XCTAssertLessThan(frames, 10_000)
        XCTAssertLessThan(abs(run.velocity), SheetGridMomentum.minVelocity)
        // What is left below 20 pt/s is under 10 pt.
        let total = SheetGridMomentum(velocity: 1000).totalDistance
        XCTAssertLessThan(travelled, total)
        XCTAssertGreaterThan(travelled, total - 10)
    }

    func testMomentumStepIsExactForAnyFrameLength() {
        var a = SheetGridMomentum(velocity: -800)
        var b = SheetGridMomentum(velocity: -800)
        let one = a.step(dtMs: 32)
        let two = b.step(dtMs: 16) + b.step(dtMs: 16)
        XCTAssertEqual(one, two, accuracy: 1e-9)
        XCTAssertLessThan(one, 0)
        XCTAssertEqual(a.velocity, b.velocity, accuracy: 1e-9)
        XCTAssertTrue(SheetGridMomentum(velocity: 10).finished)
        XCTAssertTrue(SheetGridMomentum(velocity: .nan).finished)
    }
}
