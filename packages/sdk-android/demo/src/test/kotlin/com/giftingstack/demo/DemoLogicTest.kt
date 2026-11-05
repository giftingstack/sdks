package com.giftingstack.demo

import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.LeaderboardMetric
import com.giftingstack.core.LeaderboardPeriod
import com.giftingstack.core.SendGiftInput
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoLogicTest {
    /** A library shaped like the live one: 24 cheap-to-grand gifts, the chosen ones and 108 hearts at one price. */
    private fun library(): String {
        val gifts = StringBuilder()
        fun add(id: String, price: Int) {
            if (gifts.isNotEmpty()) gifts.append(',')
            gifts.append("""{"id":"$id","name":"$id","suggested_price":$price}""")
        }
        for (id in PICK) add(id, 10 + id.length * 100)
        for (i in 1..120) add("gift-$i", 5 + i * 37)
        for (i in 1..108) add("heart-c$i", 500)
        add("heart-turkey", 500)
        return """{"version":1,"gifts":[$gifts]}"""
    }

    @Test fun catalogIsAboutNinetyWithTheChosenFirstAndOneCountryHeart() {
        val cat = pickCatalog(library())
        assertEquals(PICK.size + SPREAD_COUNT, cat.size)
        assertEquals(PICK, cat.take(PICK.size).map { it.id })
        assertTrue("no country heart beyond the chosen ones", cat.drop(PICK.size).none { it.id.startsWith("heart-") })
        assertEquals("sort order follows the list", cat.indices.toList(), cat.map { it.sortOrder })
        assertEquals("https://assets.giftingstack.com/gifts/pink-tulip/256.webp", cat.first().iconUrl)
        assertEquals("https://assets.giftingstack.com/gifts/pink-tulip/512.webp", cat.first().animationUrl)
        val spread = cat.drop(PICK.size).map { it.price }
        assertEquals("spread from cheap to grand", spread.sorted(), spread)
    }

    @Test fun aSmallLibraryGivesWhatItHasWithoutDuplicates() {
        val json = """{"gifts":[{"id":"pink-tulip","name":"Pink tulip","suggested_price":10},{"id":"x","name":"X","suggested_price":50}]}"""
        val cat = pickCatalog(json)
        assertEquals(listOf("pink-tulip", "x"), cat.map { it.id })
    }

    @Test fun loadGiftsFallsBackToTheSmallListOnAnyFailure() = runTest {
        assertEquals(demoGifts, loadGifts { error("offline") })
        assertEquals(demoGifts, loadGifts { emptyList() })
        assertEquals(demoGifts, loadGifts { pickCatalog("not json") })
        val live = pickCatalog(library())
        assertEquals(live, loadGifts { live })
    }

    @Test fun theMockAnswersAsATestKeySoTheTestModeBadgeShows() = runTest {
        assertEquals(false, MockClient().getMe().livemode)
    }

    @Test fun addingCoinsAddsAndNeverResets() = runTest {
        val c = MockClient()
        assertEquals(60_000, c.getMe().balance)
        c.sendGift(SendGiftInput(receiver = "mateo", giftId = "pink-tulip", quantity = 5)) // 5 x 10
        assertEquals(59_950, c.getMe().balance)
        c.credit(1_000)
        assertEquals("the pack is ADDED to what is left", 60_950, c.getMe().balance)
        c.credit(5_000)
        assertEquals(65_950, c.currentBalance)
        c.reset()
        assertEquals("only the developer menu Reset demo restores the start balance", 60_000, c.currentBalance)
    }

    @Test fun theMockClientServesTheCatalogItWasGiven() = runTest {
        val live = pickCatalog(library())
        val c = MockClient(catalog = { live })
        assertEquals(live, c.getGifts())
        // A gift only the live catalog has can be sent.
        c.sendGift(SendGiftInput(receiver = "mateo", giftId = "gift-1"))
        assertTrue(c.currentBalance < 60_000)
    }

    // ---- mock data of the gift wall, the away card and the leaderboard (demo only)

    @Test fun postWallHasTenKindsOfGiftInCatalogOrder() {
        val wall = wallGifts(initialPostWall())
        assertEquals(10, wall.size)
        assertEquals(demoGifts.map { it.id }.filter { it in initialPostWall().keys }, wall.map { it.gift.id })
        // max = 6: five gifts and one overflow chip standing for the other five kinds
        val chips = com.giftingstack.core.wallChips(wall)
        assertEquals(6, chips.size)
        // shown: 128, 64, 41, 23, 17; hidden: 9 + 6 + 4 + 2 + 1 gifts of 5 kinds
        assertEquals(com.giftingstack.core.WallChip.Overflow(count = 22, hidden = 5), chips.last())
    }

    @Test fun awaySummaryHasSeveralGroupsAndSendersIncludingADeletedOne() {
        val s = demoAwaySummary()
        assertEquals(74L, s.totalGifts)
        assertEquals(s.groups.sumOf { it.count }.toLong(), s.totalGifts)
        assertEquals(s.groups.sumOf { it.units }, s.totalUnits)
        assertTrue(s.groups.size >= 4)
        assertTrue("a deleted sender", s.groups.any { g -> g.senders.any { it.user == null } })
        assertEquals("groups come sorted by units, as the API sends them", s.groups.sortedByDescending { it.units }, s.groups)
        assertTrue(s.groups.map { it.senderCount }.toSet().containsAll(listOf(1, 2, 6)))
        val plan = com.giftingstack.core.planAwayReplay(s.groups)
        assertEquals("the large gift is last", "sun-dragon", plan.items.last().group.gift.id)
        assertTrue("the replay fits the budget", plan.endMs <= 8_000)
    }

    @Test fun leaderboardHasFifteenPeopleWithTiesAndTheViewerOutsideTheRows() {
        val b = demoLeaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.Week, LeaderboardMetric.Units, 100, true, "t")
        assertEquals(15, b.data.size)
        assertEquals(listOf(1, 1, 3, 4, 4), b.data.take(5).map { it.rank })
        assertTrue("competition ranks: equal scores share one, the next skips", b.data.map { it.rank } == b.data.map { r -> b.data.first { it.units == r.units }.let { f -> b.data.indexOf(f) + 1 } })
        val ten = demoLeaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.Week, LeaderboardMetric.Units, 10, true, "t")
        assertEquals(10, ten.data.size)
        assertTrue(ten.hasMore)
        assertEquals("ava", ten.me!!.user)
        assertTrue("the viewer is not in the rows", ten.data.none { it.user == "ava" })
        assertEquals(417, ten.me!!.rank)
        assertEquals("pinned under the list", ten.me, com.giftingstack.core.pinnedMe(ten, 10))
        assertEquals("beyond the top 1,000 for all time", null, demoLeaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.All, LeaderboardMetric.Units, 10, true, "t").me!!.rank)
        assertEquals(null, demoLeaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.Week, LeaderboardMetric.Units, 10, false, "t").me)
        val gifts = demoLeaderboard(LeaderboardBoard.Senders, LeaderboardPeriod.Week, LeaderboardMetric.Gifts, 100, true, "t")
        assertEquals(gifts.data.sortedByDescending { it.gifts }.map { it.user }, gifts.data.map { it.user })
    }

    @Test fun competitionRanksSkipAfterATie() {
        assertEquals(listOf(1, 2, 2, 4, 5, 5, 5, 8), competitionRanks(listOf(9L, 7, 7, 5, 4, 4, 4, 1)))
        assertEquals(emptyList<Int>(), competitionRanks(emptyList()))
    }

    @Test fun theMockServerCountsASentGiftOnThePostWallAndOnlyAcknowledgesAwayOnce() = runTest {
        val c = MockClient()
        val before = c.queryGiftWalls(listOf(com.giftingstack.core.GiftWallQueryItem(DEMO_AUTHOR, DEMO_POST))).single().gifts.first { it.gift.id == "pink-tulip" }.count
        c.sendGift(SendGiftInput(receiver = DEMO_AUTHOR, giftId = "pink-tulip", quantity = 2, reference = DEMO_POST))
        val after = c.queryGiftWalls(listOf(com.giftingstack.core.GiftWallQueryItem(DEMO_AUTHOR, DEMO_POST))).single().gifts.first { it.gift.id == "pink-tulip" }.count
        assertEquals(before + 2, after)
        // a gift for another post leaves this wall alone
        c.sendGift(SendGiftInput(receiver = DEMO_AUTHOR, giftId = "pink-tulip", reference = "post_7"))
        assertEquals(after, c.queryGiftWalls(listOf(com.giftingstack.core.GiftWallQueryItem(DEMO_AUTHOR, DEMO_POST))).single().gifts.first { it.gift.id == "pink-tulip" }.count)

        val away = c.getAway(com.giftingstack.core.AwayQuery())
        assertEquals(74L, away.totalGifts)
        assertEquals(2, c.getAway(com.giftingstack.core.AwayQuery(maxGroups = 2)).groups.size)
        c.ackAway(away.cursor!!)
        assertEquals(0L, c.getAway(com.giftingstack.core.AwayQuery()).totalGifts)
        c.newAwayGifts()
        assertEquals(74L, c.getAway(com.giftingstack.core.AwayQuery()).totalGifts)
    }

    @Test fun theFailNextBoardRequestFailsOnceWithABuildingError() = runTest {
        val c = MockClient()
        c.failNextLeaderboard = true
        val e = runCatching { c.getLeaderboard(LeaderboardBoard.Senders, com.giftingstack.core.LeaderboardQuery()) }.exceptionOrNull() as com.giftingstack.core.GiftingException
        assertEquals("leaderboard_building", e.type)
        assertTrue(e.retryable)
        assertEquals(10, c.getLeaderboard(LeaderboardBoard.Senders, com.giftingstack.core.LeaderboardQuery()).data.size)
    }

    @Test fun coinPacksAreThreeAndPositive() {
        assertEquals(3, COIN_PACKS.size)
        assertTrue(COIN_PACKS.all { it.coins > 0 })
    }
}
