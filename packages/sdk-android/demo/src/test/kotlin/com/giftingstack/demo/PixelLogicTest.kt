package com.giftingstack.demo

import com.giftingstack.core.EffectQuality
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftWallQueryItem
import com.giftingstack.core.GiftingException
import com.giftingstack.core.InboxQuery
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.parseIsoTimeMs
import kotlin.random.Random
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The demo's own logic (the fake app "Pixel"), on the JVM. */
class PixelLogicTest {
    private fun gift(id: String, price: Int) = Gift(id, id, null, price.toLong(), null, null, 0)

    private val catalog = listOf(gift("a", 10), gift("b", 99), gift("c", 100), gift("d", 9_999), gift("e", 10_000), gift("f", 40_000))

    // ---- the folded developer menu

    @Test fun developerMenuIsFoldedOnLaunchAndKeepsItsSettingsWhenClosed() {
        val s = DevMenuState()
        assertFalse("never open on launch", s.open)
        assertEquals(IncomingMode.SameAsTray, s.settings.incoming)
        assertEquals(EffectQuality.High, s.settings.quality)
        assertEquals(DemoTheme.Default, s.settings.theme)
        assertEquals(DemoMotion.System, s.settings.motion)
        assertFalse(s.settings.offline)
        val open = s.opened().with { it.copy(theme = DemoTheme.Pink, offline = true) }
        assertTrue(open.open)
        val closed = open.closed()
        assertFalse(closed.open)
        assertEquals(DemoTheme.Pink, closed.settings.theme)
        assertTrue(closed.settings.offline)
        assertEquals("Developer menu (not part of the SDK)", DEV_MENU_TITLE)
        assertEquals("1 second long-press", 1_000L, DEV_HOLD_MS)
        assertEquals(null, DemoMotion.System.reduced)
        assertEquals(true, DemoMotion.Reduced.reduced)
    }

    @Test fun themePickerHasTheFourThemes() {
        assertEquals(listOf("Default", "Dark", "Light", "Pink"), DemoTheme.entries.map { it.label })
    }

    // ---- the incoming gift

    @Test fun liveFeedIsOffSoNothingArrivesByItself() {
        assertFalse(LIVE_FEED)
    }

    @Test fun incomingModePicksTheTrayGiftRandomCheapestOrPriciest() {
        val sel = catalog[2]
        assertEquals(sel, giftFor(IncomingMode.SameAsTray, catalog, sel, Random(1)))
        assertEquals("falls back to the first gift", catalog[0], giftFor(IncomingMode.SameAsTray, catalog, null, Random(1)))
        assertEquals("a", giftFor(IncomingMode.Cheapest, catalog.shuffled(Random(3)), sel, Random(1))!!.id)
        assertEquals("f", giftFor(IncomingMode.Priciest, catalog.shuffled(Random(4)), sel, Random(1))!!.id)
        val seen = (0 until 200).map { giftFor(IncomingMode.Random, catalog, sel, Random(it))!!.id }.toSet()
        assertTrue("random reaches every gift", seen.containsAll(catalog.map { it.id }))
        for (m in IncomingMode.entries) assertNull(giftFor(m, emptyList(), null, Random(1)))
    }

    @Test fun tiersFollowTheEffectLimits() {
        assertEquals(Tier.Small, tierOf(99))
        assertEquals(Tier.Medium, tierOf(100))
        assertEquals(Tier.Medium, tierOf(9_999))
        assertEquals(Tier.Large, tierOf(10_000))
        assertEquals(Tier.Small, rollTier(0.0))
        assertEquals(Tier.Small, rollTier(0.779))
        assertEquals(Tier.Medium, rollTier(0.78))
        assertEquals(Tier.Medium, rollTier(0.969))
        assertEquals(Tier.Large, rollTier(0.97))
    }

    @Test fun incomingPicksMostlySmallWithSmallQuantitiesAndAFallbackForAnEmptyTier() {
        val picks = (0 until 2_000).map { pickIncoming(catalog, SENDERS, Random(it))!! }
        val small = picks.count { it.tier == Tier.Small }
        val large = picks.count { it.tier == Tier.Large }
        assertTrue("about 78 % small: $small", small in 1_400..1_700)
        assertTrue("large is rare: $large", large in 1..150)
        assertTrue(picks.all { it.sender in SENDERS })
        assertTrue(picks.filter { it.tier == Tier.Large }.all { it.quantity == 1 })
        assertTrue(picks.all { it.quantity in 1..3 })
        // Only small gifts exist: a medium or large roll falls back to the nearest tier that has gifts.
        val onlySmall = listOf(gift("x", 5), gift("y", 7))
        assertTrue((0 until 300).all { pickIncoming(onlySmall, SENDERS, Random(it))!!.tier == Tier.Small })
        assertNull(pickIncoming(emptyList(), SENDERS, Random(1)))
        assertNull(pickIncoming(catalog, emptyList(), Random(1)))
    }

    @Test fun liveDelayIsBetweenTwentyAndFortySeconds() {
        val d = (0 until 500).map { nextDelayMs(Random(it)) }
        assertTrue(d.all { it in 20_000L until 40_000L })
        assertTrue("it varies", d.toSet().size > 100)
    }

    // ---- the inbox of the mock client: the gifts the demo user received in the last 24 hours

    @Test fun inboxHasTheSeededGiftsNewestFirstAndANewGiftComesFirst() = runTest {
        val client = MockClient()
        val first = client.getInbox(InboxQuery(limit = 100))
        assertEquals(12, first.data.size)
        assertFalse(first.hasMore)
        assertNull(first.nextCursor)
        val times = first.data.map { parseIsoTimeMs(it.createdAt)!! }
        assertEquals("newest first", times.sortedDescending(), times)
        assertTrue("all within 24 hours", times.all { System.currentTimeMillis() - it < 24L * 3_600_000L })
        client.addToInbox(catalog[0], "zoe", 2)
        val next = client.getInbox(InboxQuery(limit = 100)).data
        assertEquals(13, next.size)
        assertEquals("zoe", next.first().sender)
        assertEquals(2, next.first().quantity)
        assertEquals(catalog[0].id, next.first().gift.id)
    }

    @Test fun inboxPagesByCursorAndResetBringsTheSeedBack() = runTest {
        val client = MockClient()
        val p1 = client.getInbox(InboxQuery(limit = 5))
        assertEquals(5, p1.data.size)
        assertTrue(p1.hasMore)
        val p2 = client.getInbox(InboxQuery(cursor = p1.nextCursor, limit = 100))
        assertEquals(7, p2.data.size)
        assertFalse(p2.hasMore)
        assertEquals("no row twice", 12, (p1.data + p2.data).map { it.id }.toSet().size)
        client.addToInbox(catalog[0], "zoe", 1)
        client.reset()
        assertEquals(12, client.getInbox(InboxQuery(limit = 100)).data.size)
    }

    // ---- the away card shows the first time after install only

    private class FakeStore(var flag: Boolean = false) : AwayStore {
        var writes = 0

        override fun seen() = flag

        override fun markSeen() {
            flag = true
            writes++
        }
    }

    @Test fun awayCardShowsOnTheFirstLaunchOnly() {
        val store = FakeStore()
        val first = AwayOnce(store)
        assertTrue("first launch after install", first.autoCheck)
        first.onShown()
        assertTrue("the same session keeps its decision", first.autoCheck)
        assertTrue(store.flag)
        val second = AwayOnce(store)
        assertFalse("later launches do not auto-check", second.autoCheck)
        assertEquals(1, store.writes)
        assertFalse(AwayOnce(FakeStore(flag = true)).autoCheck)
    }

    // ---- the coin store ADDS

    @Test fun everyCoinPackAddsToTheBalance() = runTest {
        val c = MockClient()
        var expected = c.getMe().balance
        for (pack in COIN_PACKS) {
            c.credit(pack.coins)
            expected += pack.coins
            assertEquals(expected, c.getMe().balance)
        }
        c.sendGift(SendGiftInput(receiver = "mateo", giftId = "pink-tulip", quantity = 3))
        assertEquals(expected - 30, c.getMe().balance)
        c.credit(1_000)
        assertEquals(expected - 30 + 1_000, c.getMe().balance)
    }

    // ---- the mock client of the fake app

    @Test fun offlineSwitchFailsEveryCallAndRecovers() = runTest {
        val c = MockClient()
        c.offline = true
        for (call in listOf<suspend () -> Any?>(
            { c.getGifts() },
            { c.getMe() },
            { c.sendGift(SendGiftInput(receiver = "mateo", giftId = "pink-tulip")) },
            { c.queryGiftWalls(listOf(GiftWallQueryItem("mateo", "post_42"))) },
            { c.getAway(com.giftingstack.core.AwayQuery()) },
            { c.getLeaderboard(com.giftingstack.core.LeaderboardBoard.Senders, com.giftingstack.core.LeaderboardQuery()) },
        )) {
            val e = runCatching { call() }.exceptionOrNull() as GiftingException
            assertEquals("network_error", e.type)
            assertTrue(e.retryable)
        }
        c.offline = false
        assertEquals(60_000, c.getMe().balance)
    }

    @Test fun everyPostHasItsOwnWallAndGiftsFromOthersLandOnTheProfileWall() = runTest {
        val c = MockClient()
        val walls = c.queryGiftWalls(POSTS.map { GiftWallQueryItem(it.author, it.id) })
        assertEquals(POSTS.size, walls.size)
        assertEquals("different posts, different numbers", POSTS.size, walls.map { w -> w.gifts.sumOf { it.count } }.toSet().size)
        suspend fun mine() = c.queryGiftWalls(listOf(GiftWallQueryItem(DEMO_VIEWER, null))).single().gifts.sumOf { it.count }
        assertEquals(START_RECEIVED, mine())
        c.addToWall(DEMO_VIEWER, "pink-tulip", 3)
        assertEquals(START_RECEIVED + 3, mine())
        c.reset()
        assertEquals(START_RECEIVED, mine())
    }

    @Test fun hidingYourselfRemovesYourRankFromTheLeaderboard() = runTest {
        val c = MockClient()
        assertEquals(417, c.getLeaderboard(com.giftingstack.core.LeaderboardBoard.Senders, com.giftingstack.core.LeaderboardQuery()).me!!.rank)
        c.hidden = true
        val me = c.getLeaderboard(com.giftingstack.core.LeaderboardBoard.Senders, com.giftingstack.core.LeaderboardQuery()).me!!
        assertTrue(me.hidden)
        assertNull(me.rank)
    }

    @Test fun sendingAGiftToAnotherPostLeavesTheFirstPostWallAlone() = runTest {
        val c = MockClient()
        val before = c.queryGiftWalls(listOf(GiftWallQueryItem("zoe", "post_43"))).single().gifts.sumOf { it.count }
        c.sendGift(SendGiftInput(receiver = "zoe", giftId = "pink-tulip", quantity = 4, reference = "post_43"))
        assertEquals(before + 4, c.queryGiftWalls(listOf(GiftWallQueryItem("zoe", "post_43"))).single().gifts.sumOf { it.count })
        assertEquals(initialPostWall().values.sum(), c.queryGiftWalls(listOf(GiftWallQueryItem(DEMO_AUTHOR, DEMO_POST))).single().gifts.sumOf { it.count })
    }

    // ---- the fake app's data

    @Test fun postsAreFourWithUniqueIdsAndKnownAuthors() {
        assertEquals(4, POSTS.size)
        assertEquals(4, POSTS.map { it.id }.toSet().size)
        assertEquals(DEMO_POST, POSTS.first().id)
        assertTrue(POSTS.all { it.author in PEOPLE })
        assertEquals(ArtKind.entries.toSet(), POSTS.map { it.art }.toSet())
        assertTrue(SENDERS.none { it == DEMO_VIEWER })
        assertTrue(SENDERS.all { it in PEOPLE })
        assertEquals("A", initialOf("ava"))
        assertEquals("Mateo", firstName("mateo"))
        assertEquals("Unknown", displayName("unknown"))
    }
}
