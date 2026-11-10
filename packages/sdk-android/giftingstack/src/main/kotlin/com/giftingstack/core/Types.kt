package com.giftingstack.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A gift as the app sees it (`GET /v1/client/gifts`). */
data class Gift(
    val id: String,
    val name: String,
    val description: String?,
    /** Coins. A `Long`: prices and balances are 64-bit on the server (audit R-06). */
    val price: Long,
    val iconUrl: String?,
    val animationUrl: String?,
    val sortOrder: Int,
) {
    /** The gift as the API sent it (snake_case keys). */
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "name" to JsonPrimitive(name),
                "description" to description.json(),
                "price" to JsonPrimitive(price),
                "icon_url" to iconUrl.json(),
                "animation_url" to animationUrl.json(),
                "sort_order" to JsonPrimitive(sortOrder),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): Gift {
            val o = e.jsonObject
            return Gift(
                id = o.str("id"),
                name = o.str("name"),
                description = o.strOrNull("description"),
                price = o.long("price"),
                iconUrl = o.strOrNull("icon_url"),
                animationUrl = o.strOrNull("animation_url"),
                sortOrder = o.int("sort_order"),
            )
        }
    }
}

/**
 * The signed-in user and their coins (`GET /v1/client/me`). [livemode] `false`: the token was
 * made with a test key (the test environment allows 50 users and 5,000 operations a month; the
 * tray shows "Test mode"). Null from older servers.
 */
data class Me(val user: String, val balance: Long, val livemode: Boolean? = null) {
    fun toJson(): JsonObject =
        JsonObject(
            buildMap {
                put("user", JsonPrimitive(user))
                put("balance", JsonPrimitive(balance))
                if (livemode != null) put("livemode", JsonPrimitive(livemode))
            },
        )

    companion object {
        fun fromJson(e: JsonElement): Me {
            val o = e.jsonObject
            val live = (o["livemode"] as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull
            return Me(o.str("user"), o.long("balance"), live)
        }
    }
}

/** The small gift reference inside [ReceivedGift] and [GiftTransaction]. */
data class GiftRef(val id: String, val name: String, val iconUrl: String?) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "name" to JsonPrimitive(name),
                "icon_url" to iconUrl.json(),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): GiftRef {
            val o = e.jsonObject
            return GiftRef(o.str("id"), o.str("name"), o.strOrNull("icon_url"))
        }
    }
}

data class ReceivedGift(val gift: GiftRef, val count: Int) {
    fun toJson(): JsonObject =
        JsonObject(mapOf("gift" to gift.toJson(), "count" to JsonPrimitive(count)))

    companion object {
        fun fromJson(e: JsonElement): ReceivedGift {
            val o = e.jsonObject
            return ReceivedGift(GiftRef.fromJson(o.getValue("gift")), o.int("count"))
        }
    }
}

/** What `POST /v1/client/gift-transactions` returns. [createdAt] stays an ISO 8601 string. */
data class GiftTransaction(
    val id: String,
    val sender: String,
    val receiver: String,
    val gift: GiftRef,
    val quantity: Int,
    val unitPrice: Long,
    val total: Long,
    val message: String?,
    val reference: String?,
    /** `"completed"` or `"reversed"`. */
    val status: String,
    val createdAt: String,
    val senderBalanceAfter: Long,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "sender" to JsonPrimitive(sender),
                "receiver" to JsonPrimitive(receiver),
                "gift" to gift.toJson(),
                "quantity" to JsonPrimitive(quantity),
                "unit_price" to JsonPrimitive(unitPrice),
                "total" to JsonPrimitive(total),
                "message" to message.json(),
                "reference" to reference.json(),
                "status" to JsonPrimitive(status),
                "created_at" to JsonPrimitive(createdAt),
                "sender_balance_after" to JsonPrimitive(senderBalanceAfter),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): GiftTransaction {
            val o = e.jsonObject
            return GiftTransaction(
                id = o.str("id"),
                sender = o.str("sender"),
                receiver = o.str("receiver"),
                gift = GiftRef.fromJson(o.getValue("gift")),
                quantity = o.int("quantity"),
                unitPrice = o.long("unit_price"),
                total = o.long("total"),
                message = o.strOrNull("message"),
                reference = o.strOrNull("reference"),
                status = o.str("status"),
                createdAt = o.str("created_at"),
                senderBalanceAfter = o.long("sender_balance_after"),
            )
        }
    }
}

/** Input of `sendGift`. Absent (null) optional fields are left out of the request body. */
data class SendGiftInput(
    val receiver: String,
    val giftId: String,
    /** 1 to 1000. Default 1 (the server's default). */
    val quantity: Int? = null,
    /** Up to 280 characters. */
    val message: String? = null,
    /** Your own context id, for example the post the gift is on. */
    val reference: String? = null,
    /** A room id (SPEC 17.1): everyone in that room sees the gift's effect. Sent as `room_id`. */
    val roomId: String? = null,
    /**
     * Identifies this send. Retrying with the same key never charges twice. The client makes
     * one per call; pass your own only to retry across app restarts. Never sent in the body.
     */
    val idempotencyKey: String? = null,
)

/** The gift part of a [GiftEffectEvent]. */
data class EffectGift(
    val id: String,
    val name: String,
    val price: Long,
    /** Large picture shown with the effect (512 px). Falls back to the icon. */
    val image: String?,
    /** Small picture for the notice (the 256 px icon). Falls back to [image]. */
    val icon: String? = null,
)

/** What an effect player needs to show a gift. */
data class GiftEffectEvent(
    val gift: EffectGift,
    /** Who sent it, shown in the notice. Default "Someone". */
    val sender: String? = null,
    /** How many were sent in this one send. Default 1. */
    val quantity: Int? = null,
    /**
     * Who got the gift, for a battle (SPEC 7.4): the notice then reads "sent Rose to Mia" and its
     * pill gets a border in the side's colour. Leave it out outside battles.
     */
    val receiver: GiftEffectReceiver? = null,
)

/** The receiving side of a battle gift (SPEC 7.4, 18.4). */
data class GiftEffectReceiver(
    /** Shown in the notice. */
    val name: String,
    /** 0 = first side, 1 = second side (the battle bar's order). Picks the default colour. */
    val side: Int? = null,
    /** The border colour as `#rgb`, `#rrggbb` or `rgba(r, g, b, a)`; null: the side's default (accent, coin). */
    val color: String? = null,
)

internal fun String?.json(): JsonElement = if (this == null) JsonNull else JsonPrimitive(this)

internal fun JsonObject.str(key: String): String = getValue(key).jsonPrimitive.content

internal fun JsonObject.strOrNull(key: String): String? {
    val v = this[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.content
}

internal fun JsonObject.int(key: String): Int = getValue(key).jsonPrimitive.int
