package com.giftingstack.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.floor

/** The spec version these constants and fixtures were written for (`recipes.json#specVersion`). */
const val SPEC_VERSION = "1.0.0"

/** The numbers a remote document may change. Caps, queue size and sender name are not here. */
data class RecipeSet(
    val thresholds: TierThresholds,
    val comboWindowMs: Long,
    val recipes: Map<EffectQuality, Map<EffectTier, EffectRecipe>>,
)

/** A parsed remote document: a full set (missing or bad fields already hold the embedded value). */
data class RemoteRecipeSet(
    /** The document's own `specVersion` (same major as the SDK). */
    val specVersion: String,
    val set: RecipeSet,
)

/** The values built into the SDK (`recipes.json`). */
fun embeddedRecipeSet(): RecipeSet =
    RecipeSet(
        thresholds = DEFAULT_THRESHOLDS,
        comboWindowMs = DEFAULT_COMBO_WINDOW_MS,
        recipes = EffectQuality.entries.associateWith { allRecipes(it) },
    )

/** Allowed range of a number a remote document may set (spec 13.3). Clamped, then rounded if [integer]. */
data class RemoteLimit(val min: Double, val max: Double, val integer: Boolean)

val REMOTE_RECIPE_LIMITS: Map<String, RemoteLimit> =
    mapOf(
        "peakScale" to RemoteLimit(0.5, 4.0, false),
        "flyInMs" to RemoteLimit(0.0, 10_000.0, true),
        "holdMs" to RemoteLimit(0.0, 10_000.0, true),
        "flyOutMs" to RemoteLimit(0.0, 10_000.0, true),
        "sparks" to RemoteLimit(0.0, 120.0, true),
        "sparkSpread" to RemoteLimit(0.0, 400.0, true),
        "coins" to RemoteLimit(0.0, 120.0, true),
        "noticeMs" to RemoteLimit(500.0, 8_000.0, true),
        "mediumFrom" to RemoteLimit(1.0, 1_000_000.0, true),
        "largeFrom" to RemoteLimit(2.0, 10_000_000.0, true),
        "comboWindowMs" to RemoteLimit(500.0, 10_000.0, true),
    )

/** A finite JSON number as a double; strings, booleans, null, arrays, objects give null. */
private fun JsonElement?.finiteNumber(): Double? {
    if (this !is JsonPrimitive || this is JsonNull || isString) return null
    val d = content.toDoubleOrNull() ?: return null
    return if (d.isFinite()) d else null
}

private fun JsonElement?.booleanValue(): Boolean? =
    if (this is JsonPrimitive && this !is JsonNull && !isString) {
        when (content) {
            "true" -> true
            "false" -> false
            else -> null
        }
    } else {
        null
    }

private fun JsonElement?.asObject(): JsonObject? = this as? JsonObject

/** A finite number, clamped and (for integer fields) rounded half up; otherwise the fallback. */
private fun clampField(key: String, value: JsonElement?, fallback: Double): Double {
    val v = value.finiteNumber() ?: return fallback
    val lim = REMOTE_RECIPE_LIMITS.getValue(key)
    val clamped = minOf(lim.max, maxOf(lim.min, v))
    // Every range is >= 0, so floor(x + 0.5) is "half up".
    return if (lim.integer) floor(clamped + 0.5) else clamped
}

private fun parseRecipe(tier: EffectTier, raw: JsonElement?, base: EffectRecipe): EffectRecipe {
    val o = raw.asObject() ?: return base.copy(tier = tier)
    return base.copy(
        tier = tier,
        peakScale = clampField("peakScale", o["peakScale"], base.peakScale),
        flyInMs = clampField("flyInMs", o["flyInMs"], base.flyInMs.toDouble()).toInt(),
        holdMs = clampField("holdMs", o["holdMs"], base.holdMs.toDouble()).toInt(),
        flyOutMs = clampField("flyOutMs", o["flyOutMs"], base.flyOutMs.toDouble()).toInt(),
        stage = (o["stage"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.let { w -> EffectStage.entries.firstOrNull { it.wire == w } } ?: base.stage,
        sparks = clampField("sparks", o["sparks"], base.sparks.toDouble()).toInt(),
        sparkSpread = clampField("sparkSpread", o["sparkSpread"], base.sparkSpread.toDouble()).toInt(),
        coins = clampField("coins", o["coins"], base.coins.toDouble()).toInt(),
        dim = o["dim"].booleanValue() ?: base.dim,
        rays = o["rays"].booleanValue() ?: base.rays,
        noticeMs = clampField("noticeMs", o["noticeMs"], base.noticeMs.toDouble()).toInt(),
        noticeBig = o["noticeBig"].booleanValue() ?: base.noticeBig,
    )
}

private fun parseThresholds(raw: JsonElement?, base: TierThresholds): TierThresholds {
    val o = raw.asObject() ?: return base
    val medium = clampField("mediumFrom", o["mediumFrom"], base.mediumFrom.toDouble()).toInt()
    val large = clampField("largeFrom", o["largeFrom"], base.largeFrom.toDouble()).toInt()
    // The pair must stay ordered; otherwise neither value is used.
    return if (large > medium) TierThresholds(medium, large) else base
}

private val VERSION = Regex("^(\\d+)\\.(\\d+)\\.(\\d+)$")

/** The major part of a `x.y.z` version, or null when the value is not such a string. */
private fun major(version: JsonElement?): String? {
    if (version !is JsonPrimitive || version is JsonNull || !version.isString) return null
    return VERSION.matchEntire(version.content)?.groupValues?.get(1)?.trimStart('0')?.ifEmpty { "0" }
}

/**
 * Reads a remote recipes document (already JSON-decoded). Returns null when the whole document
 * must be ignored: not an object, or a `specVersion` that is not `x.y.z` or whose major differs
 * from the SDK's. A single field of the wrong type keeps the embedded value for THAT field;
 * numbers out of range are clamped ([REMOTE_RECIPE_LIMITS]). Caps, queue size, sender name,
 * stage kinds and unknown keys are never taken from the document.
 */
fun parseRemoteRecipes(json: JsonElement?, embedded: RecipeSet = embeddedRecipeSet()): RemoteRecipeSet? {
    val doc = json as? JsonObject ?: return null
    val docMajor = major(doc["specVersion"]) ?: return null
    if (docMajor != major(JsonPrimitive(SPEC_VERSION))) return null
    val rawRecipes = doc["recipes"].asObject()
    val recipes =
        EffectQuality.entries.associateWith { q ->
            val rawQ = rawRecipes?.get(q.wire).asObject()
            EffectTier.entries.associateWith { t -> parseRecipe(t, rawQ?.get(t.wire), embedded.recipes.getValue(q).getValue(t)) }
        }
    return RemoteRecipeSet(
        specVersion = (doc["specVersion"] as JsonPrimitive).content,
        set =
            RecipeSet(
                thresholds = parseThresholds(doc["thresholds"], embedded.thresholds),
                comboWindowMs = clampField("comboWindowMs", doc["comboWindowMs"], embedded.comboWindowMs.toDouble()).toLong(),
                recipes = recipes,
            ),
    )
}

/** Thresholds the app gave itself; null fields are not given. */
data class PartialThresholds(val mediumFrom: Int? = null, val largeFrom: Int? = null)

/** What the app itself passed. Not clamped: the app owns its own numbers. */
data class AppRecipeOverrides(val thresholds: PartialThresholds? = null, val comboWindowMs: Long? = null)

/**
 * The set effects use. Merge order (spec 13.4): embedded < remote < app. [remote] is a parsed
 * set (it already holds embedded values where the document had none) or null.
 */
fun mergeRecipeSet(embedded: RecipeSet, remote: RecipeSet?, app: AppRecipeOverrides = AppRecipeOverrides()): RecipeSet {
    val base = remote ?: embedded
    return RecipeSet(
        thresholds =
            TierThresholds(
                mediumFrom = app.thresholds?.mediumFrom ?: base.thresholds.mediumFrom,
                largeFrom = app.thresholds?.largeFrom ?: base.thresholds.largeFrom,
            ),
        comboWindowMs = app.comboWindowMs ?: base.comboWindowMs,
        recipes = base.recipes,
    )
}

/** Default address of the hosted document. Hosting it is a separate deploy step (spec 13). */
const val DEFAULT_RECIPES_URL = "https://assets.giftingstack.com/recipes.json"

private val VERSION_ALPHABET = Regex("^[A-Za-z0-9._-]{1,64}$")

/**
 * The address to fetch. [version] pins a document: the last `.json` of the URL becomes
 * `.<version>.json`. Null (no network) when the version is not 1-64 characters of
 * `A-Z a-z 0-9 . _ -` or the URL has no `.json` to pin.
 */
fun remoteRecipesUrl(url: String? = null, version: String? = null): String? {
    val base = url ?: DEFAULT_RECIPES_URL
    if (version == null) return base
    if (!VERSION_ALPHABET.matches(version)) return null
    val at = base.lastIndexOf(".json")
    if (at < 0) return null
    return base.substring(0, at) + "." + version + base.substring(at)
}

/** A [RecipeSet] as JSON in the shape of `recipes.json` (used by tests and the cache). */
fun RecipeSet.toJson(): JsonObject =
    JsonObject(
        mapOf(
            "thresholds" to JsonObject(mapOf("mediumFrom" to JsonPrimitive(thresholds.mediumFrom), "largeFrom" to JsonPrimitive(thresholds.largeFrom))),
            "comboWindowMs" to JsonPrimitive(comboWindowMs),
            "recipes" to
                JsonObject(
                    recipes.entries.associate { (q, tiers) ->
                        q.wire to JsonObject(tiers.entries.associate { (t, r) -> t.wire to recipeToJson(r) })
                    },
                ),
        ),
    )

private fun recipeToJson(r: EffectRecipe): JsonObject =
    JsonObject(
        mapOf(
            "tier" to JsonPrimitive(r.tier.wire),
            "peakScale" to JsonPrimitive(r.peakScale),
            "flyInMs" to JsonPrimitive(r.flyInMs),
            "holdMs" to JsonPrimitive(r.holdMs),
            "flyOutMs" to JsonPrimitive(r.flyOutMs),
            "stage" to JsonPrimitive(r.stage.wire),
            "sparks" to JsonPrimitive(r.sparks),
            "sparkSpread" to JsonPrimitive(r.sparkSpread),
            "coins" to JsonPrimitive(r.coins),
            "dim" to JsonPrimitive(r.dim),
            "rays" to JsonPrimitive(r.rays),
            "noticeMs" to JsonPrimitive(r.noticeMs),
            "noticeBig" to JsonPrimitive(r.noticeBig),
        ),
    )
