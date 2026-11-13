import Foundation
import XCTest
@testable import GiftingStack

/// conformance/input-swap.json: the keyboard swap constants, inputSwapStep and keyboardPlaceHeight
/// (spec 20.2).
final class InputSwapConformanceTests: XCTestCase {
    private func event(_ value: JSONValue?, _ at: String) throws -> InputSwapEvent {
        let raw = try XCTUnwrap(value?.stringValue, "\(at): event")
        return try XCTUnwrap(InputSwapEvent(rawValue: raw), "\(at): event \(raw)")
    }

    private func check(_ got: InputSwapStep, _ expect: JSONValue?, _ at: String) {
        XCTAssertEqual(got.tray.rawValue, expect?["tray"]?.stringValue, "\(at) tray")
        XCTAssertEqual(got.input.rawValue, expect?["input"]?.stringValue, "\(at) input")
    }

    func testConstants() throws {
        let f = try Fixtures.conformance("input-swap.json")
        let c = try XCTUnwrap(f["constants"], "input-swap.json constants")
        XCTAssertEqual(keyboardPlaceFallback, c["fallback"]?.doubleValue)
        XCTAssertEqual(keyboardMinHeight, c["minKeyboard"]?.doubleValue)
        XCTAssertEqual(keyboardPlaceMaxFraction, c["maxFraction"]?.doubleValue)
    }

    func testStep() throws {
        let f = try Fixtures.conformance("input-swap.json")
        let cases = try Fixtures.list(f["step"], "input-swap.json step")
        XCTAssertEqual(cases.count, 4)
        for (i, c) in cases.enumerated() {
            let at = "[input-swap.json step] #\(i + 1)"
            let got = inputSwapStep(open: try XCTUnwrap(c["open"]?.boolValue, at), event: try event(c["event"], at))
            check(got, c["expect"], at)
        }
    }

    func testPlace() throws {
        let f = try Fixtures.conformance("input-swap.json")
        let cases = try Fixtures.list(f["place"], "input-swap.json place")
        XCTAssertEqual(cases.count, 11)
        for (i, c) in cases.enumerated() {
            let at = "[input-swap.json place] #\(i + 1) \(c["note"]?.stringValue ?? "")"
            // A missing key or JSON null is nil.
            let got = keyboardPlaceHeight(
                keyboardHeight: c["keyboardHeight"]?.doubleValue,
                containerHeight: c["containerHeight"]?.doubleValue
            )
            XCTAssertEqual(got, c["expect"]?.intValue, at)
        }
    }

    func testSequence() throws {
        let f = try Fixtures.conformance("input-swap.json")
        for s in try Fixtures.list(f["sequence"], "input-swap.json sequence") {
            let name = s["name"]?.stringValue ?? "?"
            var open = try XCTUnwrap(s["open"]?.boolValue, "\(name) open")
            for (i, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
                let at = "[input-swap.json sequence] \(name) step \(i + 1)"
                let got = inputSwapStep(open: open, event: try event(step["event"], at))
                check(got, step["expect"], at)
                switch got.tray {
                case .open:
                    open = true
                case .close:
                    open = false
                case .keep:
                    break
                }
                XCTAssertEqual(open, step["open"]?.boolValue, "\(at) open")
            }
        }
    }

    func testPlaceSnapIsAFractionOfTheContainer() {
        XCTAssertNil(keyboardPlaceSnap(keyboardHeight: 336, containerHeight: nil))
        XCTAssertNil(keyboardPlaceSnap(keyboardHeight: 336, containerHeight: 0))
        XCTAssertEqual(keyboardPlaceSnap(keyboardHeight: 336, containerHeight: 800) ?? 0, 0.42, accuracy: 1e-9)
        XCTAssertEqual(keyboardPlaceSnap(keyboardHeight: nil, containerHeight: 600) ?? 0, 0.5, accuracy: 1e-9)
    }
}
