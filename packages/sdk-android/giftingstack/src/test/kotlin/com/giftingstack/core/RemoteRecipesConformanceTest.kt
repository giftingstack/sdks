package com.giftingstack.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private val remoteFile = Fixtures.conformance("remote-recipes.json")
private val embeddedDoc = Fixtures.read("recipes.json")

/** Objects merge recursively, any other value replaces (README: "expect is a PATCH"). */
private fun overlay(base: JsonElement, patch: JsonElement): JsonElement =
    if (base is JsonObject && patch is JsonObject) {
        JsonObject(base + patch.mapValues { (k, v) -> base[k]?.let { overlay(it, v) } ?: v })
    } else {
        patch
    }

/** Deep equality; numbers compare by value (4 equals 4.0), everything else by type and content. */
private fun deepEqual(path: String, want: JsonElement, got: JsonElement) {
    when {
        want is JsonObject && got is JsonObject -> {
            assertEquals("$path keys", want.keys, got.keys)
            for ((k, v) in want) deepEqual("$path.$k", v, got.getValue(k))
        }
        want is JsonArray && got is JsonArray -> {
            assertEquals("$path length", want.size, got.size)
            want.indices.forEach { deepEqual("$path[$it]", want[it], got[it]) }
        }
        want is JsonPrimitive && got is JsonPrimitive && !want.isString && !got.isString && want !is JsonNull && got !is JsonNull &&
            want.content.toDoubleOrNull() != null && got.content.toDoubleOrNull() != null ->
            assertEquals(path, want.content.toDouble(), got.content.toDouble(), 0.0)
        else -> assertEquals(path, want, got)
    }
}

private fun resolveInput(input: JsonElement): JsonElement = if (input is JsonPrimitive && input.isString && input.content == "@embedded") embeddedDoc else input

private fun embeddedSetJson(): JsonObject =
    JsonObject(embeddedDoc.filterKeys { it == "thresholds" || it == "comboWindowMs" || it == "recipes" })

/** remote-recipes.json "parse". */
@RunWith(Parameterized::class)
class RemoteParseConformanceTest(private val name: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = scenarioParams("remote-recipes.json", "parse")
    }

    @Test
    fun parse() {
        val input = resolveInput(case.getValue("input"))
        val got = parseRemoteRecipes(input)
        val expect = case.getValue("expect")
        if (expect is JsonNull) {
            assertNull("$name: must be ignored", got)
            return
        }
        assertNotNull("$name: must parse", got)
        val want = overlay(embeddedSetJson(), expect).jsonObject + ("specVersion" to input.jsonObject.getValue("specVersion"))
        val actual = JsonObject(got!!.set.toJson() + ("specVersion" to JsonPrimitive(got.specVersion)))
        deepEqual(name, JsonObject(want), actual)
    }
}

/** remote-recipes.json "merge". */
@RunWith(Parameterized::class)
class RemoteMergeConformanceTest(private val name: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = scenarioParams("remote-recipes.json", "merge")
    }

    @Test
    fun merge() {
        val embedded = embeddedRecipeSet()
        val remote = case.getValue("remote").let { if (it is JsonNull) null else parseRemoteRecipes(it)?.set }
        val app = case.getValue("app").jsonObject
        val th = app["thresholds"]?.jsonObject
        val merged =
            mergeRecipeSet(
                embedded,
                remote,
                AppRecipeOverrides(
                    th?.let { PartialThresholds(it.intOrNull("mediumFrom"), it.intOrNull("largeFrom")) },
                    app.intOrNull("comboWindowMs")?.toLong(),
                ),
            )
        val e = case.getValue("expect").jsonObject
        val et = e.getValue("thresholds").jsonObject
        assertEquals("$name thresholds", TierThresholds(et.intOrNull("mediumFrom")!!, et.intOrNull("largeFrom")!!), merged.thresholds)
        assertEquals("$name comboWindowMs", e.intOrNull("comboWindowMs")!!.toLong(), merged.comboWindowMs)
        val wantRecipes = if (e.string("recipes") == "embedded") embedded.recipes else remote!!.recipes
        assertEquals("$name recipes", wantRecipes, merged.recipes)
    }
}

/** remote-recipes.json "urls". */
@RunWith(Parameterized::class)
class RemoteUrlsConformanceTest(private val name: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = scenarioParams("remote-recipes.json", "urls")
    }

    @Test
    fun url() {
        val got = remoteRecipesUrl(case.stringOrNull("url"), case.stringOrNull("version"))
        assertEquals(name, case.stringOrNull("expect"), got)
    }
}

/** SPEC 13.3: "a platform SHOULD check that its limits table equals SPEC.md 13.3". */
class RemoteLimitsTableTest {
    @Test
    fun limitsEqualTheSpecTable() {
        val spec = java.io.File(Fixtures.specDir, "SPEC.md").readText()
        val section = spec.substringAfter("The limits (code: `REMOTE_RECIPE_LIMITS`").substringBefore("Only remote values are clamped")
        val rows = Regex("\\|\\s*`(\\w+)`\\s*\\|\\s*([\\d.,]+)\\s*\\|\\s*([\\d.,]+)\\s*\\|\\s*(yes|no)\\s*\\|").findAll(section).toList()
        assertEquals("rows in the spec table", REMOTE_RECIPE_LIMITS.size, rows.size)
        for (r in rows) {
            val (key, min, max, integer) = r.destructured
            val lim = REMOTE_RECIPE_LIMITS.getValue(key)
            assertEquals("$key min", min.replace(",", "").toDouble(), lim.min, 0.0)
            assertEquals("$key max", max.replace(",", "").toDouble(), lim.max, 0.0)
            assertEquals("$key integer", integer == "yes", lim.integer)
        }
    }

    @Test
    fun everyEmbeddedNumberLiesInsideTheLimits() {
        val set = embeddedRecipeSet()
        fun inside(key: String, v: Double) {
            val l = REMOTE_RECIPE_LIMITS.getValue(key)
            assertTrue("$key = $v", v >= l.min && v <= l.max)
        }
        inside("mediumFrom", set.thresholds.mediumFrom.toDouble())
        inside("largeFrom", set.thresholds.largeFrom.toDouble())
        inside("comboWindowMs", set.comboWindowMs.toDouble())
        for ((_, tiers) in set.recipes) for ((_, r) in tiers) {
            inside("peakScale", r.peakScale)
            inside("flyInMs", r.flyInMs.toDouble())
            inside("holdMs", r.holdMs.toDouble())
            inside("flyOutMs", r.flyOutMs.toDouble())
            inside("sparks", r.sparks.toDouble())
            inside("sparkSpread", r.sparkSpread.toDouble())
            inside("coins", r.coins.toDouble())
            inside("noticeMs", r.noticeMs.toDouble())
        }
    }
}

/** placement.json is web only (SPEC 9.3): native platforms skip it. We only check it is acknowledged. */
class PlacementIsWebOnlyTest {
    @Test
    fun skippedOnNative() {
        val spec = java.io.File(Fixtures.specDir, "SPEC.md").readText().replace(Regex("\\s+"), " ")
        assertTrue("SPEC 9.3 must still say web only", spec.contains("**Web only**: React Native, Flutter, Android and iOS keep the bottom sheet of 9.1 and do not implement this section."))
        val f = Fixtures.conformance("placement.json")
        assertTrue(f.containsKey("resolve") && f.containsKey("popover"))
    }
}
