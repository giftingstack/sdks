import Foundation
import XCTest
@testable import GiftingStack

/// conformance/effects.json: the EffectScheduler traces and the picture gate timing.
@MainActor
final class EffectsConformanceTests: XCTestCase {
    private static let expectKeys: Set<String> = [
        "events", "active", "activeTiers", "queued", "ended", "notice",
        "noticeVisible", "noticeOwner", "noticeDurationMs",
    ]

    func testEverySchedulerScenario() throws {
        let f = try Fixtures.conformance("effects.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "effects.json gifts")
        for s in try Fixtures.list(f["scenarios"], "effects.json scenarios") {
            try runScenario(s, gifts: gifts)
        }
    }

    private func runScenario(_ s: JSONValue, gifts: [String: JSONValue]) throws {
        let name = s["name"]?.stringValue ?? "?"
        let options = s["options"]
        var clock: Double = 0
        let scheduler = EffectScheduler(
            comboWindowMs: options?["comboWindowMs"]?.intValue ?? GiftingSpec.comboWindowMs,
            now: { clock }
        )
        var thresholds = TierThresholds()
        if let medium = options?["thresholds"]?["mediumFrom"]?.intValue {
            thresholds.mediumFrom = medium
        }
        if let large = options?["thresholds"]?["largeFrom"]?.intValue {
            thresholds.largeFrom = large
        }
        scheduler.thresholds = thresholds
        if let quality = options?["quality"]?.stringValue {
            scheduler.quality = try XCTUnwrap(EffectQuality(rawValue: quality), "[effects.json] \(name): quality")
        }
        scheduler.reducedMotion = options?["reducedMotion"]?.boolValue ?? false

        let log = SchedulerLog()
        scheduler.listener = log

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "[effects.json] \(name) step \(index + 1)"
            if let play = step["play"] {
                if let t = step["atMs"]?.doubleValue {
                    clock = t
                }
                let key = try XCTUnwrap(play["gift"]?.stringValue, at)
                let gift = try XCTUnwrap(gifts[key], "\(at): unknown gift \(key)")
                let event = GiftEffectEvent(
                    gift: try giftInfo(gift, at),
                    sender: play["sender"]?.stringValue,
                    quantity: play["quantity"]?.intValue
                )
                let id = scheduler.play(event)
                if let expected = step["returns"]?.intValue {
                    XCTAssertEqual(id, expected, "\(at) play() id")
                }
            } else if let id = step["started"]?.intValue {
                scheduler.started(id)
            } else if let id = step["finished"]?.intValue {
                scheduler.finished(id)
            } else if let id = step["cancel"]?.intValue {
                scheduler.cancel(id)
            } else if step["clear"]?.boolValue == true {
                scheduler.clear()
            } else if step["noticeExpired"]?.boolValue == true {
                scheduler.noticeExpired()
            } else if let x = step["expect"]?.objectValue {
                for key in x.keys where !EffectsConformanceTests.expectKeys.contains(key) {
                    XCTFail("\(at): the runner does not know expect key \(key)")
                }
                if let events = x["events"] {
                    assertJSONEqual(.array(log.events.map { .string($0) }), events, "\(at) events")
                }
                if let active = x["active"] {
                    assertJSONEqual(ids(scheduler.active.map { $0.id }), active, "\(at) active")
                }
                if let tiers = x["activeTiers"] {
                    assertJSONEqual(.array(scheduler.active.map { .string($0.recipe.tier.rawValue) }), tiers, "\(at) activeTiers")
                }
                if let queued = x["queued"] {
                    assertJSONEqual(ids(scheduler.queued.map { $0.id }), queued, "\(at) queued")
                }
                if let ended = x["ended"] {
                    assertJSONEqual(ids(log.ended), ended, "\(at) ended")
                }
                if let notice = x["notice"] {
                    assertJSONEqual(noticeJSON(scheduler.noticeData), notice, "\(at) notice")
                }
                if let visible = x["noticeVisible"] {
                    assertJSONEqual(.bool(scheduler.noticeVisible), visible, "\(at) noticeVisible")
                }
                if let owner = x["noticeOwner"] {
                    assertJSONEqual(.number(Double(scheduler.noticeOwner)), owner, "\(at) noticeOwner")
                }
                if let duration = x["noticeDurationMs"] {
                    let actual: JSONValue = log.noticeDurationMs.map { .number(Double($0)) } ?? .null
                    assertJSONEqual(actual, duration, "\(at) noticeDurationMs")
                }
                log.events = []
            } else {
                XCTFail("\(at): unknown step \(step)")
            }
        }
    }

    private func giftInfo(_ gift: JSONValue, _ at: String) throws -> GiftEffectEvent.GiftInfo {
        // A missing `icon` key and `"icon": null` both mean no icon; both fall back to `image`.
        GiftEffectEvent.GiftInfo(
            id: try XCTUnwrap(gift["id"]?.stringValue, at),
            name: try XCTUnwrap(gift["name"]?.stringValue, at),
            price: try XCTUnwrap(gift["price"]?.intValue, at),
            image: gift["image"]?.stringValue,
            icon: gift["icon"]?.stringValue
        )
    }

    private func ids(_ values: [Int]) -> JSONValue {
        .array(values.map { .number(Double($0)) })
    }

    private func noticeJSON(_ data: NoticeData?) -> JSONValue {
        guard let data = data else {
            return .null
        }
        return .object([
            "id": .number(Double(data.id)),
            "senderName": .string(data.senderName),
            "giftName": .string(data.giftName),
            "image": data.image.map { JSONValue.string($0) } ?? .null,
            "count": .number(Double(data.count)),
            "big": .bool(data.big),
        ])
    }

    // MARK: - pictureGate

    /// The gate on a virtual clock: the picture loads or fails when the fixture says, the wait
    /// timer fires at `pictureWaitMs`. The fixture's rule is checked as the README states it:
    /// not started at `startsAtMs - 1`, started at `startsAtMs + toleranceMs` (or right after
    /// `play` for 0). This checks the decision logic the layer uses; the rendered timing on a
    /// device is an L3/L4 item.
    func testPictureGateCases() throws {
        let f = try Fixtures.conformance("effects.json")
        let gate = try XCTUnwrap(f["pictureGate"], "effects.json pictureGate")
        let tolerance = try XCTUnwrap(gate["toleranceMs"]?.doubleValue, "pictureGate toleranceMs")
        for c in try Fixtures.list(gate["cases"], "pictureGate cases") {
            let name = "[effects.json pictureGate] \(c["name"]?.stringValue ?? "?")"
            let hasPicture = try XCTUnwrap(c["image"]?.boolValue, name)
            let wait = try XCTUnwrap(c["pictureWaitMs"]?.intValue, name)
            let loadAt = c["loadAtMs"]?.doubleValue
            let errorAt = c["errorAtMs"]?.doubleValue
            let startsAt = try XCTUnwrap(c["startsAtMs"]?.doubleValue, name)

            if startsAt == 0 {
                XCTAssertTrue(
                    startedBy(0, hasPicture: hasPicture, wait: wait, loadAt: loadAt, errorAt: errorAt),
                    "\(name): started right after play"
                )
            } else {
                XCTAssertFalse(
                    startedBy(startsAt - 1, hasPicture: hasPicture, wait: wait, loadAt: loadAt, errorAt: errorAt),
                    "\(name): not yet at \(startsAt - 1) ms"
                )
                XCTAssertTrue(
                    startedBy(startsAt + tolerance, hasPicture: hasPicture, wait: wait, loadAt: loadAt, errorAt: errorAt),
                    "\(name): started by \(startsAt + tolerance) ms"
                )
            }
            XCTAssertEqual(
                startTime(hasPicture: hasPicture, wait: wait, loadAt: loadAt, errorAt: errorAt),
                startsAt,
                "\(name): exact start time"
            )
        }
    }

    /// Runs the gate with every event up to `limit` ms and says whether it started.
    private func startedBy(_ limit: Double, hasPicture: Bool, wait: Int, loadAt: Double?, errorAt: Double?) -> Bool {
        guard let start = startTime(hasPicture: hasPicture, wait: wait, loadAt: loadAt, errorAt: errorAt) else {
            return false
        }
        return start <= limit
    }

    /// The virtual time at which the gate fired, or nil if never.
    private func startTime(hasPicture: Bool, wait: Int, loadAt: Double?, errorAt: Double?) -> Double? {
        var now: Double = 0
        var startedAt: Double?
        let gate = PictureGate(hasPicture: hasPicture, pictureWaitMs: wait) {
            if startedAt == nil {
                startedAt = now
            }
        }
        guard let timeout = gate.begin() else {
            return startedAt
        }
        // (time, action); ties keep this order: load, error, timer.
        var events: [(Double, () -> Void)] = []
        if let t = loadAt {
            events.append((t, { gate.pictureLoaded() }))
        }
        if let t = errorAt {
            events.append((t, { gate.pictureFailed() }))
        }
        events.append((Double(timeout), { gate.waitElapsed() }))
        let ordered = events.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
        }
        for entry in ordered {
            now = entry.element.0
            entry.element.1()
        }
        return startedAt
    }

    // MARK: - Timeline numbers from spec 7.3

    func testEffectEndTimesMatchTheSpec() {
        XCTAssertEqual(EffectTimeline.totalMs(recipeFor(.small)), 1600)
        XCTAssertEqual(EffectTimeline.totalMs(recipeFor(.medium)), 2100)
        XCTAssertEqual(EffectTimeline.totalMs(recipeFor(.large)), 3850)
        XCTAssertEqual(EffectTimeline.totalMs(recipeFor(.large, quality: .low)), 3050)
    }

    func testTimelineFrameShape() {
        let recipe = recipeFor(.large)
        var seed = 0.0
        let layout = EffectLayout(recipe: recipe, width: 390, height: 844, origin: EffectPoint(x: 195, y: 726)) {
            seed = (seed + 0.37).truncatingRemainder(dividingBy: 1)
            return seed
        }
        XCTAssertEqual(layout.sparks.count, 50)
        XCTAssertEqual(layout.coins.count, 34)
        XCTAssertEqual(layout.stage, EffectPoint(x: 195, y: 844 * 0.38))

        let first = EffectTimeline.frame(at: 0, recipe: recipe, layout: layout)
        XCTAssertEqual(first.pictureOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(first.pictureScale, 0.3, accuracy: 1e-9)
        XCTAssertEqual(first.pictureCenter.x, 195, accuracy: 1e-9)
        XCTAssertEqual(first.pictureCenter.y, 726, accuracy: 1e-9)
        XCTAssertEqual(first.dimOpacity, 0, accuracy: 1e-9)

        let held = EffectTimeline.frame(at: 1500, recipe: recipe, layout: layout)
        XCTAssertEqual(held.pictureScale, 2.8, accuracy: 1e-9)
        XCTAssertEqual(held.pictureOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(held.pictureCenter.y, 844 * 0.38, accuracy: 1e-9)
        XCTAssertEqual(held.dimOpacity, 0.62, accuracy: 1e-9)

        let gone = EffectTimeline.frame(at: 900 + 1600 + 550, recipe: recipe, layout: layout)
        XCTAssertEqual(gone.pictureOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(gone.pictureScale, 2.8 * 0.55, accuracy: 1e-9)
        XCTAssertEqual(gone.dimOpacity, 0, accuracy: 1e-9)

        // Overshoot: back(1.3) passes the stage before settling.
        let mid = EffectTimeline.frame(at: 700, recipe: recipe, layout: layout)
        XCTAssertGreaterThan(mid.pictureScale, 2.8)
    }
}

/// Records the listener calls as the README's event strings.
@MainActor
final class SchedulerLog: EffectSchedulerListener {
    var events: [String] = []
    var ended: [Int] = []
    var noticeDurationMs: Int?

    func effectDidEnter(_ effect: ScheduledEffect) {
        events.append("enter:\(effect.id)")
    }

    func effectDidExit(_ effect: ScheduledEffect) {
        events.append("exit:\(effect.id)")
    }

    func effectDidEnd(_ effect: ScheduledEffect) {
        events.append("end:\(effect.id)")
        ended.append(effect.id)
    }

    func noticeDidShow(_ notice: NoticeData, durationMs: Int) {
        events.append("notice:\(notice.id)")
        noticeDurationMs = durationMs
    }

    func noticeDidHide() {
        events.append("noticeHide")
    }

    func effectsDidClear() {
        events.append("clear")
    }
}
