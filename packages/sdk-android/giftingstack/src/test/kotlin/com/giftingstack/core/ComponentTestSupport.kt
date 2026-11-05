package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue

/**
 * A virtual clock with timers (conformance/README.md, "Fake clock"). `advance(ms)` fires every
 * timer due up to the new time, in due order (ties: the order they were set), with the clock set
 * to each timer's due time.
 */
class FakeClock {
    var now = 0L
        private set
    private var seq = 0
    private class T(val id: Int, val due: Long, val fn: () -> Unit)

    private var timers = ArrayList<T>()

    val timersApi = Timers(set = { ms, fn -> setTimeout(ms, fn) }, clear = { clearTimeout(it) })

    fun setTimeout(ms: Long, fn: () -> Unit): Any {
        val id = ++seq
        timers.add(T(id, now + maxOf(0L, ms), fn))
        return id
    }

    fun clearTimeout(handle: Any) {
        timers = ArrayList(timers.filter { it.id != handle })
    }

    private fun next(limit: Long): T? {
        var best: T? = null
        for (t in timers) {
            if (t.due <= limit && (best == null || t.due < best.due || (t.due == best.due && t.id < best.id))) best = t
        }
        return best
    }

    /** Fire the timers due now. */
    fun runDue() {
        var t = next(now)
        while (t != null) {
            clearTimeout(t.id)
            t.fn()
            t = next(now)
        }
    }

    fun advance(ms: Long) {
        val target = now + ms
        var t = next(target)
        while (t != null) {
            now = t.due
            clearTimeout(t.id)
            t.fn()
            t = next(target)
        }
        now = target
    }
}

/**
 * Lets pending coroutine work run, then fires timers that became due, until nothing changes
 * (conformance/README.md: "After EVERY step the runner lets pending asynchronous work run").
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun TestScope.settle(clock: FakeClock) {
    repeat(3) {
        runCurrent()
        clock.runDue()
    }
    runCurrent()
}

fun errorFromJson(e: JsonObject): GiftingException =
    GiftingException(e.intOrNull("status")!!, e.string("type"), e.string("message"), e.stringOrNull("requestId"))

class ScriptedCall(val method: String, val result: CompletableDeferred<Any?>)

/** A client whose every call waits until a step settles it (oldest call of a method first). */
class ScriptedCalls {
    val pending = ArrayList<ScriptedCall>()
    val calls = ArrayList<JsonObject>()

    fun call(method: String, args: JsonElement): CompletableDeferred<Any?> {
        val d = CompletableDeferred<Any?>()
        calls.add(JsonObject(mapOf("method" to JsonPrimitive(method), "args" to args)))
        pending.add(ScriptedCall(method, d))
        return d
    }

    fun take(method: String, at: String): ScriptedCall {
        val idx = pending.indexOfFirst { it.method == method }
        assertTrue("$at: no pending $method", idx >= 0)
        return pending.removeAt(idx)
    }

    val callsJson: JsonArray get() = JsonArray(calls)
}

/** `[{"gift": id, "count": n}]` of a list of received gifts. */
fun compactGifts(list: List<ReceivedGift>): JsonArray =
    JsonArray(list.map { JsonObject(mapOf("gift" to JsonPrimitive(it.gift.id), "count" to JsonPrimitive(it.count))) })

/** Parameters for a Parameterized runner over an array of a fixture file, named by [name]. */
fun arrayParams(file: String, key: String, name: (Int, JsonObject) -> String): List<Array<Any>> =
    Fixtures.conformance(file).getValue(key).arr().mapIndexed { i, e -> arrayOf(name(i, e.obj()), e) }

fun JsonElement.str(): String = jsonPrimitive.content

fun JsonObject.obj(key: String): JsonObject = getValue(key).obj()

fun JsonObject.opt(key: String): JsonElement? = this[key]?.takeIf { it !is JsonNull }
