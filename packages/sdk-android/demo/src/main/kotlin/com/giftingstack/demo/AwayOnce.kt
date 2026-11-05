package com.giftingstack.demo

import android.content.Context
import android.content.SharedPreferences

/** Where "the away card was shown" is kept. */
interface AwayStore {
    fun seen(): Boolean

    fun markSeen()
}

/** SharedPreferences is part of Android: the flag survives app restarts, and is gone with an uninstall. */
class PrefsAwayStore(private val prefs: SharedPreferences) : AwayStore {
    constructor(context: Context) : this(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))

    override fun seen(): Boolean = prefs.getBoolean(KEY, false)

    override fun markSeen() {
        prefs.edit().putBoolean(KEY, true).apply()
    }

    companion object {
        const val PREFS_NAME = "pixel_demo"
        const val KEY = "away_seen"
    }
}

/**
 * The away card shows the first time after install only (a real app shows it until new gifts
 * arrive; this demo's data is mock). Afterwards only the developer menu shows it again.
 * [autoCheck] is read once at launch, so showing the card does not switch it off mid-session.
 */
class AwayOnce(private val store: AwayStore) {
    val autoCheck: Boolean = !store.seen()

    /** Call when the card was shown. */
    fun onShown() = store.markSeen()
}
