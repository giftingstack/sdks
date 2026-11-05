import Foundation
import XCTest
@testable import GiftingStack

/// L1: the Swift constants equal packages/sdk-spec/recipes.json, field by field. Fails when
/// SpecData.generated.swift drifts from the JSON (regenerate with
/// `node packages/sdk-ios/tool/generate-spec-data.mjs`) or when `recipeFor` stops matching it.
final class RecipesDriftTests: XCTestCase {
    func testConstantsMatchRecipesJSON() throws {
        let file = try Fixtures.load("recipes.json")
        let swift = try swiftSpec(recipe: { tier, quality in recipeFor(tier, quality: quality) })
        let differences = jsonDifferences(expected: file, actual: swift)
        for difference in differences {
            XCTFail("recipes.json vs Swift (recipeFor): \(difference)")
        }
    }

    func testGeneratedTableMatchesRecipesJSON() throws {
        let file = try Fixtures.load("recipes.json")
        let swift = try swiftSpec(recipe: { tier, quality in GiftingSpec.specRecipe(tier, quality: quality) })
        for difference in jsonDifferences(expected: file, actual: swift) {
            XCTFail("recipes.json vs SpecData.generated.swift: \(difference)")
        }
    }

    func testAllRecipesHasEveryTier() {
        for quality in EffectQuality.allCases {
            let table = allRecipes(quality)
            XCTAssertEqual(Set(table.keys), Set(EffectTier.allCases))
            for tier in EffectTier.allCases {
                XCTAssertEqual(table[tier], recipeFor(tier, quality: quality))
            }
        }
    }

    /// The Swift numbers in the shape of recipes.json.
    private func swiftSpec(recipe: (EffectTier, EffectQuality) -> EffectRecipe) throws -> JSONValue {
        var recipes: [String: JSONValue] = [:]
        for quality in EffectQuality.allCases {
            var tiers: [String: JSONValue] = [:]
            for tier in EffectTier.allCases {
                tiers[tier.rawValue] = try JSONValue.of(recipe(tier, quality))
            }
            recipes[quality.rawValue] = .object(tiers)
        }
        return .object([
            "specVersion": .string(GiftingSpec.specVersion),
            "thresholds": .object([
                "mediumFrom": .number(Double(TierThresholds().mediumFrom)),
                "largeFrom": .number(Double(TierThresholds().largeFrom)),
            ]),
            "comboWindowMs": .number(Double(ComboTracker().windowMs)),
            "maxConcurrentEffects": .object([
                "small": .number(Double(GiftingSpec.maxConcurrentEffects(.small))),
                "medium": .number(Double(GiftingSpec.maxConcurrentEffects(.medium))),
                "large": .number(Double(GiftingSpec.maxConcurrentEffects(.large))),
            ]),
            "maxQueuedLarge": .number(Double(GiftingSpec.maxQueuedLarge)),
            "defaultSenderName": .string(GiftingSpec.defaultSenderName),
            "recipes": .object(recipes),
        ])
    }
}
