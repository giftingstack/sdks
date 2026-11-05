package com.giftingstack.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private val awayFile: JsonObject by lazy { Fixtures.conformance("away.json") }

/** A group written with `"gift": "<id>"`: the wire group built from `gifts[id]`. */
private fun group(g: JsonElement): AwayGroup {
    val o = g.obj()
    return AwayGroup.fromJson(JsonObject(o + ("gift" to awayFile.obj("gifts").getValue(o.string("gift")))))
}

private fun summary(key: String): AwaySummary {
    val s = awayFile.obj("summaries").obj(key)
    return AwaySummary.fromJson(JsonObject(s + ("groups" to JsonArray(s.getValue("groups").arr().map { group(it).toJson() }))))
}

private fun senderLabels(l: JsonObject?): AwaySenderLabels {
    val d = AwaySenderLabels()
    return AwaySenderLabels(
        someone = l?.stringOrNull("someone") ?: d.someone,
        pair = l?.stringOrNull("pair") ?: d.pair,
        oneOther = l?.stringOrNull("oneOther") ?: d.oneOther,
        others = l?.stringOrNull("others") ?: d.others,
    )
}

/** away.json "plan": planAwayReplay(groups, options). */
@RunWith(Parameterized::class)
class AwayPlanConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("away.json", "plan") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun plan() {
        val names = c["names"]?.obj()
        val o = c["options"]?.obj()
        val d = AwayReplayOptions()
        val t = o?.get("thresholds")?.obj()
        val plan =
            planAwayReplay(
                c.getValue("groups").arr().map(::group),
                AwayReplayOptions(
                    maxEffects = o?.intOrNull("maxEffects") ?: d.maxEffects,
                    budgetMs = o?.intOrNull("budgetMs")?.toLong() ?: d.budgetMs,
                    thresholds = t?.let { TierThresholds(it.intOrNull("mediumFrom") ?: DEFAULT_THRESHOLDS.mediumFrom, it.intOrNull("largeFrom") ?: DEFAULT_THRESHOLDS.largeFrom) },
                    quality = o?.stringOrNull("quality")?.let { EffectQuality.fromWire(it) } ?: d.quality,
                    reducedMotion = o?.get("reducedMotion")?.str() == "true",
                    resolveName = { u -> names?.stringOrNull(u) ?: u },
                    labels = senderLabels(o?.get("labels")?.obj()),
                ),
            )
        val want = c.obj("expect")
        assertEquals("$name: endMs", want.intOrNull("endMs")!!.toLong(), plan.endMs)
        val items = want.getValue("items").arr()
        assertEquals("$name: items", items.size, plan.items.size)
        plan.items.forEachIndexed { i, item ->
            val e = item.event
            val actual =
                mapOf(
                    "gift" to JsonPrimitive(e.gift.id),
                    "name" to JsonPrimitive(e.gift.name),
                    "price" to JsonPrimitive(e.gift.price),
                    "image" to (e.gift.image?.let { JsonPrimitive(it) } ?: JsonNull),
                    "icon" to (e.gift.icon?.let { JsonPrimitive(it) } ?: JsonNull),
                    "atMs" to JsonPrimitive(item.atMs),
                    "durationMs" to JsonPrimitive(item.durationMs),
                    "tier" to JsonPrimitive(item.tier.wire),
                    "quantity" to JsonPrimitive(e.quantity),
                    "sender" to JsonPrimitive(e.sender),
                )
            for ((k, v) in items[i].obj()) assertEquals("$name: item ${i + 1}.$k", v, actual.getValue(k))
        }
    }
}

/** away.json "senderLabel": awaySenderLabel(names, senderCount, labels). */
@RunWith(Parameterized::class)
class AwaySenderLabelConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("away.json", "senderLabel") { _, o -> "${o["names"]} x${o["senderCount"]} ${o["labels"] ?: "{}"} -> ${o["expect"]}" }
    }

    @org.junit.Test
    fun label() {
        val names = c.getValue("names").arr().map { it.str() }
        assertEquals(name, c.string("expect"), awaySenderLabel(names, c.intOrNull("senderCount")!!, senderLabels(c["labels"]?.obj())))
    }
}

/** away.json "controller": an AwayController with the fake clock, a scripted client and a stub effect player. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(Parameterized::class)
class AwayControllerConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("away.json", "controller") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun scenario() = runTest {
        val clock = FakeClock()
        val script = ScriptedCalls()
        val played = ArrayList<JsonObject>()
        val errors = ArrayList<String>()
        var shown = 0
        var done = 0
        val o = s["options"]?.obj()

        val player =
            AwayEffectPlayer { event ->
                played.add(
                    JsonObject(
                        mapOf(
                            "atMs" to JsonPrimitive(clock.now),
                            "gift" to JsonPrimitive(event.gift.id),
                            "quantity" to JsonPrimitive(event.quantity),
                            "sender" to JsonPrimitive(event.sender),
                        ),
                    ),
                )
                played.size
            }
        val client =
            object : AwayApi {
                override suspend fun getAway(query: AwayQuery): AwaySummary {
                    val args = buildMap<String, JsonElement> {
                        query.since?.let { put("since", JsonPrimitive(it)) }
                        query.maxGroups?.let { put("maxGroups", JsonPrimitive(it)) }
                    }
                    return script.call("getAway", JsonObject(args)).await() as AwaySummary
                }

                override suspend fun ackAway(cursor: String) {
                    script.call("ackAway", JsonObject(mapOf("cursor" to JsonPrimitive(cursor)))).await()
                }
            }
        val d = AwayControllerOptions(client)
        val controller =
            AwayController(
                AwayControllerOptions(
                    client = client,
                    effects = if (o?.get("effects")?.str() == "false") null else ({ player }),
                    reducedMotion = if (o?.get("reducedMotion")?.str() == "true") ({ true }) else null,
                    ackOn =
                        when (o?.stringOrNull("ackOn")) {
                            "finished" -> AwayAckOn.Finished
                            "manual" -> AwayAckOn.Manual
                            else -> AwayAckOn.Shown
                        },
                    maxGroups = o?.intOrNull("maxGroups"),
                    maxEffects = o?.intOrNull("maxEffects") ?: d.maxEffects,
                    budgetMs = o?.intOrNull("budgetMs")?.toLong() ?: d.budgetMs,
                    onShow = { shown++ },
                    onDone = { done++ },
                    onError = { errors.add(it.type) },
                ),
                scope = backgroundScope,
                now = { clock.now },
                timers = clock.timersApi,
            )

        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("check") -> controller.check()
                step.has("foreground") -> controller.foreground()
                step.has("start") -> controller.start()
                step.has("dismiss") -> controller.dismiss()
                step.has("ack") -> controller.ack()
                step.has("dispose") -> controller.dispose()
                step.has("advance") -> clock.advance(step.intOrNull("advance")!!.toLong())
                step.has("resolve") -> {
                    val r = step.obj("resolve")
                    val method = r.string("method")
                    script.take(method, at).result.complete(if (method == "getAway") summary(r.string("value")) else Unit)
                }
                step.has("reject") -> {
                    val r = step.obj("reject")
                    script.take(r.string("method"), at).result.completeExceptionally(errorFromJson(r.obj("error")))
                }
                step.has("expect") -> {
                    val x = step.obj("expect")
                    val st2 = controller.state.value
                    if (x.has("status")) assertEquals("$at status", x.string("status"), st2.status.name.lowercase())
                    if (x.has("summaryCursor")) assertEquals("$at summaryCursor", x.stringOrNull("summaryCursor"), st2.summary?.cursor)
                    if (x.has("planEndMs")) assertEquals("$at planEndMs", x.intOrNull("planEndMs")?.toLong(), st2.plan?.endMs)
                    if (x.has("played")) assertEquals("$at played", x.getValue("played"), JsonArray(played))
                    if (x.has("calls")) assertEquals("$at calls", x.getValue("calls"), script.callsJson)
                    if (x.has("pending")) assertEquals("$at pending", x.getValue("pending").arr().map { it.str() }, script.pending.map { it.method })
                    if (x.has("shown")) assertEquals("$at shown", x.intOrNull("shown"), shown)
                    if (x.has("done")) assertEquals("$at done", x.intOrNull("done"), done)
                    if (x.has("errors")) assertEquals("$at errors", x.getValue("errors").arr().map { it.str() }, errors)
                }
                else -> error("$at: unknown step $step")
            }
            settle(clock)
        }
    }
}

/** away.json "client": getAway (with and without a query) and ackAway (204, retry, 400). */
@RunWith(Parameterized::class)
class AwayClientConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("away.json", "client") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun scenario() {
        runClientScenario(name, s)
    }
}
