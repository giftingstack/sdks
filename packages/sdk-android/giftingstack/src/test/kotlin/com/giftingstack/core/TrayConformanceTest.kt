package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private class PendingCall(val method: String, val result: CompletableDeferred<Any?>)

/** tray.json "scenarios": the GiftTrayController with a scripted client. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(Parameterized::class)
class TrayConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        private val file = Fixtures.conformance("tray.json")

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = file.getValue("scenarios").arr().map { arrayOf<Any>(it.obj().string("name"), it) }
    }

    private fun str(s: String?): JsonElement = if (s == null) JsonNull else JsonPrimitive(s)

    @org.junit.Test
    fun scenario() = runTest {
        val gifts = file.getValue("gifts").obj()
        val transactions = file.getValue("transactions").obj()
        val pending = ArrayList<PendingCall>()
        val calls = ArrayList<JsonObject>()

        fun call(method: String, args: JsonObject?): CompletableDeferred<Any?> {
            val d = CompletableDeferred<Any?>()
            calls.add(JsonObject(buildMap { put("method", JsonPrimitive(method)); if (args != null) put("args", args) }))
            pending.add(PendingCall(method, d))
            return d
        }

        val client =
            object : GiftingApi {
                @Suppress("UNCHECKED_CAST")
                override suspend fun getGifts(): List<Gift> = call("getGifts", null).await() as List<Gift>

                override suspend fun getMe(): Me = call("getMe", null).await() as Me

                override suspend fun getReceivedGifts(user: String): List<ReceivedGift> =
                    call("getReceivedGifts", JsonObject(mapOf("user" to JsonPrimitive(user)))).await().let { emptyList() }

                override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
                    val args = buildMap<String, JsonElement> {
                        put("receiver", JsonPrimitive(input.receiver))
                        put("giftId", JsonPrimitive(input.giftId))
                        input.reference?.let { put("reference", JsonPrimitive(it)) }
                    }
                    return call("sendGift", JsonObject(args)).await() as GiftTransaction
                }
            }

        val played = ArrayList<JsonObject>()
        val cancelled = ArrayList<Int>()
        val prefetched = ArrayList<String>()
        val sent = ArrayList<String>()
        val errors = ArrayList<String>()
        val player =
            object : EffectPlayer {
                override fun play(event: GiftEffectEvent): Int {
                    val id = played.size + 1
                    val g = event.gift
                    val gift =
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(g.id),
                                "name" to JsonPrimitive(g.name),
                                "price" to JsonPrimitive(g.price),
                                "image" to str(g.image),
                                "icon" to str(g.icon),
                            ),
                        )
                    val ev = buildMap<String, JsonElement> {
                        put("gift", gift)
                        event.sender?.let { put("sender", JsonPrimitive(it)) }
                        event.quantity?.let { put("quantity", JsonPrimitive(it)) }
                    }
                    played.add(JsonObject(mapOf("id" to JsonPrimitive(id), "event" to JsonObject(ev))))
                    return id
                }

                override fun cancel(id: Int) {
                    cancelled.add(id)
                }
            }

        val o = s["options"]?.obj() ?: JsonObject(emptyMap())
        val controller =
            GiftTrayController(
                GiftTrayOptions(
                    client = client,
                    receiver = o.string("receiver"),
                    reference = o.stringOrNull("reference"),
                    playOn = if (o.stringOrNull("playOn") == "success") PlayOn.Success else PlayOn.Tap,
                    effects = if (o["effects"]?.jsonPrimitive?.content == "false") null else ({ player }),
                    prefetch = { prefetched.add(it) },
                    onSent = { sent.add(it.id) },
                    onError = { errors.add(it.type) },
                ),
            )

        fun take(method: String, at: String): PendingCall {
            val idx = pending.indexOfFirst { it.method == method }
            assertTrue("$at: no pending $method", idx >= 0)
            return pending.removeAt(idx)
        }

        fun toError(e: JsonObject): Throwable =
            if (e.has("plain")) {
                RuntimeException(e.string("plain"))
            } else {
                GiftingException(e.intOrNull("status")!!, e.string("type"), e.string("message"), e.stringOrNull("requestId"))
            }

        fun value(method: String, v: JsonElement): Any? =
            when {
                method == "getGifts" -> v.arr().map { Gift.fromJson(gifts.getValue(it.jsonPrimitive.content)) }
                method == "getMe" -> Me.fromJson(v)
                method == "sendGift" && v is JsonPrimitive -> GiftTransaction.fromJson(transactions.getValue(v.content))
                else -> error("unsupported resolve value for $method")
            }

        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("mount") || step.has("refresh") -> backgroundScope.launch { controller.refresh() }
                step.has("dispose") -> controller.dispose()
                step.has("send") -> {
                    val g = Gift.fromJson(gifts.getValue(step.string("send")))
                    backgroundScope.launch { controller.send(g) }
                }
                step.has("resolve") -> {
                    val r = step.getValue("resolve").obj()
                    take(r.string("method"), at).result.complete(value(r.string("method"), r.getValue("value")))
                }
                step.has("reject") -> {
                    val r = step.getValue("reject").obj()
                    take(r.string("method"), at).result.completeExceptionally(toError(r.getValue("error").obj()))
                }
                step.has("expect") -> {
                    val x = step.getValue("expect").obj()
                    val st = controller.state.value
                    if (x.has("balance")) assertEquals("$at balance", x.intOrNull("balance")?.toLong(), st.balance)
                    if (x.has("user")) assertEquals("$at user", x.stringOrNull("user"), st.user)
                    if (x.has("loading")) assertEquals("$at loading", x.bool("loading"), st.loading)
                    if (x.has("testMode")) assertEquals("$at testMode", x.bool("testMode"), st.testMode)
                    if (x.has("gifts")) assertEquals("$at gifts", x.getValue("gifts").arr().map { it.jsonPrimitive.content }, st.gifts.map { it.id })
                    if (x.has("error")) {
                        val want = x.getValue("error")
                        if (want is JsonNull) {
                            assertEquals("$at error", null, st.error)
                        } else {
                            val e = st.error!!
                            val actual = mapOf<String, JsonElement>(
                                "status" to JsonPrimitive(e.status),
                                "type" to JsonPrimitive(e.type),
                                "message" to JsonPrimitive(e.message),
                                "requestId" to str(e.requestId),
                                "retryable" to JsonPrimitive(e.retryable),
                                "insufficientBalance" to JsonPrimitive(e.insufficientBalance),
                            )
                            for ((k, v) in want.obj()) assertEquals("$at error.$k", v, actual.getValue(k))
                        }
                    }
                    if (x.has("played")) assertEquals("$at played", x.getValue("played"), JsonArray(played))
                    if (x.has("playedCount")) assertEquals("$at playedCount", x.intOrNull("playedCount"), played.size)
                    if (x.has("cancelled")) assertEquals("$at cancelled", x.getValue("cancelled").arr().map { it.jsonPrimitive.content.toInt() }, cancelled)
                    if (x.has("sent")) assertEquals("$at sent", x.getValue("sent").arr().map { it.jsonPrimitive.content }, sent)
                    if (x.has("errors")) assertEquals("$at errors", x.getValue("errors").arr().map { it.jsonPrimitive.content }, errors)
                    if (x.has("prefetched")) assertEquals("$at prefetched", x.getValue("prefetched").arr().map { it.jsonPrimitive.content }, prefetched)
                    if (x.has("pending")) assertEquals("$at pending", x.getValue("pending").arr().map { it.jsonPrimitive.content }, pending.map { it.method })
                    if (x.has("lastCall")) assertEquals("$at lastCall", x.getValue("lastCall"), calls.last())
                    if (x.has("callCount")) {
                        val counts = LinkedHashMap<String, JsonElement>()
                        for (c in calls) {
                            val m = c.string("method")
                            counts[m] = JsonPrimitive((counts[m]?.jsonPrimitive?.content?.toInt() ?: 0) + 1)
                        }
                        assertEquals("$at callCount", x.getValue("callCount"), JsonObject(counts))
                    }
                }
                else -> error("$at: unknown step $step")
            }
            // Let every pending coroutine run until nothing more can run (no clock advance).
            runCurrent()
        }
    }
}

/** tray.json "sendButton": sendButtonState(...) must deep-equal `expect`. */
@RunWith(Parameterized::class)
class SendButtonConformanceTest(private val name: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() =
            Fixtures.conformance("tray.json").getValue("sendButton").obj().getValue("cases").arr().map { arrayOf<Any>(it.obj().string("name"), it) }
    }

    @org.junit.Test
    fun sendButton() {
        val input = case.getValue("input").obj()
        val gifts = input.getValue("gifts").arr().map {
            val g = it.obj()
            Gift(g.string("id"), g.string("id"), null, g.intOrNull("price")!!.toLong(), null, null, 0)
        }
        val r = sendButtonState(
            gifts = gifts,
            selectedId = input.stringOrNull("selectedId"),
            balance = input.intOrNull("balance")!!.toLong(),
            disabled = input.bool("disabled"),
            canTopUp = input.bool("canTopUp"),
        )
        val actual = JsonObject(
            mapOf(
                "selectedId" to (r.selectedId?.let { JsonPrimitive(it) } ?: JsonNull),
                "broke" to JsonPrimitive(r.broke),
                "label" to JsonPrimitive(r.label.wire),
                "pressable" to JsonPrimitive(r.pressable),
                "action" to JsonPrimitive(r.action.wire),
            ),
        )
        assertEquals(name, case.getValue("expect"), actual)
    }
}
