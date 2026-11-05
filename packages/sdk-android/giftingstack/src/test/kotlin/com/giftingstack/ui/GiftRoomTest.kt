package com.giftingstack.ui

import com.giftingstack.core.EffectPlayer
import com.giftingstack.core.FakeClock
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.RoomSocket
import com.giftingstack.core.RoomSocketHandlers
import com.giftingstack.core.RoomStatus
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.GiftTrayOptions
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GiftRoom] with a fake socket: lifecycle pause/resume, playing on the effect layer, the catalog. */
@OptIn(ExperimentalCoroutinesApi::class)
class GiftRoomTest {
    private class FakeSocket(val url: String, val protocols: List<String>, val handlers: RoomSocketHandlers) : RoomSocket {
        val sent = ArrayList<String>()
        var closed: Pair<Int, String>? = null

        override fun send(data: String) {
            sent.add(data)
        }

        override fun close(code: Int, reason: String) {
            closed = code to reason
        }
    }

    private class Player : EffectPlayer {
        val played = ArrayList<GiftEffectEvent>()

        override fun play(event: GiftEffectEvent): Int {
            played.add(event)
            return played.size
        }

        override fun cancel(id: Int) {}
    }

    private fun gift(id: Long, tx: String, at: Long = 1000, sender: String = "ayla", price: Int = 50) =
        """{"t":"gift","id":$id,"at":$at,"tx":"$tx","gift":{"id":"rose","name":"Rose","price":$price,"icon_url":"https://i/rose.webp"},"quantity":3,"sender":{"id":"$sender","name":"Ayla"},"receiver":{"id":"host"}}"""

    private fun welcome(now: Long = 1000) = """{"t":"welcome","v":1,"viewers":2,"gap":false,"replay":[],"ttl":3600,"now":$now}"""

    private class Harness(scope: TestScope) {
        val clock = FakeClock()
        val sockets = ArrayList<FakeSocket>()
        val player = Player()
        val tokens = ArrayList<Boolean>()
        val battleSeen = ArrayList<String?>()
        val catalogCalls = IntArray(1)
        val api =
            object : GiftingApi by NoApi {
                override suspend fun getGifts(): List<Gift> {
                    catalogCalls[0]++
                    return listOf(Gift("rose", "Rose (catalog)", null, 99, "https://i/cat-icon.webp", "https://i/big.webp", 1))
                }
            }
        val room =
            GiftRoom(
                GiftRoomOptions(
                    room = "live_1",
                    getToken = { refresh ->
                        tokens.add(refresh)
                        "gs_ct_eyJ1IjoibWUifQ.sig" // {"u":"me"}
                    },
                    client = api,
                    effects = { player },
                    onBattle = { battleSeen.add(it?.round) },
                    socket = { url, protocols, handlers -> FakeSocket(url, protocols, handlers).also { sockets.add(it) } },
                    now = { clock.now },
                    random = { 0.5 },
                ),
                scope.backgroundScope,
                clock.timersApi,
            )
    }

    @Test
    fun connectsHelloPlaysRoomGiftsAndSkipsOwn() = runTest {
        val h = Harness(this)
        h.room.loadCatalog()
        h.room.foreground()
        runCurrent()
        assertEquals(1, h.catalogCalls[0])
        assertEquals(listOf(false), h.tokens)
        val s = h.sockets.single()
        assertEquals("wss://rt.giftingstack.com/v1/rooms/live_1", s.url)
        assertEquals(listOf("gs.v1", "gs_ct_eyJ1IjoibWUifQ.sig"), s.protocols)
        s.handlers.onOpen()
        assertEquals(listOf("""{"t":"hello","v":1,"last":null}"""), s.sent)
        s.handlers.onMessage(welcome())
        assertEquals(RoomStatus.Open, h.room.state.value.status)
        assertEquals(2L, h.room.state.value.viewers)
        s.handlers.onMessage(gift(1, "gtx_a"))
        s.handlers.onMessage(gift(2, "gtx_own", sender = "me"))
        assertEquals("one gift played, the user's own skipped", 1, h.player.played.size)
        val e = h.player.played.single()
        assertEquals("Ayla", e.sender)
        assertEquals(3, e.quantity)
        assertEquals("the big picture comes from the catalog", "https://i/big.webp", e.gift.image)
        assertEquals("https://i/rose.webp", e.gift.icon)
        assertEquals(50, e.gift.price)
    }

    @Test
    fun backgroundPausesAndForegroundResumesWithLast() = runTest {
        val h = Harness(this)
        h.room.foreground()
        runCurrent()
        val first = h.sockets.single()
        first.handlers.onOpen()
        first.handlers.onMessage(welcome())
        first.handlers.onMessage(gift(7, "gtx_a"))
        h.room.background()
        assertEquals(RoomStatus.Paused, h.room.state.value.status)
        assertEquals(1000 to "client", first.closed)
        // Nothing arrives for a closed socket, and nothing reconnects while paused.
        first.handlers.onMessage(gift(8, "gtx_b"))
        h.clock.advance(120_000)
        runCurrent()
        assertEquals(1, h.sockets.size)
        assertEquals(1, h.player.played.size)

        h.room.foreground()
        runCurrent()
        assertEquals(2, h.sockets.size)
        val second = h.sockets[1]
        second.handlers.onOpen()
        assertEquals("resume with the last id", listOf("""{"t":"hello","v":1,"last":7}"""), second.sent)
        second.handlers.onMessage(welcome())
        second.handlers.onMessage(gift(7, "gtx_a")) // already seen
        assertEquals(1, h.player.played.size)
        assertEquals(listOf(false, false), h.tokens)
    }

    @Test
    fun foregroundTwiceOpensOneSocketAndLeaveClosesForGood() = runTest {
        val h = Harness(this)
        h.room.foreground()
        h.room.foreground()
        runCurrent()
        assertEquals(1, h.sockets.size)
        h.room.leave()
        assertEquals(RoomStatus.Closed, h.room.state.value.status)
        assertEquals(1000, h.room.state.value.code)
        h.room.foreground()
        runCurrent()
        assertEquals("closed is terminal", 1, h.sockets.size)
    }

    @Test
    fun optionsCanChangeBetweenCalls() = runTest {
        val h = Harness(this)
        h.room.foreground()
        runCurrent()
        val s = h.sockets.single()
        s.handlers.onOpen()
        s.handlers.onMessage(welcome())
        val seen = ArrayList<String>()
        h.room.setOptions(
            GiftRoomOptions(
                room = "live_1",
                getToken = { "t" },
                effects = null,
                onEvent = { seen.add(it.tx) },
                socket = null,
                now = { h.clock.now },
            ),
        )
        s.handlers.onMessage(gift(1, "gtx_a"))
        assertEquals(listOf("gtx_a"), seen)
        assertTrue("effects were switched off", h.player.played.isEmpty())
    }

    @Test
    fun exposesTheBattleRoundAndViewAndCallsOnBattle() = runTest {
        val h = Harness(this)
        h.room.foreground()
        runCurrent()
        val s = h.sockets.single()
        s.handlers.onOpen()
        s.handlers.onMessage(welcome())
        assertNull(h.room.battle.value)
        assertNull(h.room.battleView())
        s.handlers.onMessage(
            """{"t":"scores","battle":{"round":"r1","started":0,"ends":100000000000000,"scores":[{"id":"ava","units":10,"gifts":1},{"id":"mateo","units":30,"gifts":2}]}}""",
        )
        assertEquals("r1", h.room.battle.value!!.round)
        val v = h.room.battleView()!!
        assertEquals("mateo", v.leader)
        assertEquals(listOf(0.25, 0.75), v.sides.map { it.share })
        s.handlers.onMessage("""{"t":"scores","battle":null}""")
        assertNull(h.room.battle.value)
        assertEquals(listOf<String?>("r1", null), h.battleSeen)
    }

    @Test
    fun aBadRoomIdClosesAtOnceWithNoSocket() = runTest {
        val sockets = ArrayList<FakeSocket>()
        val room =
            GiftRoom(
                GiftRoomOptions(room = "no spaces", getToken = { "t" }, socket = { u, p, hd -> FakeSocket(u, p, hd).also { sockets.add(it) } }),
                backgroundScope,
                FakeClock().timersApi,
            )
        room.foreground()
        runCurrent()
        assertEquals(RoomStatus.Closed, room.state.value.status)
        assertEquals(4004, room.state.value.code)
        assertTrue(sockets.isEmpty())
    }

    @Test
    fun trayOptionsCarryTheRoomIdIntoTheSend() = runTest {
        val sent = ArrayList<SendGiftInput>()
        val api =
            object : GiftingApi by NoApi {
                override suspend fun getGifts() = listOf(Gift("rose", "Rose", null, 10, null, null, 1))

                override suspend fun getMe() = com.giftingstack.core.Me("me", 100)

                override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
                    sent.add(input)
                    return GiftTransaction("t", "me", input.receiver, com.giftingstack.core.GiftRef("rose", "Rose", null), 1, 10, 10, null, null, "completed", "2026-01-01T00:00:00Z", 90)
                }
            }
        val withRoom = GiftTrayHolder(GiftTrayOptions(api, "host", roomId = "live_1"), backgroundScope)
        withRoom.refresh()
        runCurrent()
        withRoom.send(api.getGifts()[0])
        runCurrent()
        val without = GiftTrayHolder(GiftTrayOptions(api, "host"), backgroundScope)
        without.send(api.getGifts()[0])
        runCurrent()
        assertEquals("live_1", sent[0].roomId)
        assertNull(sent[1].roomId)
    }
}

/** A client that fails every call; tests override what they use. */
private object NoApi : GiftingApi {
    override suspend fun getGifts(): List<Gift> = error("unused")

    override suspend fun getMe(): com.giftingstack.core.Me = error("unused")

    override suspend fun getReceivedGifts(user: String): List<com.giftingstack.core.ReceivedGift> = error("unused")

    override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("unused")
}
