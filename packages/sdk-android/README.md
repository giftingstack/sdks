# GiftingStack for Android

Kotlin and Jetpack Compose SDK for GiftingStack: a gift tray, a gift effect layer (fly-in, sparks,
coin rain, light rays, "ayla sent Rose x3" notice) and the client for `/v1/client`. It follows
`packages/sdk-spec` (spec version 1.0.0) and mirrors the React Native reference in
`packages/sdk-js`. The tray is a draggable bottom sheet (spec 9.1), themeable (9.2), and the effect numbers can
be tuned remotely (13). Three read-only components sit next to the tray: a gift wall (chips under a
post, spec 14), a "while you were away" card with an effect replay (15) and a leaderboard (16).

- `minSdk 24`, Kotlin 2.2, Compose BOM 2025.10, coroutines. No Material, no OkHttp, no image library.
  The only AndroidX library besides Compose is `lifecycle-runtime-compose` (the away card checks again when the app returns).
- The logic (client, combo, scheduler, tray controller, wall chips and loader, away planner and controller,
  leaderboard controller) is pure Kotlin and runs in plain JVM tests.

## Install

The coordinates are `com.giftingstack:giftingstack:0.1.4` on Maven Central:

```kotlin
dependencies {
    implementation("com.giftingstack:giftingstack:0.1.4")
}
```

The app needs the `INTERNET` permission (the library manifest already declares it).

## Token flow

Your app never holds your GiftingStack API key. Your own server creates a short-lived client token
for the signed-in user (`POST /v1/client-tokens`), and the app asks your server for it:

```kotlin
val client = GiftingClient(
    getToken = { forceRefresh ->
        // forceRefresh is true after the API rejected the token (401): fetch a fresh one.
        myBackend.giftingToken(forceRefresh)
    },
)
```

`getToken` is called once per client call, plus once more with `forceRefresh = true` after a 401.
Errors it throws are not wrapped.

## Usage

```kotlin
@Composable
fun PostScreen(client: GiftingApi) {
    val effects = rememberGiftEffectLayerState()
    val tray = rememberGiftTrayHolder(client, receiver = "mert", effects = effects, reference = "post_42")

    var inset by remember { mutableStateOf(0.dp) }
    Box(Modifier.fillMaxSize()) {
        /* your post */
        GiftTray(                                            // a bottom sheet over the screen
            tray = tray,                                     // gifts, balance, Send and the "Test mode" badge come from the holder
            onTopUp = { openCoinStore() },                   // optional: "+ Coins" and "Get coins"
            onInsetChange = { inset = it },                  // the sheet's visible height
            bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding(),
        )
        GiftEffectLayer(effects, noticeBottom = inset + 12.dp) // once, on top; never takes touches
    }
}
```

A gift someone else sent (a live stream, a push message) uses the layer directly:

```kotlin
effects.play(
    GiftEffectEvent(
        gift = EffectGift(id = "rose", name = "Rose", price = 10, image = art512Url, icon = icon256Url),
        sender = "zeynep",
    ),
)
```

`play` returns an id (1, 2, 3, ...) for `cancel(id)`. `clear()` stops everything. Call all of them
from the main thread.

- `GiftEffectLayer(state, thresholds, quality, reducedMotion, origin, pictureWaitMs, noticeBottom,
theme, onEffectEnd)`. `quality = EffectQuality.Low` drops coin rain and rays and divides the
  sparks by three. `reducedMotion` defaults to the system setting "Remove animations" (animator
  duration scale 0), followed live; it then shows only the notice.
- `GiftTray(tray, gifts, balance, onSend, onTopUp, title, coinName, sendLabel, notEnoughLabel,
getCoinsLabel, columns, gridMaxHeight, defaultSelectedId, disabled, theme, onSelectedChange, sheet,
initialSnap, snaps, onSnapChange, onInsetChange, bottomInset, controller, collapseOnSelect, testMode, testModeLabel)`. `tray` is a `GiftTrayHolder`; the three fields you pass win over it. It is a bottom sheet by
  default (peek, default = two rows, expanded = 90 % of its parent): put it in a `Box` over your
  screen. `sheet = false` is the old fixed-height tray (`gridMaxHeight`). The "Test mode" badge needs nothing from you:
  `testMode = null` (default) follows the tray state (`tray = holder`), else any `rememberGiftTrayHolder` that reports a test key
  (`me.livemode == false`); `true`/`false` force it (with your own `GiftTrayHolder` in a ViewModel pass `tray = holder`). Icons are `min(72 dp, 78 % of the cell)`.
  `GiftEffectLayer` also takes `pictureScale` (automatic: 1 on a phone, up to 2 in a big layout).
- `GiftingTheme` has all colour tokens of the spec; pass `GiftingTheme(accent = ...)`, `GiftingTheme.Dark`,
  `GiftingTheme.Light` or `GiftingTheme.fromAccent("#ff4f9a", dark = true)` (text always 4.5:1; throws on a bad colour).
- Remote effect numbers (spec 13): `GiftEffectLayer(remoteRecipes = true, recipesVersion = null, recipesUrl = null)`
  fetches `https://assets.giftingstack.com/recipes.json` (deployed; any failure is silently ignored and the embedded numbers apply), caches it
  (memory by default; set `RecipesLoaders.storage` to persist, `RecipesLoaders.fetch` to replace the HTTP call) and
  refreshes at most every 6 h. `remoteRecipes = false` makes no request. Running effects keep their recipe.
- `placement` (sheet/popover/inline) is web only and not implemented here.
- `GiftTrayHolder(options, scope)` is the state holder behind `rememberGiftTrayHolder`. Use it in a
  `ViewModel` with `viewModelScope` and call `dispose()` in `onCleared()`.
- `playOn = PlayOn.Tap` (default) plays the effect at the tap and takes it back if the send fails;
  `PlayOn.Success` waits for the server.

### Gift wall, "while you were away", leaderboard

`GiftingClient` implements the three small interfaces the components need (`GiftWallApi`, `AwayApi`,
`LeaderboardApi`), so a test double only fakes the one it uses. All three take a `GiftingTheme` and a
`GiftLabels` (every visible and spoken word, English defaults, `copy(...)` to translate) and follow the system
"Remove animations" setting unless you pass `reducedMotion`.

```kotlin
// A row of chips under a post: [rose 12] [heart 3] [+37]. Walls on one screen share their requests (50 ms window,
// 25 per call, answers kept 60 s). A failed or empty wall draws nothing; failures only reach onError.
GiftWall(client, user = "mert", reference = "post_42", refreshKey = sentCount, onPressChip = { openTray(it) })

// "While you were away: 37 gifts from 12 people": a card, plus the biggest groups replayed through your effect layer.
val away = rememberGiftAwayHandle()                      // only for ackOn = Manual or a "check now" button
Box(Modifier.fillMaxSize()) {
    GiftAwaySummary(client, effects = effects, resolveUsers = { ids -> myBackend.names(ids) }, handle = away)
    GiftEffectLayer(effects)                             // above the card, so the replay shows over it
}

// Top senders or receivers, tabs for today / this week / this month / all time, the viewer's row pinned when outside.
GiftLeaderboard(client, board = LeaderboardBoard.Senders, limit = 10, metricToggle = true,
    resolveUsers = { ids -> myBackend.names(ids).mapValues { LeaderboardUser(it.value) } }, onPressUser = { openProfile(it) })
```

- `GiftWall(client, user, reference, max = 6, order, size = Sm | Md, data, refreshKey, onPressChip, onError, theme, labels, loader)`.
  `data` skips the request; changing `refreshKey` invalidates and fetches again. One loader per client is shared by every wall
  (`GiftWallLoaders`); give a screen its own through `LocalGiftWallLoader`.
- `GiftAwaySummary(client, effects, resolveUsers, autoCheck, ackOn, maxEffects, budgetMs, thresholds, quality, focusOnShow,
onShow, onDone, onError, theme, labels, handle)`. It waits up to 1.5 s for `resolveUsers`, then shows the card. The cursor is
  acknowledged once, with the cursor of the summary that was shown (`AwayAckOn.Shown`, `Finished` or `Manual`). Nothing new or any
  failure: nothing is drawn. Reduced motion: no replay and no slide-in; the text is announced as a live region.
- `GiftLeaderboard(client, board, periods, initialPeriod, metric, metricToggle, limit, resolveUsers, highlightUser,
refreshIntervalMs, onPressUser, onError, theme, labels, coinName, handle)`. A tab already seen shows at once and is fetched
  again in the background when 30 s old; its rows stay while that runs. Medal colours are `RANK_COLORS` (not part of `GiftingTheme`).
- Pure core for your own UI: `wallChips`, `formatCount`, `GiftWallLoader`, `planAwayReplay`, `awaySenderLabel`, `AwayController`,
  `LeaderboardController`, `pinnedMe`, `leaderboardRankLabel`, `GiftLabels` and the text helpers. The controllers take a
  `CoroutineScope` (use `viewModelScope` or a Compose scope: the main thread) and expose a `StateFlow`.
- `GiftingClient.getReceivedGifts(user, reference)` (counters of one post), `queryGiftWalls`, `getAway`, `ackAway` (204: nothing is
  parsed) and `getLeaderboard` are on the client; `GiftingApi` is unchanged.

### Render slots

Draw the inside of a chip, a row or the card body yourself with a nullable composable lambda. The SDK
keeps loading, order, names, the container, the spoken label (`clearAndSetSemantics`), the press and the actions.
Null (the default) draws the default; call `Default()` on the context to keep the default for some items.

```kotlin
GiftWall(client, user = post.author, onPressChip = ::openTray,
    renderChip = { chip -> BasicText("${chip.gift.name} x${chip.countText}") }) // WallChipContext
GiftLeaderboard(client,
    renderRow = { row -> if (row.isMe) row.Default() else MyRow(row.rank, row.name, row.scoreText) }) // LeaderboardRowContext
GiftAwaySummary(client,
    // AwaySummaryContext: summary, title, headline, gifts, people, senders, dismiss, ack, theme.
    renderSummary = { s -> MyCard(s.headline, onClose = s.dismiss) }) // no close button, a tap does not dismiss
```

The "+37" overflow chip and the pinned "You" row stay the default.

### Gift rooms (live)

Everyone in a room sees every gift sent into it (SPEC 17-18; gift events only: no chat, no media, no message text). Your server mints the
client token with `rooms` (a room pattern such as `live_*`) and optionally `name` (the sender's display name); the same `getToken` you give
`GiftingClient` is used. Rooms are off until the project's "Gift rooms" switch is on.

```kotlin
val effects = rememberGiftEffectLayerState()
val room = rememberGiftRoom(room = "live_123", getToken = ::myToken, client = client, effects = effects)   // null room: not in a room
val roomState by room.state.collectAsState()                    // status, viewers, attempt, retryInMs, code
val tray = rememberGiftTrayHolder(client, receiver = "host", effects = effects, roomId = "live_123")       // your own sends reach the others
Box(Modifier.fillMaxSize()) { /* your screen */ GiftEffectLayer(effects) }
```

- `rememberGiftRoom` joins while it is composed and the screen is STARTED. When the lifecycle drops below STARTED (app in the background)
  the socket closes (1000) without leaving; coming back reconnects and resumes after the last gift (`hello.last`), so nothing is lost or
  replayed twice. Leaving the composition leaves the room. A new `room` leaves the old one.
- Gifts other people send play on `effects` automatically. Your own gifts are skipped (`skipOwn`, default true): the tray already played
  them at the tap. Options: `onEvent`, `onGap`, `maxReplayAgeMs` (10 s), `minTier`, `thresholds`, `resolveName`, `url`
  (default `wss://rt.giftingstack.com`), `socket`.
- Reconnects with full-jitter backoff, refreshes the token before the 60 minute limit, answers 4001/4008/4009 as in SPEC 18.3.
- Transport: `javaRoomSocketFactory()`, a small RFC 6455 client on `java.net.Socket` (no OkHttp, no new dependency; `wss` uses the platform
  trust store and host name check). Callbacks arrive on the main thread. For a ViewModel use `GiftRoom(GiftRoomOptions(...), viewModelScope)`
  and call `foreground()`, `background()` and `leave()` yourself.
- Pure core (SPEC 18, the five `rooms-*.json` fixtures run on the JVM): `parseRoomFrame`, `roomHelloFrame`, `roomUrl`, `roomTokenUser`,
  `roomRetryDecision`, `RoomEventFilter`, `roomGiftToEffect`, `RoomClient` (inject `RoomSocketFactory`, `Timers`, clock, random, `getToken`).
  `RoomGiftEvent.toEffect()` gives the `GiftEffectEvent` for `play`. `RoomClient` is single-threaded: use the main thread.
- `SendGiftInput(roomId = ...)` and `GiftTrayOptions(roomId = ...)` send `room_id` with the gift.
- Demo: the Live tab runs the real `rememberGiftRoom` against `FakeRoomServer`, a pretend rooms server that speaks the wire protocol.

### Battle bar (versus)

`GiftBattleBar` draws a battle round of the room (SPEC 18.7): both receivers with their scores, a countdown, and a bar whose boundary slides as gifts arrive. It draws `battleView` only; your server starts and ends rounds. Nothing is drawn while the room has no round with two sides.

```kotlin
val room = rememberGiftRoom(room = "live_42", getToken = { force -> myServer.token(force) })
GiftBattleBar(
    room,                                         // follows room.battle and ticks the clock by itself
    users = mapOf(                                // names and pictures by id (fallback: the id)
        "ava" to BattleBarUser("Ava", avatarUrl = "https://..."),
        "mateo" to BattleBarUser("Mateo"),
    ),
    theme = GiftingTheme.Dark,                    // accent against coin colour, 4.5:1 text on both
    sideColors = listOf(Color(0xFFE0457B), Color(0xFF3A8DFF)), // optional: one colour per side (a pair `a to b` works too)
    labels = BattleBarLabels(finalText = "Bitti", wins = "{name} kazandı"),
    reducedMotion = null,                         // null: follows the system "Remove animations"
)
// Or draw a view you hold yourself: GiftBattleBar(room.battleView(), ...)
```

The gift notice of a battle says who got the gift: `sent Rose to Mia`, with a 2 px border in the side's colour (accent for the first side, coin colour for the second). Pass the same colours to the room as to the bar, and the names from `resolveName`: `rememberGiftRoom(sideColors = listOf(Color(0xFFE0457B), Color(0xFF3A8DFF)), resolveName = ...)`. Outside battles nothing changes. The user's own gift says who got it too when the tray knows the room: `rememberGiftTrayHolder(receiverOf = room::receiverFor, ...)`. An app that plays its own events can set `GiftEffectEvent(receiver = GiftEffectReceiver(name, side, color))`.

The pure model (`battleBarModel`, `formatBattleScore`, `formatBattleClock`, `battleSideColors`) is in `core`; the numbers are the shared fixture `battle-bar.json`. Reduced motion: no sliding, counting or pulse.

### Tests without a network

`GiftingClient` takes a `GiftingTransport` (`suspend fun send(TransportRequest): TransportResponse`),
and the tray and the holder take any `GiftingApi`, so no test needs a network. The picture loader is
replaceable through `LocalGiftImageLoader` (use your own Coil or Glide bridge if you prefer).

## Limits

- Pictures are cached in memory only (an eighth of the app heap); the SDK installs no process-wide HTTP cache
  (`DefaultGiftImageLoader.installDiskCache` is a deprecated no-op). Only `https` pictures load (`http` to
  localhost, 127.0.0.1, ::1 and 10.0.2.2 for a local server, and `data:image` base64; SPEC 7.6: `isPictureUrl`). A picture is at most 5 MiB, decoded subsampled (at most
  1024 px a side and 4 MP), and one that failed is not asked for again for 60 s. Decoding happens at prefetch time, once.
  `DefaultGiftImageLoader.cancelAll()` aborts the downloads in flight.
- The effect starts when its picture is ready or after `pictureWaitMs` (300 ms), so the tray prefetches
  every icon (the catalog load) and the selected gift's big picture (the tray). Without prefetch the first gift of a kind waits.
- `GiftingClient(baseUrl = ...)` refuses `http://` unless the host is localhost, 127.0.0.1, ::1 or 10.0.2.2 or you pass
  `allowInsecure = true`; the rooms URL (`wss://`) follows the same rule (`rememberGiftRoom(allowInsecure = ...)`).
- Number format is always en-US grouping (`1,234`), as the spec says.
- `Gift.price` and balances are `Long`, quantities are `Int`.
- The default transport has no retry beyond the spec's one 5xx retry and no certificate pinning.
- Frame smoothness on real hardware is not verified (see below).

## Layout

```text
giftingstack/   library: core (pure Kotlin) and ui (Compose)
demo/           demo app: "Pixel", a fake social app that is ONE example integration (bottom tabs Feed, Live, Top, Inbox, Me; a Gift
                button per post opens the tray for its author, one wall per post, the away card the first time after install only,
                the leaderboard on Top, a coin store that ADDS coins on Me; 250 ms mock latency, balance 60000, about 90 gifts from
                the live library with a small fallback list). No debug buttons on screen: the only debug surface is the developer
                menu (a bottom sheet "Developer menu (not part of the SDK)"), opened by a 1 s long-press on the Pixel logo.
                Gifts from others never arrive by themselves (`LIVE_FEED = false`); the menu plays them
docs/screenshots/
```

Build and test (Java 21, Android SDK 35):

```bash
./gradlew :giftingstack:testDebugUnitTest :demo:testDebugUnitTest  # conformance fixtures + unit tests, JVM
./gradlew :giftingstack:connectedDebugAndroidTest  # Compose UI tests, needs an emulator or device
./gradlew :giftingstack:lintDebug :demo:lintDebug
./gradlew :demo:installDebug
```

Versions: Gradle 8.14.3, Android Gradle Plugin 8.13.2, Kotlin 2.2.0 (Compose compiler plugin),
Compose BOM 2025.10.00, kotlinx-coroutines 1.10.2, kotlinx-serialization-json 1.9.0, compileSdk 35.

## Verification

| level                                                 | what                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | result                                                                                                                                                                                                                    |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1 constants                                          | `SpecDriftTest` compares thresholds, window, caps, queue size, sender and all recipe fields (high and low) with `recipes.json`; the remote limits table is compared with SPEC.md 13.3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | 4 + 2 tests pass                                                                                                                                                                                                          |
| L2 logic                                              | every case of `tiers`, `combo`, `client`, `effects`, `tray`, `sheet` (12 heights, 22 scenarios), `theme` (contrast, presets, 9 accents x 2 modes, 4 invalid, 300 random accents) and `remote-recipes` (33 parse, 5 merge, 9 urls) runs on the JVM from `../sdk-spec/conformance`. `placement.json` is web only (SPEC 9.3): skipped, acknowledged by a test                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | 392 JVM tests in the library + 27 in the demo pass (the Pixel rebuild) (2026-10-12, Windows, JDK 21); 237 + 6 of them predate the components                                                                              |
| L3 component timing                                   | picture gate (8 cases of `effects.json#pictureGate`), pass-through of touches, combo "x2/x3", reduced motion, effect end and notice expiry, cancel, tray                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | 15 instrumented Compose tests pass on an emulator (Android 35)                                                                                                                                                            |
| L3 on the emulator by eye                             | demo app screenshots in `docs/screenshots/`: tray, small, medium and large effect mid-animation, notice with x3, "Get coins" state                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | looked right (see below)                                                                                                                                                                                                  |
| Sheet, theme, remote loader, demo (new, 2026-10-11)   | Pure logic and the loader (injected fetch, storage, clock) are unit tested. The sheet UI (drag, flick, nested scroll, inset callback, handle semantics), the theme and the icons are **only checked by eye on the emulator**: default state, swipe down to peek and swipe up to expanded were seen to work; flick feel, slop, handle accessibility actions, themes and the coin store were not exercised. A new instrumented sheet test is written and compiles but was NOT run. The existing 15 Compose tests were not re-run after the tray rewrite (they use `sheet = false`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | partly read, not measured                                                                                                                                                                                                 |
| Components: wall, away, leaderboard (new, 2026-10-12) | **Logic, tested on the JVM:** every case of `wall.json` (12 chips, 22 formatCount, 8 loader scenarios, 4 client), `away.json` (16 plan, 10 senderLabel, 15 controller scenarios, 5 client) and `leaderboard.json` (6 rankLabel, 10 pin, medal tokens with contrast, 14 controller scenarios, 5 client), plus 24 unit tests of the rules the fixtures do not spell out (Int overflow of the chip sum, default coroutine timers, texts, a 204 is never parsed). `FixtureCoverageTest` fails when a conformance file has no runner (`placement.json` is listed as web only). The fixtures are Gradle test inputs. Every `client` scenario, including `away.json` "getAway with since and maxGroups" (its fixture body used to write `"gift": "dragon"`, fixed 2026-10-12), is checked on the full request and the parsed result. **UI, compiled and run in 25 instrumented tests on the emulator:** the three Compose components follow SPEC 14.5, 15.5 and 16.4 and compile in the library and the demo; 9 instrumented Compose tests (`ComponentsUiTest`: wall label and buttons, load and failure, away announce / ack once / dismiss / replay / reduced motion, leaderboard labels, tabs, pinned row, Try again) RUN on the emulator (API 35, 2026-10-12): 25 of 25 instrumented tests pass. The first run found a real crash (an unescaped `}` in the label placeholder regex that the JVM accepts but Android's regex rejects) and a wrong `testTag` order in `GiftWall`; both are fixed. Compose UI tests do not run on the JVM in this project. Nothing was looked at on a screen: layout, the 120 ms fade, the 240 ms slide, the spinner, TalkBack output, `focusOnShow` and the touch target (the platform minimum of 48 dp, which covers the 44 dp of the document) are **not verified**. | logic: tested; UI: 25 instrumented tests pass on the emulator, demo looked at on the emulator, not on a phone                                                                                                             |
| L4 device feel                                        | smoothness on a mid and a low-end phone, easing and overshoot feel, spark and coin spread, ray look, notice pop, heat                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | **not verified**: the emulator renders with software GPU; the frame-time numbers below are dominated by it. A person must compare with the React Native reference app on a real device (`quality = Low` for slow phones). |

Emulator numbers (Android 35 emulator, software GPU, `dumpsys gfxinfo`): one large effect 98 % janky
frames (median 121 ms), one medium 91 % (81 ms), one small 84 % (77 ms), and a trivial baseline, only
the balance count-up text, 72 % (73 ms). The baseline is as slow as the effects, so these numbers say
the emulator is slow, not that the effects are. Spamming Send and Incoming gift 30 times in the debug
build gave 97 % janky frames. None of this tells anything about a real device.

### Mutation checks

Added 2026-10-11 (all caught, restored): sheet flick threshold exclusive; ties to the less open state; expanded fraction 0.9 to 0.75; `scrollOwner` ignoring the grid's scroll position; `onSnapChange` on every settle; remote clamp removed; remote rounding removed; threshold order unchecked; `sparks` limit 120 to 200 in code only (fails the table test and the clamp case).

Components (2026-10-12): 24 mutations of the new core code, each run through the library's unit tests and reverted: **all 24 caught** (the last 12 rows below, some rows cover several mutations). Rules broken one at a time in the core, the unit tests run, the change reverted (all caught):

| mutation                                                                              | failing tests                                                                                   |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| combo window inclusive (`<` to `<=`)                                                  | combo: "a gap of exactly 2500 ms starts over", "custom window of 2000 ms"                       |
| 5xx retry sends a new idempotency key                                                 | client: 500-then-success, 503 twice, 401-refresh-500, network failure on the retry (4 cases)    |
| space encoded as `+` in the user id                                                   | client: "encodes the user id like encodeURIComponent" and `encodeUriComponentMatchesJavaScript` |
| full large queue drops the newest, not the oldest                                     | effects: "at most 5 large gifts wait; a new one drops the OLDEST"                               |
| no balance refund when a send fails                                                   | tray: 5 scenarios (tap and success mode, burst, no effect layer, ...)                           |
| `holdMs` 1600 changed to 1700 in the recipe                                           | `SpecDriftTest` and two timeline tests                                                          |
| notice uses `image` instead of `icon ?: image`                                        | effects: 10 scenarios                                                                           |
| `formatCount` rounds instead of flooring                                              | wall: 1099, 1999, 9999, 10999, 999999 and more cases, unit test                                 |
| overflow chip counts kinds; `max` chips before it                                     | wall chips (several cases), 4 unit tests (sum of gifts, Int overflow, `max` 0)                  |
| replay budget `>` to `>=`; drops the highest first                                    | away plan: "an end exactly at the budget fits", budgets 7000 and 6000, unit test                |
| replay takes the last large group                                                     | away plan: "two large groups", unit test                                                        |
| ack more than once per summary                                                        | away controller: 6 scenarios (shown, manual, retry, ...)                                        |
| failed ack retried at every check                                                     | away controller: "retried once before the next read", "a retried ack that succeeds"             |
| foreground throttle `<` to `<=`                                                       | away controller: "60,000 itself checks"                                                         |
| pinned at `rank >= limit`; tie at the cut; zero score                                 | leaderboard pin (3 cases), controller "me without a score", unit tests                          |
| cache stale only above 30 s; never stale                                              | leaderboard controller: "a cached tab 30,000 ms old ..."                                        |
| `includeMe = false` not sent; failed revalidation drops rows                          | leaderboard controller: "limit and includeMe false", "keeps the stale rows visible"             |
| loader: ttl `<=`; stale answer cached after `invalidate`; no sharing of a queued wall | wall loader: 3 scenarios, unit test                                                             |
| 204 body parsed; leaderboard query order; medal colour; "and 1 other" branch          | away client (2), leaderboard client, rank colours (2), sender label (2)                         |

## Notes on the port

- Rooms (SPEC 17-18, 2026-10-12): ported from `rooms.ts` against the five `rooms-*.json` fixtures (including the `batch` filter step and optional `quantity`). `RoomGiftEvent` is its own class with `toEffect()` (a Kotlin data class cannot be extended); counts are `Long`; prices and quantities above `Int.MAX_VALUE` are clamped when turned into a `GiftEffectEvent`. The heartbeat is the app-level text `ping` (45 s), not protocol pings. Verified: JVM fixtures, a JVM RFC 6455 server test of the transport, 2 instrumented tests on the emulator (lifecycle pause/resume with a fake socket; the real transport over loopback). `wss` was tried once on the JVM against a public echo server (TLS and upgrade reached, a host name mismatch refused; not on Android). **Not verified:** a real rooms Worker, a real phone, Doze/network-change behaviour (no `reconnectNow` hook yet).
- Components (SPEC 14-16): the controllers take a `CoroutineScope` and a `Timers` object (default: `delay` on the scope, a fake clock in tests) and expose `StateFlow`; their server calls start undispatched on the calling thread, like the reference's un-awaited promises. Counters that add up are `Long`. `GiftingClient` also implements `GiftWallApi`, `AwayApi` and `LeaderboardApi`, so `GiftingApi` and its test doubles are unchanged. A 204 answer is never parsed.
- The away card's "back to the foreground" is the host's lifecycle `ON_START` (needs `lifecycle-runtime-compose`); an `ON_RESUME` after a dialog does not recheck.

- `GiftingException` is the spec's name for the error; `GiftingError` is a typealias for it.
- The `GiftTrayController` runs `reconcile` inside `send` (the TypeScript fires it and forgets it);
  the observable states are the same, `send` just returns after the reconcile `getMe` answered.
- The picture gate needs two frames in the zero-wait case (one composes the effect, one composes the
  notice). Everything else is within one frame of the fixture times.
- Effects are drawn with one timeline value read only in the draw phase: a single `Canvas` for dim,
  rays, glow, sparks and coins and a `graphicsLayer` for the picture, so no frame recomposes.

## License

MIT, see [LICENSE](LICENSE). The licence covers this package's code only. The GiftingStack
name and logo, the GiftingStack service and API, and the ready-made gift library
(`assets.giftingstack.com`) are not part of it; the gift library has its own terms.
