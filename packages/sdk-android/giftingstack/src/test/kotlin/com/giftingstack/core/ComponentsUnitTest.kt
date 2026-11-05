package com.giftingstack.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun gift(id: String, name: String = id.replaceFirstChar { it.uppercase() }) = GiftRef(id, name, "https://t/$id")

private fun rec(id: String, count: Int) = ReceivedGift(gift(id), count)

private fun awayGift(id: String, price: Int = 10) = AwayGift(id, id, price.toLong(), "https://t/$id-256", "https://t/$id-512")

private fun agroup(id: String, price: Int, count: Int, units: Long, vararg senders: String?) =
    AwayGroup(awayGift(id, price), count, units, senders.size, senders.map { AwaySender(it, 1) })

/** Rules of the three components that the fixtures do not spell out as cases, plus the pure texts. */
@OptIn(ExperimentalCoroutinesApi::class)
class ComponentsUnitTest {
    // ------------------------------------------------------------ wall

    @Test fun wallMaxBelowOneCountsAsOneAndShowsOnlyTheOverflow() {
        val chips = wallChips(listOf(rec("a", 5), rec("b", 3)), max = 0)
        assertEquals(listOf<WallChip>(WallChip.Overflow(8, 2)), chips)
    }

    @Test fun overflowSumsTheCountsOfEveryHiddenGiftNotTheKinds() {
        val items = (1..9).map { rec("g$it", it * 100) }
        val chips = wallChips(items, max = 4)
        // count order: g9 g8 g7 shown (max - 1), g6..g1 hidden: 600+500+400+300+200+100
        assertEquals(WallChip.Overflow(2100, 6), chips.last())
        assertEquals(listOf("g9", "g8", "g7"), chips.filterIsInstance<WallChip.Gift>().map { it.gift.id })
    }

    @Test fun overflowSumDoesNotWrapAroundAnInt() {
        val chips = wallChips(listOf(rec("a", 9), rec("b", Int.MAX_VALUE), rec("c", Int.MAX_VALUE)), max = 2)
        assertEquals(WallChip.Overflow(Int.MAX_VALUE.toLong() + 9, 2), chips.last())
    }

    @Test fun catalogOrderKeepsTheServersOrderAndZeroCountsAreDropped() {
        val chips = wallChips(listOf(rec("a", 1), rec("b", 0), rec("c", 7), rec("d", -2)), order = WallOrder.Catalog)
        assertEquals(listOf("a", "c"), chips.filterIsInstance<WallChip.Gift>().map { it.gift.id })
    }

    @Test fun equalCountsKeepTheCatalogOrder() {
        val chips = wallChips(listOf(rec("a", 3), rec("b", 5), rec("c", 3), rec("d", 5)))
        assertEquals(listOf("b", "d", "a", "c"), chips.filterIsInstance<WallChip.Gift>().map { it.gift.id })
    }

    @Test fun formatCountFloorsAndNeverOverstates() {
        assertEquals("1.9K", formatCount(1999))
        assertEquals("999K", formatCount(999_999))
        assertEquals("1.2M", formatCount(1_299_999))
        assertEquals("9.9M", formatCount(9_999_999))
        assertEquals("10M", formatCount(10_000_000))
        assertEquals("-5", formatCount(-5))
        assertEquals("3", formatCount(3L))
        assertEquals("2K", formatCount(2000))
    }

    @Test fun groupThousandsAndInitialOf() {
        assertEquals("1,234,567", groupThousands(1_234_567))
        assertEquals("999", groupThousands(999))
        assertEquals("-1,000", groupThousands(-1000))
        assertEquals("1.000", groupThousands(1000, "."))
        assertEquals("A", initialOf("ayla"))
        assertEquals("?", initialOf("  "))
        assertEquals("🐉", initialOf("🐉 dragon")) // a whole code point, not half a surrogate pair
    }

    @Test fun wallTextsFollowTheDocument() {
        val chips = wallChips(listOf(rec("rose", 12), rec("heart", 3), rec("dragon", 1), rec("star", 20), rec("hat", 17)), max = 3)
        assertEquals("Gifts: 20 Stars, 17 Hats, and 16 more", wallSummaryText(chips))
        assertEquals("Gifts: 1 Dragon", wallSummaryText(wallChips(listOf(rec("dragon", 1)))))
        assertEquals("Rose, 1,200", wallChipLabel(WallChip.Gift(gift("rose"), 1200)))
        assertEquals("+37", wallChipText(WallChip.Overflow(37, 2)))
        assertEquals("+1.1K", wallChipText(WallChip.Overflow(1100, 2)))
        assertEquals("12", wallChipText(WallChip.Gift(gift("rose"), 12)))
        val tr = GiftLabels(wallSummary = "Hediyeler: {list}", wallMore = "ve {n} daha", plural = "")
        assertEquals("Hediyeler: 20 Star, 17 Hat, ve 16 daha", wallSummaryText(chips, tr))
    }

    @Test fun fillLeavesUnknownPlaceholders() {
        assertEquals("Rank 4, {name}", fill("Rank {rank}, {name}", "rank" to 4))
    }

    // ------------------------------------------------------------ wall loader with the default timers

    @Test fun theLoaderUsesRealCoroutineTimersByDefault() = runTest {
        val batches = ArrayList<List<GiftWallQueryItem>>()
        val loader =
            GiftWallLoader(
                query = { items ->
                    batches.add(items)
                    items.map { GiftWall(it.receiver, it.reference, listOf(rec("rose", 1))) }
                },
                scope = backgroundScope,
                now = { currentTime },
            )
        val a = async { loader.load("u1") }
        val b = async { loader.load("u2", "p") }
        runCurrent()
        assertTrue("nothing is sent before the 50 ms window closes", batches.isEmpty())
        advanceTimeBy(49)
        runCurrent()
        assertTrue(batches.isEmpty())
        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, batches.size)
        assertEquals(listOf(GiftWallQueryItem("u1", null), GiftWallQueryItem("u2", "p")), batches[0])
        assertEquals(1, a.await().size)
        assertEquals(1, b.await().size)
        // fresh for 60 s: no new request
        assertEquals(1, loader.load("u1").size)
        assertEquals(1, batches.size)
        // exactly 60 s old is stale
        advanceTimeBy(60_000)
        assertNull(loader.peek("u1"))
    }

    @Test fun aWallRequestedAtExactlyTheWindowEndStartsTheNextBatch() = runTest {
        val clock = FakeClock()
        val batches = ArrayList<Int>()
        val loader =
            GiftWallLoader(
                query = { items -> batches.add(items.size); items.map { GiftWall(it.receiver, null, emptyList()) } },
                scope = backgroundScope,
                now = { clock.now },
                timers = clock.timersApi,
            )
        backgroundScope.launch { loader.load("a") }
        settle(clock)
        clock.advance(50)
        settle(clock)
        backgroundScope.launch { loader.load("b") }
        settle(clock)
        clock.advance(50)
        settle(clock)
        assertEquals(listOf(1, 1), batches)
    }

    // ------------------------------------------------------------ away

    @Test fun replayBudgetDropsTheLowestUnitsFirstAndAFittingEndIsKept() {
        // small (1600) at 0, medium (2100) at 450, medium at 1550: ends 3650; large starts 3950, ends 7800 <= 8000
        val groups = listOf(agroup("big", 20000, 1, 20000, "a"), agroup("m1", 500, 2, 1000, "a"), agroup("m2", 500, 3, 1500, "b"), agroup("s1", 10, 5, 50, "c"))
        val plan = planAwayReplay(groups)
        assertEquals(listOf("s1", "m1", "m2", "big"), plan.items.map { it.group.gift.id })
        assertEquals(7800L, plan.endMs)
        // A budget of exactly the end fits; one less drops the lowest-units item (s1) and replans.
        assertEquals(7800L, planAwayReplay(groups, AwayReplayOptions(budgetMs = 7800)).endMs)
        val tighter = planAwayReplay(groups, AwayReplayOptions(budgetMs = 7799))
        assertEquals(listOf("m1", "m2", "big"), tighter.items.map { it.group.gift.id })
    }

    @Test fun onlyTheFirstLargeGroupIsReplayedAndOnlyFromTheFirstMaxEffects() {
        val groups = listOf(agroup("l1", 20000, 1, 20000, "a"), agroup("l2", 30000, 1, 19000, "a"), agroup("s", 10, 1, 10, "a"))
        assertEquals(listOf("s", "l1"), planAwayReplay(groups).items.map { it.group.gift.id })
        assertEquals(listOf("l1"), planAwayReplay(groups, AwayReplayOptions(maxEffects = 1)).items.map { it.group.gift.id })
        assertTrue(planAwayReplay(groups, AwayReplayOptions(maxEffects = 0)).items.isEmpty())
    }

    @Test fun reducedMotionGivesAnEmptyPlanAndTheCardStaysAtLeastFourSeconds() {
        val plan = planAwayReplay(listOf(agroup("s", 10, 1, 10, "a")), AwayReplayOptions(reducedMotion = true))
        assertTrue(plan.items.isEmpty())
        assertEquals(0L, plan.endMs)
        assertEquals(4000L, awayCardDurationMs(plan))
        assertEquals(7150L + 1500L, awayCardDurationMs(AwayReplayPlan(emptyList(), 7150)))
    }

    @Test fun aDeletedSenderIsSomeoneAndNeverReachesResolveName() {
        val asked = ArrayList<String>()
        val plan =
            planAwayReplay(
                listOf(agroup("s", 10, 2, 20, "ayla", null)),
                AwayReplayOptions(resolveName = { asked.add(it); it.uppercase() }, labels = AwaySenderLabels(someone = "Biri")),
            )
        assertEquals(listOf("ayla"), asked)
        assertEquals("AYLA and Biri", plan.items[0].event.sender)
    }

    @Test fun awayTextsSayTwoThousandPlusWhenTruncated() {
        fun summary(total: Long, people: Int, truncated: Boolean = false) =
            AwaySummary("u", "s", "e", "c", truncated, total, 0, people, emptyList(), emptyList())
        assertEquals("37 gifts from 12 people", awayTexts(summary(37, 12)).line)
        assertEquals("1 gift from 1 person", awayTexts(summary(1, 1)).line)
        assertEquals("2,000+ gifts from 12 people", awayTexts(summary(2000, 12, truncated = true)).line)
        assertEquals("1,234 gifts from 1,200 people", awayTexts(summary(1234, 1200)).line)
        assertEquals("You received 37 gifts from 12 people while you were away", awayTexts(summary(37, 12)).announce)
        // The parts renderSummary hands to a custom card.
        assertEquals("37 gifts", awayTexts(summary(37, 12)).gifts)
        assertEquals("12 people", awayTexts(summary(37, 12)).people)
        assertEquals("2,000+ gifts", awayTexts(summary(2000, 12, truncated = true)).gifts)
        assertEquals("1 person", awayTexts(summary(1, 1)).people)
        assertEquals("ayla, 1 gift", awaySenderSpoken("ayla", 1))
        assertEquals("ayla, 15 gifts", awaySenderSpoken("ayla", 15))
        assertEquals("Dragon, 1", awayGroupSpoken(agroup("dragon", 1, 1, 1, "a").let { it.copy(gift = it.gift.copy(name = "Dragon")) }))
    }

    @Test fun awayControllerWorksWithTheDefaultTimersToo() = runTest {
        val acks = ArrayList<String>()
        val summary = AwaySummary("u", "s", "e", "cur1", false, 3, 30, 1, listOf(agroup("s", 10, 3, 30, "ayla")), emptyList())
        val client =
            object : AwayApi {
                override suspend fun getAway(query: AwayQuery) = summary

                override suspend fun ackAway(cursor: String) {
                    acks.add(cursor)
                }
            }
        val played = ArrayList<String>()
        val c = AwayController(AwayControllerOptions(client, effects = { AwayEffectPlayer { played.add(it.gift.id); 1 } }), backgroundScope, now = { currentTime })
        c.check()
        runCurrent()
        assertEquals(AwayStatus.Ready, c.state.value.status)
        c.start()
        runCurrent()
        assertEquals(AwayStatus.Playing, c.state.value.status)
        assertEquals(listOf("s"), played)
        advanceTimeBy(3999)
        runCurrent()
        assertEquals(AwayStatus.Playing, c.state.value.status)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(AwayStatus.Done, c.state.value.status)
        assertEquals("acknowledged once, with the cursor of the summary that was shown", listOf("cur1"), acks)
    }

    // ------------------------------------------------------------ leaderboard

    private fun me(rank: Int?, gifts: Long = 3, units: Long = 120, hidden: Boolean = false) = LeaderboardMe("me", rank, gifts, units, hidden)

    private fun board(metric: LeaderboardMetric, rows: List<LeaderboardEntry>, me: LeaderboardMe?) =
        Leaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.Week, metric, "2026-W41", null, null, "t", rows, false, me)

    @Test fun pinningUsesTheScoreOfTheBoardsMetric() {
        val rows = listOf(LeaderboardEntry(1, "ayla", 5, 50))
        assertNull(pinnedMe(board(LeaderboardMetric.Units, rows, me(417, gifts = 9, units = 0)), 10))
        assertEquals(me(417, gifts = 9, units = 0), pinnedMe(board(LeaderboardMetric.Gifts, rows, me(417, gifts = 9, units = 0)), 10))
        assertNull(pinnedMe(null, 10))
        assertNull(pinnedMe(board(LeaderboardMetric.Units, rows, null), 10))
        assertNull(pinnedMe(board(LeaderboardMetric.Units, rows, me(417, hidden = true)), 10))
    }

    @Test fun rankIsPinnedAtTheLimitOnlyWhenTheRowIsMissing() {
        val rows = (1..3).map { LeaderboardEntry(it, "u$it", 1, 1) } // the cut at 3
        assertNull("rank == limit and listed", pinnedMe(board(LeaderboardMetric.Units, rows, me(3).copy(user = "u3")), 3))
        assertEquals("rank 4 > limit 3", me(4), pinnedMe(board(LeaderboardMetric.Units, rows, me(4)), 3))
        assertEquals("a tie at the cut left them out", me(3), pinnedMe(board(LeaderboardMetric.Units, rows, me(3)), 3))
        assertEquals("beyond the top 1,000", me(null), pinnedMe(board(LeaderboardMetric.Units, rows, me(null)), 3))
    }

    @Test fun rankLabelsAndMedals() {
        assertEquals("#1", leaderboardRankLabel(1))
        assertEquals("#1,000", leaderboardRankLabel(1000))
        assertEquals("1,000+", leaderboardRankLabel(null))
        assertEquals("1000+", leaderboardRankLabel(null, "1000+"))
        assertEquals("#e8a93a", rankColor(1))
        assertEquals("#b8bcc8", rankColor(2))
        assertEquals("#c07a45", rankColor(3))
        assertNull(rankColor(4))
        assertNull(rankColor(0))
    }

    @Test fun leaderboardTextsFollowTheDocument() {
        val l = GiftLabels()
        val e = LeaderboardEntry(1, "ayla", 120, 54000)
        assertEquals("Rank 1, ayla, 54,000 coins", leaderboardRowSpoken(e, "ayla", LeaderboardMetric.Units, l, "coins"))
        assertEquals("Rank 1, Ayla, 120 gifts", leaderboardRowSpoken(e, "Ayla", LeaderboardMetric.Gifts, l, "coins"))
        assertEquals("54K", leaderboardScore(LeaderboardMetric.Units, 120, 54000, l, "coins", spoken = false))
        assertEquals("1,200", leaderboardScore(LeaderboardMetric.Gifts, 1200, 5, l, "coins", spoken = false))
        val m = LeaderboardMe("me", 417, 3, 120, false)
        assertEquals("You: #417", leaderboardPinnedText(m, l))
        assertEquals("You: 1,000+", leaderboardPinnedText(m.copy(rank = null), l))
        assertEquals("Your rank: 417, 120 coins", leaderboardPinnedSpoken(m, LeaderboardMetric.Units, l, "coins"))
        assertEquals("Your rank: 1,000+, 120 coins", leaderboardPinnedSpoken(m.copy(rank = null), LeaderboardMetric.Units, l, "coins"))
        assertEquals("Coins", leaderboardUnitsName(l, "coins"))
        assertEquals("Elmas", leaderboardUnitsName(l.copy(metricUnits = "Elmas"), "coins"))
        assertEquals("No gifts yet this week", l.empty.getValue(LeaderboardPeriod.Week))
    }

    @Test fun anEmptyPeriodsListCountsAsTheDefaultAndAMissingInitialPeriodFallsBackToTheFirst() = runTest {
        val client = object : LeaderboardApi {
            override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard = error("not called")
        }
        val a = LeaderboardController(LeaderboardControllerOptions(client, periods = emptyList()), backgroundScope)
        assertEquals(LEADERBOARD_PERIODS, a.state.value.periods)
        assertEquals(LeaderboardPeriod.Week, a.state.value.period)
        val b = LeaderboardController(LeaderboardControllerOptions(client, periods = listOf(LeaderboardPeriod.Month, LeaderboardPeriod.All)), backgroundScope)
        assertEquals(LeaderboardPeriod.Month, b.state.value.period)
        // senders default to units, receivers to gifts (decision F.11)
        assertEquals(LeaderboardMetric.Units, a.state.value.metric)
        val r = LeaderboardController(LeaderboardControllerOptions(client, board = LeaderboardBoard.Receivers), backgroundScope)
        assertEquals(LeaderboardMetric.Gifts, r.state.value.metric)
    }

    // ------------------------------------------------------------ client

    @Test fun aNoContentAnswerIsNeverParsed() = kotlinx.coroutines.runBlocking {
        var sent: TransportRequest? = null
        val client = GiftingClient({ "tok" }, transport = { req -> sent = req; TransportResponse(204, emptyMap(), "this is not json") })
        client.ackAway("aw1.X")
        assertEquals("PUT", sent!!.method)
        assertEquals("https://api.giftingstack.com/v1/client/me/away/cursor", sent!!.url)
        assertEquals("""{"cursor":"aw1.X"}""", sent!!.body)
        assertNull(sent!!.headers["Idempotency-Key"])
        assertEquals("application/json", sent!!.headers["Content-Type"])
    }

    @Test fun aWallQueryNeverSendsANullReferenceAndAnEmptyListSendsNothing() = kotlinx.coroutines.runBlocking {
        var calls = 0
        var body: String? = null
        val client =
            GiftingClient(
                { "tok" },
                transport = { req -> calls++; body = req.body; TransportResponse(200, emptyMap(), """{"data":[{"receiver":"a","reference":null,"gifts":[]}]}""") },
            )
        assertEquals(emptyList<GiftWall>(), client.queryGiftWalls(emptyList()))
        assertEquals(0, calls)
        client.queryGiftWalls(listOf(GiftWallQueryItem("a", null)))
        assertEquals("""{"items":[{"receiver":"a"}]}""", body)
    }
}
