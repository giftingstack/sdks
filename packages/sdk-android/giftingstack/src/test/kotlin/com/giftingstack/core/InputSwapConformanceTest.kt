package com.giftingstack.core

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

private val swapFile = Fixtures.conformance("input-swap.json")

private fun eventOf(wire: String) =
    when (wire) {
        "button" -> InputSwapEvent.Button
        "inputFocus" -> InputSwapEvent.InputFocus
        else -> error("unknown event $wire")
    }

private fun wireOf(step: InputSwapStep) = step.tray.name.lowercase() to step.input.name.lowercase()

private fun expectOf(o: kotlinx.serialization.json.JsonObject) =
    o.getValue("expect").jsonObject.let { it.string("tray") to it.string("input") }

private fun numberOrNull(o: kotlinx.serialization.json.JsonObject, key: String): Double? {
    val v = o[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.double
}

/** input-swap.json: the constants, inputSwapStep, keyboardPlaceHeight and the sequences (SPEC 20.2). */
class InputSwapConformanceTest {
    @Test
    fun constants() {
        val c = swapFile.getValue("constants").jsonObject
        assertEquals(c.getValue("fallback").jsonPrimitive.int, KEYBOARD_PLACE_FALLBACK)
        assertEquals(c.getValue("minKeyboard").jsonPrimitive.int, KEYBOARD_MIN_HEIGHT)
        assertEquals(c.getValue("maxFraction").jsonPrimitive.double, KEYBOARD_PLACE_MAX_FRACTION, 0.0)
    }

    @Test
    fun step() {
        val cases = swapFile.getValue("step").jsonArray
        assertEquals(4, cases.size)
        for (e in cases) {
            val o = e.jsonObject
            assertEquals("step $o", expectOf(o), wireOf(inputSwapStep(o.bool("open"), eventOf(o.string("event")))))
        }
    }

    @Test
    fun place() {
        val cases = swapFile.getValue("place").jsonArray
        assertEquals(11, cases.size)
        for (e in cases) {
            val o = e.jsonObject
            val got = keyboardPlaceHeight(numberOrNull(o, "keyboardHeight"), numberOrNull(o, "containerHeight"))
            assertEquals(o.string("note"), o.getValue("expect").jsonPrimitive.int, got)
        }
    }

    @Test
    fun sequence() {
        for (s in swapFile.getValue("sequence").jsonArray) {
            val seq = s.jsonObject
            var open = seq.bool("open")
            seq.getValue("steps").jsonArray.forEachIndexed { i, st ->
                val step = st.jsonObject
                val at = "${seq.string("name")}: step ${i + 1}"
                val got = inputSwapStep(open, eventOf(step.string("event")))
                assertEquals(at, expectOf(step), wireOf(got))
                open =
                    when (got.tray) {
                        InputSwapTray.Open -> true
                        InputSwapTray.Close -> false
                        InputSwapTray.Keep -> open
                    }
                assertEquals("$at open", step.bool("open"), open)
            }
        }
    }

    @Test
    fun placeSnapIsAFractionOfTheContainer() {
        assertEquals(336.0 / 800.0, keyboardPlaceSnap(336.0, 800.0)!!, 1e-9)
        assertEquals(null, keyboardPlaceSnap(336.0, 0.0))
        assertEquals(null, keyboardPlaceSnap(336.0, null))
        assertEquals(300.0 / 900.0, keyboardPlaceSnap(Double.NaN, 900.0)!!, 1e-9)
    }
}
