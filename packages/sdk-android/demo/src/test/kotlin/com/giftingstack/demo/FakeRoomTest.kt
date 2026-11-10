package com.giftingstack.demo

import com.giftingstack.core.Gift
import com.giftingstack.core.RoomClient
import com.giftingstack.core.RoomClientOptions
import com.giftingstack.core.RoomGiftEvent
import com.giftingstack.core.RoomState
import com.giftingstack.core.RoomStatus
import com.giftingstack.core.Timers
import com.giftingstack.core.roomTokenUser
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pretend rooms server of the Live tab, driven by the real RoomClient on a manual clock. */
@OptIn(ExperimentalCoroutinesApi::class)
class FakeRoomTest {
    private class Clock {
        var now = 1_760_000_000_000L
        private var seq = 0
        private val timers = ArrayList<Triple<Int, Long, () -> Unit>>()
        val api = Timers(set = { ms, fn -> val id = ++seq; timers.add(Triple(id, now + ms, fn)); id }, clear = { h -> timers.removeAll { it.first == h } })

        fun advance(ms: Long) {
            val target = now + ms
            while (true) {
                val t = timers.filter { it.second <= target }.minByOrNull { it.second * 1000 + it.first } ?: break
                timers.remove(t)
                now = t.second
                t.third()
            }
            now = target
        }
    }

    private val catalog = listOf(Gift("rose", "Rose", null, 50, "https://i/rose.webp", null, 1))

    @Test fun demoTokenNamesTheUser() {
        assertEquals("ava", roomTokenUser(demoRoomToken("ava")))
        assertEquals("caleb", roomTokenUser(demoRoomToken("caleb")))
    }

    @Test fun base64UrlMatchesTheStandardAlphabet() {
        assertEquals("", base64Url(ByteArray(0)))
        assertEquals("Zg", base64Url("f".toByteArray()))
        assertEquals("Zm8", base64Url("fo".toByteArray()))
        assertEquals("Zm9v", base64Url("foo".toByteArray()))
        assertEquals("-_8", base64Url(byteArrayOf(0xfb.toByte(), 0xff.toByte())))
    }

    @Test fun statusLineNamesEachState() {
        assertEquals("Live · 41 watching", liveStatusLine(RoomState(status = RoomStatus.Open, viewers = 41)))
        assertEquals("Connecting...", liveStatusLine(RoomState(status = RoomStatus.Connecting)))
        assertEquals("Paused (app in the background)", liveStatusLine(RoomState(status = RoomStatus.Paused)))
    }

    @Test fun battle4HasFourHostsInEveryRound() = runTest {
        val clock = Clock()
        val server = FakeRoomServer(gifts = { catalog }, timers = clock.api, now = { clock.now }, random = Random(7), sides = 4)
        val room =
            RoomClient(
                RoomClientOptions(
                    room = LIVE_ROOM_4,
                    getToken = { demoRoomToken(DEMO_VIEWER) },
                    socket = server.factory,
                    scope = backgroundScope,
                    timers = clock.api,
                    now = { clock.now },
                ),
            )
        room.start()
        runCurrent()
        clock.advance(200)
        assertEquals(LIVE_HOSTS, room.getBattle()?.scores?.map { it.id })
        clock.advance(60_000)
        assertEquals("demo_r2", room.getBattle()?.round)
        assertEquals(4, room.getBattle()?.scores?.size)
        room.leave()
    }

    @Test fun roomClientJoinsGetsViewersAndOthersGifts() = runTest {
        val clock = Clock()
        val server = FakeRoomServer(gifts = { catalog }, timers = clock.api, now = { clock.now }, random = Random(7))
        val events = ArrayList<RoomGiftEvent>()
        val room =
            RoomClient(
                RoomClientOptions(
                    room = LIVE_ROOM,
                    getToken = { demoRoomToken(DEMO_VIEWER) },
                    socket = server.factory,
                    scope = backgroundScope,
                    timers = clock.api,
                    now = { clock.now },
                    onEvent = { events.add(it) },
                ),
            )
        room.start()
        runCurrent()
        clock.advance(200)
        assertEquals(RoomStatus.Open, room.getState().status)
        assertTrue("a viewer count came with the welcome", (room.getState().viewers ?: 0) in 38..60)
        assertEquals("wss://rt.giftingstack.com/v1/rooms/$LIVE_ROOM", server.sockets.single().url)
        // The battle: the welcome carries round 1 between the two hosts and gifts score into it.
        clock.advance(40_000)
        val battle = room.getBattle()
        assertEquals("demo_r1", battle?.round)
        assertEquals(listOf(LIVE_HOST, LIVE_RIVAL), battle?.scores?.map { it.id })
        assertTrue("gifts scored into the round", (battle?.scores?.sumOf { it.units } ?: 0L) > 0L)
        // The round ends after 45 s and a new one starts after the break.
        clock.advance(20_000)
        assertEquals("demo_r2", room.getBattle()?.round)
        assertEquals(listOf(LIVE_HOST, LIVE_RIVAL), room.getBattle()?.scores?.map { it.id })
        assertTrue("others sent gifts", events.isNotEmpty())
        assertTrue(events.all { it.senderId in LIVE_SENDERS && !it.replayed && it.gift.id == "rose" })
        assertTrue("names come from the sender", events.all { it.sender == displayName(it.senderId) })
        // The pretend server stops when the client pauses (app in the background).
        room.pause()
        assertTrue(server.sockets.single().closed)
        val n = events.size
        clock.advance(60_000)
        assertEquals(n, events.size)
        room.leave()
    }
}
