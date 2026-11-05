package com.giftingstack.core

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * battle-bar.json (SPEC 18.7): the numbers every platform is held to. The format is "Battle bar"
 * of conformance/README.md; the reference runner is the "conformance: battle-bar.json" block of
 * packages/sdk-js/test/battle-bar-core.test.ts.
 */
private fun labelsOf(c: JsonObject): BattleBarLabels {
    val m = c["labels"] as? JsonObject ?: return BattleBarLabels()
    val d = BattleBarLabels()
    return BattleBarLabels(
        vs = m.stringOrNull("vs") ?: d.vs,
        finalText = m.stringOrNull("final") ?: d.finalText,
        wins = m.stringOrNull("wins") ?: d.wins,
        draw = m.stringOrNull("draw") ?: d.draw,
        spoken = m.stringOrNull("spoken") ?: d.spoken,
        side = m.stringOrNull("side") ?: d.side,
        thousand = m.stringOrNull("thousand") ?: d.thousand,
        million = m.stringOrNull("million") ?: d.million,
    )
}

@RunWith(Parameterized::class)
class BattleBarScoreConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("battle-bar.json", "score") { _, o -> "${o["units"]} ${o["labels"] ?: "{}"}" }
    }

    @Test
    fun score() {
        assertEquals(name, c.string("expect"), formatBattleScore(c.getValue("units").jsonPrimitive.content.toLong(), labelsOf(c)))
    }
}

@RunWith(Parameterized::class)
class BattleBarClockConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("battle-bar.json", "clock") { _, o -> "${o["remainingMs"]}" }
    }

    @Test
    fun clock() {
        assertEquals(name, c.string("expect"), formatBattleClock(c.getValue("remainingMs").jsonPrimitive.content.toLong()))
    }
}

@RunWith(Parameterized::class)
class BattleBarModelConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("battle-bar.json", "model") { _, o -> o.string("name") }
    }

    @Test
    fun model() {
        val frame = JsonObject(mapOf("t" to JsonPrimitive("scores"), "battle" to c.getValue("battle")))
        val battle = (parseRoomFrame(frame.toString()) as RoomServerMessage.Scores).battle!!
        val serverNow = c.getValue("serverNow").jsonPrimitive.content.toLong()
        val names = c["names"] as? JsonObject
        val m = battleBarModel(battleView(battle, serverNow), { id -> names?.stringOrNull(id) ?: id }, labelsOf(c))
        if (c.getValue("expect") is JsonNull) {
            assertNull(name, m)
            return
        }
        assertNotNull(name, m)
        m!!
        val want = c.obj("expect")
        val got =
            mapOf<String, Any?>(
                "clock" to m.clock,
                "urgent" to m.urgent,
                "final" to m.isFinal,
                "winner" to m.winner,
                "banner" to m.banner,
                "spoken" to m.spoken,
            )
        for ((k, v) in want) {
            when (k) {
                "sides" -> Unit
                "pct" -> assertEquals("$name pct", v.jsonPrimitive.double, m.pct, 1e-6)
                else -> assertEquals("$name $k", if (v is JsonNull) null else v.jsonPrimitive.let { p -> if (p.isString) p.content else p.boolean }, got.getValue(k))
            }
        }
        want["sides"]?.arr()?.forEachIndexed { i, sw ->
            val s = m.sides[i]
            val side =
                mapOf<String, Any?>(
                    "id" to s.id,
                    "name" to s.name,
                    "units" to s.units,
                    "score" to s.score,
                    "spoken" to s.spoken,
                    "leads" to s.leads,
                    "won" to s.won,
                    "lost" to s.lost,
                )
            for ((k, v) in sw.obj()) {
                val p = v.jsonPrimitive
                val expected: Any = if (k == "units") p.content.toLong() else if (p.isString) p.content else p.boolean
                assertEquals("$name sides[$i].$k", expected, side.getValue(k))
            }
        }
    }
}

@RunWith(Parameterized::class)
class BattleBarGainsConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("battle-bar.json", "gains") { _, o -> "${o["before"]} -> ${o["after"]}" }
    }

    @Test
    fun gains() {
        val before = if (c.getValue("before") is JsonNull) null else c.getValue("before").arr().map { it.jsonPrimitive.content.toLong() }
        val after = c.getValue("after").arr().map { it.jsonPrimitive.content.toLong() }
        assertEquals(name, c.getValue("expect").arr().map { it.jsonPrimitive.boolean }, battleGains(before, after))
    }
}

@RunWith(Parameterized::class)
class BattleBarColorsConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("battle-bar.json", "colors") { _, o -> o.string("name") }
    }

    @Test
    fun colors() {
        val theme =
            when (c.string("theme")) {
                "dark" -> darkThemeTokens
                "light" -> lightThemeTokens
                else -> defaultThemeTokens
            }
        val over = c["override"]?.arr()?.map { it.str() }?.let { it[0] to it[1] }
        val got = battleSideColors(theme, over)
        val want = c.getValue("expect").arr().map { SideColor(it.obj().string("color"), it.obj().string("text")) }
        assertEquals(name, want, got)
    }
}

class BattleBarFixtureTest {
    @Test
    fun theFixtureHasCases() {
        val f = Fixtures.conformance("battle-bar.json")
        assertTrue(f.getValue("score").arr().size > 4)
        assertTrue(f.getValue("clock").arr().size > 4)
        assertTrue(f.getValue("model").arr().size > 10)
        assertTrue(f.getValue("gains").arr().size > 3)
        assertTrue(f.getValue("colors").arr().size > 5)
    }
}
