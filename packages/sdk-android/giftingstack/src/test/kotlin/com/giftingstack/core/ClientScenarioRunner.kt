package com.giftingstack.core

import java.io.IOException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail

private val UUID_LIKE = Regex("^[0-9A-Fa-f-]{16,255}$")

/**
 * One client scenario (conformance/README.md, "client.json") against a scripted transport and
 * token provider. Shared by client.json and the `client` sections of wall.json, away.json and
 * leaderboard.json.
 */
fun runClientScenario(name: String, s: JsonObject) {
    val tokens = s.getValue("tokens").arr()
    val exchanges = s.getValue("exchanges").arr()
    val tokenCalls = ArrayList<Boolean>()
    val seenHeaders = ArrayList<Map<String, String>>()
    var n = 0

    val getToken: suspend (Boolean) -> String = { force ->
        val next = tokens.getOrNull(tokenCalls.size)
        tokenCalls.add(force)
        assertNotNull("$name: unexpected getToken call #${tokenCalls.size}", next)
        assertEquals("$name: getToken #${tokenCalls.size} forceRefresh", next!!.obj().bool("forceRefresh"), force)
        next.obj().string("returns")
    }

    val transport = GiftingTransport { req ->
        val at = "$name: request ${n + 1}"
        val ex = exchanges.getOrNull(n)?.obj()
        n++
        assertNotNull("unexpected $at: ${req.method} ${req.url}", ex)
        val want = ex!!.getValue("request").obj()
        assertEquals("$at method", want.string("method"), req.method)
        assertEquals("$at url", want.string("url"), req.url)
        val headers = req.headers.mapKeys { it.key.lowercase() }
        seenHeaders.add(headers)
        for ((k, v) in want.getValue("headers").obj()) {
            val expected = v.jsonPrimitive.content
            val got = headers[k.lowercase()]
            val same = Regex("^<same-as-request:(\\d+)>$").find(expected)
            when {
                expected == "<any-uuid-like>" -> {
                    assertNotNull("$at $k", got)
                    assertTrue("$at $k must look like a UUID, got $got", UUID_LIKE.matches(got!!))
                }
                same != null -> {
                    assertNotNull("$at $k", got)
                    assertEquals("$at $k", seenHeaders[same.groupValues[1].toInt() - 1][k.lowercase()], got)
                }
                else -> assertEquals("$at $k", expected, got)
            }
        }
        for (k in want.getValue("absentHeaders").arr()) {
            assertNull("$at ${k.jsonPrimitive.content} must be absent", headers[k.jsonPrimitive.content.lowercase()])
        }
        val wantBody = want.getValue("body")
        if (wantBody is JsonNull) {
            assertNull("$at body", req.body)
        } else {
            assertNotNull("$at body", req.body)
            assertEquals("$at body", wantBody, Json.parseToJsonElement(req.body!!))
        }
        if (ex.containsKey("networkError")) throw IOException("Network request failed")
        val r = ex.getValue("response").obj()
        val text = if (r.has("bodyText")) r.string("bodyText") else r.getValue("body").toString()
        TransportResponse(
            status = r.getValue("status").jsonPrimitive.content.toInt(),
            headers = r.getValue("headers").obj().mapValues { it.value.jsonPrimitive.content },
            body = text,
        )
    }

    val client =
        if (s.has("baseUrl")) GiftingClient(getToken, s.string("baseUrl"), transport)
        else GiftingClient(getToken, transport = transport)

    val call = s.getValue("call").obj()
    val args = call["args"]?.obj() ?: JsonObject(emptyMap())
    var result: JsonElement? = null
    var failure: Throwable? = null
    try {
        result =
            runBlocking {
                when (val m = call.string("method")) {
                    "getGifts" -> JsonArray(client.getGifts().map { it.toJson() })
                    "getMe" -> client.getMe().toJson()
                    "getReceivedGifts" ->
                        JsonArray(client.getReceivedGifts(args.string("user"), args.stringOrNull("reference")).map { it.toJson() })
                    "sendGift" -> client.sendGift(sendInput(args.getValue("input").obj())).toJson()
                    "queryGiftWalls" ->
                        JsonArray(
                            client.queryGiftWalls(
                                args.getValue("items").arr().map { GiftWallQueryItem(it.obj().string("receiver"), it.obj().stringOrNull("reference")) },
                            ).map { it.toJson() },
                        )
                    "getAway" -> client.getAway(awayQuery(args["query"]?.obj())).toJson()
                    "ackAway" -> {
                        client.ackAway(args.string("cursor"))
                        JsonNull
                    }
                    "getInbox" -> client.getInbox(inboxQuery(args["query"]?.obj())).toJson()
                    "getLeaderboard" ->
                        client.getLeaderboard(LeaderboardBoard.fromWire(args.string("board")), leaderboardQuery(args["query"]?.obj())).toJson()
                    else -> error("unknown call $m")
                }
            }
    } catch (e: Throwable) {
        failure = e
    }

    if (s.has("error")) {
        if (failure !is GiftingException) fail("$name: expected a GiftingException, got $failure")
        val e = failure as GiftingException
        val want = s.getValue("error").obj()
        assertEquals("status", want.intOrNull("status"), e.status)
        assertEquals("type", want.string("type"), e.type)
        assertEquals("message", want.string("message"), e.message)
        assertEquals("requestId", want.stringOrNull("requestId"), e.requestId)
        assertEquals("retryable", want.bool("retryable"), e.retryable)
        assertEquals("insufficientBalance", want.bool("insufficientBalance"), e.insufficientBalance)
    } else {
        if (failure != null) throw failure
        assertEquals("$name: result", s.getValue("result"), result)
    }
    assertEquals("$name: requests made", exchanges.size, n)
    assertEquals("$name: getToken calls", tokens.size, tokenCalls.size)
}

private fun sendInput(o: JsonObject) =
    SendGiftInput(
        receiver = o.string("receiver"),
        giftId = o.string("giftId"),
        quantity = o.intOrNull("quantity"),
        message = o.stringOrNull("message"),
        reference = o.stringOrNull("reference"),
        idempotencyKey = o.stringOrNull("idempotencyKey"),
    )

private fun awayQuery(q: JsonObject?) =
    if (q == null) AwayQuery() else AwayQuery(since = q.stringOrNull("since"), maxGroups = q.intOrNull("maxGroups"))

private fun inboxQuery(q: JsonObject?) =
    if (q == null) InboxQuery() else InboxQuery(cursor = q.stringOrNull("cursor"), limit = q.intOrNull("limit"))

private fun leaderboardQuery(q: JsonObject?) =
    if (q == null) {
        LeaderboardQuery()
    } else {
        LeaderboardQuery(
            period = q.stringOrNull("period")?.let { LeaderboardPeriod.fromWire(it) },
            metric = q.stringOrNull("metric")?.let { LeaderboardMetric.fromWire(it) },
            at = q.stringOrNull("at"),
            limit = q.intOrNull("limit"),
            includeMe = q["includeMe"]?.let { if (it is JsonNull) null else it.jsonPrimitive.content.toBoolean() },
        )
    }
