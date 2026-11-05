# Changelog

## 0.1.1

No code change. The four SDKs (JavaScript, Flutter, Android, iOS) share one version number from now
on; Android and iOS gained the 5,000 ms leaderboard polling minimum this package already had.

## 0.1.0 (preview)

First release on pub.dev. Everything below was built before it; the API can still change before 1.0.

### audit 2026-10-25 fixes, publishing readiness (2026-11-03)

- **Test mode badge by itself**: `GiftTray(tray: notifier)` takes the gifts, balance, Send and `testMode` from the
  `GiftTrayNotifier` and rebuilds when it changes; the badge shows while `me.livemode == false` (a test key).
  `GiftTray.testMode` is now `bool?`: null follows the notifier, `false` forces it off, `true` forces it on; `gifts`,
  `balance` and `onSend` are optional when `tray` is given and win over it. The example's mock `getMe` answers
  `livemode: false`.
- **Plain-text URLs refused (R-07)**: `GiftingClient(baseUrl:)` and `RoomClientOptions.url` throw an `ArgumentError` for
  `http://` / `ws://` unless the host is `localhost`, `127.0.0.1`, `::1` or `10.0.2.2`, or `allowInsecure: true`
  (`GiftRoom(allowInsecure:)`). Helpers `urlHost`, `isLoopbackHost`, `isInsecureUrl`, `assertSecureUrl`.
- **Pictures (R-08)**: `GiftNetworkImage` (the default image provider) loads only `https://`, `data:image/` and loopback
  `http://`, stops a download over 5 MB, and remembers a failed picture for 60 s (`PictureFailures`, `isPictureUrl`,
  `pictureMaxBytes`). `GiftTrayController` prefetches the small icons only; the tray warms the selected gift's big picture.
- `sendGift` repeats a lost connection once with the same idempotency key (not a timeout) (R-18).
- `reconnectNow()` never skips a 4008/4009 wait (R-15). `leaderboardPollMs`: `refreshIntervalMs` is at least 5,000 (R-17).
- The package compiles for Flutter web (R-24): the `dart:io` room transport sits behind a conditional import; on web pass
  `GiftRoom(socket: ...)`.
- Fix: a sheet tray with an empty catalog now becomes visible (it waited for a measured first row).
- Publishing: `publish_to` removed, description, `homepage`, `repository`, `issue_tracker` and `topics` set, `.pubignore`
  (docs, tool, example build output). `flutter pub publish --dry-run` reports only the git state.
- New fixtures: `pictures.json`, `tray.json` (`testMode`, icons-only prefetch), `client.json` (lost-connection repeat),
  `rooms-session.json` (rate-limit waits), `leaderboard.json` (`pollMs`).

### robustness (audit R-03, R-04, R-05, R-14, R-21) (2026-11-03)

- Rooms reconnect (SPEC 18.3, 18.5), one rule set on all five SDKs: jittered waits never below 500 ms; after 12 failed attempts in a row the room is `closed` with the reason `retries_exhausted` (no more endless loops on unknown codes, a deleted project or a failing token endpoint); 4011 (project suspended) closes without retry; a 4008 with `retry_after` waits longer each time (up to 5 minutes) and never gives up; the proactive token refresh is spread over 2 minutes (`refreshJitterMs`, set by `GiftRoom`); a `getToken` that never answers ends the attempt after 20 s (`token_timeout`). `GiftRoom.reconnectNow()` / `RoomClient.reconnectNow()` also restarts a room that stopped that way (`retries_exhausted`, 4011, the 4008/4009 limit). New: `roomMaxAttempts`, `roomRetryFloorMs`, `roomTokenMs`, `roomReasonExhausted`, `roomRateLimitedDelayMs`, `RoomNoRetry.resumable` / `exhausted`.
- `GiftingClient(timeout:)`: one HTTP attempt has 20 s by default (`Duration.zero` = off); a slower one is the same `network_error` as a lost connection, never retried.
- A 2xx whose body is not JSON, or not what the model expects, is `GiftingException(status, "invalid_response", "Invalid response (200).")` with no body text and `retryable` false (fixture cases in `client.json`).
- `GiftTrayOptions.onSent` / `onError` (and the effect call of `PlayOn.success`) run outside the send's failure handling: a callback that throws no longer refunds a send that went through.
- Tests: `test/client_robustness_test.dart`; `rooms-reconnect.json`, `rooms-session.json` and `client.json` have the new cases. Run with Flutter on 2026-11-03 (the non-UI suites; UI suites could not load while another change was mid-edit in `gift_tray.dart`).

### gift inbox (SPEC 19) (2026-11-02)

- `GiftingClient.getInbox({cursor, limit})` (`GET /v1/client/me/inbox`), models `Inbox`, `InboxItem`, `InboxRow`; pure `inboxTimeLabel`, `inboxRows`, `inboxUnread` (`giftingstack_core.dart`).
- `GiftInbox` widget (`GiftInboxState.refresh()`): loading / empty / error with "Try again" / newest-first list with "Show more", reversed gifts hidden, `resolveUsers`, `onLoaded`, one spoken element per row. New `GiftLabels`: `inboxEmpty`, `inboxError`, `inboxShowMore`, `inboxSent`, `inboxQuantity`, `inboxRowSpoken`.
- Fixture `conformance/inbox.json` runs in `test/inbox_conformance_test.dart`; widget tests in `test/gift_inbox_test.dart`. The example's Inbox tab is the SDK widget on a mock `getInbox`; its badge uses `inboxUnread`.
- Not compiled with Flutter yet: run `flutter analyze` and `flutter test`.

### battle bar (SPEC 18.7) (2026-10-20)

- `GiftBattleBar` (`BattleBarUser`): the drawn versus bar, 1:1 with the web and React Native bars (avatars in rings, crown and gold ring for the winner, loser at half opacity, clock pill that turns urgent in the last 10 s and "Final", 16 px split bar with a sliding boundary and a spark, banner, one spoken sentence). Follows a `GiftRoom` (`room:`, clock tick `tickMs`) or draws a `view:` you pass. Theme, `sideColors`, `labels` (`BattleBarLabels`), reduced motion (`reducedMotion` or `MediaQuery.disableAnimations`).
- Pure core (`giftingstack_core.dart`): `battleBarModel`, `formatBattleScore`, `formatBattleClock`, `battleSideColors`, `battleGains`, `BattleBarLabels`.
- Fixture `conformance/battle-bar.json` runs in `test/battle_bar_conformance_test.dart`; widget tests in `test/gift_battle_bar_test.dart`. The example's Live tab shows the bar on its pretend room (a round between Mira and Noor).
- Not compiled with Flutter yet: the pure core ran with the Dart SDK only; run `flutter test` and `flutter analyze`.

### render slots (2026-10-18)

- `GiftWall.renderChip` (`WallChipContext`), `GiftLeaderboard.renderRow` (`LeaderboardRowContext`), `GiftAwaySummary.renderSummary` (`AwaySummaryContext`, `AwaySenderInfo`): builders `Widget? Function(BuildContext, Context)`; null draws the default. Same names and fields as sdk-js (SPEC 16.5). The SDK keeps the container, semantics, press and actions; a custom away body has no close button and a tap does not dismiss.
- `awayTexts` also returns `gifts` and `people`.
- Tests: custom, null fallback, press, spoken labels, replay and live-region kept (`gift_wall_test`, `gift_leaderboard_test`, `gift_away_summary_test`).

### battle scores (SPEC 17.8, 18.6) (2026-10-18)

- Headless client side of battle (versus) rounds, mirroring `packages/sdk-js/src/core/rooms.ts`: `parseRoomFrame` reads `scores` and `welcome.battle`
  (`RoomScoresMessage`, `RoomWelcomeMessage.battle`, models `RoomBattle`, `RoomScoreEntry`), pure `battleView(battle, serverNow)` (`BattleView`, `BattleSide`: shares,
  leader or null on a tie, `open`, `remainingMs`, `total`, sides in server order).
- `RoomClient`: `getBattle()`, `subscribeBattle(listener)`, `serverNow()`, `getBattleView()`, option `onBattle`. The round survives a reconnect until the next welcome.
- `GiftRoom`: `battle`, `battleView` (a getter; call it again on a timer to count down), `onBattle` parameter; listeners are notified on every change. No UI component.
- Fixture `conformance/rooms-battle.json` (moved up from `pending-native/`) runs in `test/rooms_conformance_test.dart`; session tests in `test/rooms_battle_test.dart`.

### "Test mode" badge (SPEC 9) (2026-10-17)

- `Me.livemode` (`GET /v1/client/me`; null from older servers) and the tray state's `testMode`
  (`livemode == false`: the token was made with a test key; the test environment allows 50 users and
  5,000 operations a month).
- `GiftTray(testMode:, testModeLabel:)` shows a "Test mode" badge after the title; pass `GiftTrayNotifier.testMode`.

### Earlier work

Brings the package up to the shared contract of 2026-10-11 (SPEC 9.1 sheet, 9.2 theming, 13 remote
recipes, 14 gift wall, 15 away summary, 16 leaderboard; 9.3 placements are web only and are not
implemented). Spec version is still 1.0.0. Not run on a device or an emulator.

- **Gift wall, "while you were away" card, leaderboard** (SPEC 14-16, ported from `packages/sdk-js`).
  Pure core (`giftingstack_core.dart`, no Flutter imports): `wallChips`, `formatCount`, `GiftWallLoader`,
  `planAwayReplay`, `awaySenderLabel`, `AwayController`, `LeaderboardController`, `pinnedMe`,
  `leaderboardRankLabel`, `groupThousands`, `leaderboardRankColors`, and the models `GiftWallResult`,
  `AwaySummary`, `Leaderboard` and friends. New client calls: `getReceivedGifts(user, [reference])`,
  `queryGiftWalls`, `getAway`, `ackAway` (the 204 is not parsed) and `getLeaderboard`. Widgets: `GiftWall`,
  `GiftAwaySummary` (the replay plays through the existing `GiftEffectController`), `GiftLeaderboard`, all
  themed with `GiftingTheme`, with `GiftLabels` for every word, `Semantics`, reduced motion and tab
  keyboard (arrows, Home, End). **Breaking for apps that `implements GiftingClient` to fake it**: add the
  four new methods and the new optional `reference` parameter of `getReceivedGifts`. The wire model of a
  wall answer is called `GiftWallResult` (the name `GiftWall` is the widget). `wall.json`, `away.json` and
  `leaderboard.json` now have a runner (`test/components_conformance_test.dart`, including their `client`
  sections) and are no longer in the "pending native port" list of `test/fixture_coverage_test.dart`.
- Example app: a gift wall under the post (about ten kinds, the "+N" chip, it counts what you send), and
  two labelled demo-only buttons, "Away summary (demo)" and "Leaderboard (demo)" (15 users with ties, you
  outside the rows); the picture of the post is smaller so the wall is not hidden by the sheet. Not run on a
  phone or an emulator.
- Tests: 372 -> 642 in the package (components fixtures 129, core 24, widgets 117), example 8 -> 15. Mutation
  checks of the new rules: README "Mutation checks". Nothing measured on a phone.
- `away.json#client` "getAway with since and maxGroups" now writes the gift objects the API sends (it
  used to write `"gift": "<id>"`); the client runner no longer rewrites response bodies or results.

- **Tray as a bottom sheet** (default): `GiftTray` fills its parent and is dragged between peek, default and
  expanded (90 % of the parent, the grid scrolls inside). New options `sheet`, `initialSnap`, `snaps`,
  `onSnapChange`, `onInsetChange`, `containerHeight`, `bottomInset`, `reducedMotion`, `onSelect`.
  `sheet: false` keeps the old fixed tray. **Breaking for apps that put `GiftTray` in a column or an
  `Align`**: put it in a `Stack` with `Positioned.fill`, or pass `sheet: false`. Pure logic in
  `TraySheetController` and `resolveSheetHeights`, driven by `conformance/sheet.json`.
- **Themes**: `GiftingTheme` has three new tokens (`coinText`, `selected`, `comboText`; defaults keep the old
  fixed colours); `darkTheme`, `lightTheme`, `themeFromAccent(hex, mode)` (text at 4.5:1); pure
  `GiftThemeTokens` in the core, driven by `conformance/theme.json`.
- **Remote recipes** (SPEC 13): `parseRemoteRecipes`, `mergeRecipeSet`, `remoteRecipesUrl`, `RecipesLoader`
  (injectable fetch and storage, memory by default; 6 h refresh, backoff, 3 s timeout). `GiftEffectLayer`
  options `remoteRecipes` (default true), `recipesVersion`, `recipesUrl`, `recipesLoader`. The document is not
  deployed yet, so the request fails quietly. Effects on screen keep their recipe. `TierThresholds` now
  knows which fields the app gave (`givenMediumFrom`) and `GiftEffectLayer.comboWindowMs` is nullable (null =
  2500 ms or the remote value); `ComboTracker.windowMs` is mutable.
- Bigger icons (`min(72, 78 %)` of the cell, as the web tray) and `pictureScale` in the effect layer (as the web
  layer; 1 on a phone, up to 2 on a tablet).
- Tests: 191 -> 372. `placement.json` is acknowledged as web only; a new fixture file without a runner fails
  `test/fixture_coverage_test.dart`.
- Example app: mock coin store (Get coins ADDS coins), "Reset coins" renamed "Reset (demo)", catalog of about 90
  gifts from the live `library.json` (12-gift fallback), labelled "Incoming gift" with "same as tray", theme picker.

## 0.1.0

First version. Conforms to spec 1.0.0 (`packages/sdk-spec`).

- Pure Dart core (`package:giftingstack/giftingstack_core.dart`): models, `GiftingClient`, `GiftingException`, tiers and
  recipes (generated from `recipes.json`), `ComboTracker`, `EffectScheduler`, `GiftTrayController`,
  `sendButtonState`.
- Flutter UI: `GiftEffectLayer` with `GiftEffectController`, `GiftTray`, `GiftTrayNotifier`, `GiftingTheme`.
- All conformance fixtures of `packages/sdk-spec/conformance` run in `test/`.
- Example app in `example/` (mock client, mirrors the web demo).
- Not yet checked on a device (spec level L4).
