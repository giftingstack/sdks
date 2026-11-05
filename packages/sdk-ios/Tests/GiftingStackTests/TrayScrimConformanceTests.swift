import Foundation
import XCTest
@testable import GiftingStack

/// conformance/tray-scrim.json: the scrim constants, scrimVisible, scrimFadeMs, scrimTapOutcome and
/// TrayOpenState (spec 9.4).
final class TrayScrimConformanceTests: XCTestCase {
    private func snap(_ value: JSONValue?, _ at: String) throws -> SheetSnap {
        let raw = try XCTUnwrap(value?.stringValue, "\(at): snap")
        return try XCTUnwrap(SheetSnap(rawValue: raw), "\(at): snap \(raw)")
    }

    func testConstants() throws {
        let f = try Fixtures.conformance("tray-scrim.json")
        let c = try XCTUnwrap(f["constants"], "tray-scrim.json constants")
        XCTAssertEqual(scrimFadeDurationMs, c["fadeMs"]?.intValue)
        XCTAssertEqual(scrimOpacity, c["opacity"]?.doubleValue)
    }

    func testVisible() throws {
        let f = try Fixtures.conformance("tray-scrim.json")
        let cases = try Fixtures.list(f["visible"], "tray-scrim.json visible")
        XCTAssertEqual(cases.count, 24)
        for (i, c) in cases.enumerated() {
            let at = "[tray-scrim.json visible] #\(i + 1)"
            let got = scrimVisible(
                scrim: try XCTUnwrap(c["scrim"]?.boolValue, at),
                open: try XCTUnwrap(c["open"]?.boolValue, at),
                snap: try snap(c["snap"], at),
                placed: try XCTUnwrap(c["placed"]?.boolValue, at)
            )
            XCTAssertEqual(got, c["expect"]?.boolValue, at)
        }
    }

    func testFade() throws {
        let f = try Fixtures.conformance("tray-scrim.json")
        for c in try Fixtures.list(f["fade"], "tray-scrim.json fade") {
            let name = "[tray-scrim.json fade] \(c["name"]?.stringValue ?? "?")"
            XCTAssertEqual(scrimFadeMs(reducedMotion: c["reducedMotion"]?.boolValue ?? false), c["ms"]?.intValue, name)
        }
    }

    func testTap() throws {
        let f = try Fixtures.conformance("tray-scrim.json")
        for (i, c) in try Fixtures.list(f["tap"], "tray-scrim.json tap").enumerated() {
            let at = "[tray-scrim.json tap] #\(i + 1)"
            let tap: ScrimTap = c["scrimTap"]?.stringValue == "dismiss" ? .dismiss : .lower
            let got = scrimTapOutcome(
                scrim: try XCTUnwrap(c["scrim"]?.boolValue, at),
                scrimTap: tap,
                open: try XCTUnwrap(c["open"]?.boolValue, at),
                snap: try snap(c["snap"], at)
            )
            XCTAssertEqual(got.rawValue, c["expect"]?.stringValue, at)
        }
    }

    func testOpenState() throws {
        let f = try Fixtures.conformance("tray-scrim.json")
        for s in try Fixtures.list(f["open"], "tray-scrim.json open") {
            let name = s["name"]?.stringValue ?? "?"
            var changes: [Bool] = []
            let state = TrayOpenState(open: s["open"]?.boolValue ?? true, onChange: { changes.append($0) })
            for (i, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
                let at = "[tray-scrim.json open] \(name) step \(i + 1)"
                if let call = step["call"]?.stringValue {
                    let got: Bool
                    switch call {
                    case "open":
                        got = state.open()
                    case "close":
                        got = state.close()
                    case "toggle":
                        got = state.toggle()
                    default:
                        XCTFail("\(at): unknown call \(call)")
                        continue
                    }
                    XCTAssertEqual(got, step["returns"]?.boolValue, "\(at) returns")
                } else if let e = step["expect"] {
                    XCTAssertEqual(state.isOpen, e["open"]?.boolValue, "\(at) open")
                    let want = (e["changes"]?.arrayValue ?? []).compactMap { $0.boolValue }
                    XCTAssertEqual(changes, want, "\(at) changes")
                } else {
                    XCTFail("\(at): unknown step")
                }
            }
        }
    }

    func testSubscribersRunBeforeOnChangeAndOnlyOnChange() {
        var order: [String] = []
        let state = TrayOpenState(open: true, onChange: { order.append("change:\($0)") })
        let stop = state.subscribe { order.append("sub:\(state.isOpen)") }
        state.open()
        state.close()
        XCTAssertEqual(order, ["sub:false", "change:false"])
        stop()
        state.open()
        XCTAssertEqual(order, ["sub:false", "change:false", "change:true"])
    }
}
