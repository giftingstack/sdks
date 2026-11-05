import Foundation
import XCTest
@testable import GiftingStack
#if canImport(SwiftUI)
import SwiftUI
#endif

/// conformance/theme.json: the WCAG contrast ratio, the presets and themeFromAccent (spec 9.2).
final class ThemeConformanceTests: XCTestCase {
    private struct Rule {
        let fg: String
        let bg: String
        let min: Double
    }

    func testContrastRatios() throws {
        let f = try Fixtures.conformance("theme.json")
        for c in try Fixtures.list(f["contrast"], "theme.json contrast") {
            let a = try XCTUnwrap(c["a"]?.stringValue)
            let b = try XCTUnwrap(c["b"]?.stringValue)
            let expected = try XCTUnwrap(c["ratio"]?.doubleValue)
            // Rounded to two decimals, half up (README).
            let rounded = (contrastRatio(a, b) * 100 + 0.5).rounded(.down) / 100
            XCTAssertEqual(rounded, expected, accuracy: 1e-9, "[theme.json contrast] \(a) on \(b)")
        }
    }

    func testPresetsMeetEveryRule() throws {
        let f = try Fixtures.conformance("theme.json")
        let rules = try ThemeConformanceTests.rules(f)
        for preset in try Fixtures.list(f["presets"], "theme.json presets") {
            let name = try XCTUnwrap(preset.stringValue)
            let theme: GiftTheme
            switch name {
            case "darkTheme":
                theme = GiftTheme.darkTheme
            case "lightTheme":
                theme = GiftTheme.lightTheme
            default:
                XCTFail("[theme.json] unknown preset \(name)")
                continue
            }
            check(theme, rules, "[theme.json preset] \(name)")
        }
    }

    func testThemeFromAccentMeetsEveryRuleAndKeepsTheAccent() throws {
        let f = try Fixtures.conformance("theme.json")
        let rules = try ThemeConformanceTests.rules(f)
        let modes = try Fixtures.list(f["modes"], "theme.json modes")
        for c in try Fixtures.list(f["accents"], "theme.json accents") {
            let accent = try XCTUnwrap(c["accent"]?.stringValue)
            let normalized = try XCTUnwrap(c["normalized"]?.stringValue)
            for m in modes {
                let modeName = try XCTUnwrap(m.stringValue)
                let mode = try XCTUnwrap(ThemeMode(rawValue: modeName), "mode \(modeName)")
                let context = "[theme.json] themeFromAccent(\(accent), \(modeName))"
                let theme = try themeFromAccent(accent, mode: mode)
                XCTAssertEqual(theme.accent, normalized, "\(context) accent")
                check(theme, rules, context)
            }
        }
    }

    func testInvalidAccentsThrow() throws {
        let f = try Fixtures.conformance("theme.json")
        for v in try Fixtures.list(f["invalid"], "theme.json invalid") {
            let value = try XCTUnwrap(v.stringValue)
            XCTAssertThrowsError(try themeFromAccent(value, mode: .dark), "[theme.json invalid] \(value)")
        }
    }

    private func check(_ theme: GiftTheme, _ rules: [Rule], _ context: String) {
        for rule in rules {
            guard let fg = theme.token(rule.fg), let bg = theme.token(rule.bg) else {
                XCTFail("\(context): unknown token \(rule.fg) or \(rule.bg)")
                continue
            }
            let ratio = contrastRatio(fg, bg)
            XCTAssertGreaterThanOrEqual(ratio, rule.min, "\(context): \(rule.fg) \(fg) on \(rule.bg) \(bg)")
        }
    }

    private static func rules(_ f: JSONValue) throws -> [Rule] {
        try Fixtures.list(f["rules"], "theme.json rules").map { r in
            Rule(
                fg: try XCTUnwrap(r["fg"]?.stringValue),
                bg: try XCTUnwrap(r["bg"]?.stringValue),
                min: try XCTUnwrap(r["min"]?.doubleValue)
            )
        }
    }

    // MARK: - Beyond the fixture

    func testDefaultThemeIsTheSpecTable() {
        let t = GiftTheme.defaultTheme
        XCTAssertEqual(t.background, "#14141f")
        XCTAssertEqual(t.accent, "#8b7bff")
        XCTAssertEqual(t.noticeBackground, "rgba(123, 107, 255, 0.92)")
        XCTAssertEqual(t.coinText, "#2a1600")
        XCTAssertEqual(t.selected, "#221f45")
        XCTAssertEqual(t.comboText, "#fff3c4")
        XCTAssertEqual(GiftTheme.darkTheme.accent, "#6d5cf0")
        XCTAssertEqual(GiftTheme.lightTheme.coin, "#9a6300")
    }

    func testHexHelpers() throws {
        XCTAssertEqual(parseHexColor("#f80"), ThemeRGB(r: 255, g: 136, b: 0))
        XCTAssertNil(parseHexColor("#12345"))
        XCTAssertNil(parseHexColor("ff8800"))
        XCTAssertEqual(hexColor(ThemeRGB(r: 255.4, g: -3, b: 0.5)), "#ff0001")
        XCTAssertEqual(mixHexColor("#000000", "#ffffff", 0.5), "#808080")
        XCTAssertEqual(readableOn("#ffeb3b"), "#000000")
        XCTAssertEqual(try themeFromAccent("#ff4f9a").noticeBackground, "rgba(255, 79, 154, 0.92)")
    }

    #if canImport(SwiftUI)
    func testCSSColoursParse() {
        XCTAssertNotNil(Color(giftingCSS: "#1e1e2e"))
        XCTAssertNotNil(Color(giftingCSS: "rgba(106, 84, 232, 0.94)"))
        XCTAssertNil(Color(giftingCSS: "red"))
    }
    #endif
}
