# Changelog

## 0.1.6

- Gift button in the app's message bar (SPEC 20). New `GiftButton(tray: notifier)`: a small round gift button to put next to your text field, like an emoji button (`label` "Send a gift", `filled`, `size` a fixed `GiftButtonSize` (`small` 32, `medium` 36 default, `large` 44) with a 44 x 44 touch target, `icon`, `disabled`, `theme`, `onPressed`). It is active while its tray is open and reports "expanded" to screen readers.
- `GiftButton` custom icon and fixed sizes (SPEC 20.4): `icon: (context, color) => Widget` replaces the gift glyph; it is centred in the fixed glyph box and fitted (scaled down, never up, clipped), so it cannot change the button's size. `size` is now the enum `GiftButtonSize { small, medium, large }` (32 / 36 / 44) instead of a number.
- `GiftTrayNotifier(input: focusNode)` binds the tray to your text field: the button closes the keyboard and opens the tray in its place, a tap on the field closes the tray and the keyboard comes back, the button toggles (`toggle()` blurs before it opens and focuses after it closes; `open()` blurs too; `close()` never moves focus). With a field bound the tray starts closed (an explicit `open` wins) and keeps `scrim` off; `GiftTray` records the keyboard height (`MediaQuery.viewInsetsOf(context).bottom`) and makes the default state that tall (300 before any keyboard, at most 60 % of its box) unless you pass `snaps` with `SheetSnap.standard`. New `inputBound`, `keyboardHeight`, and the pure `inputSwapStep`, `keyboardPlaceHeight` (fixture `input-swap.json`). Nothing changes for an app that binds no field.
- `GiftTrayNotifier(open:)` is now `bool?`: null means open, or closed when a field is bound.
- One gift button for a battle: the receiver picker (SPEC 21). `GiftTrayNotifier(receivers: [TrayReceiver(id:, name:, color:, avatarUrl:)])` (also a setter: a new list keeps the pick while that side is still in it) makes the tray show a "Send to" row under its header when there are two or more sides (`GiftTray(sendToLabel:)`, default "Send to"): 30 dp avatars in a 2 dp ring of the side colour (default the battle palette), gap 8; only the picked side shows its name (accent, after the avatar, “…” after 72 dp) and an outer ring, the others are the avatar alone at 55 % (named for screen readers), so four sides fit a 375 dp phone; a tap picks (no send, no snap change); a radio group for screen readers; scrolls sideways, and whenever the pick changes (a tap, `selectReceiver`, a new list, opening the tray) the row scrolls its own offset the least distance so the whole picked side is in sight (never the sheet or the grid); the peek height counts the row. New `selectReceiver(id)` (ids that are not a side are ignored), `receiver` (the pick, else the side gifted last, else the plain `receiver` when it is a side, else the first) and `onReceiverChange`; every send goes to `receiver` and a successful one makes its side the default. `GiftBattleBar(onPressSide:, pressSideLabel:)` turns each side's avatar (versus and multi layout) into a button ("Send {name} a gift", at least 44 dp) so the app can do `tray..selectReceiver(id)..open()`. New pure `resolveReceiver`, `kSendToLabel`, `kPressSideLabel` (fixture `receivers.json`). `GiftTrayController.send` takes an optional `receiver` and completes with whether the server accepted the gift. Without `receivers` and `onPressSide` nothing changes.
- The example app's Live tab has one gift button for the battle: the per-side "Gift X" buttons are gone; the comment bar's gift button opens a tray with the round's sides, a tap on a side of the battle bar picks it and opens the tray, and your gift's line in the comment column takes the receiving side's colour.
- The example app has a Chat tab (your app's conversation with the gift button in its message bar) and a comment bar with the gift button under the live stream.

## 0.1.5

No Flutter release; the shared version moved with the web tray.

## 0.1.4

- The tray title stays on one line and ends with "…" when it does not fit (SPEC 9): a long or translated `title` no longer wraps and pushes the small (peek) tray taller.

## 0.1.3

- With `scrim` on, a tap on the empty space beside a tray at peek (the small state) now closes it: the dim stays hidden there, but it takes the tap (SPEC 9.4, `scrimTakesTouches`; a tall tray still lowers to peek first with `scrimTap` "lower"). The page behind a peeking tray is no longer touchable while the tray is open; leave `scrim` off for that.
- The bar of three or more sides no longer reports a RenderFlex overflow while its segments slide after the bar got narrower (a turn of the phone, a resize): the row is clipped for that moment.
- A battle can have three to eight sides (SPEC 18.7, a free-for-all: everybody races on their own; teams are not part of it). The battle bar draws every side: two sides look exactly as before, three or more get a row of cells (avatar, name, score) with the clock above and a bar of proportional segments (each side in its colour, none under 6 %, white lines between them); the winner, the banner and the spoken sentence cover every side. `sideColors` is a list with one colour per side (`GiftBattleBar`, `GiftRoom`) (a shorter list keeps the default for the sides it does not name; the default palette is the theme's accent, its coin colour, then teal `#2ec4b6` and pink `#ff5d8f`, then the same four again). The gift notice of a battle names the receiver and borders its pill for every side, not only the first two. New: `battleSidePalette`, `battleSegmentPcts`, `BattleBarModel.pcts`.

- The gift notice of a battle says who got the gift (SPEC 7.4, 18.4): line two reads `sent Rose to Mia` and the pill has a 2 px border in the receiving side's colour (the bar's accent / coin colour, or the new `GiftRoom(sideColors: ...)`, the same pair you give `GiftBattleBar`). Only in a battle with two sides; every other notice looks as before. `GiftEffectEvent.receiver` is new for apps that play their own events. The user's own gift says who got it too: `GiftTrayNotifier(receiverOf: room.receiverFor)` (new `RoomClient.receiverFor`, `GiftRoom.receiverFor`). The border is a 2 px ring in the side colour plus a 1 px line in the text colour inside it, so it shows on a pill of the same colour; a gift only counts as a battle gift inside the round; a combo counts per receiver.
- The tray no longer flashes at the top and then drops when its gifts arrive after it opened (the app
  fetches the catalog when it makes the tray): the sheet now rises smoothly from where it is drawn.

## 0.1.2

No code change. The shared version moved with the web, React Native and iOS trays, whose "Test mode"
badge no longer touches the drag handle (SPEC 9.1); this tray already matched.

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
