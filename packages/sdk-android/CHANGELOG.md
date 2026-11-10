# Changelog

## 0.1.3

- With `scrim` on, a tap on the empty space beside a tray at peek (the small state) now closes it: the dim stays hidden there, but it takes the tap (SPEC 9.4, `scrimTakesTouches`; a tall tray still lowers to peek first with `scrimTap` "lower"). The page behind a peeking tray is no longer touchable while the tray is open; leave `scrim` off for that.
- A battle can have three to eight sides (SPEC 18.7, a free-for-all: everybody races on their own; teams are not part of it). The battle bar draws every side: two sides look exactly as before, three or more get a row of cells (avatar, name, score) with the clock above and a bar of proportional segments (each side in its colour, none under 6 %, white lines between them); the winner, the banner and the spoken sentence cover every side. `sideColors` is a list with one colour per side (`GiftBattleBar(sideColors = listOf(...))`, `rememberGiftRoom`; the pair form `sideColors = a to b` of the bar still works) (a shorter list keeps the default for the sides it does not name; the default palette is the theme's accent, its coin colour, then teal `#2ec4b6` and pink `#ff5d8f`, then the same four again). The gift notice of a battle names the receiver and borders its pill for every side, not only the first two. New: `battleSidePalette`, `battleSegmentPcts`, `BattleBarModel.pcts`.

- The gift notice of a battle says who got the gift (SPEC 7.4, 18.4): line two reads `sent Rose to Mia` and the pill has a 2 px border in the receiving side's colour (the bar's accent / coin colour, or the new `rememberGiftRoom(sideColors = ...)`, the same pair you give `GiftBattleBar`). Only in a battle with two sides; every other notice looks as before. `GiftEffectEvent.receiver` is new for apps that play their own events. The user's own gift says who got it too: `rememberGiftTrayHolder(receiverOf = room::receiverFor)` (new `RoomClient.receiverFor`, `GiftRoom.receiverFor`). The border is a 2 px ring in the side colour plus a 1 px line in the text colour inside it, so it shows on a pill of the same colour; a gift only counts as a battle gift inside the round; a combo counts per receiver.

## 0.1.2

No code change. The shared version moved with the web, React Native and iOS trays, whose "Test mode"
badge no longer touches the drag handle (SPEC 9.1); this tray already matched.

## 0.1.1

- Leaderboard polling is at least 5,000 ms (SPEC 16.4, audit R-17): `GiftLeaderboard(refreshIntervalMs = ...)`
  raises a smaller value to 5,000. New core `leaderboardPollMs` and `LEADERBOARD_MIN_POLL_MS`, tested
  with the `pollMs` fixture. 0.1.0 polled at exactly the value it was given.
- The four SDKs (JavaScript, Flutter, Android, iOS) share one version number from now on.

## 0.1.0 (preview)

First release on Maven Central. Everything below was built before it; the API can still change before 1.0.

### tray scrim, open state and the Gift button (SPEC 9.4); room socket RFC 6455 rules (2026-11-04)

- SPEC 9.4, off or unchanged by default: `GiftTray(scrim, scrimTap = ScrimTap.Lower / .Dismiss, onDismiss, open)`; the holder (`rememberGiftTrayHolder(open = ..., onOpenChange = ...)`, `GiftTrayHolder`) has `open()`, `close()`, `toggle()` (each returns the new state) and `isOpen` (snapshot state). Core (`core/Scrim.kt`): `SCRIM_FADE_MS` 200, `SCRIM_OPACITY` 0.4, `scrimVisible`, `scrimFadeMs`, `scrimTapOutcome`, `TrayOpenState`. The dim is black at 0.4, fades in with the sheet's entrance (instant with remove animations), is hidden at peek, takes touches only while visible (button "Close gift tray"). A closed tray is not composed: invisible, no touches, out of the accessibility tree, `onInsetChange(0)`; closing resets the sheet to `initialSnap` with a jump. A dismissal closes the holder first (unless `open` is passed) and then calls `onDismiss`.
- The demo uses `scrim = true`, `scrimTap = Dismiss` and `tray.toggle()`; its hand-written dim, outside tap and snap controller are gone. The dim now follows the system "remove animations" setting like the sheet (not the dev menu's motion override) and is 0.4 black.
- Tests: `TrayScrimConformanceTest` (`tray-scrim.json`), `FixtureCoverageTest`. Nothing was compiled or run with Gradle.
- Room socket (RFC 6455): a masked server frame, a continuation frame with nothing to continue, a data frame inside a fragmented message, a fragmented or longer-than-125-byte control frame and a one-byte close payload are protocol errors (1002); a text message that is not UTF-8 is 1007; a close frame without a status is reported as 1006 (like Flutter). `RoomSocketTest` has the cases.

### "Test mode" shows by itself, transport rules, release setup (audit R-07, R-08, R-09, R-13, R-25) (2026-11-03)

- Owner bug: the "Test mode" badge never showed because the host had to pass `testMode`. `GiftTray(testMode: Boolean? = null)`: `null` follows the token, `true` / `false` force it. New `GiftTray(tray = holder)` takes gifts, balance, Send and the badge from a `GiftTrayHolder` (`gifts`, `balance`, `onSend` are nullable now and win when given; the three or a `tray` are required). With neither, the badge follows any `rememberGiftTrayHolder` that reported `me.livemode == false` (a snapshot registry, removed when the holder leaves the composition). The demo's `MockClient.getMe` answers `livemode = false`. The header is narrow-safe (title: 2 lines at most, badge: one line, never overlapping the balance).
- R-07: `GiftingClient(baseUrl)` and the rooms `url` (`RoomClientOptions`, `GiftRoomOptions`, `rememberGiftRoom`) refuse a plain `http://` / `ws://` URL unless the host is `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` or `allowInsecure = true` (new last parameter / option): `IllegalArgumentException` at construction, also when `RoomClient.setOptions` replaces the url (SPEC 3.1). The real socket (`javaRoomSocketFactory(allowInsecure)`) closes 1006 `insecure_url` for such a URL as a second line of defence.
- R-08 / R-25 (SPEC 7.6, new `pictures.json`): core `isPictureUrl`, `PictureFailures`, `PICTURE_MAX_BYTES`, `PICTURE_FAILURE_MEMORY_MS`; `DefaultGiftImageLoader` loads only such URLs (`https`, `http` to loopback, `data:image` base64), stops a download at 5 MiB, decodes with `inJustDecodeBounds` + `inSampleSize` (at most 1024 px a side and 4 MP), catches `Throwable` (also `OutOfMemoryError`), remembers a failure for 60 s (200 URLs), runs at most 4 downloads at once, and a cancelled download closes its connection (`cancelAll()`). It no longer installs a process-wide `HttpResponseCache`: `installDiskCache` is a deprecated no-op. `GiftTrayController.refresh` prefetches the icons only (SPEC 8 step 2, `tray.json`); `GiftTray` fetches the big picture of the selected gift.
- `GiftTrayController.pending` is an `AtomicInteger`.
- Follow-ups of the shared spec of the same day: `GiftingClient.sendGift` repeats ONE lost connection at once with the same key (R-18; not a `SocketTimeoutException`, not a GET, not a send with an empty key; `LostConnectionRepeatTest`, the new `client.json` cases); `RoomClient.reconnectNow()` never skips a 4008/4009 wait (R-15, the new `rooms-session.json` cases); `TrayConformanceTest` reads the `testMode` expectation.
- R-09: `api` for compose-ui, ui-graphics, foundation, the Compose BOM and kotlinx-serialization-json (their types are in the public API); publishing setup (`maven-publish`, `signing` from `SIGNING_KEY` / `SIGNING_PASSWORD`, sources and Javadoc jars, POM with MIT licence, scm, developer), coordinates `com.giftingstack:giftingstack:0.1.0`; the `../sdk-spec` fixtures are wired for the tests only and only when the folder exists. `explicitApi()` is not on (not verified without a build). Nothing is published.
- R-13: the demo's `tierOf` uses the SDK's `tierFor`. Docs: README install coordinates, `Long` money, five demo tabs, recipes are deployed.
- Tests: `SecureUrlTest`, `ImageLimitsTest` (decode bounds), `RoomSocketTest` (plain ws refused), `PicturesConformanceTest` (new fixture), `TestModeTest` (registry), `TrayConformanceTest` reads `testMode`; instrumented `GiftUiTest` (badge by itself, `tray =`, explicit false/true, narrow header, no overlap). Core compiled (frontend) with kotlinc 1.9.24 outside Gradle; nothing was built or run with Gradle.

### robustness (audit R-03, R-05, R-06, R-14, R-21) (2026-11-03)

- Rooms reconnect (SPEC 18.3, 18.5), one rule set on all five SDKs: jittered waits never below 500 ms (`ROOM_RETRY_FLOOR_MS`); after 12 failed attempts in a row the room is `Closed` with the reason `retries_exhausted` (`ROOM_MAX_ATTEMPTS`; no more endless loops on unknown codes, a deleted project or a failing token endpoint); 4011 (project suspended) closes without retry; a 4008 with `retry_after` waits longer each time (up to 5 minutes, `roomRateLimitedDelayMs`) and never gives up; the proactive token refresh is spread over 2 minutes (`RoomClientOptions.refreshJitterMs`, set by `GiftRoom`); a `getToken` that never answers ends the attempt after 20 s (`token_timeout`, `ROOM_TOKEN_MS`). `reconnectNow()` also restarts a room that stopped that way (`retries_exhausted`, 4011, the 4008/4009 limit); `GiftRoom.foreground()` now calls it after `resume()`. `RoomRetryDecision.Stop` is a class with `resumable` / `exhausted` (it was an object).
- A 2xx whose body is not JSON, or not what the model expects, is `GiftingException(status, "invalid_response", "Invalid response (200).")` with no body text and `retryable` false (fixture cases in `client.json`). `getToken` errors still propagate unchanged. The request timeouts stay 15 s to connect and 30 s to read (SPEC 3.4).
- Money is 64-bit (audit R-06): `Gift.price`, `Me.balance`, `GiftTransaction.unitPrice` / `total` / `senderBalanceAfter`, `EffectGift.price`, `AwayGift.price`, `InboxGift.price` and `GiftTrayState.balance` are `Long`; new `tierFor(Long)` and `sendButtonState(..., balance: Long)` (the `Int` overload stays). Quantities stay `Int` (the server caps a send at 1,000). BREAKING for apps that read these fields as `Int`. `ui/GiftTray.kt` still has `Int` money in `formatCoins`, the `balance` parameters and `PriceRow` / `CountUpText`; it has to move to `Long` too (see the lead's note) before the module compiles.
- `GiftTrayOptions.onSent` / `onError` (and the effect call of `PlayOn.Success`) run outside the send's failure handling: a callback that throws no longer refunds a send that went through.
- Tests: `RobustnessTest`; `rooms-reconnect.json`, `rooms-session.json` and `client.json` have the new cases. The core (not the Compose UI) was compiled with kotlinc 1.9.24 outside Gradle and its fixture suites passed (223 tests, with a stand-in for `kotlinx-coroutines-test`); nothing was built or run with Gradle, and the UI module and the demo were not compiled.

### gift inbox (SPEC 19) (2026-11-02)

- `GiftInbox(client, pageSize = 20, resolveUsers, onLoaded, handle, labels)` (`InboxLabels`, `rememberGiftInboxHandle`): who sent the signed-in user which gift in the last 24 hours, newest first, "Show more" appends the next page, reversed gifts hidden; one spoken sentence per row.
- Core: `InboxApi.getInbox(InboxQuery(cursor, limit))` (on `GiftingClient`), models `Inbox`, `InboxItem`, `InboxGift`; pure `inboxTimeLabel`, `inboxRows`, `inboxUnread` (+ `parseIsoTimeMs`, `inboxTimeSpoken`, `inboxRowText`); `InboxController` holds the paging.
- Fixture `conformance/inbox.json` runs in `InboxConformanceTest.kt`; paging in `InboxControllerTest.kt`. The demo's Inbox tab is the SDK composable, its badge uses `inboxUnread`.
- Not built with Gradle yet: nothing here was compiled or run.

### battle bar (SPEC 18.7) (2026-10-20)

- `GiftBattleBar(room | view, ...)` (`BattleBarUser`): the drawn versus bar, 1:1 with the web and React Native bars (avatars in rings, crown and gold ring for the winner, loser at half opacity, clock pill that turns urgent in the last 10 s and "Final", 16 dp split bar with a sliding boundary and a spark, banner, one spoken sentence). Theme, `sideColors`, `labels` (`BattleBarLabels`), reduced motion (`reducedMotion` or the system "Remove animations").
- Pure core: `battleBarModel`, `formatBattleScore`, `formatBattleClock`, `battleSideColors`, `battleGains`, `BattleBarLabels`.
- Fixture `conformance/battle-bar.json` runs in `BattleBarConformanceTest` (40 cases, passed on the JVM with Kotlin 1.9.24 outside Gradle); instrumented `GiftBattleBarUiTest` (needs a device). The demo's Live tab shows the bar on its pretend room (a round between Zoe and Mateo).
- Not built with Gradle yet: the Compose files (`GiftBattleBar.kt`, the demo) and the instrumented test were not compiled.

### render slots (2026-10-18)

- `GiftWall(renderChip)` (`WallChipContext`), `GiftLeaderboard(renderRow)` (`LeaderboardRowContext`), `GiftAwaySummary(renderSummary)` (`AwaySummaryContext`, `AwaySenderInfo`): nullable `@Composable` lambdas; null (default) draws the default, and `Default()` on the context draws the default for one item. Same names and fields as sdk-js (SPEC 16.5); the SDK keeps container, semantics, press and actions.
- `AwayTexts` also carries `gifts` and `people`.
- Tests: JVM test for the new `AwayTexts` parts; instrumented `RenderSlotsUiTest` (needs a device).

### battle scores (SPEC 17.8, 18.6) (2026-10-18)

- Headless client side of battle (versus) rounds: `parseRoomFrame` reads `scores` (`RoomServerMessage.Scores`) and `welcome.battle` (`Welcome.battle`), models `RoomBattle`,
  `RoomScoreEntry`; pure `battleView(battle, serverNow)` (`BattleView`, `BattleSide`: shares, leader or null on a tie, `open`, `remainingMs`, `total`, sides in server order).
- `RoomClient`: `battle` (`StateFlow<RoomBattle?>`), `getBattle()`, `serverNow()`, `getBattleView()`, option `onBattle`. The round survives a reconnect until the next welcome.
- `GiftRoom` (holder): `battle`, `battleView()`, `GiftRoomOptions.onBattle`; `rememberGiftRoom(onBattle = ...)`. No UI component.
- Fixture `conformance/rooms-battle.json` (moved up from `pending-native/`) runs in `RoomsConformanceTest.kt`; session tests in `RoomsBattleTest.kt`.

### "Test mode" badge (SPEC 9) (2026-10-17)

- `Me.livemode` (`GET /v1/client/me`; null from older servers) and the tray state's `testMode`
  (`livemode == false`: the token was made with a test key; the test environment allows 50 users and
  5,000 operations a month).
- `GiftTray(..., testMode, testModeLabel)` (last parameters) shows a "Test mode" badge after the title; pass `GiftTrayState.testMode`.

### gift wall, "while you were away", leaderboard (SPEC 14-16) (2026-10-12)

- Core (pure Kotlin): `wallChips`, `formatCount`, `GiftWallLoader`, `planAwayReplay`, `awaySenderLabel`, `AwayController`, `LeaderboardController`,
  `pinnedMe`, `leaderboardRankLabel`, `RANK_COLORS`, `GiftLabels` with the visible and spoken text helpers, `Timers`; models `GiftWall`, `AwaySummary`,
  `Leaderboard` and friends. Client: `queryGiftWalls`, `getAway`, `ackAway` (204, nothing parsed), `getLeaderboard`, `getReceivedGifts(user, reference)`,
  behind `GiftWallApi`, `AwayApi` and `LeaderboardApi` (`GiftingApi` is unchanged).
- UI: `GiftWall`, `GiftAwaySummary` (card plus replay through `GiftEffectLayerState`) and `GiftLeaderboard`, with `GiftingTheme`, semantics per the design
  doc and reduced motion. New dependency: `androidx.lifecycle:lifecycle-runtime-compose` (foreground check of the away card).
- Demo: the wall under the post (10 kinds, updated after a send), the away card and a leaderboard panel with mock data, behind labelled "(demo)" buttons;
  the debug buttons are now one wrapping group.
- Tests: runners for `wall.json`, `away.json`, `leaderboard.json` and their `client` sections (the fixtures are Gradle inputs), `FixtureCoverageTest` (fails for a
  conformance file without a runner; `placement.json` is web only), 24 rule tests, 6 more demo tests; 392 + 14 JVM tests pass. 9 instrumented Compose tests are
  written and compile but were NOT run (no emulator). The components were not looked at on a screen.
- `away.json#client` "getAway with since and maxGroups" now writes the gift objects the API sends (it used to write `"gift": "dragon"`); the runner
  compares its request and its parsed result like every other client scenario. The request-only special case and its counter test are gone: the JS
  runner now rejects any `client` 2xx body that does not match the typed models.
- 24 mutations of the new rules, all caught (see the README).

### brought up to the current shared contract (2026-10-11)

- Core: `TraySheetController` and `resolveSheetHeights` (peek/default/expanded, 90 % expanded, flick at 600 units/s,
  nested scroll hand-off, inset), `GiftThemeTokens` with dark/light presets and `themeFromAccent` (4.5:1),
  remote recipes (`parseRemoteRecipes`, `mergeRecipeSet`, `remoteRecipesUrl`, `RecipesLoader` with injectable fetch and
  storage, backoff, 6 h refresh, 3 s timeout, single flight), `pictureScale`. `EffectScheduler` reads a recipe set at each
  `play`; running effects keep their recipe.
- UI: `GiftTray` is a draggable bottom sheet by default (`sheet = false` keeps the fixed tray; behaviour change: it now
  overlays its parent), bigger icons, `GiftingTheme` presets and `fromAccent`, three new tokens, `GiftEffectLayer`
  `pictureScale`, `remoteRecipes`, `recipesVersion`, `recipesUrl`; `thresholds` is nullable (null = not given).
- Demo: coin store that adds coins, "Reset (demo)", "Incoming: same as tray / random", about 90 gifts from the live library.
- Tests: new fixtures (sheet, theme, remote-recipes) run; `placement.json` skipped (web only); Gradle now treats the
  fixtures as test inputs (a changed fixture no longer replays a cached green result); CI also runs the demo's unit tests.

### First build, for spec version 1.0.0

First version of the Android SDK (Kotlin, Jetpack Compose), for spec version 1.0.0.

- Pure Kotlin core in `com.giftingstack.core`: models, `GiftingException`, `GiftingClient` with an
  injectable `GiftingTransport`, `ComboTracker`, tiers and recipes, `EffectScheduler`,
  `GiftTrayController` and `sendButtonState`, ported from `packages/sdk-js/src/core`.
- Compose UI in `com.giftingstack.ui`: `GiftEffectLayer` with `GiftEffectLayerState`, notice with
  combo counter, `GiftTray`, `GiftTrayHolder`, `GiftingTheme`, a small picture loader.
- Demo app (`demo`) that mirrors the web demo.
- Tests: every file in `packages/sdk-spec/conformance` runs on the JVM, plus a spec drift test and
  instrumented Compose tests (picture gate and layer behaviour).
