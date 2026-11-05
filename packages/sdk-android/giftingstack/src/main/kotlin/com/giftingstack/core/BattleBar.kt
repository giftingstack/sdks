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
    val sides: List<BattleBarSide>,
    /** The first side's part of the bar, percent, kept inside the visible band. */
    val pct: Double,
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
 * The bar for [view], or null when it has fewer than two sides (a round with one receiver has
 * nothing to compare). Extra sides beyond two are ignored: the bar is a versus.
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
    val a = side(view.sides[0])
    val b = side(view.sides[1])
    val secs = ceilSeconds(view.remainingMs)
    val winner = if (ended) view.leader else null
    return BattleBarModel(
        sides = listOf(a, b),
        pct = minOf(100 - BATTLE_MIN_SHARE_PCT, maxOf(BATTLE_MIN_SHARE_PCT, view.sides[0].share * 100)),
        clock = if (ended) labels.finalText else formatBattleClock(view.remainingMs),
        urgent = !ended && secs <= BATTLE_URGENT_SECONDS,
        isFinal = ended,
        winner = winner,
        banner =
            when {
                !ended -> ""
                winner != null -> fillText(labels.wins, mapOf("name" to if (winner == a.id) a.name else b.name))
                else -> labels.draw
            },
        spoken = fillText(labels.spoken, mapOf("a" to a.spoken, "b" to b.spoken)),
    )
}

/** A colour and the text colour that reads on it, as `#rrggbb` strings (the colour is as given). */
data class SideColor(val color: String, val text: String)

/** White or black, whichever contrasts more with [hex]; an unreadable colour string counts as white. */
fun battleReadableOn(hex: String): String =
    if (parseHex(hex) == null || contrastRatio("#ffffff", hex) >= contrastRatio("#000000", hex)) "#ffffff" else "#000000"

/**
 * The two side colours: the theme's accent against its coin colour (each with the theme's own text
 * colour on it, already 4.5:1 in both presets), or [override] (text picked by contrast).
 */
fun battleSideColors(theme: GiftThemeTokens, override: Pair<String, String>? = null): List<SideColor> =
    if (override != null) {
        listOf(SideColor(override.first, battleReadableOn(override.first)), SideColor(override.second, battleReadableOn(override.second)))
    } else {
        listOf(SideColor(theme.accent, theme.accentText), SideColor(theme.coin, theme.coinText))
    }

/** Which sides gained score since [before] (to pulse them). [before] null: nobody pulses. */
fun battleGains(before: List<Long>?, after: List<Long>): List<Boolean> =
    after.mapIndexed { i, u -> before != null && u > (before.getOrNull(i) ?: u) }
