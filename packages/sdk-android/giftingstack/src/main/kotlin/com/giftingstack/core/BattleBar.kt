package com.giftingstack.core

/**
 * What the battle bar (SPEC 18.7) shows, as plain data: the split, the clock, the winner, the
 * words and the two side colours. Pure, no Compose. Port of
 * `packages/sdk-js/src/core/battleBar.ts`; fixture `battle-bar.json`.
 */

/** Every word of the bar. `{name}`, `{a}`, `{b}` mark a place a value goes. */
data class BattleBarLabels(
    /** The small "VS" over the clock. */
    val vs: String = "VS",
    /** The clock when the round has ended. */
    val finalText: String = "Final",
    /** Below the bar when a side won. */
    val wins: String = "{name} wins the round",
    /** Below the bar when the round ended level. */
    val draw: String = "Draw: nobody wins this round",
    /** The spoken summary: `{a}, {b}`, each side [side]. */
    val spoken: String = "{a}, {b}",
    /** One side, spoken. */
    val side: String = "{name} {score}",
    /** Count suffixes, as in [formatCount]. */
    val thousand: String = "K",
    val million: String = "M",
)

private val PLACEHOLDER = Regex("""\{(\w+)\}""")

private fun fillText(template: String, values: Map<String, String>): String =
    PLACEHOLDER.replace(template) { m -> values[m.groupValues[1]] ?: m.value }

/** Seconds left on the clock at which it turns urgent. */
const val BATTLE_URGENT_SECONDS = 10

/** The boundary never leaves this band, so both sides stay visible (percent of the bar). */
const val BATTLE_MIN_SHARE_PCT = 6.0

/** A score for the bar: `9,999` in full, then `10K`, `1.2M`. */
fun formatBattleScore(n: Long, labels: BattleBarLabels = BattleBarLabels()): String =
    if (n >= 10_000) formatCount(n, CountLabels(thousand = labels.thousand, million = labels.million)) else groupThousands(maxOf(0L, n))

private fun ceilSeconds(ms: Long): Long = -Math.floorDiv(-ms, 1000L)

/** `m:ss`, rounded up like a countdown. */
fun formatBattleClock(remainingMs: Long): String {
    val secs = maxOf(0L, ceilSeconds(remainingMs))
    return "${secs / 60}:${(secs % 60).toString().padStart(2, '0')}"
}

/** One side of the bar. */
data class BattleBarSide(
    val id: String,
    /** The display name (the id when unknown). */
    val name: String,
    /** The full score. */
    val units: Long,
    /** The short form (`135K`). */
    val score: String,
    /** Spoken: `Mia 1,800`. */
    val spoken: String,
    /** This side leads while the round is open, or won it. */
    val leads: Boolean,
    /** The round ended and this side led. */
    val won: Boolean,
    /** The round ended and the other side led. */
    val lost: Boolean,
)

/** The bar for one [BattleView]. */
data class BattleBarModel(
    /** Every side, in the server's order: two or more (up to the API's 8). */
    val sides: List<BattleBarSide>,
    /** The first side's part of the bar, percent, kept inside the visible band (`pcts[0]`). */
    val pct: Double,
    /** Every side's part of the bar, percent, summing to 100; none under [BATTLE_MIN_SHARE_PCT] (see [battleSegmentPcts]). */
    val pcts: List<Double>,
    /** `m:ss`, or the `final` label once the round ended. */
    val clock: String,
    /** Under [BATTLE_URGENT_SECONDS] and still open. */
    val urgent: Boolean,
    /** The round has ended. */
    val isFinal: Boolean,
    /** The winning receiver once ended, else null (also null for a draw). */
    val winner: String?,
    /** The line under the bar once the round ended; empty before. */
    val banner: String,
    /** One sentence for a screen reader: both sides and their scores. */
    val spoken: String,
)

/**
 * Every side's part of a bar, percent (SPEC 18.7): `share x 100`, but no side under
 * [BATTLE_MIN_SHARE_PCT]: such a side is held at the minimum and the rest share what is left in
 * proportion to their shares, repeated until every part is visible. Sums to 100.
 */
fun battleSegmentPcts(shares: List<Double>): List<Double> {
    val n = shares.size
    val pinned = BooleanArray(n)
    val out = DoubleArray(n)
    while (true) {
        val free = (0 until n).filter { !pinned[it] }
        val left = 100.0 - BATTLE_MIN_SHARE_PCT * (n - free.size)
        val sum = free.sumOf { shares[it] }
        var again = false
        for (i in free) {
            out[i] = if (sum > 0) shares[i] / sum * left else left / free.size
            if (out[i] < BATTLE_MIN_SHARE_PCT) {
                pinned[i] = true
                again = true
            }
        }
        if (!again) break
        for (i in 0 until n) if (pinned[i]) out[i] = BATTLE_MIN_SHARE_PCT
    }
    for (i in 0 until n) if (pinned[i]) out[i] = BATTLE_MIN_SHARE_PCT
    return out.toList()
}

/**
 * The bar for [view], or null when it has fewer than two sides (a round with one receiver has
 * nothing to compare). Every side is a cell of the bar (a free-for-all of up to 8); two sides look
 * exactly as the versus always did.
 */
fun battleBarModel(
    view: BattleView?,
    nameOf: (String) -> String = { it },
    labels: BattleBarLabels = BattleBarLabels(),
): BattleBarModel? {
    if (view == null || view.sides.size < 2) return null
    val ended = !view.open

    fun side(s: BattleSide): BattleBarSide {
        val name = nameOf(s.id)
        return BattleBarSide(
            id = s.id,
            name = name,
            units = s.units,
            score = formatBattleScore(s.units, labels),
            spoken = fillText(labels.side, mapOf("name" to name, "score" to groupThousands(s.units))),
            leads = view.leader == s.id,
            won = ended && view.leader == s.id,
            lost = ended && view.leader != null && view.leader != s.id,
        )
    }
    val sides = view.sides.map(::side)
    val secs = ceilSeconds(view.remainingMs)
    val winner = if (ended) view.leader else null
    val pct = minOf(100 - BATTLE_MIN_SHARE_PCT, maxOf(BATTLE_MIN_SHARE_PCT, view.sides[0].share * 100))
    val pcts = if (sides.size == 2) listOf(pct, 100 - pct) else battleSegmentPcts(view.sides.map { it.share })
    return BattleBarModel(
        sides = sides,
        pct = if (sides.size == 2) pct else pcts[0],
        pcts = pcts,
        clock = if (ended) labels.finalText else formatBattleClock(view.remainingMs),
        urgent = !ended && secs <= BATTLE_URGENT_SECONDS,
        isFinal = ended,
        winner = winner,
        banner =
            when {
                !ended -> ""
                winner != null -> fillText(labels.wins, mapOf("name" to (sides.firstOrNull { it.id == winner }?.name ?: winner)))
                else -> labels.draw
            },
        // Two sides: the `spoken` label (`{a}, {b}`); more: every side's text joined by ", ".
        spoken =
            if (sides.size == 2) {
                fillText(labels.spoken, mapOf("a" to sides[0].spoken, "b" to sides[1].spoken))
            } else {
                sides.joinToString(", ") { it.spoken }
            },
    )
}

/** A colour and the text colour that reads on it, as `#rrggbb` strings (the colour is as given). */
data class SideColor(val color: String, val text: String)

/** White or black, whichever contrasts more with [hex]; an unreadable colour string counts as white. */
fun battleReadableOn(hex: String): String =
    if (parseHex(hex) == null || contrastRatio("#ffffff", hex) >= contrastRatio("#000000", hex)) "#ffffff" else "#000000"

/** The third and fourth side colour of the default palette (teal, pink); the fifth side starts over with the theme's accent. */
val BATTLE_EXTRA_COLORS = listOf("#2ec4b6", "#ff5d8f")

/**
 * The colour of every side of a bar or notice (SPEC 18.7, 7.4): side `i` takes `override[i]` when the app gave one
 * (text picked by contrast), else the default palette: the theme's accent, its coin colour (each with the theme's
 * own text colour on it, already 4.5:1 in both presets), then [BATTLE_EXTRA_COLORS], then the same four again.
 */
fun battleSidePalette(theme: GiftThemeTokens, count: Int, override: List<String>? = null): List<SideColor> {
    val defaults =
        listOf(SideColor(theme.accent, theme.accentText), SideColor(theme.coin, theme.coinText)) +
            BATTLE_EXTRA_COLORS.map { SideColor(it, battleReadableOn(it)) }
    return List(count) { i ->
        val own = override?.getOrNull(i)?.takeIf { it.isNotEmpty() }
        if (own != null) SideColor(own, battleReadableOn(own)) else defaults[i % defaults.size]
    }
}

/**
 * The two side colours: the theme's accent against its coin colour (each with the theme's own text colour on it,
 * already 4.5:1 in both presets), or [override] (text picked by contrast). [battleSidePalette] for any number of sides.
 */
fun battleSideColors(theme: GiftThemeTokens, override: List<String>? = null): List<SideColor> = battleSidePalette(theme, 2, override)

/** Which sides gained score since [before] (to pulse them). [before] null: nobody pulses. */
fun battleGains(before: List<Long>?, after: List<Long>): List<Boolean> =
    after.mapIndexed { i, u -> before != null && u > (before.getOrNull(i) ?: u) }
