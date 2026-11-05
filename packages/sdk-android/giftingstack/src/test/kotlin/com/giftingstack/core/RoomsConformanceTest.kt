package com.giftingstack.core

import kotlin.math.floor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * The six rooms-*.json fixtures (SPEC sections 17-18); conformance/README.md ("Rooms fixtures")
 * is the contract. Port of `packages/sdk-js/test/rooms-conformance.test.ts`.
 */

private fun num(d: Double): JsonPrimitive = if (d == floor(d) && Math.abs(d) < 1e15) JsonPrimitive(d.toLong()) else JsonPrimitive(d)

private fun battleJson(b: RoomBattle?): JsonElement =
    if (b == null) {
        JsonNull
    } else {
        JsonObject(
            mapOf(
                "round" to JsonPrimitive(b.round),
                "started" to JsonPrimitive(b.started),
                "ends" to JsonPrimitive(b.ends),
                "scores" to
                    JsonArray(
                        b.scores.map {
                            JsonObject(mapOf("id" to JsonPrimitive(it.id), "units" to JsonPrimitive(it.units), "gifts" to JsonPrimitive(it.gifts)))
                        },
                    ),
            ),
        )
    }

/** The parsed message in the wire names of SPEC 17.4 (`receiver: null` when missing). */
internal fun roomMessageJson(m: RoomServerMessage?): JsonElement =
    when (m) {
        null -> JsonNull
        is RoomServerMessage.Gift -> m.gift.toJson()
        is RoomServerMessage.Welcome ->
            JsonObject(
                buildMap {
                    put("t", JsonPrimitive("welcome"))
                    put("viewers", JsonPrimitive(m.viewers))
                    put("gap", JsonPrimitive(m.gap))
                    put("replay", JsonArray(m.replay.map { it.toJson() }))
                    put("ttl", num(m.ttl))
                    put("now", JsonPrimitive(m.now))
                    if (m.battle != null) put("battle", battleJson(m.battle))
                },
            )
        is RoomServerMessage.Scores -> JsonObject(mapOf("t" to JsonPrimitive("scores"), "battle" to battleJson(m.battle)))
        is RoomServerMessage.Viewers -> JsonObject(mapOf("t" to JsonPrimitive("viewers"), "n" to JsonPrimitive(m.n)))
        is RoomServerMessage.Batch -> JsonObject(mapOf("t" to JsonPrimitive("batch"), "events" to JsonArray(m.events.map { it.toJson() })))
        RoomServerMessage.Pong -> JsonObject(mapOf("t" to JsonPrimitive("pong")))
    }

/** A JSON frame object is sent as its JSON text; `text` is sent as is. */
private fun frameText(c: JsonObject): String = c.stringOrNull("text") ?: c.getValue("frame").toString()

// ================================================================ rooms-protocol.json

@RunWith(Parameterized::class)
class RoomsProtocolParseTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("rooms-protocol.json", "parse") { _, o -> o.string("name") }
    }

    @Test
    fun parse() {
        assertEquals(name, c.getValue("expect"), roomMessageJson(parseRoomFrame(frameText(c))))
    }
}

class RoomsProtocolHelpersTest {
    private val f = Fixtures.conformance("rooms-protocol.json")

    @Test
    fun hello() {
        for (c in f.getValue("hello").arr().map { it.obj() }) {
            val last = if (c["last"] is JsonNull) null else c.getValue("last").str().toLong()
            assertEquals(c.getValue("expect"), Json.parseToJsonElement(roomHelloFrame(last)))
        }
    }

    @Test
    fun helloKeysAreInOrder() {
        assertEquals("""{"t":"hello","v":1,"last":null}""", roomHelloFrame(null))
        assertEquals("""{"t":"hello","v":1,"last":1760180000123001}""", roomHelloFrame(1760180000123001))
    }

    @Test
    fun url() {
        for (c in f.getValue("url").arr().map { it.obj() }) {
            val base = c.stringOrNull("baseUrl")
            assertEquals(c.string("expect"), if (base == null) roomUrl(c.string("room")) else roomUrl(c.string("room"), base))
        }
    }

    @Test
    fun tokenUser() {
        for (c in f.getValue("tokenUser").arr().map { it.obj() }) {
            assertEquals(c.string("token"), c.stringOrNull("expect"), roomTokenUser(c.string("token")))
        }
    }

    @Test
    fun roomIdRule() {
        assertTrue(isValidRoomId("live_123") && isValidRoomId("match:42.a-b") && isValidRoomId("x".repeat(64)))
        assertTrue(!isValidRoomId("") && !isValidRoomId("x".repeat(65)) && !isValidRoomId("a b") && !isValidRoomId("a/b") && !isValidRoomId("é") && !isValidRoomId("a\n"))
    }
}

// ================================================================ rooms-reconnect.json

@RunWith(Parameterized::class)
class RoomsReconnectTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("rooms-reconnect.json", "cases") { _, o -> o.string("name") }
    }

    @Test
    fun decision() {
        var calls = 0
        val random = c["random"]?.str()?.toDouble()
        val d =
            roomRetryDecision(RoomRetryInput(c.intOrNull("code")!!, c.string("reason"), c.intOrNull("attempt")!!, c.intOrNull("limited")!!)) {
                calls++
                assertNotNull("$name: random() called but the case gives none", random)
                random!!
            }
        val want = c.obj("expect")
        when (d) {
            is RoomRetryDecision.Stop ->
                assertEquals(
                    name,
                    want,
                    JsonObject(
                        buildMap<String, JsonElement> {
                            put("retry", JsonPrimitive(false))
                            if (d.resumable) put("resumable", JsonPrimitive(true))
                            if (d.exhausted) put("exhausted", JsonPrimitive(true))
                        },
                    ),
                )
            is RoomRetryDecision.Retry ->
                assertEquals(
                    name,
                    want,
                    JsonObject(
                        mapOf(
                            "retry" to JsonPrimitive(true),
                            "delayMs" to JsonPrimitive(d.delayMs),
                            "refreshToken" to JsonPrimitive(d.refreshToken),
                            "limited" to JsonPrimitive(d.limited),
                        ),
                    ),
                )
        }
        assertTrue("$name: random() called $calls times", calls <= 1)
    }
}

// ================================================================ rooms-filter.json

private val filterFile: JsonObject by lazy { Fixtures.conformance("rooms-filter.json") }

private fun filterOptions(o: JsonObject?): RoomEventFilterOptions {
    val d = RoomEventFilterOptions()
    val t = o?.get("thresholds")?.obj()
    return RoomEventFilterOptions(
        user = o?.stringOrNull("user"),
        skipOwn = o?.get("skipOwn")?.str()?.toBoolean() ?: d.skipOwn,
        maxReplayAgeMs = o?.intOrNull("maxReplayAgeMs")?.toLong() ?: d.maxReplayAgeMs,
        minTier = o?.stringOrNull("minTier")?.let { EffectTier.fromWire(it) } ?: d.minTier,
        thresholds = TierThresholds(t?.intOrNull("mediumFrom") ?: d.thresholds.mediumFrom, t?.intOrNull("largeFrom") ?: d.thresholds.largeFrom),
    )
}

@RunWith(Parameterized::class)
class RoomsFilterTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("rooms-filter.json", "scenarios") { _, o -> o.string("name") }
    }

    private fun ev(n: String): RoomGiftMessage {
        val m = parseRoomFrame(filterFile.obj("events").getValue(n).toString())
        assertTrue("$n parses", m is RoomServerMessage.Gift)
        return (m as RoomServerMessage.Gift).gift
    }

    @Test
    fun scenario() {
        val filter = RoomEventFilter(filterOptions(s["options"]?.obj()))
        var fills = 0
        var serverOffset = 0L
        for ((i, e) in s.getValue("steps").arr().withIndex()) {
            val step = e.obj()
            val at = "$name: step ${i + 1}"
            val localNow = step.intOrNull("at")!!.toLong()
            val r: RoomFilterResult =
                when {
                    step.has("welcome") -> {
                        val w = step.obj("welcome")
                        serverOffset = w.intOrNull("now")!!.toLong() - localNow
                        filter.welcome(
                            RoomServerMessage.Welcome(
                                w.intOrNull("viewers")!!.toLong(),
                                w.bool("gap"),
                                w.getValue("replay").arr().map { ev(it.str()) },
                                w.getValue("ttl").str().toDouble(),
                                w.intOrNull("now")!!.toLong(),
                            ),
                            localNow,
                        )
                    }
                    step.has("live") -> filter.live(step.getValue("live").arr().map { ev(it.str()) }, localNow)
                    step.has("batch") -> {
                        // A wire `batch` frame: parsed, then its gifts go through `live` in order.
                        val frame =
                            JsonObject(
                                mapOf(
                                    "t" to JsonPrimitive("batch"),
                                    "events" to JsonArray(step.getValue("batch").arr().map { filterFile.obj("events").getValue(it.str()) }),
                                ),
                            )
                        val m = parseRoomFrame(frame.toString())
                        assertTrue("$at batch parsed", m is RoomServerMessage.Batch)
                        filter.live((m as RoomServerMessage.Batch).events, localNow)
                    }
                    step.has("fill") -> {
                        val list = ArrayList<RoomGiftMessage>()
                        repeat(step.intOrNull("fill")!!) {
                            fills++
                            list.add(
                                RoomGiftMessage(
                                    id = 1000L + fills,
                                    at = localNow + serverOffset,
                                    tx = "gtx_fill_$fills",
                                    gift = RoomGiftInfo("rose", "Rose", 10, null),
                                    quantity = 1,
                                    sender = RoomSender("filler"),
                                    receiver = "host",
                                ),
                            )
                        }
                        filter.live(list, localNow)
                    }
                    else -> error("$at: unknown step")
                }
            val x = step["expect"]?.obj() ?: continue
            x["passed"]?.let { assertEquals("$at passed", it.arr().map { t -> t.str() }, r.events.map { m -> m.tx }) }
            if (x.has("last")) assertEquals("$at last", x.intOrNull("last")?.toLong(), filter.last)
            if (x.has("gap")) assertEquals("$at gap", x.bool("gap"), r.gap)
        }
    }

    @Test
    fun seenTxKeepsTheLast256() {
        val f = RoomEventFilter()
        f.welcome(RoomServerMessage.Welcome(0, false, emptyList(), 10.0, 1_000_000), 0)
        for (k in 1..300) {
            f.live(listOf(RoomGiftMessage(k.toLong(), 1_000_000, "t$k", RoomGiftInfo("g", "G", 1, null), 1, RoomSender("u"), null)), 0)
        }
        assertEquals(256, f.seenTx().size)
        assertEquals("t45", f.seenTx().first())
        assertEquals("t300", f.seenTx().last())
    }
}

// ================================================================ rooms-mapping.json

@RunWith(Parameterized::class)
class RoomsMappingTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("rooms-mapping.json", "cases") { _, o -> o.string("name") }
    }

    @Test
    fun mapping() {
        val f = Fixtures.conformance("rooms-mapping.json")
        val msg = (parseRoomFrame(c.getValue("event").toString()) as RoomServerMessage.Gift).gift
        val names = c["names"]?.obj()
        val out =
            roomGiftToEffect(
                msg,
                RoomMappingOptions(
                    catalog = if (c["catalog"]?.str() == "true") f.getValue("catalog").arr().map { Gift.fromJson(it) } else null,
                    resolveName = names?.let { n -> { u: String -> n.stringOrNull(u) } },
                    replayed = c["replayed"]?.str()?.toBoolean() ?: false,
                ),
            )
        val actual =
            buildMap<String, JsonElement> {
                put(
                    "gift",
                    JsonObject(
                        mapOf(
                            "id" to JsonPrimitive(out.gift.id),
                            "name" to JsonPrimitive(out.gift.name),
                            "price" to JsonPrimitive(out.gift.price),
                            "image" to out.gift.image.json(),
                            "icon" to out.gift.icon.json(),
                        ),
                    ),
                )
                // A missing `sender` key means absent.
                out.sender?.let { put("sender", JsonPrimitive(it)) }
                put("quantity", JsonPrimitive(out.quantity))
                put("id", JsonPrimitive(out.id))
                put("tx", JsonPrimitive(out.tx))
                put("at", JsonPrimitive(out.at))
                put("senderId", JsonPrimitive(out.senderId))
                put("senderName", out.senderName.json())
                put("receiverId", out.receiverId.json())
                put("replayed", JsonPrimitive(out.replayed))
            }
        assertEquals(name, c.getValue("expect"), JsonObject(actual))
        // `toEffect` is what the layer plays.
        val e = out.toEffect()
        assertEquals(out.sender, e.sender)
        assertEquals(out.quantity.toInt(), e.quantity)
        assertEquals(out.gift, e.gift)
    }
}

// ================================================================ rooms-session.json

private class FakeRoomSocket(val url: String, val protocols: List<String>, val handlers: RoomSocketHandlers) : RoomSocket {
    val sent = ArrayList<JsonElement>()
    var closed: Pair<Int, String>? = null

    override fun send(data: String) {
        // Frames are JSON objects, or plain text ("ping"), kept as a string.
        sent.add(if (data.startsWith("{")) Json.parseToJsonElement(data) else JsonPrimitive(data))
    }

    override fun close(code: Int, reason: String) {
        closed = code to reason
    }

    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "url" to JsonPrimitive(url),
                "protocols" to JsonArray(protocols.map { JsonPrimitive(it) }),
                "sent" to JsonArray(sent),
                "closed" to (closed?.let { JsonObject(mapOf("code" to JsonPrimitive(it.first), "reason" to JsonPrimitive(it.second))) } ?: JsonNull),
            ),
        )
}

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(Parameterized::class)
class RoomsSessionTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("rooms-session.json", "scenarios") { _, o -> o.string("name") }
    }

    @Test
    fun scenario() = runTest {
        val clock = FakeClock()
        val randoms = s["random"]?.arr()?.map { it.str().toDouble() }
        var r = 0
        val random = {
            if (randoms == null) {
                0.5
            } else {
                assertTrue("random() call ${r + 1} beyond the list", r < randoms.size)
                randoms[r++]
            }
        }
        val tokens = ArrayList<Boolean>()
        val pendingTokens = ArrayList<CompletableDeferred<String>>()
        val sockets = ArrayList<FakeRoomSocket>()
        val events = ArrayList<RoomGiftEvent>()
        val viewers = ArrayList<Long>()
        var gaps = 0
        val o = s.obj("options")

        val room =
            RoomClient(
                RoomClientOptions(
                    room = o.string("room"),
                    getToken = { refresh ->
                        tokens.add(refresh)
                        val d = CompletableDeferred<String>()
                        pendingTokens.add(d)
                        d.await()
                    },
                    socket = { url, protocols, handlers -> FakeRoomSocket(url, protocols, handlers).also { sockets.add(it) } },
                    scope = backgroundScope,
                    timers = clock.timersApi,
                    user = o.stringOrNull("user"),
                    skipOwn = o["skipOwn"]?.str()?.toBoolean() ?: true,
                    heartbeatMs = o.intOrNull("heartbeatMs")?.toLong() ?: ROOM_HEARTBEAT_MS,
                    refreshJitterMs = o.intOrNull("refreshJitterMs")?.toLong() ?: 0L,
                    onEvent = { events.add(it) },
                    onViewers = { viewers.add(it) },
                    onGap = { gaps++ },
                    now = { clock.now },
                    random = random,
                ),
            )
        fun newest(at: String): FakeRoomSocket {
            assertTrue("$at: no socket", sockets.isNotEmpty())
            return sockets.last()
        }

        for ((i, e) in s.getValue("steps").arr().withIndex()) {
            val step = e.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("start") -> room.start()
                step.has("leave") -> room.leave()
                step.has("pause") -> room.pause()
                step.has("resume") -> room.resume()
                step.has("reconnectNow") -> room.reconnectNow()
                step.has("advance") -> clock.advance(step.intOrNull("advance")!!.toLong())
                step.has("token") -> {
                    assertTrue("$at: no pending getToken", pendingTokens.isNotEmpty())
                    pendingTokens.removeAt(0).complete(step.string("token"))
                }
                step.has("tokenFail") -> {
                    assertTrue("$at: no pending getToken", pendingTokens.isNotEmpty())
                    pendingTokens.removeAt(0).completeExceptionally(RuntimeException("token server down"))
                }
                step.has("open") -> newest(at).handlers.onOpen()
                step.has("receive") -> {
                    val rv = step.getValue("receive")
                    val data = if (rv is JsonPrimitive && rv.isString) rv.content else rv.toString()
                    newest(at).handlers.onMessage(data)
                }
                step.has("close") -> {
                    val c = step.obj("close")
                    newest(at).handlers.onClose(c.intOrNull("code")!!, c.string("reason"))
                }
                !step.has("expect") -> error("$at: unknown step $step")
            }
            settle(clock)

            val x = step["expect"]?.obj() ?: continue
            x["state"]?.obj()?.let { want ->
                val st = room.getState()
                val have =
                    mapOf(
                        "status" to JsonPrimitive(st.status.wire),
                        "attempt" to JsonPrimitive(st.attempt),
                        "retryInMs" to (st.retryInMs?.let { JsonPrimitive(it) } ?: JsonNull),
                        "code" to (st.code?.let { JsonPrimitive(it) } ?: JsonNull),
                        "reason" to st.reason.json(),
                        "viewers" to (st.viewers?.let { JsonPrimitive(it) } ?: JsonNull),
                    )
                for ((k, v) in want) assertEquals("$at state.$k", v, have.getValue(k))
            }
            x["tokens"]?.let { assertEquals("$at tokens", it.arr().map { b -> b.str().toBoolean() }, tokens) }
            x["sockets"]?.arr()?.let { want ->
                assertEquals("$at socket count", want.size, sockets.size)
                want.forEachIndexed { k, w ->
                    val got = sockets[k].toJson()
                    for ((key, v) in w.obj()) assertEquals("$at sockets[$k].$key", v, got.getValue(key))
                }
            }
            x["events"]?.arr()?.let { want ->
                val got =
                    events.mapIndexed { k, ev ->
                        buildMap<String, JsonElement> {
                            put("tx", JsonPrimitive(ev.tx))
                            put("sender", ev.sender.json())
                            put("replayed", JsonPrimitive(ev.replayed))
                            // `quantity` is compared only where the fixture lists it.
                            if (k < want.size && want[k].obj().has("quantity")) put("quantity", JsonPrimitive(ev.quantity))
                        }.let { JsonObject(it) }
                    }
                assertEquals("$at events", JsonArray(want), JsonArray(got))
            }
            x["viewers"]?.let { assertEquals("$at viewers", it.arr().map { v -> v.str().toLong() }, viewers) }
            if (x.has("gaps")) assertEquals("$at gaps", x.intOrNull("gaps"), gaps)
        }
    }
}

// ================================================================ rooms-battle.json

@RunWith(Parameterized::class)
class RoomsBattleParseTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("rooms-battle.json", "parse") { _, o -> o.string("name") }
    }

    @Test
    fun parse() {
        assertEquals(name, c.getValue("expect"), roomMessageJson(parseRoomFrame(frameText(c))))
    }
}

@RunWith(Parameterized::class)
class RoomsBattleViewTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("rooms-battle.json", "view") { _, o -> o.string("name") }
    }

    @Test
    fun view() {
        val frame = JsonObject(mapOf("t" to JsonPrimitive("scores"), "battle" to c.getValue("battle")))
        val battle = (parseRoomFrame(frame.toString()) as RoomServerMessage.Scores).battle!!
        val serverNow = if (c["serverNow"] is JsonNull) null else c.getValue("serverNow").str().toLong()
        val v = battleView(battle, serverNow)
        val got =
            JsonObject(
                mapOf(
                    "round" to JsonPrimitive(v.round),
                    "open" to JsonPrimitive(v.open),
                    "remainingMs" to JsonPrimitive(v.remainingMs),
                    "total" to JsonPrimitive(v.total),
                    "sides" to
                        JsonArray(
                            v.sides.map {
                                JsonObject(
                                    mapOf(
                                        "id" to JsonPrimitive(it.id),
                                        "units" to JsonPrimitive(it.units),
                                        "gifts" to JsonPrimitive(it.gifts),
                                        "share" to num(it.share),
                                    ),
                                )
                            },
                        ),
                    "leader" to (v.leader?.let { JsonPrimitive(it) } ?: JsonNull),
                ),
            )
        assertEquals(name, c.getValue("expect"), got)
    }
}

class RoomsBattleFixtureTest {
    @Test
    fun theFixtureHasCases() {
        val f = Fixtures.conformance("rooms-battle.json")
        assertTrue(f.getValue("parse").arr().size > 6)
        assertTrue(f.getValue("view").arr().size > 4)
    }
}
