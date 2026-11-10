# Changelog

## 0.1.3 (preview)

- With `scrim` on, a tap on the empty space beside a tray at peek (the small state) now closes it: the dim stays hidden there, but it takes the tap (SPEC 9.4, `scrimTakesTouches`; a tall tray still lowers to peek first with `scrimTap` "lower"). The page behind a peeking tray is no longer touchable while the tray is open; leave `scrim` off for that.
- A battle can have three to eight sides (SPEC 18.7, a free-for-all: everybody races on their own; teams are not part of it). The battle bar draws every side: two sides look exactly as before, three or more get a row of cells (avatar, name, score) with the clock above and a bar of proportional segments (each side in its colour, none under 6 %, white lines between them); the winner, the banner and the spoken sentence cover every side. `sideColors` is a list with one colour per side (`GiftBattleBar`, `GiftRoomModel`) (a shorter list keeps the default for the sides it does not name; the default palette is the theme's accent, its coin colour, then teal `#2ec4b6` and pink `#ff5d8f`, then the same four again). The gift notice of a battle names the receiver and borders its pill for every side, not only the first two. New: `battleSidePalette`, `battleSegmentPcts`, `BattleBarModel.pcts`.
- The tray opens as softly as Flutter's (SPEC 9.4): the sheet fades in over 200 ms while rising from 3 % of its height below its place over 220 ms, and the snaps use the same critically damped spring (stiffness 320, damping 36). Reduced motion: none of it.

- The gift notice of a battle says who got the gift (SPEC 7.4, 18.4): line two reads `sent Rose to Mia` and the pill has a 2 px border in the receiving side's colour (the bar's accent / coin colour, or the new `GiftRoomModel(sideColors:)`, the same pair you give `GiftBattleBar`). Only in a battle with two sides; every other notice looks as before. `GiftEffectEvent.receiver` is new for apps that play their own events. The user's own gift says who got it too: `GiftTrayModel(receiverOf: room.receiverFor)` (new `RoomClient.receiverFor`, `GiftRoomModel.receiverFor`). The border is a 2 px ring in the side colour plus a 1 px line in the text colour inside it, so it shows on a pill of the same colour; a gift only counts as a battle gift inside the round; a combo counts per receiver.
- A tray opened again for the same receiver (`toggle()` or `open()` after a close) now shows its sheet. It
  stayed open but invisible: the delayed show read the previous render's closed state. Meanwhile the hidden
  sheet reported its height (notices moved up over nothing) and took the touches meant for the screen
  behind it; an unseen sheet now takes no touches, and an open tray is shown after 700 ms at most.

## 0.1.2 (preview)

- The tray's "Test mode" badge no longer touches the drag handle: the header starts right below the
  handle (SPEC 9.1). The sheet is a few points taller; its heights are measured, so nothing else changes.

## 0.1.1 (preview)

First release as a Swift package, together with the JavaScript, Flutter and Android SDKs (all four
share one version number from now on). The package was built and tested on a macOS runner for the
first time: everything below was written before that, without a Swift compiler. It now builds on
macOS and for the iOS Simulator and passes all 156 tests (every fixture of the shared contract).
The API can still change before 1.0.

- Compile fixes found by the first build: a Swift keyword (`repeat`) used as a variable name in
  `GiftingClient`, a spacing error in `GiftTrayModel`, lost string interpolation in
  `SecureURL.refusalMessage`.
- Leaderboard polling is at least 5,000 ms (SPEC 16.4, audit R-17): `leaderboardPollMs` and
  `leaderboardMinPollMs`, tested with the `pollMs` fixture; `GiftLeaderboardModel` uses it.
  Before this a tiny `refreshIntervalMs` polled that fast.
- The README states the real verification status and the Swift Package Manager install.

### tray scrim, open state and the Gift button (SPEC 9.4) (2026-11-04)

- Off or unchanged by default: `GiftTray(scrim:scrimTap:onDismiss:open:)` (both initialisers), `ScrimTap` `.lower` / `.dismiss`; `GiftTrayModel(open:onOpenChange:)` with `open()`, `close()`, `toggle()` (each returns the new state) and `isOpen` (published). Core (`Core/Scrim.swift`): `scrimFadeDurationMs` (SCRIM_FADE_MS, 200), `scrimOpacity` (SCRIM_OPACITY, 0.4), `scrimVisible`, `scrimFadeMs(reducedMotion:)`, `scrimTapOutcome`, `TrayOpenState`. The dim is black at 0.4, fades in with the sheet (200 ms, instant with Reduce Motion), is hidden at peek, takes touches only while visible (button "Close gift tray"). A closed tray is invisible, takes no touches, is hidden from VoiceOver and reports inset 0; closing resets the sheet to `initialSnap` with a jump. A dismissal closes the `tray` model first (unless `open` is passed) and then calls `onDismiss`.
- The demo uses `scrim: true`, `scrimTap: .dismiss` and `tray.toggle()`; its hand-written dim, outside tap and `GiftTrayHandle` use are gone. The dim is now 0.4 black (was 0.35) and fills the tray's area, which the demo extends under the status bar.
- Tests: `TrayScrimConformanceTests` (`tray-scrim.json`), `FixtureCoverageTests`. Nothing was compiled or run here (no Swift available).

### "Test mode" shows by itself, transport rules, privacy manifest (audit R-07, R-08, R-10, R-29, R-30) (2026-11-03)

- Owner bug: the "Test mode" badge never showed because the host had to pass `testMode`. `GiftTray(testMode: Bool? = nil)`: `nil` follows the token (any live `GiftTrayModel` that reported `me.livemode == false`, via an internal observable registry; a model's report goes away on `stop()` and on release), `true` / `false` force it. New `GiftTray(tray: model, ...)` initialiser takes gifts, balance, Send and the badge from a `GiftTrayModel` (the three are optional and win when given). The demo's `MockGiftingClient.getMe` answers `livemode: false` and its tray uses `tray:`. Header: the title is at most two lines, the badge never wraps.
- R-07 (SPEC 3.1): `GiftingClient(baseURL:)` and `RoomClient.url` (`GiftRoomModel(url:)`) with a plain `http://` / `ws://` host that is not `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` stop the app with a `precondition` failure that names `allowInsecure`, unless `allowInsecure: true` (new last parameter of `GiftingClient.init`, `RoomClient.init`, `GiftRoomModel.init`; `RoomClient.allowInsecure` is a property). `urlSessionRoomSocketFactory(allowInsecure:)` also refuses such a socket. The same rule: 127.0.0.2 and `localhost@evil` are not loopback.
- R-08 (SPEC 7.6, new `pictures.json`): core `isPictureUrl`, `PictureFailures`, `pictureMaxBytes`, `pictureFailureMemoryMs`; `GiftImageCache` loads only such URLs (`https`, `http` to loopback, `data:image` base64), stops a download at 5 MiB (declared and streamed), decodes as a thumbnail (`kCGImageSourceThumbnailMaxPixelSize` 1024), remembers a failure for 60 s (200 URLs), `cancelAll()`. `GiftTrayController.refresh` prefetches the icons only (SPEC 8 step 2, `tray.json`); `GiftTray` fetches the big picture of the selected gift.
- R-10: `PrivacyInfo.xcprivacy` (no tracking, no collected data, `NSPrivacyAccessedAPICategorySystemBootTime` / 35F9.1 for `ProcessInfo.systemUptime`), declared as a resource in `Package.swift`.
- R-29: `SystemGiftClock.schedule` clamps the wait (1e12 ms) before converting to nanoseconds: a huge `retry_after` no longer overflows and traps.
- R-30: `URLSessionTransport` cancels the URLSession task when the calling `Task` is cancelled (it used to run on until the timeout). Not changed (uncertain): mapping a cancelled call to `network_error` instead of `CancellationError`, URL cache and cookie settings of the default session, redirect handling.
- Follow-ups of the shared spec of the same day: `GiftingClient.sendGift` repeats ONE lost connection at once with the same key (R-18; not `URLError.timedOut`, not a GET, not a send with an empty key; `LostConnectionRepeatTests`, the new `client.json` cases); `RoomClient.reconnectNow()` never skips a 4008/4009 wait (R-15, the new `rooms-session.json` cases); `TrayConformanceTests` reads the `testMode` expectation.
- An EMPTY catalog no longer leaves the sheet invisible: the gate uses `SheetMeasure.floorsReady` (a row is only needed when there are gifts), and a 700 ms fallback shows the sheet when no row was measured (like web).
- README: the render-slot sample compiles (the string interpolation backslashes were missing), rooms and recipes are deployed, transport rules.
- Tests: `SecureURLTests`, `PicturesConformanceTests` (new fixture, also in `FixtureCoverageTests`), `GiftImageCacheTests` (URLProtocol stub: 404 memory, 5 MB cap, thumbnail, data URL), `TestModeBadgeTests`, `ClockLimitTests`, `SheetMeasureTests` (empty catalog), `TrayConformanceTests` reads `testMode`. Nothing was compiled or run here (no Swift available).

### robustness (audit R-03, R-04, R-05, R-21) (2026-11-03)

- Rooms reconnect (SPEC 18.3, 18.5), one rule set on all five SDKs: jittered waits never below 500 ms (`roomRetryFloorMs`); after 12 failed attempts in a row the room is `closed` with the reason `retries_exhausted` (`roomMaxAttempts`; no more endless loops on unknown codes, a deleted project or a failing token endpoint); 4011 (project suspended) closes without retry; a 4008 with `retry_after` waits longer each time (up to 5 minutes, `roomRateLimitedDelayMs`) and never gives up; the proactive token refresh is spread over 2 minutes (`RoomClient.refreshJitterMs`, set by `GiftRoomModel`); a `getToken` that never answers ends the attempt after 20 s (`token_timeout`, `roomTokenMs`). `reconnectNow()` (also `GiftRoomModel.reconnectNow()`) restarts a room that stopped that way (`retries_exhausted`, 4011, the 4008/4009 limit). `RoomRetryDecision.stop` now carries `resumable` and `exhausted` (use `.stop()`).
- `GiftingClient(timeout:)` (default 20 s) and `URLSessionTransport(timeout:)`: the default transport builds its own session whose `timeoutIntervalForRequest` and `timeoutIntervalForResource` are the timeout (0 keeps the URLSession defaults); a slower attempt is the same `network_error` as a lost connection, never retried. `URLSessionTransport(session:)` keeps the session you pass; `GiftingClient(transport:)` is now optional.
- A 2xx whose body is not JSON, or not what the model expects, is `GiftingError(status:type: "invalid_response", message: "Invalid response (200).")` with no body text and `retryable` false (it used to throw the decoder's error). Fixture cases in `client.json`.
- Not applicable here: R-06 (Swift `Int` is 64-bit) and R-14 (the tray callbacks are non-throwing closures).
- Tests: `ClientRobustnessTests`; `rooms-reconnect.json`, `rooms-session.json` and `client.json` have the new cases. Written without a compiler: unverified until the "SDK iOS" workflow builds and tests it.

### gift inbox (SPEC 19) (2026-11-02)

- Core: `getInbox(_ query: InboxQuery)` / `getInbox()` on `GiftingClient` and the new `GiftInboxAPI` protocol (`GET /v1/client/me/inbox`, query `cursor` then `limit`), models `Inbox`, `InboxItem`, `InboxGift`, `InboxQuery`, and the pure helpers `inboxTimeLabel`, `inboxRows` (`InboxRow`), `inboxUnread` in `Core/Inbox.swift`.
- UI: `GiftInboxModel` (load / refresh / loadMore, `resolveUsers`, `pageSize` 20, `onLoaded`) and `GiftInbox` (loading, empty, error with "Try again", "Show more", reversed gifts hidden, one VoiceOver element per row). New `GiftLabels` fields: `inboxSentYou`, `inboxQuantity`, `inboxEmpty`, `inboxError`, `showMore`.
- Fixture `conformance/inbox.json` runs in `InboxConformanceTests`; `GiftInboxModelTests` covers the model with a fake client. The Pixel demo's Inbox tab now shows `GiftInbox` over `MockGiftingClient.getInbox` (badge via `inboxUnread`). Written without a compiler: unverified until the "SDK iOS" workflow builds and tests it.

### battle bar (SPEC 18.7) (2026-10-20)

- `GiftBattleBar(room:)` / `GiftBattleBar(view:)` (`BattleBarUser`): the drawn versus bar, 1:1 with the web and React Native bars (avatars in rings, crown and gold ring for the winner, loser at half opacity, clock pill that turns urgent in the last 10 s and "Final", 16 pt split bar with a sliding boundary and a spark, banner, one VoiceOver element). Theme, `sideColors` (two `#rrggbb`), `labels` (`BattleBarLabels`), Reduce Motion (`reducedMotion` or the system setting). iOS 15 APIs only.
- Pure core (`Core/BattleBarLogic.swift`): `battleBarModel`, `formatBattleScore`, `formatBattleClock`, `battleSideColors`, `battleGains`, `BattleBarLabels`.
- Fixture `conformance/battle-bar.json` runs in `BattleBarConformanceTests`. The Pixel demo's Live tab now uses the SDK bar instead of its own drawing.
- Written without a compiler: unverified until the "SDK iOS" workflow builds and tests it.

### render slots (2026-10-18)

- `GiftWall(renderChip:)` (`WallChipContext`), `GiftLeaderboard(renderRow:)` (`LeaderboardRowContext`), `GiftAwaySummary(renderSummary:)` (`AwaySummaryContext`, `AwaySenderInfo`): closures returning `AnyView?` (nil draws the default; no existing call site changes). Same names and fields as sdk-js (SPEC 16.5); the SDK keeps container, accessibility, press and actions.
- Tests: `RenderSlotTests` (contexts and slot closures). Written without a compiler: unverified until CI runs.

### Live tab in the Pixel demo (2026-10-18)

- Demo only (`Demo/Sources`, the library is unchanged): a Live tab like the web demo's. `DemoFakeRoom.swift` is a pretend rooms server (`RoomSocket` through the existing `GiftRoomModel(socket:)` factory seam) that speaks the real protocol: `hello` -> `welcome` (viewers, battle), others' gifts every 4-9 s (1 in 6 a combo of five), viewer drift, battle rounds with `scores` at most every 250 ms, no frame at round end, a new round after a break, and `publish` for the demo's own sends (`room_id`). `PixelLiveTab`: stream art, LIVE tag, "N watching", Mia vs Theo battle bar from `battleView()`, Gift Mia / Gift Theo (tray with `roomId`), room feed, effects through `GiftEffectLayer`. The demo has no test target, so the fake room has no unit tests. Written without a compiler: unverified until the "SDK iOS" workflow builds it.

### battle scores (SPEC 17.8, 18.6) (2026-10-18)

- Headless client side of battle (versus) rounds: `parseRoomFrame` reads `scores` (`RoomServerMessage.scores`) and `welcome.battle` (`RoomWelcomeMessage.battle`), models `RoomBattle`,
  `RoomScoreEntry`; pure `battleView(_:serverNow:)` (`BattleView`, `BattleSide`: shares, leader or nil on a tie, `open`, `remainingMs`, `total`, sides in server order).
- `RoomClient`: `battle`, `subscribeBattle(_:)`, `serverNow()`, `battleView()`, `onBattle`. The round survives a reconnect until the next welcome.
- `GiftRoomModel`: `@Published battle`, `battleView()`, `onBattle`. No UI component.
- Fixture `conformance/rooms-battle.json` (moved up from `pending-native/`) runs in `RoomsConformanceTests.testBattle`; session tests in `RoomBattleSessionTests`. Written without a compiler: unverified until CI runs.

### "Test mode" badge (SPEC 9) (2026-10-17)

- `Me.livemode` (`GET /v1/client/me`; null from older servers) and the tray state's `testMode`
  (`livemode == false`: the token was made with a test key; the test environment allows 50 users and
  5,000 operations a month).
- `GiftTray(..., testMode:, testModeLabel:)` (last parameters) shows a "Test mode" badge after the title; pass `GiftTrayModel.testMode`.

### gift rooms (spec 17-18)

Ports the client side of gift rooms from `packages/sdk-js/src/core/rooms.ts`. Written without a
compiler: nothing here has been built, tested or run on a device.

- Pure core `Core/Rooms.swift`: `parseRoomFrame` (incl. `batch`), `roomHelloFrame`, `roomUrl`,
  `roomTokenUser`, `roomRetryDecision`, `RoomEventFilter`, `roomGiftToEffect`, `RoomClient`
  (injected socket factory, `GiftClock`, random source, `getToken`).
- Transport `URLSessionRoomSocket` (`URLSessionWebSocketTask`, protocols `gs.v1` + token, protocol
  pings) and SwiftUI `GiftRoomModel` (plays room gifts in a `GiftEffectController`, closes in the
  background, resumes in the foreground, `inactive` keeps the socket).
- `roomId` on `SendGiftInput` (`room_id` in the body), `GiftTrayController` and `GiftTrayModel`.
- Tests: `RoomsConformanceTests` runs the five `rooms-*.json` fixtures (the filter's `batch` step,
  `quantity` where the session fixture lists it); `GiftRoomModelTests` drives the model with a
  fake socket. `FixtureCoverageTests` no longer acknowledges the rooms files as pending.

### 0.3.0 (earlier work)

Ports the three components of spec sections 14-16 (gift wall, "while you were away",
leaderboard) from the reference (`packages/sdk-js/src/core/{wall,away,leaderboard}.ts`). Written
without a compiler: nothing here has been built, tested or run on a device.

- Client: `getReceivedGifts(_:reference:)` (`?reference=` only when given), `queryGiftWalls`
  (POST, no idempotency key, empty list = no request), `getAway(_:)` (`since`, `max_groups`),
  `ackAway(_:)` (PUT; a 204 body is never parsed), `getLeaderboard(_:query:)` (`period`, `metric`,
  `at`, `limit`, `include_me=false` only). New protocols `GiftWallAPI`, `GiftAwayAPI`,
  `GiftLeaderboardAPI`; `GiftingAPI` keeps its four calls. Internally the attempts of spec 3.4
  moved into `perform`, shared by decoding calls and the 204 call. Models in `ComponentModels.swift`
  (`GiftWallResult` (the wire model; `GiftWall` is the SwiftUI view), `AwaySummary`, `AwayGroup`, `Leaderboard`, `LeaderboardMe`, ...).
- Pure core: `wallChips`, `formatCount`, `GiftWallLoader` (50 ms window, batches of 25, 60 s cache,
  in-flight sharing, invalidate generations), `awaySenderLabel`, `planAwayReplay`,
  `awayCardDurationMs`, `AwayController`, `leaderboardRankLabel`, `groupThousands`, `pinnedMe`,
  `LeaderboardController`, `GiftRankColors`, `GiftLabels`, `fillLabel`. `GiftClock` /
  `SystemGiftClock` inject time and timers.
- SwiftUI: `GiftWall` (takes the shared `GiftWallLoader`), `GiftAwayModel` + `GiftAwaySummary`
  (card + replay through `GiftEffectController`, foreground check via `scenePhase`),
  `GiftLeaderboardModel` + `GiftLeaderboard` (tabs, metric switch, medal discs, pinned row,
  polling with `refreshIntervalMs`). Reduced motion and VoiceOver as in the README.
- Tests: `WallConformanceTests`, `AwayConformanceTests`, `LeaderboardConformanceTests` run every
  case of the three fixtures and their `client` sections and fail on unknown keys; the client
  scenario runner moved to `Support/ClientScenarioRunner.swift` (shared with client.json);
  `FixtureCoverageTests` now demands runners for the three files. The away `client` section runs
  like every other client scenario (full request and parsed result): its fixture now writes the
  gift objects the API sends (2026-10-12; it used to write `"gift": "<id>"`, which the runner
  had to expand).
- Demo rebuilt as "Pixel", the same pretend app as the web demo: tabs
  Feed / Top / Inbox / Me in plain SwiftUI, a Gift button per post (tray for the author,
  `reference` = post id, closes after a send), walls per post and on the profile, a coin store
  that adds, an offline banner, the away card once after install. No debug buttons on screen:
  a developer menu opens on a 1 s hold of the logo. Mock data now matches the web demo. Written
  blind: not compiled yet.

### 0.2.0 (earlier work)

Catches up with the shared contract of 2026-10-11 (`sheet.json`, `theme.json`,
`remote-recipes.json`; `placement.json` is web only and acknowledged). Written without a compiler;
CI has not run it yet.

- Bottom sheet (spec 9.1): pure `TraySheetController` and `resolveSheetHeights` (peek / default /
  expanded at 90 %, flick at 600 pt/s, ties to the more open state, nested scroll owner, inset),
  `SheetVelocityTracker`; `GiftTray` is a draggable sheet by default (`sheet: false` keeps the old
  tray) with `initialSnap`, `snaps`, `onSnapChange`, `onInsetChange`, VoiceOver adjust and custom
  actions on the handle. Icons are `min(72 pt, 78 % of the cell)` like the web.
- Themes (spec 9.2): pure `GiftTheme` (17 tokens), `darkTheme`, `lightTheme`, `themeFromAccent`
  (4.5:1 contrast rule), `contrastRatio`; `GiftingTheme` gains `coinText`, `selected`, `comboText`
  (were fixed colours), `.dark`, `.light`, `fromAccent`, `init(GiftTheme)`.
- Remote recipes (spec 13): `parseRemoteRecipes`, `mergeRecipeSet`, `remoteRecipesUrl`,
  `RemoteRecipesLoader` (injectable transport and storage, in-memory default, 3 s timeout, 6 h
  refresh, backoff, one request in flight). `EffectScheduler.recipes`; the recipe is fixed at
  `play`. Layer options `remoteRecipes`, `recipesVersion`, `recipesUrl`.
- Source changes: `EffectScheduler.thresholds`, `GiftEffectController.thresholds` and the layer's
  `thresholds` are now optional (nil = the recipe set's); `comboWindowMs` parameters are optional
  (nil = the recipe set's); `ComboTracker.windowMs` is a `var`; `recipeFor(_:quality:set:)`.
- Effect layer: the picture and spark spread grow with the layer like the web (`pictureScale`,
  `EffectTimeline.pictureScale`).
- Demo: about 90 gifts from the live library (12-gift fallback), the sheet tray, a pretend coin
  store that ADDS coins, "Reset (demo)", "Incoming: same as tray / random / a gift", x5 combo,
  theme switch.
- Tests: runners for `sheet.json`, `theme.json`, `remote-recipes.json`, the SPEC 13.3 limits table,
  loader tests, and a coverage test that fails on a fixture file without a runner.
- Sheet fixes after the first iPhone test of a 0.2.0 build (written blind, not compiled or tested
  on a device yet; `TraySheet.swift` and `sheet.json` unchanged):
  - Expanded stopped below 90 %: the layout was re-run from `onChange(of: gifts.count)`, whose
    action can still see the previous render's `gifts`, so after the demo's 12 fallback gifts were
    replaced by ~90 the content cap stayed at 3 rows. All inputs now form one `SheetMeasure` value
    applied from `onChange(of: measure)` using only the new value. As on Android the container
    counts as 0 until header, footer and a row are measured; the header block is measured at its
    natural height; the row height comes from the first row.
  - Erratic grid scrolling: momentum was a 0.45 s SwiftUI animation of the scroll value, so a new
    touch started from the animation's end (a jump) and `scrollOwner` saw that end as the scroll
    position. Momentum now runs frame by frame in `TraySheetModel` (decay 0.998 per ms, stopped by
    the next drag or a tap, which then does not select); the finger velocity comes from the same
    tracker as the sheet's. A drag cancelled without `onEnded` left `sheetDrag` and the
    controller's `dragging` set (the next drag jumped by the old translation, taps were blocked);
    a `@GestureState` reset and a start-location check now close it with `cancel()`.
  - The plain-rows grid used `ForEach(..., id: .self)` (missing backslash), which does not
    compile; now `\.self`.
  - New pure `SheetMeasure` and `SheetGridMomentum` (Core) with `SheetMeasureTests`.

### 0.1.0 (first build)

First version, written against spec 1.0.0 (`packages/sdk-spec`). Compiled by CI for the first time
in a later release.

- Core (Foundation only): models with snake_case JSON keys, `GiftingError`, `GiftingClient` with
  an injectable `GiftingTransport` (`HTTPTransport`) and a `URLSession` default, token refresh on
  401, one 5xx retry with the same idempotency key, `encodeURIComponent`-exact user ids.
- Tiers and recipes generated from `recipes.json` (`tool/generate-spec-data.mjs`), `ComboTracker`,
  `EffectScheduler`, `PictureGate`, `EffectTimeline`, `GiftTrayController`, `sendButtonState`.
- SwiftUI: `GiftEffectLayer` + `GiftEffectController`, notice with combo counter, `GiftTray`,
  `GiftTrayModel`, `GiftImageCache` with prefetch and decode ahead, `GiftingTheme`.
- Tests: a runner for every conformance fixture, a recipes drift test, state holder tests.
- Demo app sources mirroring the web demo.
