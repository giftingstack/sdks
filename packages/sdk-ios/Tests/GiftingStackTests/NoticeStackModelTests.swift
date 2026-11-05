import XCTest
@testable import GiftingStack

final class NoticeStackModelTests: XCTestCase {
    private func notice(_ id: Int, sender: String = "ayla", count: Int = 1) -> NoticeData {
        NoticeData(id: id, senderName: sender, giftName: "Rose", image: nil, count: count, big: false)
    }

    func testTwoSendersMakeTwoLinesNewestLast() {
        var model = NoticeStackModel()
        XCTAssertEqual(model.show(notice(1, sender: "ayla")), .added(dropped: nil))
        XCTAssertEqual(model.show(notice(2, sender: "mert")), .added(dropped: nil))
        XCTAssertEqual(model.lines.map { $0.id }, [1, 2])
        XCTAssertEqual(model.lines.last?.data.senderName, "mert")
    }

    func testSameIdUpdatesInPlace() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        XCTAssertEqual(model.show(notice(1, count: 3)), .updated)
        XCTAssertEqual(model.lines.map { $0.id }, [1, 2])
        XCTAssertEqual(model.lines.first?.data.count, 3)
    }

    func testFourthLineDropsTheOldest() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        model.show(notice(3))
        XCTAssertEqual(model.show(notice(4)), .added(dropped: 1))
        XCTAssertEqual(model.lines.map { $0.id }, [2, 3, 4])
    }

    func testEachLineExpiresOnItsOwn() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        XCTAssertTrue(model.expire(id: 1))
        XCTAssertEqual(model.lines.map { $0.visible }, [false, true])
        XCTAssertFalse(model.expire(id: 1), "already sliding out")
        XCTAssertTrue(model.removeHidden(id: 1))
        XCTAssertEqual(model.lines.map { $0.id }, [2])
        XCTAssertFalse(model.expire(id: 99), "unknown id")
    }

    func testExpiredIdComesBackAsANewBottomLine() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        model.expire(id: 1)
        XCTAssertEqual(model.show(notice(1)), .added(dropped: nil))
        XCTAssertEqual(model.lines.map { $0.id }, [2, 1])
        XCTAssertEqual(model.lines.map { $0.visible }, [true, true])
        XCTAssertFalse(model.removeHidden(id: 1), "the new line is not removed by the old timer")
    }

    func testHideRemovesOnlyTheNewest() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        XCTAssertEqual(model.hideNewest(), 2)
        XCTAssertEqual(model.lines.map { $0.visible }, [true, false])
        XCTAssertEqual(model.hideNewest(), 1, "next newest visible one")
        XCTAssertNil(model.hideNewest())
    }

    func testClearRemovesAll() {
        var model = NoticeStackModel()
        model.show(notice(1))
        model.show(notice(2))
        model.clear()
        XCTAssertTrue(model.lines.isEmpty)
    }
}
