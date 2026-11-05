package com.giftingstack.core

import java.util.LinkedHashMap

/** Most bytes one picture may have (SPEC 7.6): 5 MiB. */
const val PICTURE_MAX_BYTES: Int = 5_242_880

/** A picture that failed is not requested again for this long (SPEC 7.6). */
const val PICTURE_FAILURE_MEMORY_MS: Long = 60_000L

/** At most this many failed URLs are remembered, the oldest forgotten first. */
const val PICTURE_FAILURES_KEPT: Int = 200

/** A `data:image` URL longer than this many characters is refused: `ceil(PICTURE_MAX_BYTES x 4 / 3) + 256`. */
const val PICTURE_DATA_URL_MAX_CHARS: Long = (PICTURE_MAX_BYTES * 4L + 2L) / 3L + 256L

private fun String.startsWithIgnoreCase(prefix: String): Boolean = regionMatches(0, prefix, 0, prefix.length, ignoreCase = true)

/**
 * Which picture URLs the SDK draws (SPEC 7.6, audit R-08): `https://` always; `http://` only to a
 * loopback host (`localhost`, `127.0.0.1`, `::1`, `10.0.2.2`); `data:image/...` up to
 * [PICTURE_DATA_URL_MAX_CHARS] characters; nothing else (`javascript:`, `file:`, `blob:`, `ftp:`, a
 * scheme-less or empty string). A refused URL is never requested: the placeholder is drawn instead.
 */
fun isPictureUrl(url: String): Boolean =
    when {
        url.startsWithIgnoreCase("https://") -> true
        url.startsWithIgnoreCase("http://") -> isLoopbackUrl(url)
        url.startsWithIgnoreCase("data:image/") -> url.length <= PICTURE_DATA_URL_MAX_CHARS
        else -> false
    }

/**
 * The URLs whose picture failed, for [PICTURE_FAILURE_MEMORY_MS] (SPEC 7.6): until then the same URL is
 * not requested again by a prefetch, a rebuilt grid or the next effect. Time is passed in (`atMs`, any
 * clock that only moves forward), so it is pure and testable. At most [PICTURE_FAILURES_KEPT] URLs; failing
 * a URL again restarts its minute and makes it the newest.
 */
class PictureFailures {
    private val failedAt = LinkedHashMap<String, Long>()

    /** Records that [url] failed at [atMs]. */
    fun fail(url: String, atMs: Long) {
        failedAt.remove(url)
        failedAt[url] = atMs
        while (failedAt.size > PICTURE_FAILURES_KEPT) {
            val oldest = failedAt.keys.iterator()
            oldest.next()
            oldest.remove()
        }
    }

    /** True while [url] failed less than a minute before [atMs]. */
    fun has(url: String, atMs: Long): Boolean {
        val at = failedAt[url] ?: return false
        if (atMs - at < PICTURE_FAILURE_MEMORY_MS) return true
        failedAt.remove(url)
        return false
    }
}
