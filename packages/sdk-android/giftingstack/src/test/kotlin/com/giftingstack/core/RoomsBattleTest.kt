package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Battle scores on the session (SPEC 18.6): the round from welcome and scores frames, the server
 * clock offset, callbacks that throw. Wire parsing and battleView run in RoomsConformanceTest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RoomsBattleTest {
    private class Wire : RoomSocket {
        override fun send(data: String) {}

        override fun close(code: Int, reason: String) {}
    }

    private class Session(scope: TestScope, throwOnBattle: Boolean = false) {
        val clock = FakeClock()
        var nowMs = 0L
        val handlers = ArrayList<RoomSocketHandlers>()
        val calls = ArrayList<RoomBattle?>()
        val room =
            RoomClient(
                RoomClientOptions(
                    room = "live_1",
                    getToken = { CompletableDeferred("tok").await() },
                    socket = { _, _, h ->
                        handlers.add(h)
                        Wire()
                    },
                    scope = scope.backgroundScope,
                    timers = clock.timersApi,
                    heartbeatMs = 0,
                    onBattle = {
                        calls.add(it)
                        if (throwOnBattle) throw IllegalStateException("app bug")
                    },
                    now = { nowMs },
                ),
            )

        fun send(frame: String) = handlers.last().onMessage(frame)
    }

    private fun battleJson(ava: Int, mateo: Int, round: String = "r1") =
        """{"round":"$round","started":1000,"ends":61000,"scores":[{"id":"ava","units":$ava,"gifts":${if (ava > 0) 1 else 0}},{"id":"mateo","units":$mateo,"gifts":${if (mateo > 0) 1 else 0}}]}"""

    private fun battleOf(ava: Int, mateo: Int) =
        RoomBattle(
            "r1",
            1000,
            61000,
            listOf(RoomScoreEntry("ava", ava.toLong(), if (ava > 0) 1 else 0), RoomScoreEntry("mateo", mateo.toLong(), if (mateo > 0) 1 else 0)),
        )

    private fun welcome(now: Long = 1000, battle: String? = null): String {
        val extra = if (battle != null) ",\"battle\":$battle" else ""
        return """{"t":"welcome","v":1,"viewers":3,"gap":false,"replay":[],"ttl":3600,"now":$now$extra}"""
    }

    @Test
    fun takesTheRoundFromWelcomeThenEachScoresFrameNullWhenRemoved() = runTest {
        val s = Session(this)
        s.room.start()
        runCurrent()
        s.handlers.last().onOpen()
        assertNull(s.room.getBattle())
        assertNull(s.room.serverNow())
        // Local clock 100, server clock 31,000: offset 30,900.
        s.nowMs = 100
        s.send(welcome(now = 31_000, battle = battleJson(0, 0)))
        assertEquals(battleOf(0, 0), s.room.getBattle())
        assertEquals(31_000L, s.room.serverNow())
        s.send("""{"t":"scores","battle":${battleJson(300, 100)}}""")
        s.nowMs = 10_100
        val v = s.room.getBattleView()!!
        assertEquals(true, v.open)
        assertEquals(20_000L, v.remainingMs)
        assertEquals(400L, v.total)
        assertEquals("ava", v.leader)
        s.send("""{"t":"scores","battle":null}""")
        assertNull(s.room.getBattle())
        assertNull(s.room.getBattleView())
        assertNull(s.room.battle.value)
        assertEquals(listOf(battleOf(0, 0), battleOf(300, 100), null), s.calls)
    }

    @Test
    fun ignoresMalformedScoresAndKeepsTheRoundAcrossAReconnectUntilTheNextWelcome() = runTest {
        val s = Session(this)
        s.room.start()
        runCurrent()
        s.handlers.last().onOpen()
        s.send(welcome(battle = battleJson(5, 0)))
        s.send("""{"t":"scores","battle":{"round":""}}""")
        s.send("""{"t":"scores"}""")
        assertEquals(battleOf(5, 0), s.room.getBattle())
        s.handlers.last().onClose(1006, "")
        assertEquals(RoomStatus.Reconnecting, s.room.getState().status)
        assertEquals(battleOf(5, 0), s.room.getBattle())
        s.room.reconnectNow()
        runCurrent()
        s.handlers.last().onOpen()
        // The new welcome has no round: it was removed while we were away.
        s.send(welcome())
        assertNull(s.room.getBattle())
    }

    @Test
    fun aScoresFrameBeforeTheWelcomeIsIgnored() = runTest {
        val s = Session(this)
        s.room.start()
        runCurrent()
        s.handlers.last().onOpen()
        s.send("""{"t":"scores","battle":${battleJson(1, 2)}}""")
        assertNull(s.room.getBattle())
    }

    @Test
    fun appCallbacksThatThrowNeverBreakTheRoom() = runTest {
        val s = Session(this, throwOnBattle = true)
        s.room.start()
        runCurrent()
        s.handlers.last().onOpen()
        s.send(welcome(battle = battleJson(1, 2)))
        assertEquals(RoomStatus.Open, s.room.getState().status)
        assertEquals(battleOf(1, 2), s.room.getBattle())
    }
}
