package com.giftingstack.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** effects.json "scenarios": drives the EffectScheduler with a virtual clock. */
@RunWith(Parameterized::class)
class EffectsConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        private val file = Fixtures.conformance("effects.json")

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = file.getValue("scenarios").arr().map { arrayOf<Any>(it.obj().string("name"), it) }

        fun gift(key: String): EffectGift {
            val g = file.getValue("gifts").obj().getValue(key).obj()
            // A missing "icon" key means "not given"; null means null. Both fall back to image.
            return EffectGift(g.string("id"), g.string("name"), g.intOrNull("price")!!.toLong(), g.stringOrNull("image"), g.stringOrNull("icon"))
        }
    }

    private fun noticeJson(d: NoticeData?): JsonElement =
        if (d == null) {
            JsonNull
        } else {
            JsonObject(
                mapOf(
                    "id" to JsonPrimitive(d.id),
                    "senderName" to JsonPrimitive(d.senderName),
                    "giftName" to JsonPrimitive(d.giftName),
                    "image" to (d.image?.let { JsonPrimitive(it) } ?: JsonNull),
                    "count" to JsonPrimitive(d.count),
                    "big" to JsonPrimitive(d.big),
                ) +
                    (
                        d.receiver?.let { r ->
                            mapOf(
                                "receiver" to
                                    JsonObject(
                                        buildMap {
                                            put("name", JsonPrimitive(r.name))
                                            r.side?.let { put("side", JsonPrimitive(it)) }
                                            put("color", r.color?.let { JsonPrimitive(it) } ?: JsonNull)
                                        },
                                    ),
                            )
                        } ?: emptyMap()
                    ),
            )
        }

    @org.junit.Test
    fun scenario() {
        var clock = 0L
        val opt = s["options"]?.obj()
        val scheduler = EffectScheduler(comboWindowMs = opt?.intOrNull("comboWindowMs")?.toLong() ?: DEFAULT_COMBO_WINDOW_MS, now = { clock })
        val th = opt?.get("thresholds")?.obj()
        scheduler.options =
            EffectSchedulerOptions(
                thresholds = TierThresholds(th?.intOrNull("mediumFrom") ?: 100, th?.intOrNull("largeFrom") ?: 10_000),
                quality = opt?.stringOrNull("quality")?.let { EffectQuality.fromWire(it) } ?: EffectQuality.High,
                reducedMotion = opt?.get("reducedMotion")?.jsonPrimitive?.content == "true",
            )
        var events = ArrayList<String>()
        val ended = ArrayList<Int>()
        var noticeDurationMs: Int? = null
        scheduler.listener =
            object : EffectSchedulerListener {
                override fun enter(effect: ScheduledEffect) {
                    events.add("enter:${effect.id}")
                }

                override fun exit(effect: ScheduledEffect) {
                    events.add("exit:${effect.id}")
                }

                override fun end(effect: ScheduledEffect) {
                    events.add("end:${effect.id}")
                    ended.add(effect.id)
                }

                override fun notice(notice: NoticeData, durationMs: Int) {
                    events.add("notice:${notice.id}")
                    noticeDurationMs = durationMs
                }

                override fun noticeHide() {
                    events.add("noticeHide")
                }

                override fun clear() {
                    events.add("clear")
                }
            }

        fun ints(a: JsonElement) = a.arr().map { it.jsonPrimitive.content.toInt() }

        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("play") -> {
                    step.intOrNull("atMs")?.let { clock = it.toLong() }
                    val p = step.getValue("play").obj()
                    val receiver =
                        p["receiver"]?.obj()?.let { r -> GiftEffectReceiver(r.string("name"), r.intOrNull("side"), r.stringOrNull("color")) }
                    val id = scheduler.play(GiftEffectEvent(gift(p.string("gift")), p.stringOrNull("sender"), p.intOrNull("quantity"), receiver))
                    step.intOrNull("returns")?.let { assertEquals("$at play() id", it, id) }
                }
                step.has("started") -> scheduler.started(step.intOrNull("started")!!)
                step.has("finished") -> scheduler.finished(step.intOrNull("finished")!!)
                step.has("cancel") -> scheduler.cancel(step.intOrNull("cancel")!!)
                step.has("clear") -> scheduler.clear()
                step.has("noticeExpired") -> scheduler.noticeExpired()
                step.has("expect") -> {
                    val x = step.getValue("expect").obj()
                    val notice = scheduler.notice()
                    if (x.has("events")) assertEquals("$at events", x.getValue("events").arr().map { it.jsonPrimitive.content }, events)
                    if (x.has("active")) assertEquals("$at active", ints(x.getValue("active")), scheduler.active().map { it.id })
                    if (x.has("activeTiers")) {
                        assertEquals("$at activeTiers", x.getValue("activeTiers").arr().map { it.jsonPrimitive.content }, scheduler.active().map { it.recipe.tier.wire })
                    }
                    if (x.has("queued")) assertEquals("$at queued", ints(x.getValue("queued")), scheduler.queued().map { it.id })
                    if (x.has("ended")) assertEquals("$at ended", ints(x.getValue("ended")), ended)
                    if (x.has("notice")) assertEquals("$at notice", x.getValue("notice"), noticeJson(notice.data))
                    if (x.has("noticeVisible")) assertEquals("$at noticeVisible", x.getValue("noticeVisible").jsonPrimitive.content == "true", notice.visible)
                    if (x.has("noticeOwner")) assertEquals("$at noticeOwner", x.intOrNull("noticeOwner"), notice.owner)
                    if (x.has("noticeDurationMs")) assertEquals("$at noticeDurationMs", x.intOrNull("noticeDurationMs"), noticeDurationMs)
                    events = ArrayList()
                }
                else -> error("$at: unknown step $step")
            }
        }
    }
}
