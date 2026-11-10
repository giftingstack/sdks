package com.giftingstack.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private val scrimFile = Fixtures.conformance("tray-scrim.json")

private fun snapOf(wire: String) = SheetSnap.fromWire(wire)

/** tray-scrim.json: the constants, scrimVisible, scrimFadeMs and scrimTapOutcome. */
class TrayScrimPureConformanceTest {
    @Test
    fun constants() {
        val c = scrimFile.getValue("constants").jsonObject
        assertEquals(c.getValue("fadeMs").jsonPrimitive.int, SCRIM_FADE_MS)
        assertEquals(c.getValue("opacity").jsonPrimitive.double, SCRIM_OPACITY, 0.0)
    }

    @Test
    fun visible() {
        val cases = scrimFile.getValue("visible").jsonArray
        assertEquals(24, cases.size)
        for (e in cases) {
            val o = e.jsonObject
            val got = scrimVisible(o.bool("scrim"), o.bool("open"), snapOf(o.string("snap")), o.bool("placed"))
            assertEquals("visible $o", o.bool("expect"), got)
        }
    }

    @Test
    fun takesTouches() {
        val cases = scrimFile.getValue("takesTouches").jsonArray
        assertEquals(8, cases.size)
        for (e in cases) {
            val o = e.jsonObject
            assertEquals("takesTouches $o", o.bool("expect"), scrimTakesTouches(o.bool("scrim"), o.bool("open"), o.bool("placed")))
        }
    }

    @Test
    fun fade() {
        for (e in scrimFile.getValue("fade").jsonArray) {
            val o = e.jsonObject
            assertEquals(o.string("name"), o.getValue("ms").jsonPrimitive.int, scrimFadeMs(o.bool("reducedMotion")))
        }
    }

    @Test
    fun tap() {
        for (e in scrimFile.getValue("tap").jsonArray) {
            val o = e.jsonObject
            val tap = if (o.has("scrimTap")) (if (o.string("scrimTap") == "dismiss") ScrimTap.Dismiss else ScrimTap.Lower) else ScrimTap.Lower
            val got = scrimTapOutcome(o.bool("scrim"), tap, o.bool("open"), snapOf(o.string("snap")))
            assertEquals("tap $o", o.string("expect"), got.name.lowercase())
        }
    }
}

/** tray-scrim.json "open": TrayOpenState. */
@RunWith(Parameterized::class)
class TrayOpenStateConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = scenarioParams("tray-scrim.json", "open")
    }

    @Test
    fun scenario() {
        val changes = ArrayList<Boolean>()
        val state = TrayOpenState(open = if (s.has("open")) s.bool("open") else true, onChange = { changes.add(it) })
        s.getValue("steps").jsonArray.forEachIndexed { i, st ->
            val step = st.jsonObject
            val at = "$name: step ${i + 1}"
            when {
                step.has("call") -> {
                    val got =
                        when (step.string("call")) {
                            "open" -> state.open()
                            "close" -> state.close()
                            "toggle" -> state.toggle()
                            else -> error("$at: unknown call $step")
                        }
                    assertEquals("$at returns", step.bool("returns"), got)
                }
                step.has("expect") -> {
                    val e = step.getValue("expect").jsonObject
                    assertEquals("$at open", e.bool("open"), state.isOpen)
                    assertEquals("$at changes", e.getValue("changes").jsonArray.map { it.jsonPrimitive.content == "true" }, changes)
                }
                else -> error("$at: unknown step $step")
            }
        }
    }

    @Test
    fun subscribersRunBeforeOnChangeAndOnlyOnChange() {
        val order = ArrayList<String>()
        val st = TrayOpenState(open = true, onChange = { order.add("change:$it") })
        val stop = st.subscribe { order.add("sub:${st.isOpen}") }
        st.open()
        st.close()
        assertEquals(listOf("sub:false", "change:false"), order)
        stop()
        st.open()
        assertEquals(listOf("sub:false", "change:false", "change:true"), order)
    }
}
