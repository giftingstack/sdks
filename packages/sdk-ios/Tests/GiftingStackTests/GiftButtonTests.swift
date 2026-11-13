#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI
import XCTest
@testable import GiftingStack

/// Spec 20: the gift button in the app's message bar. The keyboard swap on `GiftTrayModel` with an injected
/// focus setter (what `.giftTrayInput` installs), the keyboard's place on `GiftTray(tray:)`, and `GiftButton`.
@MainActor
final class GiftButtonTests: XCTestCase {
    private func makeModel(open: Bool? = nil, onOpenChange: ((Bool) -> Void)? = nil) -> GiftTrayModel {
        GiftTrayModel(
            client: InstantClient(balance: 1000, gifts: sampleGifts),
            receiver: "mert",
            open: open,
            onOpenChange: onOpenChange
        )
    }

    // MARK: - Open by default

    func testWithoutAFieldTheTrayStartsOpenAsBefore() {
        let model = makeModel()
        XCTAssertTrue(model.isOpen)
        XCTAssertFalse(model.inputBound)
        XCTAssertNil(model.keyboardHeight)
    }

    func testABoundFieldStartsTheTrayClosedWithoutOnOpenChange() {
        var changes: [Bool] = []
        let model = makeModel(onOpenChange: { changes.append($0) })
        model.bindInput { _ in }
        XCTAssertTrue(model.inputBound)
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(changes, [])
    }

    func testAnExplicitOpenWins() {
        let model = makeModel(open: true)
        model.bindInput { _ in }
        XCTAssertTrue(model.isOpen)
        let closed = makeModel(open: false)
        closed.bindInput { _ in }
        XCTAssertFalse(closed.isOpen)
    }

    func testABindingAfterTheHostOpenedOrClosedKeepsTheState() {
        let model = makeModel()
        model.close()
        model.open()
        model.bindInput { _ in }
        XCTAssertTrue(model.isOpen)
    }

    // MARK: - The swap

    func testToggleBlursBeforeOpeningAndClosesBeforeFocusing() {
        let model = makeModel()
        var log: [String] = []
        model.bindInput { focus in
            log.append("focus \(focus), open \(model.isOpen)")
        }
        XCTAssertTrue(model.toggle())
        XCTAssertEqual(log, ["focus false, open false"], "blur runs before open")
        XCTAssertTrue(model.isOpen)

        XCTAssertFalse(model.toggle())
        XCTAssertEqual(log, ["focus false, open false", "focus true, open false"], "close runs before focus")
        XCTAssertFalse(model.isOpen)
    }

    func testTheFieldsFocusClosesAnOpenTrayAndMovesNoFocus() {
        let model = makeModel()
        var focusCalls: [Bool] = []
        model.bindInput { focusCalls.append($0) }
        model.toggle()
        focusCalls = []
        model.inputFocused()
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(focusCalls, [])
        // Closed: nothing happens (the focus that `toggle()` causes is such an event).
        model.inputFocused()
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(focusCalls, [])
    }

    func testOpenBlursFirstAndCloseNeverMovesFocus() {
        let model = makeModel()
        var focusCalls: [Bool] = []
        model.bindInput { focusCalls.append($0) }
        XCTAssertTrue(model.open())
        XCTAssertEqual(focusCalls, [false])
        model.open()
        XCTAssertEqual(focusCalls, [false], "already open: no blur")
        model.close()
        XCTAssertEqual(focusCalls, [false])
    }

    func testOnOpenChangeFollowsTheSwap() {
        var changes: [Bool] = []
        let model = makeModel(onOpenChange: { changes.append($0) })
        model.bindInput { _ in }
        model.toggle()
        model.inputFocused()
        XCTAssertEqual(changes, [true, false])
    }

    func testUnbindingEndsTheSwapAndAnOldTokenKeepsANewerBinding() {
        let model = makeModel()
        var first: [Bool] = []
        var second: [Bool] = []
        let old = model.bindInput { first.append($0) }
        let current = model.bindInput { second.append($0) }
        model.unbindInput(old)
        XCTAssertTrue(model.inputBound)
        model.toggle()
        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [false])

        model.unbindInput(current)
        XCTAssertFalse(model.inputBound)
        model.toggle()
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(second, [false], "unbound: a plain toggle")
        model.inputFocused()
        XCTAssertFalse(model.isOpen)
    }

    func testWithoutAFieldInputFocusDoesNothing() {
        let model = makeModel()
        model.inputFocused()
        XCTAssertTrue(model.isOpen)
    }

    // MARK: - Keyboard height

    func testTheLastKeyboardHeightIsKept() {
        let model = makeModel()
        model.recordKeyboardHeight(336)
        XCTAssertEqual(model.keyboardHeight, 336)
        model.recordKeyboardHeight(0)
        XCTAssertEqual(model.keyboardHeight, 336, "the keyboard went down: kept")
        model.recordKeyboardHeight(44)
        XCTAssertEqual(model.keyboardHeight, 336, "an accessory bar is not a keyboard")
        model.recordKeyboardHeight(120)
        XCTAssertEqual(model.keyboardHeight, 120)
        model.recordKeyboardHeight(.infinity)
        XCTAssertEqual(model.keyboardHeight, 120)
    }

    func testTheTrayTakesTheKeyboardsPlace() {
        let model = makeModel()
        XCTAssertNil(GiftTray(tray: model).sheetSnaps(container: 800), "no field: the host's snaps")

        model.bindInput { _ in }
        let fallback = GiftTray(tray: model).sheetSnaps(container: 800)
        XCTAssertEqual(fallback?.default ?? 0, 300.0 / 800, accuracy: 1e-9)
        XCTAssertNil(GiftTray(tray: model).sheetSnaps(container: 0), "not measured yet")

        model.recordKeyboardHeight(336)
        let seen = GiftTray(tray: model, snaps: SheetSnaps(expanded: 0.8)).sheetSnaps(container: 800)
        XCTAssertEqual(seen?.default ?? 0, 0.42, accuracy: 1e-9)
        XCTAssertEqual(seen?.expanded, 0.8, "the host's other snaps stay")

        let hostDefault = GiftTray(tray: model, snaps: SheetSnaps(default: 0.5)).sheetSnaps(container: 800)
        XCTAssertEqual(hostDefault?.default, 0.5, "the host's default wins")
    }

    // MARK: - GiftButton

    func testAPressTogglesTheTrayThenCallsOnPress() {
        let model = makeModel()
        model.bindInput { _ in }
        var seen: [Bool] = []
        let button = GiftButton(tray: model, onPress: { seen.append(model.isOpen) })
        button.press()
        XCTAssertTrue(model.isOpen)
        button.press()
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(seen, [true, false], "onPress runs after the toggle")
    }

    func testADisabledButtonDoesNothing() {
        let model = makeModel()
        var presses = 0
        GiftButton(tray: model, disabled: true, onPress: { presses += 1 }).press()
        XCTAssertTrue(model.isOpen)
        XCTAssertEqual(presses, 0)
    }

    func testWithoutATrayOnPressIsTheOnlyAction() {
        var presses = 0
        GiftButton(onPress: { presses += 1 }).press()
        XCTAssertEqual(presses, 1)
    }

    func testTheFixedSizesMapToCircleAndGlyphBox() {
        XCTAssertEqual(GiftButtonSize.small.circle, 32, accuracy: 0.01)
        XCTAssertEqual(GiftButtonSize.medium.circle, 36, accuracy: 0.01)
        XCTAssertEqual(GiftButtonSize.large.circle, 44, accuracy: 0.01)
        XCTAssertEqual(GiftButtonSize.small.glyphBox, 19.56, accuracy: 0.01)
        XCTAssertEqual(GiftButtonSize.medium.glyphBox, 22, accuracy: 0.01)
        XCTAssertEqual(GiftButtonSize.large.glyphBox, 26.89, accuracy: 0.01)
    }

    func testTheDefaultSizeIsMediumAndTheIconIsOptional() {
        let button = GiftButton()
        XCTAssertEqual(button.size, GiftButtonSize.medium)
        XCTAssertNil(button.icon)
        let custom = GiftButton(size: .large, icon: { _ in AnyView(Color.clear) })
        XCTAssertEqual(custom.size, GiftButtonSize.large)
        XCTAssertNotNil(custom.icon)
    }

    func testTheGlyphColourRule() {
        let theme = GiftingTheme()
        XCTAssertEqual(GiftButton.glyphColor(theme: theme, filled: false, active: false), theme.accent)
        XCTAssertEqual(GiftButton.glyphColor(theme: theme, filled: false, active: true), theme.accent)
        XCTAssertEqual(GiftButton.glyphColor(theme: theme, filled: true, active: true), theme.accent)
        XCTAssertEqual(GiftButton.glyphColor(theme: theme, filled: true, active: false), theme.accentText)
    }

    func testTheGlyphFillsItsBoxLikeTheSpec() {
        let box = GiftGlyph().path(in: CGRect(x: 0, y: 0, width: 24, height: 24)).boundingRect
        XCTAssertEqual(box.minX, 3, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 21, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 21, accuracy: 0.01)
        let scaled = GiftGlyph().path(in: CGRect(x: 0, y: 0, width: 48, height: 48)).boundingRect
        XCTAssertEqual(scaled.maxX, 42, accuracy: 0.01)
    }

    func testAnIconIsScaledDownIntoTheGlyphBoxNeverUp() {
        let box = GiftButtonSize.medium.glyphBox
        XCTAssertEqual(GiftButton.iconFitScale(width: 10, height: 10, box: box), 1, accuracy: 0.0001)
        XCTAssertEqual(GiftButton.iconFitScale(width: 44, height: 22, box: box), 0.5, accuracy: 0.0001)
        XCTAssertEqual(GiftButton.iconFitScale(width: 22, height: 88, box: box), 0.25, accuracy: 0.0001)
        XCTAssertEqual(GiftButton.iconFitScale(width: 500, height: 500, box: box), 22 / 500, accuracy: 0.0001)
        XCTAssertEqual(GiftButton.iconFitScale(width: 0, height: 0, box: box), 1, accuracy: 0.0001)
    }
}
#endif
