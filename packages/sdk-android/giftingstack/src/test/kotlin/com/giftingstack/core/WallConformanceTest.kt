package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private val wallFile: JsonObject by lazy { Fixtures.conformance("wall.json") }

/** `[{ "gift": id, "count": n }]` as received gifts built from `gifts[id]`. */
private fun received(items: JsonArray): List<ReceivedGift> =
    items.map {
        val o = it.obj()
        ReceivedGift(GiftRef.fromJson(wallFile.obj("gifts").getValue(o.string("gift"))), o.intOrNull("count")!!)
    }

private fun chipJson(c: WallChip): JsonObject =
    when (c) {
        is WallChip.Gift -> JsonObject(mapOf("gift" to JsonPrimitive(c.gift.id), "count" to JsonPrimitive(c.count)))
        is WallChip.Overflow -> JsonObject(mapOf("overflow" to JsonPrimitive(c.count), "hidden" to JsonPrimitive(c.hidden)))
    }

/** wall.json "chips": wallChips(items, options). */
@RunWith(Parameterized::class)
class WallChipsConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("wall.json", "chips") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun chips() {
        val o = c["options"]?.obj()
        val chips =
            wallChips(
                received(c.getValue("items").arr()),
                max = o?.intOrNull("max") ?: DEFAULT_WALL_MAX,
                order = if (o?.stringOrNull("order") == "catalog") WallOrder.Catalog else WallOrder.Count,
            )
        assertEquals(name, c.getValue("expect"), JsonArray(chips.map(::chipJson)))
    }
}

/** wall.json "formatCount". */
@RunWith(Parameterized::class)
class FormatCountConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("wall.json", "formatCount") { _, o -> "${o.string("n")} ${o["labels"] ?: "{}"} -> ${o.string("expect")}" }
    }

    @org.junit.Test
    fun formatCount() {
        val l = c["labels"]?.obj()
        val labels =
            CountLabels(
                thousand = l?.stringOrNull("thousand") ?: "K",
                million = l?.stringOrNull("million") ?: "M",
                decimal = l?.stringOrNull("decimal") ?: ".",
            )
        assertEquals(name, c.string("expect"), formatCount(c.string("n").toLong(), labels))
    }
}

private class Batch(val items: List<GiftWallQueryItem>, val answer: CompletableDeferred<List<GiftWall>>)

private fun itemJson(i: GiftWallQueryItem): JsonObject =
    JsonObject(buildMap { put("receiver", JsonPrimitive(i.receiver)); i.reference?.let { put("reference", JsonPrimitive(it)) } })

/** wall.json "loader": a GiftWallLoader with the fake clock and a scripted batch call. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(Parameterized::class)
class WallLoaderConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("wall.json", "loader") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun scenario() = runTest {
        val clock = FakeClock()
        val batches = ArrayList<Batch>()
        val loader =
            GiftWallLoader(
                query = { items ->
                    val b = Batch(items, CompletableDeferred())
                    batches.add(b)
                    b.answer.await()
                },
                scope = backgroundScope,
                now = { clock.now },
                timers = clock.timersApi,
            )
        val promises = LinkedHashMap<String, Deferred<Result<List<ReceivedGift>>>>()
        fun ref(a: JsonArray) = if (a.size > 1) a[1].takeIf { it !is JsonNull }?.str() else null

        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("load") -> {
                    val a = step.getValue("load").arr()
                    promises[step.string("id")] =
                        backgroundScope.async(start = CoroutineStart.UNDISPATCHED) { runCatching { loader.load(a[0].str(), ref(a)) } }
                }
                step.has("advance") -> clock.advance(step.intOrNull("advance")!!.toLong())
                step.has("invalidate") -> {
                    val a = step.getValue("invalidate").arr()
                    loader.invalidate(a[0].str(), ref(a))
                }
                step.has("respond") -> {
                    val r = step.obj("respond")
                    val b = batches.getOrNull(r.intOrNull("batch")!! - 1)
                    assertTrue("$at: batch ${r.intOrNull("batch")}", b != null)
                    val walls = r.getValue("walls").arr()
                    b!!.answer.complete(
                        b.items.mapIndexed { k, item -> GiftWall(item.receiver, item.reference, received(walls[k].arr())) },
                    )
                }
                step.has("fail") -> {
                    val f = step.obj("fail")
                    batches[f.intOrNull("batch")!! - 1].answer.completeExceptionally(errorFromJson(f.obj("error")))
                }
                step.has("expect") -> {
                    val x = step.obj("expect")
                    if (x.has("batches")) {
                        assertEquals("$at batches", x.getValue("batches"), JsonArray(batches.map { b -> JsonArray(b.items.map(::itemJson)) }))
                    }
                    if (x.has("waiting")) {
                        val waiting = promises.filter { !it.value.isCompleted }.keys.toList()
                        assertEquals("$at waiting", x.getValue("waiting").arr().map { it.str() }, waiting)
                    }
                    for ((id, v) in x["resolved"]?.obj() ?: JsonObject(emptyMap())) {
                        assertTrue("$at $id is not settled", promises.getValue(id).isCompleted)
                        val r = promises.getValue(id).getCompleted()
                        assertTrue("$at resolved $id: ${r.exceptionOrNull()}", r.isSuccess)
                        assertEquals("$at resolved $id", v, compactGifts(r.getOrThrow()))
                    }
                    for ((id, v) in x["rejected"]?.obj() ?: JsonObject(emptyMap())) {
                        assertTrue("$at $id is not settled", promises.getValue(id).isCompleted)
                        val r = promises.getValue(id).getCompleted()
                        assertTrue("$at rejected $id", r.isFailure)
                        assertEquals("$at rejected $id", v.str(), (r.exceptionOrNull() as GiftingException).type)
                    }
                }
                else -> error("$at: unknown step $step")
            }
            settle(clock)
        }
    }
}

/** wall.json "client": the client calls of the wall (and received gifts with a reference). */
@RunWith(Parameterized::class)
class WallClientConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("wall.json", "client") { _, o -> o.string("name") }
    }

    @org.junit.Test
    fun scenario() {
        runClientScenario(name, s)
    }
}
