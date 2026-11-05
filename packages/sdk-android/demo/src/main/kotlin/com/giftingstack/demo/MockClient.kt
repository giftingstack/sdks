package com.giftingstack.demo

import com.giftingstack.core.AwayApi
import com.giftingstack.core.AwayQuery
import com.giftingstack.core.AwaySummary
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftWall
import com.giftingstack.core.GiftWallApi
import com.giftingstack.core.GiftWallQueryItem
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.GiftingException
import com.giftingstack.core.Inbox
import com.giftingstack.core.InboxApi
import com.giftingstack.core.InboxGift
import com.giftingstack.core.InboxItem as CoreInboxItem
import com.giftingstack.core.InboxQuery
import com.giftingstack.core.Leaderboard
import com.giftingstack.core.LeaderboardApi
import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.LeaderboardMetric
import com.giftingstack.core.LeaderboardPeriod
import com.giftingstack.core.LeaderboardQuery
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.newIdempotencyKey
import com.giftingstack.core.parseIsoTimeMs
import kotlinx.coroutines.delay

/**
 * The gift pictures come from the public library host, like in a real app: downloaded once, then
 * kept by the phone.
 */
private const val ASSETS = "https://assets.giftingstack.com"

fun iconUrl(id: String) = "$ASSETS/gifts/$id/256.webp"

fun artUrl(id: String) = "$ASSETS/gifts/$id/512.webp"

private val CATALOG =
    listOf(
        Triple("pink-tulip", "Pink tulip", 10),
        Triple("heart-latte", "Heart latte", 20),
        Triple("party-popper", "Party popper", 25),
        Triple("bear-boba", "Bear boba", 45),
        Triple("cool-star", "Cool star", 100),
        Triple("magic-hat", "Magic hat", 350),
        Triple("rainbow-gem", "Rainbow gem", 500),
        Triple("treasure-chest", "Treasure chest", 1000),
        Triple("heart-box", "Heart box", 2000),
        Triple("crystal-pegasus", "Crystal pegasus", 18000),
        Triple("golden-griffin", "Golden griffin", 22000),
        Triple("sun-dragon", "Sun dragon", 40000),
    )

/** The small built-in list: the fallback when the live library cannot be loaded. */
val demoGifts: List<Gift> =
    CATALOG.mapIndexed { i, (id, name, price) ->
        Gift(id, name, null, price.toLong(), iconUrl(id), artUrl(id), i)
    }

private const val START_BALANCE = 60_000L
private const val LATENCY_MS = 250L

/**
 * A stand-in for GiftingStack that lives in the app: same shapes and errors as `/v1/client`, a
 * quarter second of fake network delay, and a coin balance. [credit] is what your server does
 * after a purchase (`POST /v1/users/{id}/credit`): it ADDS coins. [reset] is a debug helper.
 * Swap it for `GiftingClient(getToken = { ... })` to talk to the real API.
 *
 * @param catalog the gifts, loaded on the first `getGifts` (the demo reads the live library and
 *   falls back to [demoGifts]).
 */
class MockClient(private val catalog: suspend () -> List<Gift> = { demoGifts }) : GiftingApi, GiftWallApi, AwayApi, LeaderboardApi, InboxApi {
    private var balance = START_BALANCE
    private var gifts: List<Gift>? = null
    private val sent = HashMap<String, GiftTransaction>()

    /** Wall counters by `receiver|reference` (the profile wall has an empty reference). */
    private val walls = HashMap<String, LinkedHashMap<String, Int>>()
    private var awaySeen = false

    /** The gifts the demo user received in the last 24 hours, newest first (the inbox). */
    private val inbox = ArrayList<CoreInboxItem>(seedInbox())
    private var inboxCounter = 0
    private var awayRound = 1

    /** Debug: the next leaderboard request fails once (a 503, as during the one-time backfill). */
    @Volatile var failNextLeaderboard = false

    /** The mock failure switch: while true, every call fails like a lost connection. */
    @Volatile var offline = false

    /** "Hide me from leaderboards": the viewer's own block says hidden and has no rank. */
    @Volatile var hidden = false

    private fun down() {
        if (offline) throw GiftingException(0, "network_error", "You are offline.")
    }

    /** Gifts that reached a wall from elsewhere (an incoming gift, "wall +5"). */
    fun addToWall(receiver: String, giftId: String, quantity: Int, reference: String? = null) {
        if (reference != null) wallOf(receiver, reference).merge(giftId, quantity, Int::plus)
        wallOf(receiver, null).merge(giftId, quantity, Int::plus)
    }

    /** Every acknowledged away cursor, for tests and the debug bar. */
    val awayAcks = ArrayList<String>()

    private fun wallOf(receiver: String, reference: String?) =
        walls.getOrPut("$receiver|${reference.orEmpty()}") {
            initialWall(receiver, reference)
        }

    /** The balance now (for tests and the debug bar). */
    val currentBalance: Long get() = balance

    /** Debug: back to the start balance. Not what a coin store does. */
    fun reset() {
        balance = START_BALANCE
        walls.clear()
        hidden = false
        inbox.clear()
        inbox.addAll(seedInbox())
        newAwayGifts()
    }

    /** Debug: gifts arrived again, so the next away check has something to show. */
    fun newAwayGifts() {
        awaySeen = false
        awayRound++
    }

    /** What a coin purchase does on your server: the coins are ADDED to the balance. */
    fun credit(coins: Int) {
        balance += coins
    }

    private suspend fun catalogNow(): List<Gift> = gifts ?: catalog().also { gifts = it }

    override suspend fun getGifts(): List<Gift> {
        delay(LATENCY_MS)
        down()
        return catalogNow()
    }

    override suspend fun getMe(): Me {
        delay(LATENCY_MS / 2)
        down()
        // livemode false = a test key: the tray shows its "Test mode" badge by itself (SPEC 9), like a real test app.
        return Me("ava", balance, livemode = false)
    }

    override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

    override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
        delay(LATENCY_MS)
        down()
        val key = input.idempotencyKey ?: newIdempotencyKey()
        sent[key]?.let { return it }
        val gift = catalogNow().firstOrNull { it.id == input.giftId } ?: throw GiftingException(404, "not_found", "Gift not found.")
        val quantity = input.quantity ?: 1
        val total = gift.price * quantity
        if (balance < total) throw GiftingException(422, "insufficient_balance", "Insufficient balance.")
        balance -= total
        val tx =
            GiftTransaction(
                id = "gtx_$key",
                sender = "ava",
                receiver = input.receiver,
                gift = GiftRef(gift.id, gift.name, gift.iconUrl),
                quantity = quantity,
                unitPrice = gift.price,
                total = total,
                message = input.message,
                reference = input.reference,
                status = "completed",
                createdAt = isoNow(),
                senderBalanceAfter = balance,
            )
        sent[key] = tx
        // The receiver's walls count it: the post's wall (with the reference) and the profile wall.
        if (input.reference != null) wallOf(input.receiver, input.reference).merge(gift.id, quantity, Int::plus)
        wallOf(input.receiver, null).merge(gift.id, quantity, Int::plus)
        return tx
    }

    override suspend fun queryGiftWalls(items: List<GiftWallQueryItem>): List<GiftWall> {
        delay(LATENCY_MS)
        down()
        val catalog = catalogNow()
        return items.map { GiftWall(it.receiver, it.reference, wallGifts(wallOf(it.receiver, it.reference), catalog)) }
    }

    override suspend fun getAway(query: AwayQuery): AwaySummary {
        delay(LATENCY_MS)
        down()
        val cursor = "aw1.demo-$awayRound"
        if (awaySeen) return demoAwayEmpty(cursor)
        val full = demoAwaySummary(cursor)
        return query.maxGroups?.let { n -> full.copy(groups = full.groups.take(n)) } ?: full
    }

    override suspend fun ackAway(cursor: String) {
        delay(LATENCY_MS / 2)
        down()
        awayAcks.add(cursor)
        awaySeen = true
    }

    /** A gift somebody else sent the demo user: it shows in the inbox as the newest row. */
    fun addToInbox(gift: Gift, sender: String, quantity: Int) {
        inboxCounter++
        inbox.add(
            0,
            inboxItem("gtx_demo_in_$inboxCounter", System.currentTimeMillis(), sender, gift.id, gift.name, gift.price, gift.iconUrl, gift.animationUrl, quantity),
        )
    }

    override suspend fun getInbox(query: InboxQuery): Inbox {
        delay(LATENCY_MS)
        down()
        val now = System.currentTimeMillis()
        val since = now - INBOX_WINDOW_MS
        val live = inbox.filter { (parseIsoTimeMs(it.createdAt) ?: 0L) >= since }
        val after = query.cursor?.let { c -> live.indexOfFirst { it.id == c.removePrefix("ib1.") } + 1 } ?: 0
        val page = live.drop(after).take((query.limit ?: 20).coerceIn(1, 100))
        val more = after + page.size < live.size
        return Inbox("ava", isoAt(since), isoAt(now), page, more, if (more) "ib1." + page.last().id else null)
    }

    override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard {
        delay(LATENCY_MS)
        down()
        if (failNextLeaderboard) {
            failNextLeaderboard = false
            throw GiftingException(503, "leaderboard_building", "Leaderboards are being built. Try again shortly.", "req_demo")
        }
        val period = query.period ?: LeaderboardPeriod.Week
        val metric = query.metric ?: LeaderboardMetric.Units
        return demoLeaderboard(board, period, metric, query.limit ?: 10, query.includeMe != false, isoNow(), hidden)
    }
}

private fun isoNow(): String = isoAt(System.currentTimeMillis())

private fun isoAt(ms: Long): String =
    java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
        .format(java.util.Date(ms))

private const val INBOX_WINDOW_MS = 24L * 60 * 60 * 1000

private fun inboxItem(id: String, atMs: Long, sender: String, giftId: String, name: String, price: Long, icon: String?, art: String?, quantity: Int) =
    CoreInboxItem(id, isoAt(atMs), sender, InboxGift(giftId, name, price, icon, art), quantity, price * quantity, "completed")

private class SeededGift(val sender: String, val giftId: String, val quantity: Int, val minutesAgo: Int)

/** Gifts received earlier today, all inside the 24 hour window. */
private val SEEDED_INBOX =
    listOf(
        SeededGift("mateo", "pink-tulip", 1, 40),
        SeededGift("zoe", "heart-latte", 2, 130),
        SeededGift("ethan", "cool-star", 1, 190),
        SeededGift("sofia", "bear-boba", 3, 300),
        SeededGift("dana", "party-popper", 1, 420),
        SeededGift("daphne", "magic-hat", 1, 540),
        SeededGift("caleb", "pink-tulip", 5, 660),
        SeededGift("elise", "rainbow-gem", 1, 800),
        SeededGift("kai", "heart-latte", 1, 940),
        SeededGift("aisha", "treasure-chest", 1, 1100),
        SeededGift("zoe", "bear-boba", 2, 1250),
        SeededGift("mateo", "cool-star", 1, 1380),
    )

/** The seeded part of the inbox, dated from [nowMs] so it always sits inside the last 24 hours. Newest first. */
internal fun seedInbox(nowMs: Long = System.currentTimeMillis()): List<CoreInboxItem> =
    SEEDED_INBOX.mapIndexed { i, s ->
        val g = demoGifts.first { it.id == s.giftId }
        inboxItem("gtx_demo_seed_$i", nowMs - s.minutesAgo * 60_000L, s.sender, g.id, g.name, g.price, g.iconUrl, g.animationUrl, s.quantity)
    }
