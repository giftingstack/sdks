package com.giftingstack.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * L1 (spec section 11): every shared number equals `packages/sdk-spec/recipes.json`. This test
 * fails when the Kotlin constants and the generated file drift apart, in either direction.
 */
class SpecDriftTest {
    private val spec = Fixtures.read("recipes.json")

    @Test
    fun specVersionIsTheOneThisSdkWasBuiltFor() {
        assertEquals("1.0.0", spec.string("specVersion"))
    }

    @Test
    fun thresholdsComboWindowCapsAndSender() {
        val t = spec.getValue("thresholds").obj()
        assertEquals(t.intOrNull("mediumFrom"), DEFAULT_THRESHOLDS.mediumFrom)
        assertEquals(t.intOrNull("largeFrom"), DEFAULT_THRESHOLDS.largeFrom)
        assertEquals(spec.intOrNull("comboWindowMs")!!.toLong(), DEFAULT_COMBO_WINDOW_MS)
        val caps = spec.getValue("maxConcurrentEffects").obj()
        for (tier in EffectTier.entries) assertEquals(tier.wire, caps.intOrNull(tier.wire), MAX_CONCURRENT_EFFECTS[tier])
        assertEquals(spec.intOrNull("maxQueuedLarge"), MAX_QUEUED_LARGE)
        assertEquals(spec.string("defaultSenderName"), DEFAULT_SENDER_NAME)
    }

    @Test
    fun everyRecipeFieldMatchesBothQualities() {
        val recipes = spec.getValue("recipes").obj()
        for (quality in EffectQuality.entries) {
            val q = recipes.getValue(quality.wire).obj()
            for (tier in EffectTier.entries) {
                val want = q.getValue(tier.wire).obj()
                val got: Map<String, JsonElement> = recipeFields(recipeFor(tier, quality))
                assertEquals("${quality.wire}/${tier.wire} field names", want.keys, got.keys)
                for ((k, v) in want) {
                    assertEquals("${quality.wire}/${tier.wire}.$k", v.jsonPrimitive.content, (got.getValue(k) as JsonPrimitive).content)
                }
            }
        }
    }

    @Test
    fun allRecipesHasAllThreeTiers() {
        assertEquals(EffectTier.entries.toSet(), allRecipes(EffectQuality.Low).keys)
    }
}
