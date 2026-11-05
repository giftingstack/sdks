package com.giftingstack.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.platform.app.InstrumentationRegistry
import com.giftingstack.core.EffectGift
import com.giftingstack.core.GiftEffectEvent
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** A loader whose pictures load or fail at the times a fixture says, on the compose test clock. */
private class ScriptedLoader(private val loadAtMs: Int?, private val errorAtMs: Int?) : GiftImageLoader {
    override fun peek(url: String): ImageBitmap? = null

    override suspend fun load(url: String): ImageBitmap? {
        if (loadAtMs != null) {
            delay(loadAtMs.toLong())
            return ImageBitmap(8, 8)
        }
        if (errorAtMs != null) {
            delay(errorAtMs.toLong())
            return null
        }
        awaitCancellation()
    }

    override fun prefetch(url: String) {}
}

/**
 * effects.json "pictureGate" (spec 7.2, level L3): the effect, and with it the notice, starts
 * when the picture loads or fails, or after pictureWaitMs, whichever is first; never before, and
 * at most one frame (16 ms) later.
 */
@RunWith(Parameterized::class)
class PictureGateTest(private val name: String, private val case: JsonObject, private val toleranceMs: Int) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val ctx = InstrumentationRegistry.getInstrumentation().context
            val text = ctx.assets.open("effects.json").bufferedReader().readText()
            val gate = Json.parseToJsonElement(text).jsonObject.getValue("pictureGate").jsonObject
            val tol = gate.getValue("toleranceMs").jsonPrimitive.int
            return gate.getValue("cases").jsonArray.map {
                val o = it.jsonObject
                arrayOf(o.getValue("name").jsonPrimitive.content, o, tol)
            }
        }
    }

    @get:Rule val rule = createComposeRule()

    private fun started() = rule.onAllNodesWithTag("gift-notice").fetchSemanticsNodes().isNotEmpty()

    @Test
    fun startsAtTheRightTime() {
        fun int(key: String): Int? = case[key]?.jsonPrimitive?.intOrNull
        val startsAt = int("startsAtMs")!!
        val image = case.getValue("image").jsonPrimitive.boolean
        val state = GiftEffectLayerState()
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides ScriptedLoader(int("loadAtMs"), int("errorAtMs"))) {
                GiftEffectLayer(state, reducedMotion = false, pictureWaitMs = int("pictureWaitMs")!!)
            }
        }
        rule.mainClock.advanceTimeBy(100) // the layer is measured
        // The test clock starts here; the effect enters now.
        rule.runOnIdle {
            state.play(EffectGift("gate", "Gate", 50_000, if (image) "https://assets.test/gate.webp" else null).let { GiftEffectEvent(it) })
        }
        // Fixture times count from the moment the effect enters: play() on the fake clock.
        if (startsAt == 0) {
            // Two frames: one composes the effect (which starts it), one composes the notice it shows.
            rule.mainClock.advanceTimeBy(2L * toleranceMs)
            assertTrue("$name: started right after play", started())
            return
        }
        rule.mainClock.advanceTimeBy(startsAt - 1L)
        assertFalse("$name: not yet at ${startsAt - 1} ms", started())
        rule.mainClock.advanceTimeBy(1L + toleranceMs)
        assertTrue("$name: started by ${startsAt + toleranceMs} ms", started())
    }
}
