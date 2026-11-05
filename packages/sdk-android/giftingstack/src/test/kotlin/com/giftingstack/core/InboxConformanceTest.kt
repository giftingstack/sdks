package com.giftingstack.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** inbox.json "client": getInbox with and without a query. */
@RunWith(Parameterized::class)
class InboxClientConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("inbox.json", "client") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun scenario() {
        runClientScenario(name, s)
    }
}

/** inbox.json "time": inboxTimeLabel(createdAtMs, nowMs). */
@RunWith(Parameterized::class)
class InboxTimeConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("inbox.json", "time") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun label() {
        assertEquals(name, c.string("label"), inboxTimeLabel(c.string("createdAtMs").toLong(), c.string("nowMs").toLong()))
    }
}

/** inbox.json "rows": inboxRows(items, nowMs, names). */
@RunWith(Parameterized::class)
class InboxRowsConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("inbox.json", "rows") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun rows() {
        val names = c.obj("names").mapValues { it.value.str() }
        val rows = inboxRows(c.getValue("items").arr().map { InboxItem.fromJson(it) }, c.string("nowMs").toLong(), names)
        val want = c.getValue("expect").arr()
        assertEquals("$name: rows", want.size, rows.size)
        rows.forEachIndexed { i, row ->
            val actual =
                mapOf(
                    "id" to JsonPrimitive(row.id),
                    "senderName" to JsonPrimitive(row.senderName),
                    "giftName" to JsonPrimitive(row.giftName),
                    "quantity" to JsonPrimitive(row.quantity),
                    "time" to JsonPrimitive(row.time),
                )
            for ((k, v) in want[i].obj()) assertEquals("$name: row ${i + 1}.$k", v, actual.getValue(k))
        }
    }
}

/** inbox.json "unread": inboxUnread(items, lastSeenMs). The fixture items carry only created_at and status. */
@RunWith(Parameterized::class)
class InboxUnreadConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("inbox.json", "unread") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun unread() {
        val items =
            c.getValue("items").arr().mapIndexed { i, e ->
                val o = e.obj()
                InboxItem("g$i", o.string("created_at"), "ayla", InboxGift("rose", "Rose", 10, null, null), o.intOrNull("quantity") ?: 1, 10, o.string("status"))
            }
        val lastSeen = c.stringOrNull("lastSeenMs")?.toLong()
        assertEquals(name, c.intOrNull("count"), inboxUnread(items, lastSeen))
    }
}
