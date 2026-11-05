package com.giftingstack.demo

import com.giftingstack.core.AwayGift
import com.giftingstack.core.AwayGroup
import com.giftingstack.core.AwaySender
import com.giftingstack.core.AwaySummary
import com.giftingstack.core.AwayTopSender
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftRef
import com.giftingstack.core.Leaderboard
import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.LeaderboardEntry
import com.giftingstack.core.LeaderboardMe
import com.giftingstack.core.LeaderboardMetric
import com.giftingstack.core.LeaderboardPeriod
import com.giftingstack.core.ReceivedGift

/**
 * Believable mock data for the wall, the away card and the leaderboard. Demo only: a real app gets
 * all of this from GiftingStack. Pure (no Android), so `DemoLogicTest` can check it.
 */

/** The post the demo screen shows, and its author. */
const val DEMO_POST = "post_42"
const val DEMO_AUTHOR = "mateo"

/** The viewer of the demo (what `MockClient.getMe` says). */
const val DEMO_VIEWER = "ava"

/** Counters of the post's wall at the start: ten kinds of gift, in catalog order (as the API sends them). */
fun initialPostWall(): LinkedHashMap<String, Int> =
    linkedMapOf(
        "pink-tulip" to 128,
        "heart-latte" to 64,
        "party-popper" to 41,
        "bear-boba" to 23,
        "cool-star" to 17,
        "magic-hat" to 9,
        "rainbow-gem" to 6,
        "treasure-chest" to 4,
        "heart-box" to 2,
        "crystal-pegasus" to 1,
    )

/** Gifts of the signed-in user's profile wall at the start: 214 gifts in all. */
fun initialProfileWall(): LinkedHashMap<String, Int> =
    linkedMapOf("pink-tulip" to 90, "heart-latte" to 52, "party-popper" to 28, "bear-boba" to 20, "cool-star" to 12, "magic-hat" to 7, "rainbow-gem" to 3, "treasure-chest" to 2)

/** How many gifts the profile wall counts at the start (the "Gifts received" number of the Me tab). */
val START_RECEIVED: Int = initialProfileWall().values.sum()

private fun scaledPostWall(num: Int, den: Int): LinkedHashMap<String, Int> =
    LinkedHashMap(initialPostWall().mapValues { (_, v) -> maxOf(1, v * num / den) })

/** The wall counters a post or a profile starts with (the other posts get other numbers). */
fun initialWall(receiver: String, reference: String?): LinkedHashMap<String, Int> =
    when {
        reference == DEMO_POST && receiver == DEMO_AUTHOR -> initialPostWall()
        reference == "post_43" -> scaledPostWall(3, 2)
        reference == "post_44" -> scaledPostWall(1, 2)
        reference == "post_45" -> scaledPostWall(5, 2)
        reference == null && receiver == DEMO_VIEWER -> initialProfileWall()
        else -> LinkedHashMap()
    }

/**
 * The wall counters as `ReceivedGift`s, in catalog order, zero counts left out. Gifts the catalog
 * lacks (the small built-in list stands in) are kept after it.
 */
fun wallGifts(counts: Map<String, Int>, catalog: List<Gift> = demoGifts): List<ReceivedGift> {
    val all = catalog + demoGifts.filter { d -> catalog.none { it.id == d.id } }
    return all.mapNotNull { g -> counts[g.id]?.takeIf { it > 0 }?.let { ReceivedGift(GiftRef(g.id, g.name, g.iconUrl), it) } }
}

private fun awayGift(id: String): AwayGift {
    val g = demoGifts.first { it.id == id }
    return AwayGift(g.id, g.name, g.price, g.iconUrl, g.animationUrl)
}

private fun senders(vararg s: Pair<String?, Int>) = s.map { AwaySender(it.first, it.second) }

/**
 * What arrived while the viewer was away: four groups (one large gift, two medium, one small), a
 * group with a deleted sender (`user = null`), groups with one, two and six senders, 74 gifts from
 * 9 people. `groups` are sorted by units, then gift id, as the API sends them.
 */
fun demoAwaySummary(cursor: String = "aw1.demo-1"): AwaySummary =
    AwaySummary(
        user = DEMO_VIEWER,
        since = "2026-10-08T09:12:44.120Z",
        until = "2026-10-11T07:30:02.511Z",
        cursor = cursor,
        truncated = false,
        totalGifts = 74,
        totalUnits = 47_800,
        senderCount = 9,
        groups =
            listOf(
                AwayGroup(awayGift("sun-dragon"), 1, 40_000, 1, senders("zoe" to 1)),
                AwayGroup(awayGift("magic-hat"), 20, 7_000, 6, senders("caleb" to 9, null to 4, "elise" to 3)),
                AwayGroup(awayGift("pink-tulip"), 50, 500, 2, senders("elise" to 30, "caleb" to 20)),
                AwayGroup(awayGift("cool-star"), 3, 300, 1, senders(null to 3)),
            ),
        topSenders =
            listOf(
                AwayTopSender("zoe", 1, 40_000),
                AwayTopSender("caleb", 29, 5_000),
                AwayTopSender("elise", 33, 2_300),
                AwayTopSender(null, 7, 450),
            ),
    )

/** The same summary after it was acknowledged: nothing new, the cursor unchanged. */
fun demoAwayEmpty(cursor: String): AwaySummary =
    AwaySummary(DEMO_VIEWER, "2026-10-11T07:30:02.511Z", "2026-10-11T07:31:10.000Z", cursor, false, 0, 0, 0, emptyList(), emptyList())

private class Person(val user: String, val gifts: Long, val units: Long)

/** Fifteen people, with ties on both metrics. This week's numbers. */
private val BOARD_PEOPLE =
    listOf(
        Person("zoe", 410, 82_000),
        Person("caleb", 95, 82_000),
        Person("elise", 300, 54_000),
        Person("mateo", 280, 41_000),
        Person("dana", 120, 41_000),
        Person("sofia", 64, 33_000),
        Person("ben", 90, 18_000),
        Person("emma", 50, 18_000),
        Person("kai", 77, 12_500),
        Person("mila", 41, 9_000),
        Person("owen", 41, 9_000),
        Person("ada", 30, 7_400),
        Person("ethan", 22, 3_100),
        Person("irem", 18, 1_200),
        Person("yigit", 9, 450),
    )

/** The period's numbers are this week's scaled; people whose score rounds to 0 are not ranked. */
private fun scale(period: LeaderboardPeriod, v: Long): Long =
    when (period) {
        LeaderboardPeriod.Day -> v / 7
        LeaderboardPeriod.Week -> v
        LeaderboardPeriod.Month -> v * 4
        LeaderboardPeriod.All -> v * 14
    }

/** `1, 2, 2, 4`: equal scores share a rank, the next rank skips (competition ranking). [sorted] is descending. */
fun competitionRanks(sorted: List<Long>): List<Int> =
    sorted.map { v -> sorted.indexOfFirst { it == v } + 1 }

/** The viewer's rank per period and metric; null is "beyond the top 1,000". */
private fun viewerRank(period: LeaderboardPeriod, metric: LeaderboardMetric): Int? =
    when (metric) {
        LeaderboardMetric.Units ->
            when (period) {
                LeaderboardPeriod.Day -> null
                LeaderboardPeriod.Week -> 417
                LeaderboardPeriod.Month -> 305
                LeaderboardPeriod.All -> null
            }
        LeaderboardMetric.Gifts ->
            when (period) {
                LeaderboardPeriod.Day -> 612
                LeaderboardPeriod.Week -> 540
                LeaderboardPeriod.Month -> 388
                LeaderboardPeriod.All -> null
            }
    }

private val LABELS =
    mapOf(LeaderboardPeriod.Day to "2026-10-11", LeaderboardPeriod.Week to "2026-W41", LeaderboardPeriod.Month to "2026-10", LeaderboardPeriod.All to "all")

/**
 * A leaderboard as the API answers it: [limit] rows (at most the 15 people), competition ranks, and
 * the viewer's own block (they are not in the rows: 3 gifts, 120 coins this week) unless
 * [includeMe] is false.
 */
fun demoLeaderboard(
    board: LeaderboardBoard,
    period: LeaderboardPeriod,
    metric: LeaderboardMetric,
    limit: Int,
    includeMe: Boolean,
    asOf: String,
    hidden: Boolean = false,
): Leaderboard {
    val scored =
        BOARD_PEOPLE.map { Person(it.user, scale(period, it.gifts), scale(period, it.units)) }
            .filter { (if (metric == LeaderboardMetric.Gifts) it.gifts else it.units) > 0 }
            // Descending by the metric; the list order breaks ties, as the account age does on the server.
            .sortedByDescending { if (metric == LeaderboardMetric.Gifts) it.gifts else it.units }
    val ranks = competitionRanks(scored.map { if (metric == LeaderboardMetric.Gifts) it.gifts else it.units })
    val rows = scored.mapIndexed { i, p -> LeaderboardEntry(ranks[i], p.user, p.gifts, p.units) }
    val shown = rows.take(limit.coerceIn(1, 100))
    val me =
        if (includeMe) {
            LeaderboardMe(DEMO_VIEWER, if (hidden) null else viewerRank(period, metric), scale(period, 3), scale(period, 120), hidden = hidden)
        } else {
            null
        }
    return Leaderboard(
        board = board,
        period = period,
        metric = metric,
        label = LABELS.getValue(period),
        startsAt = if (period == LeaderboardPeriod.All) null else "2026-10-05T00:00:00.000Z",
        endsAt = if (period == LeaderboardPeriod.All) null else "2026-10-12T00:00:00.000Z",
        asOf = asOf,
        data = shown,
        hasMore = rows.size > shown.size,
        me = me,
    )
}
