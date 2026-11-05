package com.giftingstack.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private fun board(key: String): Leaderboard = Leaderboard.fromJson(Fixtures.conformance("leaderboard.json").obj("boards").getValue(key))

/** leaderboard.json "pollMs": leaderboardPollMs(refreshIntervalMs), at least 5 s once polling is on (R-17). */
class LeaderboardPollMsConformanceTest {
    private val poll = Fixtures.conformance("leaderboard.json").obj("pollMs")

    @Test
    fun minimum() {
        assertEquals(poll.intOrNull("minPollMs")!!.toLong(), LEADERBOARD_MIN_POLL_MS)
    }

    @Test
    fun cases() {
        for (c in poll.getValue("cases").arr().map { it.obj() }) {
            assertEquals("$c", c.intOrNull("expect")!!.toLong(), leaderboardPollMs(c.intOrNull("refreshIntervalMs")!!.toLong()))
        }
        assertEquals(0L, leaderboardPollMs(null))
    }
}

/** leaderboard.json "rankLabel". */
@RunWith(Parameterized::class)
class LeaderboardRankLabelConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("leaderboard.json", "rankLabel") { _, o -> "${o["rank"]} ${o["labels"] ?: "{}"} -> ${o["expect"]}" }
    }

    @Test
    fun label() {
        val rank = c.intOrNull("rank")
        val overflow = c["labels"]?.obj()?.stringOrNull("overflow")
        assertEquals(name, c.string("expect"), if (overflow == null) leaderboardRankLabel(rank) else leaderboardRankLabel(rank, overflow))
    }
}

/** leaderboard.json "pin": pinnedMe(board, limit). */
@RunWith(Parameterized::class)
class LeaderboardPinConformanceTest(private val name: String, private val c: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = arrayParams("leaderboard.json", "pin") { _, o -> o.string("name") }
    }

    @Test
    fun pin() {
        val me = c["me"]?.takeIf { it !is JsonNull }?.let { LeaderboardMe.fromJson(it) }
        val b =
            Leaderboard(
                board = LeaderboardBoard.Senders,
                period = LeaderboardPeriod.Week,
                metric = LeaderboardMetric.fromWire(c.string("metric")),
                label = "2026-W41",
                startsAt = null,
                endsAt = null,
                asOf = "2026-10-11T07:30:00.000Z",
                data = c.getValue("data").arr().map { LeaderboardEntry.fromJson(it) },
                hasMore = false,
                me = me,
            )
        val pinned = pinnedMe(b, c.intOrNull("limit")!!)
        val expected = c.bool("expect")
        assertEquals(name, expected, pinned != null)
        if (expected) assertEquals(name, me, pinned)
    }
}

/** leaderboard.json "rankColors": the medal tokens and their contrast with `noticeBigText`. */
class LeaderboardRankColorsConformanceTest {
    private val rc = Fixtures.conformance("leaderboard.json").obj("rankColors")

    @Test
    fun tokensAreTheFixturesAndReachTheContrastInEveryTheme() {
        val tokens = rc.obj("tokens").mapValues { it.value.str() }
        assertEquals(tokens, RANK_COLORS)
        val themes = mapOf("defaultTheme" to defaultThemeTokens, "darkTheme" to darkThemeTokens, "lightTheme" to lightThemeTokens)
        assertEquals("the fixture names the three themes", setOf("defaultTheme", "darkTheme", "lightTheme"), rc.getValue("themes").arr().map { it.str() }.toSet())
        assertEquals("noticeBigText", rc.string("text"))
        val min = rc.getValue("min").let { (it as JsonPrimitive).content.toDouble() }
        for (name in rc.getValue("themes").arr().map { it.str() }) {
            val text = themes.getValue(name).noticeBigText
            for ((token, color) in tokens) {
                assertTrue("$name.noticeBigText on $token: ${contrastRatio(color, text)}", contrastRatio(color, text) >= min)
            }
        }
    }
}

/** leaderboard.json "controller": a LeaderboardController with the fake clock and a scripted client. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(Parameterized::class)
class LeaderboardControllerConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("leaderboard.json", "controller") { _, o -> o.string("name") }
    }

    @Test
    fun scenario() = runTest {
        val clock = FakeClock()
        val script = ScriptedCalls()
        val errors = ArrayList<String>()
        val o = s["options"]?.obj()

        val client =
            object : LeaderboardApi {
                override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard {
                    val q = buildMap<String, JsonElement> {
                        query.period?.let { put("period", JsonPrimitive(it.wire)) }
                        query.metric?.let { put("metric", JsonPrimitive(it.wire)) }
                        query.at?.let { put("at", JsonPrimitive(it)) }
                        query.limit?.let { put("limit", JsonPrimitive(it)) }
                        query.includeMe?.let { put("includeMe", JsonPrimitive(it)) }
                    }
                    val args = JsonObject(mapOf("board" to JsonPrimitive(board.wire), "query" to JsonObject(q)))
                    return script.call("getLeaderboard", args).await() as Leaderboard
                }
            }
        val d = LeaderboardControllerOptions(client)
        val controller =
            LeaderboardController(
                LeaderboardControllerOptions(
                    client = client,
                    board = o?.stringOrNull("board")?.let { LeaderboardBoard.fromWire(it) } ?: d.board,
                    periods = o?.get("periods")?.arr()?.map { LeaderboardPeriod.fromWire(it.str()) } ?: d.periods,
                    initialPeriod = o?.stringOrNull("initialPeriod")?.let { LeaderboardPeriod.fromWire(it) } ?: d.initialPeriod,
                    metric = o?.stringOrNull("metric")?.let { LeaderboardMetric.fromWire(it) },
                    limit = o?.intOrNull("limit") ?: d.limit,
                    includeMe = o?.get("includeMe")?.str()?.toBoolean() ?: d.includeMe,
                    onError = { errors.add(it.type) },
                ),
                scope = backgroundScope,
                now = { clock.now },
            )

        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            when {
                step.has("start") -> controller.start()
                step.has("setPeriod") -> controller.setPeriod(LeaderboardPeriod.fromWire(step.string("setPeriod")))
                step.has("setMetric") -> controller.setMetric(LeaderboardMetric.fromWire(step.string("setMetric")))
                step.has("refresh") -> controller.refresh()
                step.has("dispose") -> controller.dispose()
                step.has("advance") -> clock.advance(step.intOrNull("advance")!!.toLong())
                step.has("resolve") -> {
                    val r = step.obj("resolve")
                    script.take(r.string("method"), at).result.complete(board(r.string("value")))
                }
                step.has("reject") -> {
                    val r = step.obj("reject")
                    script.take(r.string("method"), at).result.completeExceptionally(errorFromJson(r.obj("error")))
                }
                step.has("expect") -> {
                    val x = step.obj("expect")
                    val st2 = controller.state.value
                    if (x.has("status")) assertEquals("$at status", x.string("status"), st2.status.name.lowercase())
                    if (x.has("period")) assertEquals("$at period", x.string("period"), st2.period.wire)
                    if (x.has("periods")) assertEquals("$at periods", x.getValue("periods").arr().map { it.str() }, st2.periods.map { it.wire })
                    if (x.has("metric")) assertEquals("$at metric", x.string("metric"), st2.metric.wire)
                    if (x.has("rows")) {
                        val rows: JsonElement = st2.data?.let { b -> JsonArray(b.data.map { JsonPrimitive(it.user) }) } ?: JsonNull
                        assertEquals("$at rows", x.getValue("rows"), rows)
                    }
                    if (x.has("asOf")) assertEquals("$at asOf", x.stringOrNull("asOf"), st2.data?.asOf)
                    if (x.has("refreshing")) assertEquals("$at refreshing", x.bool("refreshing"), st2.refreshing)
                    if (x.has("error")) assertEquals("$at error", x.stringOrNull("error"), st2.error?.type)
                    if (x.has("pinned")) assertEquals("$at pinned", x.stringOrNull("pinned"), st2.pinned?.user)
                    if (x.has("calls")) assertEquals("$at calls", x.getValue("calls"), script.callsJson)
                    if (x.has("pending")) assertEquals("$at pending", x.intOrNull("pending"), script.pending.size)
                    if (x.has("errors")) assertEquals("$at errors", x.getValue("errors").arr().map { it.str() }, errors)
                }
                else -> error("$at: unknown step $step")
            }
            settle(clock)
        }
    }
}

/** leaderboard.json "client": the leaderboard call, its query order and its 503/400 errors. */
@RunWith(Parameterized::class)
class LeaderboardClientConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = arrayParams("leaderboard.json", "client") { _, o -> o.string("name") }
    }

    @Test
    fun scenario() {
        runClientScenario(name, s)
    }
}
