package com.giftingstack.demo

import com.giftingstack.core.EffectQuality

/** Title of the hidden developer menu: the only debug surface of the demo. */
internal const val DEV_MENU_TITLE = "Developer menu (not part of the SDK)"

/** How long the Pixel logo must be held to open the developer menu. */
internal const val DEV_HOLD_MS = 1_000L

/** What the "Play gift" control plays (as the web demo's picker). */
enum class IncomingMode(val label: String) {
    SameAsTray("Same as tray"),
    Random("Random"),
    Cheapest("Cheapest"),
    Priciest("Priciest"),
}

/** The demo theme picker (an app passes one `theme` to the tray and the layer). */
enum class DemoTheme(val label: String) {
    Default("Default"),
    Dark("Dark"),
    Light("Light"),
    Pink("Pink"),
}

enum class DemoMotion(val label: String, val reduced: Boolean?) {
    System("System", null),
    Reduced("Reduced", true),
}

/** Every switch of the developer menu. */
data class DevSettings(
    val incoming: IncomingMode = IncomingMode.SameAsTray,
    val quality: EffectQuality = EffectQuality.High,
    val theme: DemoTheme = DemoTheme.Default,
    val motion: DemoMotion = DemoMotion.System,
    /** The mock failure switch: every call of the mock client fails like a lost connection. */
    val offline: Boolean = false,
)

/** The menu is folded by default, never open on launch; the settings survive closing it. */
data class DevMenuState(val open: Boolean = false, val settings: DevSettings = DevSettings()) {
    fun opened() = copy(open = true)

    fun closed() = copy(open = false)

    fun with(change: (DevSettings) -> DevSettings) = copy(settings = change(settings))
}
