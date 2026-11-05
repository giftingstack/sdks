package com.giftingstack.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/**
 * Models of the gift wall, the away summary and the leaderboard (SPEC sections 14 to 16). Counters
 * that add up (units, gift totals) are `Long`; a single gift's `count` stays `Int` like
 * [ReceivedGift]. `toJson` writes the wire shape (snake_case) the API sends.
 */

// ---------------------------------------------------------------- gift walls (SPEC 14)

/** One wall of the batch call: a receiver's profile wall, or one post's wall with [reference]. */
data class GiftWallQueryItem(val receiver: String, val reference: String? = null)

/** One answer of `POST /v1/client/gift-walls/query`, in the order of the request. */
data class GiftWall(val receiver: String, val reference: String?, val gifts: List<ReceivedGift>) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "receiver" to JsonPrimitive(receiver),
                "reference" to reference.json(),
                "gifts" to JsonArray(gifts.map { it.toJson() }),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): GiftWall {
            val o = e.jsonObject
            return GiftWall(
                receiver = o.str("receiver"),
                reference = o.strOrNull("reference"),
                gifts = o.getValue("gifts").jsonArray.map { ReceivedGift.fromJson(it) },
            )
        }
    }
}

// ---------------------------------------------------------------- away summary (SPEC 15)

data class AwayQuery(
    /** An opaque `cursor` from an earlier summary. Overrides the stored cursor for this read. */
    val since: String? = null,
    /** Most gift groups to return, 1 to 10. Server default 5. */
    val maxGroups: Int? = null,
)

/** A sender in an away group. [user] is null for deleted senders (all merged into one entry). */
data class AwaySender(val user: String?, val count: Int) {
    fun toJson(): JsonObject = JsonObject(mapOf("user" to user.json(), "count" to JsonPrimitive(count)))

    companion object {
        fun fromJson(e: JsonElement): AwaySender {
            val o = e.jsonObject
            return AwaySender(o.strOrNull("user"), o.int("count"))
        }
    }
}

/** An entry of [AwaySummary.topSenders]: a sender plus the units they sent. */
data class AwayTopSender(val user: String?, val count: Int, val units: Long) {
    fun toJson(): JsonObject =
        JsonObject(mapOf("user" to user.json(), "count" to JsonPrimitive(count), "units" to JsonPrimitive(units)))

    companion object {
        fun fromJson(e: JsonElement): AwayTopSender {
            val o = e.jsonObject
            return AwayTopSender(o.strOrNull("user"), o.int("count"), o.long("units"))
        }
    }
}

/** The gift of an [AwayGroup]. [price] is today's catalog price: the effect tier matches the tray's. */
data class AwayGift(
    val id: String,
    val name: String,
    val price: Long,
    val iconUrl: String?,
    val animationUrl: String?,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "name" to JsonPrimitive(name),
                "price" to JsonPrimitive(price),
                "icon_url" to iconUrl.json(),
                "animation_url" to animationUrl.json(),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): AwayGift {
            val o = e.jsonObject
            return AwayGift(o.str("id"), o.str("name"), o.long("price"), o.strOrNull("icon_url"), o.strOrNull("animation_url"))
        }
    }
}

data class AwayGroup(
    val gift: AwayGift,
    /** Number of gifts (sum of quantities). */
    val count: Int,
    /** Value in your own coin units. A display counter, never a balance. */
    val units: Long,
    /** Distinct people who sent this gift. */
    val senderCount: Int,
    /** At most 3, by count. */
    val senders: List<AwaySender>,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "gift" to gift.toJson(),
                "count" to JsonPrimitive(count),
                "units" to JsonPrimitive(units),
                "sender_count" to JsonPrimitive(senderCount),
                "senders" to JsonArray(senders.map { it.toJson() }),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): AwayGroup {
            val o = e.jsonObject
            return AwayGroup(
                gift = AwayGift.fromJson(o.getValue("gift")),
                count = o.int("count"),
                units = o.long("units"),
                senderCount = o.int("sender_count"),
                senders = o.getValue("senders").jsonArray.map { AwaySender.fromJson(it) },
            )
        }
    }
}

/** What `GET /v1/client/me/away` returns: gifts received since the person last looked. */
data class AwaySummary(
    val user: String,
    val since: String,
    val until: String,
    /** Send this to `ackAway` once the summary was shown. Unchanged when nothing is new. */
    val cursor: String?,
    /** More than 2,000 gifts arrived: the totals are lower bounds ("2,000+"). */
    val truncated: Boolean,
    val totalGifts: Long,
    val totalUnits: Long,
    val senderCount: Int,
    /** Biggest first (by units), at most `maxGroups`. */
    val groups: List<AwayGroup>,
    /** At most 5, by count. */
    val topSenders: List<AwayTopSender>,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "user" to JsonPrimitive(user),
                "since" to JsonPrimitive(since),
                "until" to JsonPrimitive(until),
                "cursor" to cursor.json(),
                "truncated" to JsonPrimitive(truncated),
                "total_gifts" to JsonPrimitive(totalGifts),
                "total_units" to JsonPrimitive(totalUnits),
                "sender_count" to JsonPrimitive(senderCount),
                "groups" to JsonArray(groups.map { it.toJson() }),
                "top_senders" to JsonArray(topSenders.map { it.toJson() }),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): AwaySummary {
            val o = e.jsonObject
            return AwaySummary(
                user = o.str("user"),
                since = o.str("since"),
                until = o.str("until"),
                cursor = o.strOrNull("cursor"),
                truncated = o.getValue("truncated").jsonPrimitive.boolean,
                totalGifts = o.long("total_gifts"),
                totalUnits = o.long("total_units"),
                senderCount = o.int("sender_count"),
                groups = o.getValue("groups").jsonArray.map { AwayGroup.fromJson(it) },
                topSenders = o.getValue("top_senders").jsonArray.map { AwayTopSender.fromJson(it) },
            )
        }
    }
}

// ---------------------------------------------------------------- leaderboards (SPEC 16)

enum class LeaderboardBoard(val wire: String) {
    Senders("senders"),
    Receivers("receivers"),
    ;

    companion object {
        fun fromWire(s: String): LeaderboardBoard = entries.first { it.wire == s }
    }
}

enum class LeaderboardPeriod(val wire: String) {
    Day("day"),
    Week("week"),
    Month("month"),
    All("all"),
    ;

    companion object {
        fun fromWire(s: String): LeaderboardPeriod = entries.first { it.wire == s }
    }
}

enum class LeaderboardMetric(val wire: String) {
    Units("units"),
    Gifts("gifts"),
    ;

    companion object {
        fun fromWire(s: String): LeaderboardMetric = entries.first { it.wire == s }
    }
}

data class LeaderboardQuery(
    /** Default `week` (server). */
    val period: LeaderboardPeriod? = null,
    /** Default `units` (server). */
    val metric: LeaderboardMetric? = null,
    /** `YYYY-MM-DD`, any day inside the wanted period (UTC). Default today. Ignored for `all`. */
    val at: String? = null,
    /** 1 to 100. Default 10 (server). */
    val limit: Int? = null,
    /** `false` leaves out the `me` block. Null or `true`: the default, nothing is sent. */
    val includeMe: Boolean? = null,
)

data class LeaderboardEntry(
    /** Competition rank on the metric: equal scores share a rank (1, 2, 2, 4). */
    val rank: Int,
    val user: String,
    val gifts: Long,
    val units: Long,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "rank" to JsonPrimitive(rank),
                "user" to JsonPrimitive(user),
                "gifts" to JsonPrimitive(gifts),
                "units" to JsonPrimitive(units),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): LeaderboardEntry {
            val o = e.jsonObject
            return LeaderboardEntry(o.int("rank"), o.str("user"), o.long("gifts"), o.long("units"))
        }
    }
}

data class LeaderboardMe(
    val user: String,
    /** Exact within the top 1,000, else null ("1,000+"). Also null without a score or when hidden. */
    val rank: Int?,
    val gifts: Long,
    val units: Long,
    val hidden: Boolean,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "user" to JsonPrimitive(user),
                "rank" to (rank?.let { JsonPrimitive(it) } ?: JsonNull),
                "gifts" to JsonPrimitive(gifts),
                "units" to JsonPrimitive(units),
                "hidden" to JsonPrimitive(hidden),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): LeaderboardMe {
            val o = e.jsonObject
            return LeaderboardMe(
                user = o.str("user"),
                rank = o.optInt("rank"),
                gifts = o.long("gifts"),
                units = o.long("units"),
                hidden = o.getValue("hidden").jsonPrimitive.boolean,
            )
        }
    }
}

/** What `GET /v1/client/leaderboards/{board}` returns. */
data class Leaderboard(
    val board: LeaderboardBoard,
    val period: LeaderboardPeriod,
    val metric: LeaderboardMetric,
    /** `2026-10-11`, `2026-W41`, `2026-10` or `all`. */
    val label: String,
    val startsAt: String?,
    val endsAt: String?,
    val asOf: String,
    val data: List<LeaderboardEntry>,
    val hasMore: Boolean,
    val me: LeaderboardMe?,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "board" to JsonPrimitive(board.wire),
                "period" to JsonPrimitive(period.wire),
                "metric" to JsonPrimitive(metric.wire),
                "label" to JsonPrimitive(label),
                "starts_at" to startsAt.json(),
                "ends_at" to endsAt.json(),
                "as_of" to JsonPrimitive(asOf),
                "data" to JsonArray(data.map { it.toJson() }),
                "has_more" to JsonPrimitive(hasMore),
                "me" to (me?.toJson() ?: JsonNull),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): Leaderboard {
            val o = e.jsonObject
            val me = o["me"]
            return Leaderboard(
                board = LeaderboardBoard.fromWire(o.str("board")),
                period = LeaderboardPeriod.fromWire(o.str("period")),
                metric = LeaderboardMetric.fromWire(o.str("metric")),
                label = o.str("label"),
                startsAt = o.strOrNull("starts_at"),
                endsAt = o.strOrNull("ends_at"),
                asOf = o.str("as_of"),
                data = o.getValue("data").jsonArray.map { LeaderboardEntry.fromJson(it) },
                hasMore = o.getValue("has_more").jsonPrimitive.boolean,
                me = if (me == null || me is JsonNull) null else LeaderboardMe.fromJson(me),
            )
        }
    }
}

// ---------------------------------------------------------------- json helpers

internal fun JsonObject.long(key: String): Long = getValue(key).jsonPrimitive.long

internal fun JsonObject.optInt(key: String): Int? {
    val v = this[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.content.toInt()
}
