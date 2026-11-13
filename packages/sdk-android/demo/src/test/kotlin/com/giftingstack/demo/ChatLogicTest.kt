package com.giftingstack.demo

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class ChatLogicTest {
    @Test
    fun repeatsOfTheSameGiftAddUp() {
        var list: List<ChatMessage> = CHAT_START
        list = addGiftLine(list, null, "rose", "Rose", null, 1)
        list = addGiftLine(list, null, "rose", "Rose", null, 2)
        assertEquals(CHAT_START.size + 1, list.size)
        val last = list.last() as ChatGift
        assertEquals(3L, last.count)
        assertEquals("You sent Rose ×3", giftLineText(last))
        list = addGiftLine(list, null, "star", "Star", null, 1)
        assertEquals("You sent Star", giftLineText(list.last() as ChatGift))
        list = addGiftLine(list, "zoe", "star", "Star", null, 1)
        assertEquals("another sender is a new line", CHAT_START.size + 3, list.size)
        assertEquals("Zoe sent Star", giftLineText(list.last() as ChatGift))
    }

    @Test
    fun aBattleGiftNamesItsSideAndCountsPerSide() {
        var list: List<ChatMessage> = emptyList()
        list = addGiftLine(list, null, "rose", "Rose", null, 1, LIVE_RIVAL)
        list = addGiftLine(list, null, "rose", "Rose", null, 1, LIVE_RIVAL)
        assertEquals(1, list.size)
        assertEquals("You sent Rose to Mateo ×2", giftLineText(list.last() as ChatGift))
        list = addGiftLine(list, null, "rose", "Rose", null, 1, LIVE_HOST)
        assertEquals("another side is a new line", 2, list.size)
        assertEquals(LIVE_HOST, (list.last() as ChatGift).receiver)
    }

    @Test
    fun theLiveSidesShareTheBarColours() {
        val theme = com.giftingstack.ui.GiftingTheme()
        val colors = liveSideColors(theme)
        assertEquals(listOf(theme.accent, theme.coin), colors.take(2))
        assertEquals(colors[1], liveSideColor(LIVE_RIVAL, colors))
        assertEquals(null, liveSideColor("someone", colors))
        val receivers = liveReceivers(LIVE_HOSTS.take(2), colors)
        assertEquals(listOf(LIVE_HOST, LIVE_RIVAL), receivers.map { it.id })
        assertEquals(displayName(LIVE_RIVAL), receivers[1].name)
        assertEquals(hexOf(colors[1]), receivers[1].color)
        assertEquals("#2ec4b6", liveReceivers(LIVE_HOSTS, colors)[2].color)
        assertEquals(emptyList<Any>(), liveReceivers(emptyList(), colors))
    }

    @Test
    fun aCommentBetweenDoesNotCutARunningCombo() {
        var list: List<ChatMessage> = emptyList()
        list = addGiftLine(list, null, "rose", "Rose", null, 1, now = 1_000)
        list = list + ChatText(null, "hi")
        list = addGiftLine(list, "zoe", "star", "Star", null, 1, now = 2_000)
        list = addGiftLine(list, null, "rose", "Rose", null, 1, now = 3_000)
        assertEquals("the combo line moved to the bottom", 3, list.size)
        assertEquals(ChatText(null, "hi"), list[0])
        assertEquals("You sent Rose ×2", giftLineText(list.last() as ChatGift))
        // The window counts from the line's last gift: 4.9 s later it still adds up, 5 s later it is a new line.
        list = addGiftLine(list, null, "rose", "Rose", null, 1, now = 7_900)
        assertEquals("You sent Rose ×3", giftLineText(list.last() as ChatGift))
        list = addGiftLine(list, null, "rose", "Rose", null, 1, now = 12_900)
        assertEquals(4, list.size)
        assertEquals("You sent Rose", giftLineText(list.last() as ChatGift))
    }

    @Test
    fun oneComboGetsOneThankYou() {
        val start: List<ChatMessage> = CHAT_START
        val first = addGiftLine(start, null, "rose", "Rose", null, 1, now = 1_000, moveDown = false)
        assertEquals("a new bubble", true, needsThanks(start, first))
        val second = addGiftLine(first, null, "rose", "Rose", null, 1, now = 2_000, moveDown = false)
        assertEquals("the combo goes on before its thank-you", true, needsThanks(first, second))
        val thanked = second + ChatText(CHAT_PEER, CHAT_THANKS)
        val third = addGiftLine(thanked, null, "rose", "Rose", null, 1, now = 4_000, moveDown = false)
        assertEquals("the combo goes on after its thank-you", false, needsThanks(thanked, third))
        val fourth = addGiftLine(third, null, "rose", "Rose", null, 1, now = 6_000, moveDown = false)
        assertEquals("still no second thank-you", false, needsThanks(third, fourth))
        assertEquals("the bubble stays above its thank-you", "You sent Rose ×4", giftLineText(fourth[fourth.size - 2] as ChatGift))
    }

    @Test
    fun theCommentColumnKeepsTheLastFew() {
        val many = (1..8).map { ChatText(null, "c$it") }
        assertEquals((4..8).map { ChatText(null, "c$it") }, keepLast(many))
        assertEquals(many.take(3), keepLast(many.take(3)))
    }

    @Test
    fun theBarSitsOnTheTrayOrTheKeyboard() {
        assertEquals(200.dp, barLift(trayOpen = true, trayInset = 300.dp, keyboard = 0.dp, below = 100.dp))
        assertEquals(236.dp, barLift(trayOpen = false, trayInset = 300.dp, keyboard = 336.dp, below = 100.dp))
        assertEquals(0.dp, barLift(trayOpen = false, trayInset = 0.dp, keyboard = 0.dp, below = 100.dp))
    }
}
