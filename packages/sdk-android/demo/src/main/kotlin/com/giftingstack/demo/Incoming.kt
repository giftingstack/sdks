package com.giftingstack.demo

import com.giftingstack.core.EffectTier
import com.giftingstack.core.Gift
import com.giftingstack.core.tierFor
import kotlin.random.Random

/**
 * Gifts from other people. The demo does NOT let them arrive by themselves (a gift that comes
 * unasked confuses a test); the developer menu plays them. Set this to true to see the app as a
 * live feed, with a gift from someone else every 20-40 s. Not part of the SDK.
 */
internal const val LIVE_FEED = false

enum class Tier { Small, Medium, Large }

internal const val MIN_DELAY_MS = 20_000L
internal const val MAX_DELAY_MS = 40_000L

/** The effect layer's own rule (the SDK's `tierFor`, default limits: medium from 100, large from 10,000). */
fun tierOf(price: Long): Tier =
    when (tierFor(price)) {
        EffectTier.Large -> Tier.Large
        EffectTier.Medium -> Tier.Medium
        EffectTier.Small -> Tier.Small
    }

/** 78 % small, 19 % medium, 3 % large. [r] is in 0..1. */
fun rollTier(r: Double): Tier =
    when {
        r < 0.78 -> Tier.Small
        r < 0.97 -> Tier.Medium
        else -> Tier.Large
    }

fun nextDelayMs(rand: Random): Long = MIN_DELAY_MS + rand.nextLong(MAX_DELAY_MS - MIN_DELAY_MS)

class Incoming(val gift: Gift, val sender: String, val quantity: Int) {
    val tier: Tier get() = tierOf(gift.price)
}

/** A random gift from a random sender; an empty tier falls back to the nearest one that has gifts. */
fun pickIncoming(gifts: List<Gift>, senders: List<String>, rand: Random): Incoming? {
    if (gifts.isEmpty() || senders.isEmpty()) return null
    val order = Tier.entries
    val want = rollTier(rand.nextDouble())
    val tier =
        order.sortedBy { Math.abs(it.ordinal - want.ordinal) }.firstOrNull { t -> gifts.any { tierOf(it.price) == t } } ?: want
    val pool = gifts.filter { tierOf(it.price) == tier }.ifEmpty { gifts }
    val gift = pool[rand.nextInt(pool.size)]
    val sender = senders[rand.nextInt(senders.size)]
    val quantity =
        when (tier) {
            Tier.Small -> 1 + rand.nextInt(3)
            Tier.Medium -> 1 + rand.nextInt(2)
            Tier.Large -> 1
        }
    return Incoming(gift, sender, quantity)
}

/** The gift the developer menu plays for [mode]; [selected] is the tray's selected gift. Null when there are no gifts. */
fun giftFor(mode: IncomingMode, gifts: List<Gift>, selected: Gift?, rand: Random): Gift? =
    when (mode) {
        IncomingMode.SameAsTray -> selected ?: gifts.firstOrNull()
        IncomingMode.Random -> gifts.takeIf { it.isNotEmpty() }?.let { it[rand.nextInt(it.size)] }
        IncomingMode.Cheapest -> gifts.minByOrNull { it.price }
        IncomingMode.Priciest -> gifts.maxByOrNull { it.price }
    }
