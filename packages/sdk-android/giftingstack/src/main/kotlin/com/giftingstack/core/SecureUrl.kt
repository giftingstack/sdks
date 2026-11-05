package com.giftingstack.core

import java.util.Locale

/** Hosts that never leave the device or the emulator host: plain `http`/`ws` is fine for them. */
private val LOOPBACK_HOSTS = setOf("localhost", "127.0.0.1", "::1", "10.0.2.2")

/**
 * The host of a URL (lower case, no port, no brackets), or null when there is none. Parsed by hand
 * so a malformed URL never throws and `http://localhost@evil.example` is read as `evil.example`.
 */
internal fun urlHost(url: String): String? {
    val sep = url.indexOf("://")
    if (sep < 0) return null
    var authority = url.substring(sep + 3)
    val end = authority.indexOfFirst { it == '/' || it == '?' || it == '#' }
    if (end >= 0) authority = authority.substring(0, end)
    authority = authority.substringAfterLast('@')
    val host =
        if (authority.startsWith("[")) {
            val close = authority.indexOf(']')
            if (close < 0) return null
            authority.substring(1, close)
        } else {
            authority.substringBefore(':')
        }
    return host.lowercase(Locale.ROOT).ifEmpty { null }
}

/** `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` (the emulator's name for the dev machine). */
internal fun isLoopbackUrl(url: String): Boolean = urlHost(url) in LOOPBACK_HOSTS

/**
 * Refuses a plain-text URL (SPEC 3.1, audit R-07): `http` and `ws` (any case) pass only for a loopback
 * host or with [allowInsecure]. `https`, `wss`, another scheme and a string without one all pass (the
 * transport fails the odd ones later).
 *
 * @throws IllegalArgumentException that names [what] and the option, and shows only scheme and host
 *   (never userinfo, path or query).
 */
internal fun requireSecureUrl(url: String, allowInsecure: Boolean, what: String) {
    val scheme = url.substringBefore("://", "").lowercase(Locale.ROOT)
    if (scheme != "http" && scheme != "ws") return
    require(allowInsecure || isLoopbackUrl(url)) {
        "$what uses plain $scheme://${urlHost(url) ?: "?"}. Use ${if (scheme == "ws") "wss" else "https"}, or pass " +
            "allowInsecure = true (localhost, 127.0.0.1, ::1 and 10.0.2.2 are always allowed)."
    }
}
