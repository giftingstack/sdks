package com.giftingstack.demo

import com.giftingstack.core.Gift
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The live gift library (the same file the web and React Native demos read). */
const val LIBRARY_URL = "https://assets.giftingstack.com/library.json"

/** Twelve chosen gifts, as in `packages/sdk-js/demo/shared.ts`. */
val PICK =
    listOf(
        "pink-tulip", "heart-latte", "bear-boba", "cool-star", "magic-hat", "rainbow-gem",
        "treasure-chest", "golden-griffin", "phoenix", "sun-dragon", "heart-turkey", "star-whale",
    )

/** How many more gifts are spread from cheap to grand after [PICK] (about ninety in all). */
const val SPREAD_COUNT = 78

private class LibraryGift(val id: String, val name: String, val price: Int)

/**
 * The demo catalog from the library JSON: the twelve [PICK]ed gifts, then [SPREAD_COUNT] others
 * spread from cheap to grand, so the expanded sheet has plenty to scroll. The 108 country hearts
 * share one price: keep one of them (`heart-turkey`). Same selection as `loadGifts` in
 * `packages/sdk-js/demo/shared.ts`. Throws when the text is not a library.
 */
fun pickCatalog(libraryJson: String): List<Gift> {
    val root = Json.parseToJsonElement(libraryJson).jsonObject
    val all =
        root.getValue("gifts").jsonArray.map {
            val o: JsonObject = it.jsonObject
            LibraryGift(o.getValue("id").jsonPrimitive.content, o.getValue("name").jsonPrimitive.content, o.getValue("suggested_price").jsonPrimitive.int)
        }
    val others =
        all.filter { it.id !in PICK && (!it.id.startsWith("heart-") || it.id == "heart-turkey") }
            .sortedBy { it.price }
    val want = SPREAD_COUNT
    val step = others.size.toDouble() / want
    val more = List(minOf(want, others.size)) { i -> others[Math.floor(i * step).toInt()].id }
    return (PICK + more).mapIndexedNotNull { i, id ->
        val g = all.firstOrNull { it.id == id } ?: return@mapIndexedNotNull null
        Gift(id, g.name, null, g.price.toLong(), iconUrl(id), artUrl(id), i)
    }
}

/** Downloads the library and picks the catalog. Throws on any failure (the caller falls back). */
suspend fun fetchCatalog(url: String = LIBRARY_URL): List<Gift> =
    withContext(Dispatchers.IO) {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 5_000
            c.readTimeout = 8_000
            if (c.responseCode !in 200..299) throw java.io.IOException("library: http ${c.responseCode}")
            pickCatalog(c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) })
        } finally {
            c.disconnect()
        }
    }

/** The live catalog, or the small built-in list when the library cannot be loaded. */
suspend fun loadGifts(fetch: suspend () -> List<Gift> = { fetchCatalog() }): List<Gift> =
    try {
        fetch().takeIf { it.isNotEmpty() } ?: demoGifts
    } catch (e: kotlin.coroutines.cancellation.CancellationException) {
        throw e
    } catch (_: Exception) {
        demoGifts
    }
