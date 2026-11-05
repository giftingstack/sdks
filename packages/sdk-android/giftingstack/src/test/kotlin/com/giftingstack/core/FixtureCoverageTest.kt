package com.giftingstack.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A new fixture file in packages/sdk-spec/conformance must not slip past this package unnoticed:
 * every file there is either run by a test of ours (a source file that names it) or is explicitly
 * acknowledged as web only (SPEC 9.3 says placement.json is web only: no popover or inline on
 * native).
 */
class FixtureCoverageTest {
    /** Fixture file -> the test sources of this module that run it (relative to the module). */
    private val runners: Map<String, List<String>> =
        mapOf(
            "tiers.json" to listOf("TiersAndComboConformanceTest.kt"),
            "combo.json" to listOf("TiersAndComboConformanceTest.kt"),
            "client.json" to listOf("ClientConformanceTest.kt"),
            "effects.json" to listOf("EffectsConformanceTest.kt"),
            "tray.json" to listOf("TrayConformanceTest.kt"),
            "sheet.json" to listOf("SheetConformanceTest.kt"),
            "theme.json" to listOf("ThemeConformanceTest.kt"),
            "remote-recipes.json" to listOf("RemoteRecipesConformanceTest.kt"),
            "wall.json" to listOf("WallConformanceTest.kt"),
            "away.json" to listOf("AwayConformanceTest.kt"),
            "leaderboard.json" to listOf("LeaderboardConformanceTest.kt"),
            "inbox.json" to listOf("InboxConformanceTest.kt"),
            "rooms-protocol.json" to listOf("RoomsConformanceTest.kt"),
            "rooms-reconnect.json" to listOf("RoomsConformanceTest.kt"),
            "rooms-filter.json" to listOf("RoomsConformanceTest.kt"),
            "rooms-mapping.json" to listOf("RoomsConformanceTest.kt"),
            "rooms-session.json" to listOf("RoomsConformanceTest.kt"),
            "rooms-battle.json" to listOf("RoomsConformanceTest.kt"),
            "battle-bar.json" to listOf("BattleBarConformanceTest.kt"),
            "pictures.json" to listOf("PicturesConformanceTest.kt"),
            "tray-scrim.json" to listOf("TrayScrimConformanceTest.kt"),
        )

    /** Web only by the SPEC (9.3): native platforms skip these on purpose. */
    private val webOnly =
        setOf(
            "placement.json",
        )

    private val testDir = File("src/test/kotlin/com/giftingstack/core")

    @Test
    fun everyConformanceFixtureIsRunHereOrAcknowledgedAsWebOnly() {
        val dir = File(Fixtures.specDir, "conformance")
        val files = dir.listFiles { f -> f.name.endsWith(".json") }!!.map { it.name }.toSet()
        val known = runners.keys + webOnly
        assertEquals(
            "New fixture file(s) with no runner in this package. Port the logic and add a runner, or (only if the SPEC says web only) acknowledge it here.",
            emptySet<String>(),
            files - known,
        )
        assertEquals("A fixture this package expects is gone from sdk-spec.", emptySet<String>(), known - files)
    }

    @Test
    fun everyRunnerFileExistsAndNamesItsFixture() {
        for ((fixture, sources) in runners) {
            val text = sources.joinToString("\n") { name ->
                val f = File(testDir, name)
                assertTrue("$fixture needs ${f.path} (run from the giftingstack module)", f.isFile)
                f.readText()
            }
            assertTrue("$fixture is not named by its runner(s) $sources", text.contains("\"$fixture\""))
        }
    }

    @Test
    fun placementJsonIsWebOnlyAndNotRunHere() {
        val spec = File(Fixtures.specDir, "SPEC.md").readText()
        assertTrue(
            "SPEC 9.3 must still say placement is web only",
            spec.contains("**Web only**: React Native, Flutter, Android and iOS keep the"),
        )
        val fixture = Fixtures.conformance("placement.json")
        assertTrue(fixture.keys.containsAll(listOf("resolve", "popover")))
        // The acknowledgement test of the remote recipes file reads it; no runner may exist for it.
        assertTrue(runners.keys.none { it == "placement.json" })
    }
}
