package com.giftingstack.core

import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.min
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/** Fetch timeout for the whole response, in ms (spec 13.5). */
const val RECIPES_FETCH_TIMEOUT_MS = 3_000L

/** A successful fetch is reused this long before the next one, in ms. */
const val RECIPES_REFRESH_MS = 6L * 60 * 60 * 1000

/** First wait after a failure; doubles per failure, capped at [RECIPES_REFRESH_MS]. */
const val RECIPES_BACKOFF_MS = 60_000L

private const val STORAGE_PREFIX = "giftingstack:recipes:"

/** A small key-value store for the cached document. Throwing is allowed: the loader copes. */
interface RecipesStorage {
    fun get(key: String): String?

    fun set(key: String, value: String)
}

/** The default store: memory only, gone with the process. Plug in your own for a disk cache. */
class MemoryRecipesStorage : RecipesStorage {
    private val map = HashMap<String, String>()

    @Synchronized override fun get(key: String): String? = map[key]

    @Synchronized override fun set(key: String, value: String) {
        map[key] = value
    }
}

/** Returns the response body of a GET. Throws when there is no answer or the status is not 2xx. */
fun interface RecipesFetch {
    suspend fun fetch(url: String): String
}

/** `HttpURLConnection` with the 3 s limits; no credentials, no cookies. */
val DefaultRecipesFetch =
    RecipesFetch { url ->
        withContext(Dispatchers.IO) {
            val c = URL(url).openConnection() as HttpURLConnection
            try {
                c.connectTimeout = RECIPES_FETCH_TIMEOUT_MS.toInt()
                c.readTimeout = RECIPES_FETCH_TIMEOUT_MS.toInt()
                c.instanceFollowRedirects = true
                c.setRequestProperty("Accept", "application/json")
                if (c.responseCode !in 200..299) throw java.io.IOException("recipes: http ${c.responseCode}")
                c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            } finally {
                c.disconnect()
            }
        }
    }

/**
 * Fetches and caches the remote recipes document (spec 13.5). The cached copy is used at once; a
 * refresh runs in the background when none exists or it is 6 hours old. Nothing here throws to
 * the app or delays an effect: on any failure the cached or embedded numbers stay.
 *
 * Port of `packages/sdk-js/src/web/recipes-loader.ts`. [fetch] and [storage] are injectable;
 * a null [fetch] means no network, a null [storage] memory only.
 */
class RecipesLoader(
    private val url: String,
    private val fetch: RecipesFetch? = DefaultRecipesFetch,
    private val storage: RecipesStorage? = MemoryRecipesStorage(),
    private val now: () -> Long = System::currentTimeMillis,
    private val timeoutMs: Long = RECIPES_FETCH_TIMEOUT_MS,
) {
    private val lock = Any()
    private val key = STORAGE_PREFIX + url
    private var loaded = false
    private var value: RemoteRecipeSet? = null
    private var fetchedAt: Long? = null
    private var failures = 0
    private var backoffUntil = 0L
    private var inflight: CompletableDeferred<Unit>? = null

    /** The best document known right now (cached or fetched), or null: use the embedded set. */
    fun current(): RemoteRecipeSet? {
        load()
        return synchronized(lock) { value }
    }

    /** Reads the cache once. The document is parsed again, so new limits apply to old copies. */
    private fun load() {
        synchronized(lock) {
            if (loaded) return
            loaded = true
        }
        try {
            val raw = storage?.get(key) ?: return
            val entry = Json.parseToJsonElement(raw) as? JsonObject ?: return
            val at = (entry["fetchedAt"] as? JsonPrimitive)?.longOrNull ?: return
            val parsed = parseRemoteRecipes(entry["doc"]) ?: return
            synchronized(lock) {
                value = parsed
                fetchedAt = at
            }
        } catch (_: Exception) {
            // A broken or unreadable cache entry is the same as none.
        }
    }

    private fun due(t: Long): Boolean {
        if (t < backoffUntil) return false
        val at = fetchedAt ?: return true
        // A clock that went back counts as due, so a wrong clock cannot pin an old copy forever.
        return t < at || t - at >= RECIPES_REFRESH_MS
    }

    /**
     * Fetches a fresh document when one is due and no attempt is backing off. Concurrent callers
     * share one request. Never throws (except cancellation).
     */
    suspend fun refresh() {
        load()
        var owner = false
        val shared =
            synchronized(lock) {
                inflight ?: CompletableDeferred<Unit>().also {
                    inflight = it
                    owner = true
                }
            }
        if (!owner) {
            shared.await()
            return
        }
        try {
            val f = fetch
            if (f != null && synchronized(lock) { due(now()) }) attempt(f)
        } finally {
            synchronized(lock) { inflight = null }
            shared.complete(Unit)
        }
    }

    private suspend fun attempt(f: RecipesFetch) {
        try {
            val text = withTimeoutOrNull(timeoutMs) { f.fetch(url) } ?: throw java.io.IOException("recipes: timeout")
            val doc = Json.parseToJsonElement(text)
            val parsed = parseRemoteRecipes(doc) ?: throw IllegalStateException("recipes: unusable document")
            val t = now()
            synchronized(lock) {
                value = parsed
                fetchedAt = t
                failures = 0
                backoffUntil = 0
            }
            try {
                storage?.set(key, JsonObject(mapOf("fetchedAt" to JsonPrimitive(t), "doc" to doc)).toString())
            } catch (_: Exception) {
                // Full or blocked storage: keep the copy in memory only.
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            synchronized(lock) {
                failures++
                // 60 s * 2^(n-1), capped at 6 h (the exponent is capped too, so it cannot overflow).
                val factor = 1L shl min(failures - 1, 20)
                backoffUntil = now() + min(RECIPES_REFRESH_MS, RECIPES_BACKOFF_MS * factor)
            }
        }
    }
}

/** One loader per URL per process, shared by every layer (one request at a time). */
object RecipesLoaders {
    /** Where new shared loaders cache. Default memory; set it (before the first layer) to persist. */
    @Volatile var storage: RecipesStorage? = null

    /** How new shared loaders fetch. Default `HttpURLConnection`. Null = no network. */
    @Volatile var fetch: RecipesFetch? = DefaultRecipesFetch

    private val loaders = HashMap<String, RecipesLoader>()

    fun shared(url: String): RecipesLoader =
        synchronized(loaders) { loaders.getOrPut(url) { RecipesLoader(url, fetch, storage ?: MemoryRecipesStorage()) } }

    /**
     * The shared loader for a layer, or null when remote recipes are off (`remoteRecipes = false`,
     * or a version that cannot be pinned): no request, no cache read or write.
     */
    fun forOptions(remoteRecipes: Boolean = true, recipesUrl: String? = null, recipesVersion: String? = null): RecipesLoader? {
        if (!remoteRecipes) return null
        val url = remoteRecipesUrl(recipesUrl, recipesVersion) ?: return null
        return shared(url)
    }

    /** Forget the shared loaders (tests). */
    fun reset() = synchronized(loaders) { loaders.clear() }
}
