package com.giftingstack.ui

import com.giftingstack.core.NoticeData
import com.giftingstack.core.Timers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The notice stack bookkeeping on a fake clock (no Compose, no device). */
class NoticeStackTest {
    private class Clock {
        var now = 0L
        private var next = 1
        private val pending = HashMap<Int, Pair<Long, () -> Unit>>()

        val timers =
            Timers(
                set = { ms, fn ->
                    val h = next++
                    pending[h] = Pair(now + ms, fn)
                    h
                },
                clear = { pending.remove(it as Int) },
            )

        fun advance(ms: Long) {
            val end = now + ms
            while (true) {
                val due = pending.entries.filter { it.value.first <= end }.minByOrNull { it.value.first } ?: break
                pending.remove(due.key)
                now = due.value.first
                due.value.second()
            }
            now = end
        }

        val count: Int get() = pending.size
    }

    private fun data(id: Int, sender: String = "s$id", count: Int = 1) = NoticeData(id, sender, "Gift", null, count, false)

    private fun stack(clock: Clock): NoticeStack {
        val s = NoticeStack()
        s.attach(clock.timers)
        return s
    }

    private fun NoticeStack.ids() = lines.map { it.id }

    @Test
    fun twoSendersTwoLinesNewestLast() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 2400)
        s.show(data(2), 2400)
        assertEquals(listOf(1, 2), s.ids())
        assertTrue(s.lines.all { it.visible })
    }

    @Test
    fun sameIdUpdatesInPlaceAndRestartsItsTimer() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1, count = 1), 1000)
        s.show(data(2), 5000)
        val first = s.lines[0]
        clock.advance(800)
        s.show(data(1, count = 2), 1000)
        assertEquals(listOf(1, 2), s.ids())
        assertTrue("same line object", first === s.lines[0])
        assertEquals(2, first.data.count)
        clock.advance(500) // 1300 ms after the first call: the old timer would have fired
        assertTrue(first.visible)
        clock.advance(600) // 1100 ms after the update
        assertTrue(!first.visible)
    }

    @Test
    fun aFourthLineDropsTheOldestAtOnce() {
        val clock = Clock()
        val s = stack(clock)
        for (i in 1..3) s.show(data(i), 2400)
        s.show(data(4), 2400)
        assertEquals(listOf(2, 3, 4), s.ids())
        assertTrue(s.lines.all { it.visible })
        assertEquals("the dropped line's timers are gone", 3, clock.count)
    }

    @Test
    fun eachLineExpiresOnItsOwnTimer() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 1000)
        clock.advance(500)
        s.show(data(2), 1000)
        clock.advance(500) // line 1 expires now
        assertEquals(listOf(false, true), s.lines.map { it.visible })
        clock.advance(NOTICE_EXIT_MS)
        assertEquals(listOf(2), s.ids())
        clock.advance(240) // line 2: 1000 ms after its call
        assertTrue(!s.lines.single().visible)
        clock.advance(NOTICE_EXIT_MS)
        assertTrue(s.lines.isEmpty())
        assertEquals(0, clock.count)
    }

    @Test
    fun anExpiredIdIsANewLine() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 500)
        clock.advance(500 + NOTICE_EXIT_MS)
        assertTrue(s.lines.isEmpty())
        s.show(data(1, count = 3), 500)
        assertEquals(1, s.lines.size)
        assertTrue(s.lines.single().visible)
    }

    @Test
    fun hideRemovesOnlyTheNewest() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 5000)
        s.show(data(2), 5000)
        s.hideNewest()
        assertEquals(listOf(true, false), s.lines.map { it.visible })
        clock.advance(NOTICE_EXIT_MS)
        assertEquals(listOf(1), s.ids())
        assertTrue(s.lines.single().visible)
    }

    @Test
    fun clearRemovesAllLinesAndTimers() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 5000)
        s.show(data(2), 5000)
        s.hideNewest()
        s.clear()
        assertTrue(s.lines.isEmpty())
        assertEquals(0, clock.count)
        s.hideNewest() // nothing left: no error
    }

    @Test
    fun detachCancelsTimersAndAttachRearmsThem() {
        val clock = Clock()
        val s = stack(clock)
        s.show(data(1), 1000)
        s.show(data(2), 1000)
        s.detach()
        assertEquals(0, clock.count)
        clock.advance(5000)
        assertEquals(listOf(1, 2), s.ids())
        s.attach(clock.timers)
        assertEquals(2, clock.count)
        clock.advance(1000 + NOTICE_EXIT_MS)
        assertTrue(s.lines.isEmpty())
    }

    @Test
    fun linesShownBeforeAttachGetTheirTimerOnAttach() {
        val clock = Clock()
        val s = NoticeStack()
        s.show(data(1), 1000)
        assertEquals(0, clock.count)
        s.attach(clock.timers)
        clock.advance(1000 + NOTICE_EXIT_MS)
        assertTrue(s.lines.isEmpty())
    }
}
