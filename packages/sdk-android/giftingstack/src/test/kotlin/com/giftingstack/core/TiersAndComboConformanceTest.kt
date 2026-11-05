package com.giftingstack.core

import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals as junitEquals

private fun thresholds(o: JsonObject?): TierThresholds {
    if (o == null) return TierThresholds()
    val d = TierThresholds()
    return TierThresholds(o.intOrNull("mediumFrom") ?: d.mediumFrom, o.intOrNull("largeFrom") ?: d.largeFrom)
}

/** tiers.json, "cases". */
@RunWith(Parameterized::class)
class TierCasesTest(private val label: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> =
            Fixtures.conformance("tiers.json").getValue("cases").arr().map {
                val o = it.obj()
                arrayOf("price ${o.getValue("price")} ${o["thresholds"] ?: "{}"} -> ${o.string("tier")}", o)
            }
    }

    @org.junit.Test
    fun tierFor() {
        val price = case.getValue("price").jsonPrimitive.double
        junitEquals(case.string("tier"), tierFor(price, thresholds(case["thresholds"]?.jsonObject)).wire)
    }
}

/** tiers.json, "recipes": every key in `expect` equals the recipe field of the same name. */
@RunWith(Parameterized::class)
class TierRecipeCasesTest(private val label: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> =
            Fixtures.conformance("tiers.json").getValue("recipes").arr().map {
                val o = it.obj()
                arrayOf("recipe ${o.string("tier")}/${o.string("quality")}", o)
            }
    }

    @org.junit.Test
    fun recipe() {
        val r = recipeFor(EffectTier.fromWire(case.string("tier")), EffectQuality.fromWire(case.string("quality")))
        val actual = recipeFields(r)
        for ((k, v) in case.getValue("expect").jsonObject) {
            junitEquals("$label.$k", v, actual.getValue(k))
        }
    }
}

fun recipeFields(r: EffectRecipe): Map<String, JsonElement> =
    mapOf(
        "tier" to JsonPrimitive(r.tier.wire),
        "peakScale" to JsonPrimitive(r.peakScale),
        "flyInMs" to JsonPrimitive(r.flyInMs),
        "holdMs" to JsonPrimitive(r.holdMs),
        "flyOutMs" to JsonPrimitive(r.flyOutMs),
        "stage" to JsonPrimitive(r.stage.wire),
        "sparks" to JsonPrimitive(r.sparks),
        "sparkSpread" to JsonPrimitive(r.sparkSpread),
        "coins" to JsonPrimitive(r.coins),
        "dim" to JsonPrimitive(r.dim),
        "rays" to JsonPrimitive(r.rays),
        "noticeMs" to JsonPrimitive(r.noticeMs),
        "noticeBig" to JsonPrimitive(r.noticeBig),
    )

/** combo.json. */
@RunWith(Parameterized::class)
class ComboConformanceTest(private val name: String, private val scenario: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = scenarioParams("combo.json")
    }

    @org.junit.Test
    fun scenario() {
        val window = scenario.intOrNull("windowMs")?.toLong()
        val tracker = if (window == null) ComboTracker() else ComboTracker(window)
        scenario.getValue("steps").arr().forEachIndexed { i, s ->
            val step = s.obj()
            if (step.has("reset")) {
                tracker.reset()
            } else {
                val hit = step.getValue("hit").arr()
                val got = tracker.hit(hit[0].jsonPrimitive.content, hit[1].jsonPrimitive.content, hit[2].jsonPrimitive.content.toLong())
                junitEquals("$name: step ${i + 1}", step.getValue("count").jsonPrimitive.content.toInt(), got)
            }
        }
    }
}
