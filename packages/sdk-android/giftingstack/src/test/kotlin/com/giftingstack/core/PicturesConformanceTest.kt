package com.giftingstack.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/** conformance/pictures.json (SPEC 7.6): which picture URLs are drawn and how long a failure is remembered. */
class PicturesConformanceTest {
    private val f = Fixtures.conformance("pictures.json")

    @Test
    fun theConstantsEqualTheFixture() {
        assertEquals(f.getValue("maxBytes").jsonPrimitive.int, PICTURE_MAX_BYTES)
        assertEquals(f.getValue("failureMemoryMs").jsonPrimitive.int.toLong(), PICTURE_FAILURE_MEMORY_MS)
    }

    @Test
    fun everyUrlIsAllowedOrRefused() {
        for (u in f.getValue("urls").arr()) {
            val o = u.obj()
            assertEquals("url: ${o.string("url")}", o.bool("allowed"), isPictureUrl(o.string("url")))
        }
    }

    @Test
    fun aDataUrlIsAllowedUpToTheLimit() {
        val prefix = "data:image/png;base64,"
        for (c in f.getValue("dataUrlSize").obj().getValue("cases").arr()) {
            val o = c.obj()
            val total = o.getValue("totalChars").jsonPrimitive.int
            val url = prefix + "A".repeat(total - prefix.length)
            assertEquals(total, url.length)
            assertEquals("data url of $total characters", o.bool("allowed"), isPictureUrl(url))
        }
    }

    @Test
    fun failuresAreRememberedForAMinuteAtMost200() {
        for (s in f.getValue("failures").arr()) {
            val scenario = s.obj()
            val name = scenario.string("name")
            val memory = PictureFailures()
            scenario.getValue("steps").arr().forEachIndexed { i, st ->
                val step: JsonObject = st.obj()
                val at = "$name: step ${i + 1}"
                val atMs = step.getValue("atMs").jsonPrimitive.int.toLong()
                if (step.has("fail")) memory.fail(step.string("fail"), atMs)
                if (step.has("failMany")) {
                    val m = step.getValue("failMany").obj()
                    for (n in 0 until m.getValue("count").jsonPrimitive.int) memory.fail(m.string("prefix") + n, atMs)
                }
                if (step.has("failed")) {
                    for ((url, want) in step.getValue("failed").jsonObject) {
                        assertEquals("$at $url", want.jsonPrimitive.content == "true", memory.has(url, atMs))
                    }
                }
            }
        }
    }
}
