package com.giftingstack.core

/**
 * Every visible and spoken word of the gift wall, the "while you were away" card and the
 * leaderboard (same keys and English defaults as `packages/sdk-js/src/web/labels.ts`). Pass a copy
 * with the ones you translate. `{x}` marks a place a value goes. Pure strings, no Compose.
 */
data class GiftLabels(
    /** Count suffixes of [formatCount]. */
    val thousand: String = "K",
    val million: String = "M",
    /** A deleted sender. */
    val someone: String = "Someone",
    /** Wall: the row as one element. `{list}` = `"12 Roses, 3 Hearts"`, then [wallMore]. */
    val wallSummary: String = "Gifts: {list}",
    /** Wall: the end of `{list}` when more gifts exist. */
    val wallMore: String = "and {n} more",
    /** Wall: a tappable chip, for example `"Rose, 12"`. */
    val wallChip: String = "{name}, {count}",
    /** Wall: added to a gift name when its count is above 1 (`"12 Roses"`). */
    val plural: String = "s",
    /** Wall: text under the chips when nothing was received. Default none (the wall is empty). */
    val emptyText: String = "",
    val awayTitle: String = "While you were away",
    /** `{gifts}` and `{people}` are [giftOne]/[giftOther] and [personOne]/[personOther]. */
    val awaySummary: String = "{gifts} from {people}",
    val awayAnnounce: String = "You received {summary} while you were away",
    val giftOne: String = "{n} gift",
    val giftOther: String = "{n} gifts",
    val personOne: String = "{n} person",
    val personOther: String = "{n} people",
    val dismiss: String = "Dismiss",
    val tabs: Map<LeaderboardPeriod, String> = DEFAULT_TABS,
    val empty: Map<LeaderboardPeriod, String> = DEFAULT_EMPTY,
    /** Metric switch. [metricUnits] empty = the capitalised coin name. */
    val metricUnits: String = "",
    val metricGifts: String = "Gifts",
    val metricSwitch: String = "Ranked by",
    val giftsWord: String = "gifts",
    val error: String = "Could not load the leaderboard.",
    val tryAgain: String = "Try again",
    /** `{rank}` is `"#417"` or [rankOverflow]. */
    val pinned: String = "You: {rank}",
    val pinnedSpoken: String = "Your rank: {rank}, {score}",
    val rowSpoken: String = "Rank {rank}, {name}, {score}",
    val rankOverflow: String = "1,000+",
    val loading: String = "Loading",
    val updating: String = "Updating",
) {
    /** The count suffixes as [CountLabels]. */
    val count: CountLabels get() = CountLabels(thousand, million)

    /** The sender words as [AwaySenderLabels]. */
    val sender: AwaySenderLabels get() = AwaySenderLabels(someone = someone)

    companion object {
        val DEFAULT_TABS: Map<LeaderboardPeriod, String> =
            mapOf(
                LeaderboardPeriod.Day to "Today",
                LeaderboardPeriod.Week to "This week",
                LeaderboardPeriod.Month to "This month",
                LeaderboardPeriod.All to "All time",
            )
        val DEFAULT_EMPTY: Map<LeaderboardPeriod, String> =
            mapOf(
                LeaderboardPeriod.Day to "No gifts yet today",
                LeaderboardPeriod.Week to "No gifts yet this week",
                LeaderboardPeriod.Month to "No gifts yet this month",
                LeaderboardPeriod.All to "No gifts yet",
            )
    }
}

private val PLACEHOLDER = Regex("""\{(\w+)\}""")

/** `fill("Rank {rank}", "rank" to 1)`. A `{x}` without a value stays as written. */
fun fill(template: String, vararg values: Pair<String, Any>): String {
    val map = values.toMap()
    return PLACEHOLDER.replace(template) { m -> map[m.groupValues[1]]?.toString() ?: m.value }
}

/** `1234567` -> `"1,234,567"`: whole numbers with a separator every three digits. */
fun groupThousands(n: Long, separator: String = ","): String {
    val digits = (if (n < 0) -n else n).toString() // Long.MIN_VALUE is not a count
    val sb = StringBuilder()
    digits.forEachIndexed { i, c ->
        if (i > 0 && (digits.length - i) % 3 == 0) sb.append(separator)
        sb.append(c)
    }
    return (if (n < 0) "-" else "") + sb
}

fun groupThousands(n: Int, separator: String = ","): String = groupThousands(n.toLong(), separator)

/** The first letter of a name, as the avatars show it (`"?"` for an empty name). */
fun initialOf(name: String): String {
    val t = name.trim()
    if (t.isEmpty()) return "?"
    return String(Character.toChars(t.codePointAt(0))).uppercase()
}

// ---------------------------------------------------------------- wall texts

/** `"Gifts: 12 Roses, 3 Hearts, and 37 more"`: what a screen reader says for the whole wall. */
fun wallSummaryText(chips: List<WallChip>, labels: GiftLabels = GiftLabels()): String {
    val list =
        chips.filterIsInstance<WallChip.Gift>()
            .map { "${groupThousands(it.count)} ${if (it.count > 1) it.gift.name + labels.plural else it.gift.name}" }
            .toMutableList()
    chips.filterIsInstance<WallChip.Overflow>().firstOrNull()?.let {
        list.add(fill(labels.wallMore, "n" to groupThousands(it.count)))
    }
    return fill(labels.wallSummary, "list" to list.joinToString(", "))
}

/** `"Rose, 12"`: a tappable chip. */
fun wallChipLabel(chip: WallChip.Gift, labels: GiftLabels = GiftLabels()): String =
    fill(labels.wallChip, "name" to chip.gift.name, "count" to groupThousands(chip.count))

/** `"+37"`, `"12"`: the text on a chip. */
fun wallChipText(chip: WallChip, labels: GiftLabels = GiftLabels()): String =
    when (chip) {
        is WallChip.Gift -> formatCount(chip.count, labels.count)
        is WallChip.Overflow -> "+" + formatCount(chip.count, labels.count)
    }

// ---------------------------------------------------------------- away texts

/** The card's line (`"37 gifts from 12 people"`) and the live-region announcement. */
data class AwayTexts(val line: String, val announce: String, val gifts: String = "", val people: String = "")

fun awayTexts(summary: AwaySummary, labels: GiftLabels = GiftLabels()): AwayTexts {
    val gifts = if (summary.truncated) "2,000+" else groupThousands(summary.totalGifts)
    val giftsText = fill(if (summary.totalGifts == 1L) labels.giftOne else labels.giftOther, "n" to gifts)
    val peopleText =
        fill(if (summary.senderCount == 1) labels.personOne else labels.personOther, "n" to groupThousands(summary.senderCount))
    val line = fill(labels.awaySummary, "gifts" to giftsText, "people" to peopleText)
    return AwayTexts(line, fill(labels.awayAnnounce, "summary" to line), giftsText, peopleText)
}

/** `"ayla, 15 gifts"`: a top sender, spoken. */
fun awaySenderSpoken(name: String, count: Int, labels: GiftLabels = GiftLabels()): String =
    "$name, ${fill(if (count == 1) labels.giftOne else labels.giftOther, "n" to groupThousands(count))}"

/** `"Dragon, 1"`: a gift group, spoken. */
fun awayGroupSpoken(group: AwayGroup): String = "${group.gift.name}, ${groupThousands(group.count)}"

// ---------------------------------------------------------------- leaderboard texts

/**
 * The score of a row: `formatCount` (units) or a plain number (gifts), or, [spoken], the exact
 * number with the unit word (`"54,000 coins"`, `"120 gifts"`).
 */
fun leaderboardScore(
    metric: LeaderboardMetric,
    gifts: Long,
    units: Long,
    labels: GiftLabels,
    coinName: String,
    spoken: Boolean,
): String =
    when (metric) {
        LeaderboardMetric.Units -> if (spoken) "${groupThousands(units)} $coinName" else formatCount(units, labels.count)
        LeaderboardMetric.Gifts -> if (spoken) "${groupThousands(gifts)} ${labels.giftsWord}" else groupThousands(gifts)
    }

/** `"Rank 1, ayla, 54,000 coins"`. */
fun leaderboardRowSpoken(entry: LeaderboardEntry, name: String, metric: LeaderboardMetric, labels: GiftLabels, coinName: String): String =
    fill(
        labels.rowSpoken,
        "rank" to entry.rank,
        "name" to name,
        "score" to leaderboardScore(metric, entry.gifts, entry.units, labels, coinName, spoken = true),
    )

/** `"You: #417"` / `"You: 1,000+"`. */
fun leaderboardPinnedText(me: LeaderboardMe, labels: GiftLabels): String =
    fill(labels.pinned, "rank" to leaderboardRankLabel(me.rank, labels.rankOverflow))

/** `"Your rank: 417, 120 coins"`. */
fun leaderboardPinnedSpoken(me: LeaderboardMe, metric: LeaderboardMetric, labels: GiftLabels, coinName: String): String =
    fill(
        labels.pinnedSpoken,
        "rank" to (me.rank?.let { groupThousands(it) } ?: labels.rankOverflow),
        "score" to leaderboardScore(metric, me.gifts, me.units, labels, coinName, spoken = true),
    )

/** The label of the coins tab: [GiftLabels.metricUnits], else the capitalised coin name. */
fun leaderboardUnitsName(labels: GiftLabels, coinName: String): String =
    labels.metricUnits.ifEmpty { coinName.replaceFirstChar { it.uppercase() } }
