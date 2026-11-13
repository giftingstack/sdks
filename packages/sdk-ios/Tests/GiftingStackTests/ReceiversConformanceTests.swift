import Foundation
import XCTest
@testable import GiftingStack

/// conformance/receivers.json: `resolveReceiver` (spec 21.2).
final class ReceiversConformanceTests: XCTestCase {
    func testResolve() throws {
        let f = try Fixtures.conformance("receivers.json")
        let cases = try Fixtures.list(f["resolve"], "receivers.json resolve")
        XCTAssertEqual(cases.count, 9)
        for (i, c) in cases.enumerated() {
            let at = "[receivers.json resolve] #\(i + 1) \(c["note"]?.stringValue ?? "")"
            let ids = try XCTUnwrap(c["ids"]?.arrayValue, "\(at): ids").map { value -> String in
                guard let id = value.stringValue else {
                    XCTFail("\(at): an id is not a string")
                    return ""
                }
                return id
            }
            // A missing key or JSON null is nil.
            let got = resolveReceiver(
                ids: ids,
                selected: c["selected"]?.stringValue,
                last: c["last"]?.stringValue,
                fallback: c["fallback"]?.stringValue
            )
            XCTAssertEqual(got, c["expect"]?.stringValue, at)
        }
    }

    func testDefaultLabels() {
        XCTAssertEqual(defaultSendToLabel, "Send to")
        XCTAssertEqual(defaultPressSideLabel, "Send {name} a gift")
    }
}
