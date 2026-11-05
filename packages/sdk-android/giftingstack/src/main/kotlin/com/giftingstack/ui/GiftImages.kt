package com.giftingstack.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import android.util.Base64
import com.giftingstack.core.PICTURE_MAX_BYTES
import com.giftingstack.core.PictureFailures
import com.giftingstack.core.isPictureUrl
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/**
 * Loads and keeps gift pictures. The effect starts only when its picture is ready, so pictures
 * must be fetched and decoded ahead of time (`prefetch`). Replace it with your own (Coil, Glide)
 * through [LocalGiftImageLoader]; tests use a fake one.
 */
interface GiftImageLoader {
    /** The decoded picture if it is already in memory. Never loads. */
    fun peek(url: String): ImageBitmap?

    /** Loads (or finds) the picture. Returns null when it cannot be loaded. Never throws. */
    suspend fun load(url: String): ImageBitmap?

    /** Starts loading in the background. */
    fun prefetch(url: String)
}

val LocalGiftImageLoader = compositionLocalOf<GiftImageLoader> { DefaultGiftImageLoader }

/** A decoded picture is at most this many pixels on its long side (effect art is 512, icons 256). */
internal const val IMAGE_MAX_SIDE = 1024

/** ...and at most this many pixels in all (4 MP = 16 MB as ARGB_8888). */
internal const val IMAGE_MAX_PIXELS = 4_000_000L

private const val IMAGE_PARALLEL = 4

/** The bytes of a `data:image/...;base64,...` URL, or null when it is not base64 or not valid. */
private fun dataUrlBytes(url: String): ByteArray? {
    val comma = url.indexOf(',')
    if (comma < 0 || !url.substring(0, comma).endsWith(";base64", ignoreCase = true)) return null
    return try {
        Base64.decode(url.substring(comma + 1), Base64.DEFAULT)
    } catch (e: IllegalArgumentException) {
        null
    }
}

/** The power-of-two `inSampleSize` that brings a [width] x [height] picture within [IMAGE_MAX_SIDE] and [IMAGE_MAX_PIXELS]. */
internal fun imageSampleSize(width: Int, height: Int): Int {
    if (width <= 0 || height <= 0) return 1
    var sample = 1
    while (width / sample > IMAGE_MAX_SIDE || height / sample > IMAGE_MAX_SIDE ||
        (width / sample).toLong() * (height / sample) > IMAGE_MAX_PIXELS
    ) {
        sample *= 2
    }
    return sample
}

/**
 * A tiny loader: `HttpURLConnection` + `BitmapFactory` on `Dispatchers.IO`, an in-memory LRU
 * cache of decoded bitmaps (an eighth of the app's heap) and one shared download per URL.
 * Decoded bitmaps stay in memory, so a gift flies in without decoding anything.
 *
 * Safety limits (SPEC 7.6): only [isPictureUrl] URLs (`https`, `http` to loopback for a local dev server,
 * `data:image`); a download stops at 5 MiB ([PICTURE_MAX_BYTES]); a big picture is decoded subsampled
 * (at most 1024 px a side and 4 MP); every failure, including running out of memory, is a null picture;
 * a failed URL is not requested again for 60 s ([PictureFailures]). No process-wide HTTP cache is
 * installed. [cancelAll] aborts the downloads that are running.
 */
object DefaultGiftImageLoader : GiftImageLoader {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val inFlight = HashMap<String, Deferred<ImageBitmap?>>()
    private val failures = PictureFailures()
    private val lock = Any()
    private val parallel = Semaphore(IMAGE_PARALLEL)
    private val cache =
        object : LruCache<String, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8L).toInt().coerceAtLeast(4 * 1024 * 1024)) {
            override fun sizeOf(key: String, value: ImageBitmap): Int =
                value.asAndroidBitmap().allocationByteCount
        }

    /** Monotonic clock in ms; tests replace it. */
    internal var clockMs: () -> Long = { System.nanoTime() / 1_000_000L }

    override fun peek(url: String): ImageBitmap? = cache.get(url)

    override suspend fun load(url: String): ImageBitmap? {
        cache.get(url)?.let { return it }
        if (!isPictureUrl(url) || recentlyFailed(url)) return null
        val job =
            synchronized(lock) {
                cache.get(url)?.let { return it }
                inFlight.getOrPut(url) {
                    // The download belongs to this object, not to the caller: a caller that gives up
                    // (picture wait ran out) must not cancel it, the picture is wanted later anyway.
                    scope.async(start = CoroutineStart.LAZY) { fetch(url) }.also { d ->
                        d.invokeOnCompletion {
                            synchronized(lock) { inFlight.remove(url) }
                        }
                    }
                }
            }
        job.start()
        return try {
            job.await()
        } catch (e: CancellationException) {
            // The caller itself was cancelled: let it end. Otherwise cancelAll() stopped the download.
            currentCoroutineContext().ensureActive()
            null
        }
    }

    override fun prefetch(url: String) {
        if (cache.get(url) != null || !isPictureUrl(url)) return
        scope.launch { load(url) }
    }

    /** Aborts every running download (they close their connections). Pictures already decoded stay. */
    fun cancelAll() {
        val running = synchronized(lock) { inFlight.values.toList() }
        for (d in running) d.cancel()
    }

    /**
     * Kept for source compatibility; does nothing. The SDK no longer installs a process-wide
     * `HttpResponseCache` (it would change the HTTP behaviour of the whole app). Install one yourself
     * if you want pictures on disk, or give [LocalGiftImageLoader] a loader that has its own cache.
     */
    @Deprecated("No longer installs a global HTTP cache; remove the call.")
    @Suppress("UNUSED_PARAMETER")
    fun installDiskCache(context: Context) = Unit

    private fun recentlyFailed(url: String): Boolean = synchronized(lock) { failures.has(url, clockMs()) }

    private fun rememberFailure(url: String) {
        synchronized(lock) { failures.fail(url, clockMs()) }
    }

    private suspend fun fetch(url: String): ImageBitmap? {
        val bitmap = parallel.withPermit { download(url) }
        if (bitmap == null) rememberFailure(url) else cache.put(url, bitmap)
        return bitmap
    }

    /** One download; cancelling the coroutine closes the connection, which ends the blocking read. */
    private suspend fun download(url: String): ImageBitmap? =
        withContext(Dispatchers.IO) {
            if (url.regionMatches(0, "data:", 0, 5, ignoreCase = true)) {
                return@withContext try {
                    dataUrlBytes(url)?.takeIf { it.size <= PICTURE_MAX_BYTES }?.let { decodeBounded(it) }?.asImageBitmap()
                } catch (t: Throwable) {
                    null
                }
            }
            val conn =
                try {
                    URL(url).openConnection() as HttpURLConnection
                } catch (e: Exception) {
                    return@withContext null
                }
            try {
                suspendCancellableCoroutine<ImageBitmap?> { cont ->
                    cont.invokeOnCancellation { runCatching { conn.disconnect() } }
                    // Blocking, on this IO thread. A cancel from another thread disconnects, which
                    // makes the read throw; the result is then ignored.
                    val result: ImageBitmap? =
                        try {
                            readAndDecode(conn)
                        } catch (t: Throwable) {
                            // Network errors, a bad image and OutOfMemoryError: a missing picture, never a crash.
                            null
                        }
                    cont.resume(result)
                }
            } finally {
                conn.disconnect()
            }
        }

    private fun readAndDecode(conn: HttpURLConnection): ImageBitmap? {
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        conn.useCaches = false
        if (conn.responseCode !in 200..299) return null
        val declared = conn.contentLengthLong
        if (declared > PICTURE_MAX_BYTES) return null
        val out = ByteArrayOutputStream(if (declared in 1..PICTURE_MAX_BYTES.toLong()) declared.toInt() else 16 * 1024)
        conn.inputStream.use { input ->
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (out.size() + n > PICTURE_MAX_BYTES) return null
                out.write(buffer, 0, n)
            }
        }
        return decodeBounded(out.toByteArray())?.asImageBitmap()
    }

    /** Reads the size first, then decodes subsampled so a huge picture cannot exhaust the heap. */
    private fun decodeBounded(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val opts =
            BitmapFactory.Options().apply {
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inSampleSize = imageSampleSize(bounds.outWidth, bounds.outHeight)
            }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }
}

/** The loader in use below this point of the composition. */
@Composable
internal fun currentGiftImageLoader(): GiftImageLoader = LocalGiftImageLoader.current
