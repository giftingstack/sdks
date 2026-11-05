import Foundation
import XCTest
@testable import GiftingStack

/// conformance/sheet.json: resolveSheetHeights and the TraySheetController (spec 9.1).
final class SheetConformanceTests: XCTestCase {
    private static let stepKeys: Set<String> = [
        "dragStart", "drag", "release", "returns", "cancel", "snapTo", "toggle", "step",
        "layout", "scrollOwner", "expect",
    ]
    private static let expectKeys: Set<String> = [
        "snap", "offset", "visibleHeight", "dragging", "gridScrollable", "heights", "snapChanges",
    ]

    func testHeights() throws {
        let f = try Fixtures.conformance("sheet.json")
        for c in try Fixtures.list(f["heights"], "sheet.json heights") {
            let name = "[sheet.json heights] \(c["name"]?.stringValue ?? "?")"
            let layout = try SheetConformanceTests.layout(try XCTUnwrap(c["layout"], name), name)
            let actual = SheetConformanceTests.heightsJSON(resolveSheetHeights(layout))
            assertJSONEqual(actual, try XCTUnwrap(c["expect"], name), name)
        }
    }

    func testScenarios() throws {
        let f = try Fixtures.conformance("sheet.json")
        let layouts = try XCTUnwrap(f["layouts"]?.objectValue, "sheet.json layouts")
        for s in try Fixtures.list(f["scenarios"], "sheet.json scenarios") {
            try runScenario(s, layouts: layouts)
        }
    }

    private func runScenario(_ s: JSONValue, layouts: [String: JSONValue]) throws {
        let name = s["name"]?.stringValue ?? "?"
        let layout = try SheetConformanceTests.resolveLayout(s["layout"], layouts, name)
        var initial = SheetSnap.default
        if let raw = s["initialSnap"]?.stringValue {
            initial = try XCTUnwrap(SheetSnap(rawValue: raw), "[sheet.json] \(name): initialSnap")
        }
        var changes: [String] = []
        let controller = TraySheetController(initialSnap: initial, layout: layout, onSnapChange: { snap in
            changes.append(snap.rawValue)
        })

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "[sheet.json] \(name) step \(index + 1)"
            for key in step.objectValue?.keys.sorted() ?? [] where !SheetConformanceTests.stepKeys.contains(key) {
                XCTFail("\(at): the runner does not know step key \(key)")
            }
            var returned: JSONValue?
            if step["dragStart"]?.boolValue == true {
                controller.dragStart()
            } else if let dy = step["drag"]?.doubleValue {
                controller.drag(dy)
            } else if let velocity = step["release"]?.doubleValue {
                returned = .string(controller.release(velocity).rawValue)
            } else if step["cancel"]?.boolValue == true {
                controller.cancel()
            } else if let raw = step["snapTo"]?.stringValue {
                controller.snapTo(try XCTUnwrap(SheetSnap(rawValue: raw), "\(at): snap \(raw)"))
            } else if step["toggle"]?.boolValue == true {
                returned = .string(controller.toggle().rawValue)
            } else if let direction = step["step"]?.intValue {
                returned = .string(controller.step(direction).rawValue)
            } else if let next = step["layout"] {
                controller.setLayout(try SheetConformanceTests.resolveLayout(next, layouts, at))
            } else if let ask = step["scrollOwner"] {
                let dy = try XCTUnwrap(ask["dy"]?.doubleValue, "\(at): dy")
                let top = try XCTUnwrap(ask["gridScrollTop"]?.doubleValue, "\(at): gridScrollTop")
                returned = .string(controller.scrollOwner(dy: dy, gridScrollTop: top).rawValue)
            } else if let x = step["expect"]?.objectValue {
                for key in x.keys.sorted() where !SheetConformanceTests.expectKeys.contains(key) {
                    XCTFail("\(at): the runner does not know expect key \(key)")
                }
                let st = controller.state
                if let v = x["snap"] {
                    assertJSONEqual(.string(st.snap.rawValue), v, "\(at) snap")
                }
                if let v = x["offset"] {
                    assertJSONEqual(.number(st.offset), v, "\(at) offset")
                }
                if let v = x["visibleHeight"] {
                    assertJSONEqual(.number(st.visibleHeight), v, "\(at) visibleHeight")
                }
                if let v = x["dragging"] {
                    assertJSONEqual(.bool(st.dragging), v, "\(at) dragging")
                }
                if let v = x["gridScrollable"] {
                    assertJSONEqual(.bool(st.gridScrollable), v, "\(at) gridScrollable")
                }
                if let v = x["heights"] {
                    assertJSONEqual(SheetConformanceTests.heightsJSON(st.heights), v, "\(at) heights")
                }
                if let v = x["snapChanges"] {
                    assertJSONEqual(.array(changes.map { .string($0) }), v, "\(at) snapChanges")
                }
            } else {
                XCTFail("\(at): unknown step \(step)")
            }
            if let expected = step["returns"] {
                let got = try XCTUnwrap(returned, "\(at): this step returns nothing")
                assertJSONEqual(got, expected, "\(at) returns")
            }
        }
    }

    // MARK: - Fixture helpers

    static func heightsJSON(_ h: SheetHeights) -> JSONValue {
        .object([
            "peek": .number(h.peek),
            "default": .number(h.default),
            "expanded": .number(h.expanded),
        ])
    }

    static func resolveLayout(_ value: JSONValue?, _ layouts: [String: JSONValue], _ context: String) throws -> SheetLayout {
        if let key = value?.stringValue {
            let named = try XCTUnwrap(layouts[key], "\(context): unknown layout \(key)")
            return try layout(named, context)
        }
        return try layout(try XCTUnwrap(value, "\(context): layout"), context)
    }

    /// A fixture layout. A `null` snap fraction means "not given" (README).
    static func layout(_ v: JSONValue, _ context: String) throws -> SheetLayout {
        let container = try XCTUnwrap(v["containerHeight"]?.doubleValue, "\(context): containerHeight")
        var snaps: SheetSnaps?
        if let s = v["snaps"]?.objectValue {
            snaps = SheetSnaps(
                peek: s["peek"]?.doubleValue,
                default: s["default"]?.doubleValue,
                expanded: s["expanded"]?.doubleValue
            )
        }
        return SheetLayout(
            containerHeight: container,
            snaps: snaps,
            peekMinHeight: v["peekMinHeight"]?.doubleValue,
            defaultMinHeight: v["defaultMinHeight"]?.doubleValue,
            contentHeight: v["contentHeight"]?.doubleValue
        )
    }

    // MARK: - Beyond the fixture

    func testDefaultsAreTheSpecNumbers() {
        XCTAssertEqual(TraySheetController.flickVelocity, 600)
        XCTAssertEqual(TraySheetController.defaultFractions.peek, 0)
        XCTAssertEqual(TraySheetController.defaultFractions.default, 0)
        XCTAssertEqual(TraySheetController.defaultFractions.expanded, 0.9)
        XCTAssertEqual(SheetSnap.allCases, [.peek, .default, .expanded])
    }

    func testObserversHearOnlyRealChanges() {
        let controller = TraySheetController(layout: SheetLayout(containerHeight: 800, peekMinHeight: 150, defaultMinHeight: 330))
        var calls = 0
        let stop = controller.subscribe { _ in calls += 1 }
        controller.release(0) // no drag: nothing changes
        XCTAssertEqual(calls, 0)
        controller.snapTo(.expanded)
        XCTAssertEqual(calls, 1)
        controller.snapTo(.expanded)
        XCTAssertEqual(calls, 1)
        stop()
        controller.snapTo(.peek)
        XCTAssertEqual(calls, 1)
    }

    func testVelocityFromTheLast100Ms() {
        var tracker = SheetVelocityTracker()
        XCTAssertEqual(tracker.velocity(), 0)
        tracker.add(t: 0, y: 0)
        tracker.add(t: 50, y: 30)
        tracker.add(t: 100, y: 60)
        XCTAssertEqual(tracker.velocity(), 600, accuracy: 1e-9)
        // A finger that rests 100 ms has speed 0.
        tracker.add(t: 200, y: 60)
        tracker.add(t: 300, y: 60)
        XCTAssertEqual(tracker.velocity(), 0, accuracy: 1e-9)
    }
}
