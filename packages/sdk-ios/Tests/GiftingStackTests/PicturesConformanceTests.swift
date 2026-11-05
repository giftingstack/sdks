import Foundation
import XCTest
@testable import GiftingStack

/// conformance/pictures.json (SPEC 7.6): which picture URLs are drawn and how long a failure is remembered.
final class PicturesConformanceTests: XCTestCase {
    func testTheConstantsEqualTheFixture() throws {
        let f = try Fixtures.conformance("pictures.json")
        XCTAssertEqual(f["maxBytes"]?.intValue, pictureMaxBytes)
        XCTAssertEqual(f["failureMemoryMs"]?.intValue, pictureFailureMemoryMs)
    }

    func testEveryURLIsAllowedOrRefused() throws {
        let f = try Fixtures.conformance("pictures.json")
        for u in try Fixtures.list(f["urls"], "pictures.json urls") {
            let url = try XCTUnwrap(u["url"]?.stringValue, "\(u)")
            let allowed = try XCTUnwrap(u["allowed"]?.boolValue, "\(u)")
            XCTAssertEqual(isPictureUrl(url), allowed, "[pictures.json] url: \(url)")
        }
    }

    func testADataURLIsAllowedUpToTheLimit() throws {
        let f = try Fixtures.conformance("pictures.json")
        let prefix = "data:image/png;base64,"
        let cases = try Fixtures.list(f["dataUrlSize"]?["cases"], "pictures.json dataUrlSize.cases")
        for c in cases {
            let total = try XCTUnwrap(c["totalChars"]?.intValue, "\(c)")
            let allowed = try XCTUnwrap(c["allowed"]?.boolValue, "\(c)")
            let url = prefix + String(repeating: "A", count: total - prefix.count)
            XCTAssertEqual(url.count, total)
            XCTAssertEqual(isPictureUrl(url), allowed, "[pictures.json] data url of \(total) characters")
        }
    }

    func testFailuresAreRememberedForAMinuteAtMost200() throws {
        let f = try Fixtures.conformance("pictures.json")
        for s in try Fixtures.list(f["failures"], "pictures.json failures") {
            let name = s["name"]?.stringValue ?? "?"
            var memory = PictureFailures()
            for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
                let at = "[pictures.json] \(name): step \(index + 1)"
                let atMs = try XCTUnwrap(step["atMs"]?.intValue, at)
                if let url = step["fail"]?.stringValue {
                    memory.fail(url, atMs: atMs)
                }
                if let many = step["failMany"] {
                    let prefix = try XCTUnwrap(many["prefix"]?.stringValue, at)
                    let count = try XCTUnwrap(many["count"]?.intValue, at)
                    for n in 0..<count {
                        memory.fail(prefix + String(n), atMs: atMs)
                    }
                }
                if let failed = step["failed"]?.objectValue {
                    for (url, want) in failed {
                        XCTAssertEqual(memory.has(url, atMs: atMs), want.boolValue, "\(at) \(url)")
                    }
                }
            }
        }
    }
}
