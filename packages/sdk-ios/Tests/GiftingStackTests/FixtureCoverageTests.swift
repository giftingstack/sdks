import Foundation
import XCTest

/// A new fixture file in packages/sdk-spec/conformance must not slip past this package: every
/// file there is run by a test here, or acknowledged as not for this platform (SPEC 9.3 says
/// placement.json is web only: native platforms keep the bottom sheet).
final class FixtureCoverageTests: XCTestCase {
    /// Fixture file -> the test file of this package that runs it.
    static let runners: [String: String] = [
        "tiers.json": "TiersAndComboConformanceTests.swift",
        "combo.json": "TiersAndComboConformanceTests.swift",
        "client.json": "ClientConformanceTests.swift",
        "effects.json": "EffectsConformanceTests.swift",
        "tray.json": "TrayConformanceTests.swift",
        "sheet.json": "SheetConformanceTests.swift",
        "theme.json": "ThemeConformanceTests.swift",
        "remote-recipes.json": "RemoteRecipesConformanceTests.swift",
        "wall.json": "WallConformanceTests.swift",
        "away.json": "AwayConformanceTests.swift",
        "leaderboard.json": "LeaderboardConformanceTests.swift",
        "inbox.json": "InboxConformanceTests.swift",
        "rooms-protocol.json": "RoomsConformanceTests.swift",
        "rooms-reconnect.json": "RoomsConformanceTests.swift",
        "rooms-filter.json": "RoomsConformanceTests.swift",
        "rooms-mapping.json": "RoomsConformanceTests.swift",
        "rooms-session.json": "RoomsConformanceTests.swift",
        "rooms-battle.json": "RoomsConformanceTests.swift",
        "battle-bar.json": "BattleBarConformanceTests.swift",
        "pictures.json": "PicturesConformanceTests.swift",
        "tray-scrim.json": "TrayScrimConformanceTests.swift",
    ]

    /// Web only by the SPEC (9.3). The component fixtures (wall, away, leaderboard) and the five
    /// rooms fixtures are ported and run above, so they are no longer acknowledged here.
    static let webOnly: Set<String> = ["placement.json"]

    func testEveryFixtureIsRunHereOrAcknowledgedAsWebOnly() throws {
        let dir = Fixtures.specDirectory.appendingPathComponent("conformance")
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") })
        let known = Set(FixtureCoverageTests.runners.keys).union(FixtureCoverageTests.webOnly)
        XCTAssertEqual(
            files.subtracting(known).sorted(),
            [],
            "New fixture file(s) with no runner in packages/sdk-ios. Port the logic and add a runner, or (only if the SPEC says web only) acknowledge it here."
        )
        XCTAssertEqual(known.subtracting(files).sorted(), [], "A fixture this package expects is gone from sdk-spec.")
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for (fixture, file) in FixtureCoverageTests.runners.sorted(by: { $0.key < $1.key }) {
            let path = testsDir.appendingPathComponent(file).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "\(fixture) needs \(file)")
        }
    }

    func testPlacementIsWebOnlyBySpec() throws {
        let url = Fixtures.specDirectory.appendingPathComponent("SPEC.md")
        let spec = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            spec.contains("**Web only**: React Native, Flutter, Android and iOS keep the"),
            "SPEC 9.3 no longer says placements are web only: port placement.json"
        )
        let fixture = try Fixtures.conformance("placement.json")
        XCTAssertNotNil(fixture["resolve"])
        XCTAssertNotNil(fixture["popover"])
    }
}
