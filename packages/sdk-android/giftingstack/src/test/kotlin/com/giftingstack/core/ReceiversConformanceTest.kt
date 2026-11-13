package com.giftingstack.core

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

private val receiversFile = Fixtures.conformance("receivers.json")

/** receivers.json: resolveReceiver (SPEC 21.2). */
class ReceiversConformanceTest {
    @Test
    fun resolve() {
        val cases = receiversFile.getValue("resolve").jsonArray
        assertEquals(9, cases.size)
        for (e in cases) {
            val o = e.jsonObject
            val ids = o.getValue("ids").jsonArray.map { it.jsonPrimitive.content }
            val got = resolveReceiver(ids, o.stringOrNull("selected"), o.stringOrNull("last"), o.stringOrNull("fallback"))
            assertEquals(o.string("note"), o.stringOrNull("expect"), got)
        }
    }

    @Test
    fun labels() {
        assertEquals("Send to", SEND_TO_LABEL)
        assertEquals("Send {name} a gift", PRESS_SIDE_LABEL)
        assertEquals("Send Mia a gift", pressSideLabel("Mia"))
        assertEquals("Mia'ya hediye", pressSideLabel("Mia", "{name}'ya hediye"))
    }
}
