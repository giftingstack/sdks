# giftingstack (Flutter)

Gift effects, a gift tray, a gift wall, a "while you were away" card, a leaderboard and a small client for the
GiftingStack API. Flutter port of
`@giftingstack/sdk` (React Native), built from the shared contract in `packages/sdk-spec`
(spec 1.0.0). Dart 3, null-safe. Dependencies: `flutter` and `http`.

Status: 0.1.0, a preview: the API can still change before 1.0 (see `CHANGELOG.md`). The logic is
machine-checked; how the animations and the sheet drag feel is not checked on a device yet (see
"Verification"). The newest Flutter demo was not run on a phone or an emulator at all.

## Install

```bash
flutter pub add giftingstack
```

or in `pubspec.yaml`:

```yaml
dependencies:
  giftingstack: ^0.1.0
```

The pure Dart part (no Flutter imports) is `package:giftingstack/giftingstack_core.dart`. The whole
package is `package:giftingstack/giftingstack.dart`.

## Token flow

The app never holds an API key. Your own server creates a short-lived client token for the signed-in
user (`POST /v1/client-tokens`) and the app asks your server for it:

```dart
final client = GiftingClient(
  getToken: ({required bool forceRefresh}) async {
    // Your server calls POST /v1/client-tokens and returns the token.
    return myBackend.giftingToken(forceRefresh: forceRefresh);
  },
  // baseUrl: 'https://api.giftingstack.com'   (default)
  // httpClient: http.Client()                 (injectable, tests replace it)
);
```

`getToken` is called once per client call, and once more with `forceRefresh: true` after a 401.
Errors thrown by `getToken` itself reach the caller unchanged.

## Usage

```dart
final effects = GiftEffectController();
late final tray = GiftTrayNotifier(
  client: client,
  receiver: 'mert',          // who gets the gifts
  effects: effects,          // optional: plays each gift's effect
  reference: 'post_42',      // optional: your own context id
  onError: (e) {
    if (e.insufficientBalance) openCoinStore();
  },
);

// The tray is a bottom sheet that fills its parent: give it the whole Stack. The area above the
// sheet still gets touches. The effect layer goes last and never takes touches.
Stack(children: [
  YourScreen(),
  Positioned.fill(
    child: GiftTray(
      tray: tray, // gifts, balance, send and the "Test mode" badge (a test key) come from it
      onTopUp: openCoinStore,
      theme: darkTheme, // or lightTheme, or themeFromAccent('#ff4f9a')
      bottomInset: MediaQuery.paddingOf(context).bottom,
      // The notice follows the sheet's top edge:
      onInsetChange: (px) => setState(() => noticeBottom = px + 16),
    ),
  ),
  Positioned.fill(
    child: GiftEffectLayer(controller: effects, theme: darkTheme, noticeBottom: noticeBottom),
  ),
]);

// A gift you received (from your own socket or push):
effects.play(GiftEffectEvent(
  gift: GiftEffectGift(
      id: 'rose', name: 'Rose', price: 10, image: art512Url, icon: icon256Url),
  sender: 'ayla',
));
```

`GiftTray(tray: tray)` rebuilds when the notifier changes and shows the **Test mode** badge by itself
while the token was made with a test key (`me.livemode == false`); `testMode: false` forces it off,
`testMode: true` forces it on. You can still pass `gifts`, `balance` and `onSend` yourself; they win
over `tray`.

`GiftTrayNotifier` refreshes on creation and prefetches every picture. Call `tray.dispose()` when the
screen closes (late answers then change nothing). `play` returns an id (1, 2, 3, ...); `cancel(id)` takes
a gift back, `clear()` stops everything.

| piece                                                             | what it does                                                                                                                             |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `GiftingClient`                                                   | `getGifts`, `getMe`, `getReceivedGifts(user, [reference])`, `sendGift`, `queryGiftWalls`, `getAway`, `ackAway`, `getLeaderboard`         |
| `GiftEffectLayer`                                                 | small: floats up; medium: flies to the middle, sparks; large: dim, rays, sparks, coin rain                                               |
| `GiftTray`                                                        | draggable bottom sheet (peek / default / expanded 90 %), grid, balance count-up, "Get coins" states; `sheet: false` = the old fixed tray |
| `TraySheetController`                                             | the pure sheet logic (snaps, flick >= 600 px/s, nested scroll, inset); `GiftTray` draws what it says                                     |
| `RecipesLoader`, `RemoteRecipesOptions`                           | remote effect numbers (SPEC 13): injectable fetch and storage, memory by default                                                         |
| `GiftTrayNotifier`                                                | `ChangeNotifier` around the pure `GiftTrayController`: optimistic balance, tap/success, reconcile                                        |
| `GiftingTheme`, `darkTheme`, `lightTheme`, `themeFromAccent(hex)` | every colour (17 tokens); the defaults are the 1.0 look; the presets and `themeFromAccent` keep text at 4.5:1                            |
| `GiftEffectLayer(quality: EffectQuality.low)`                     | fewer sparks, no coins, no rays (for slow phones; the app chooses)                                                                       |

Reduced motion: by default the layer follows `MediaQuery.disableAnimations`; then only the notice
shows. Pass `reducedMotion: true/false` to override.

The tray sheet: drag the handle or the header, tap the handle (default <-> peek), or use the screen
reader actions (increase / decrease / "Show more gifts"). Fully open it is 90 % of its parent; the gift
grid scrolls inside, and a pull down at the top of the grid collapses the sheet. Icons are
`min(72, 78 % of the cell)` like the web tray. Reduced motion jumps instead of animating. `snaps`,
`initialSnap`, `onSnapChange`, `onInsetChange`, `bottomInset` and `containerHeight` are the sheet options.
`placement` (popover, inline) is web only (SPEC 9.3) and does not exist here.

The scrim and the Gift button (SPEC 9.4), all off or unchanged by default: `GiftTray(scrim: true)`
draws a dim behind the sheet over the box the tray fills (a bounded parent), fading in over 200 ms
(at once with reduced motion), hidden while the sheet is at peek, black at 0.4, taking the taps
above the sheet. `scrimTap` is `ScrimTap.lower` (default: a tap lowers the sheet to peek) or
`ScrimTap.dismiss` (the tray closes). `onDismiss` tells you. `GiftTrayNotifier` holds the open
state: `tray.toggle()` is your Gift button (`open()`, `close()`, `isOpen`, `onOpenChange`;
`GiftTrayNotifier(open: false)` starts closed). A closed tray is invisible, takes no touches and
reports an inset of 0; opening shows it at `initialSnap`. `GiftTray(open:)` lets you own the state.

```dart
GiftTray(tray: tray, scrim: true, scrimTap: ScrimTap.dismiss, collapseOnSelect: true);
// onPressed: tray.toggle
```

The layer draws the gift picture bigger in a wide layer (a tablet): `pictureScale` is 1 on a phone and
grows up to 2 (`GiftEffectLayer(pictureScale: ...)` replaces the automatic value).

Remote recipes (SPEC 13): by default the layer asks `https://assets.giftingstack.com/recipes.json` once
per 6 hours for tuned effect numbers and uses them for NEW effects (the app's own `thresholds` and
`comboWindowMs` win; effects already on screen keep their recipe; the first effect never waits for the
network). The file is served from `assets.giftingstack.com`; if the request fails, the built-in
numbers apply. `remoteRecipes: false` makes no request at all; `recipesVersion` pins `recipes.<version>.json`.
The cached copy lives in memory only unless you pass a `RecipesLoader` with your own `RecipesStorage`.

Pictures load through `NetworkImage` (Flutter's image cache). Pass `imageProvider:` to the layer or
the tray to use your own cache.

## Gift wall, "while you were away", leaderboard

Three more components (SPEC 14-16, ported from `packages/sdk-js`). All take the same `client`, a
`theme` (`GiftingTheme`) and `labels` (`GiftLabels`: every visible and spoken word, English by default),
follow the OS "remove animations" setting unless you pass `reducedMotion`, and never show an error that
the person cannot act on.

```dart
// A row of chips under a post or on a profile: [rose 12] [heart 3] [+37]. Walls on one screen share
// their requests (one POST per 50 ms window, at most 25 walls, answers kept 60 s).
GiftWall(
  client: client,
  user: 'mert',                 // the receiver
  reference: 'post_42',         // your content id; null = the profile wall
  max: 6, order: WallOrder.count, size: GiftWallSize.md,
  refreshKey: sentCount,        // change it after the viewer sent a gift
  onPressChip: (gift) => openTray(),   // makes the chips buttons (44 dp cells)
  onError: (e) {},              // errors are never drawn
);

// "While you were away: 37 gifts from 12 people". Put it in the Stack above your screen and below the
// effect layer; it fills the Stack, only the card takes touches.
final away = GlobalKey<GiftAwaySummaryState>();
GiftAwaySummary(
  key: away,                    // away.currentState.check() / ack() / dismiss()
  client: client,
  effects: effects,             // the GiftEffectController of your layer; null = card only
  ackOn: AwayAckOn.shown,       // shown | finished | manual
  resolveUsers: (ids) async => {'ayla': AwayUser(name: 'Ayla K.')},
  maxEffects: 5, budgetMs: 8000,
);

// Top senders / receivers with tabs, a coins/gifts switch and your own row pinned underneath.
GiftLeaderboard(
  client: client,
  board: LeaderboardBoard.senders, periods: leaderboardPeriods,
  limit: 10, metricToggle: true, coinName: 'coins',
  resolveUsers: (ids) async => {'ayla': LeaderboardUser(name: 'Ayla K.')},
  onPressUser: (id) => openProfile(id),
);
```

Pure logic (no Flutter imports, in `giftingstack_core.dart`): `wallChips`, `formatCount` (always rounds
down: `1999` is `1.9K`), `GiftWallLoader`, `planAwayReplay`, `AwayController`, `LeaderboardController`,
`pinnedMe`, `leaderboardRankLabel`, `leaderboardRankColors`. New `GiftingClient` calls:
`getReceivedGifts(user, [reference])`, `queryGiftWalls`, `getAway`, `ackAway` (a 204, nothing parsed),
`getLeaderboard`. The wire model of a wall answer is `GiftWallResult` (the name `GiftWall` is the widget).

- The card replays at most 5 gift groups through your `GiftEffectLayer`, within 8 s, the biggest last; it
  goes after `max(4000, replay end + 1500)` ms or on a tap. It waits at most 1.5 s for `resolveUsers`.
  `ackOn: shown` sends the cursor when the card appears (at least once shown), `finished` when it goes,
  `manual` only on `ack()`. A failed ack is retried once at the next `check()`. The app resuming checks
  again at most once a minute (`autoCheck: false` turns both off).
- The leaderboard keeps the last answer of each tab and metric, shows it at once and fetches again in the
  background when it is 30 s old; there is no polling unless you pass `refreshIntervalMs`. Tabs are
  buttons in one group: arrows, Home and End move between them (only the selected tab is in the Tab
  order). Ranks 1-3 sit on medals (`#e8a93a`, `#b8bcc8`, `#c07a45`) with `noticeBigText` on top (at least
  4.5:1 in the default, dark and light themes).
- A tappable `GiftWall` chip sits in a 44 dp high cell, so a wall with `onPressChip` is taller than its
  24 dp chips.
- `implements GiftingClient` fakes must add the four new methods (the abstract surface grew).

### Render slots

Draw the inside of a chip, a row or the card body yourself; the SDK keeps loading, order, names, the
container, the spoken label, the press and the actions. A builder that returns `null` draws the default.

```dart
GiftWall(
  client: client, user: post.author, onPressChip: openTray,
  renderChip: (context, chip) => Text('${chip.gift.name} x${chip.countText}'), // WallChipContext
);
GiftLeaderboard(
  client: client,
  renderRow: (context, row) => row.isMe ? null : MyRow(row.rank, row.name, row.scoreText), // LeaderboardRowContext
);
GiftAwaySummary(
  client: client,
  // AwaySummaryContext: summary, title, headline, gifts, people, senders, dismiss, ack, theme.
  // A tap on custom content does not dismiss: call dismiss(). No close button is drawn.
  renderSummary: (context, s) => MyCard(s.headline, onClose: s.dismiss),
);
```

The `+37` overflow chip and the pinned "You" row stay the default. Same names and fields as the web SDK.

## Gift rooms (live)

Everyone watching one stream, audio room or chat sees every gift sent into it, on their own phone
(SPEC 17-18; no media, no chat, only gift events). Your server mints the client token with `rooms`
(allowed room ids or `prefix*`) and `name` (what viewers see); `GiftRoom` joins, plays what comes in
your `GiftEffectLayer`, and `GiftTrayNotifier(roomId: ...)` sends into the room.

```dart
final room = GiftRoom(
  room: 'live_42',                 // ^[A-Za-z0-9_.:-]{1,64}$
  getToken: myTokenFunction,       // the same one you give GiftingClient
  client: client,                  // optional: loads the catalog once for the big picture
  effects: effects,                // room gifts play here by themselves
  skipOwn: true,                   // default: your own gift already played on tap
  minTier: EffectTier.small,       // only gifts of this tier or bigger
  resolveName: (id) => names[id],  // sender without a name claim (default: "Someone")
  onGap: () => showCatchUpHint(),  // events may have been missed
);
ListenableBuilder(
  listenable: room,
  builder: (_, __) => Text('${room.viewers ?? 0} watching (${room.status.name})'),
);

// Send into the room, from the same screen:
final tray = GiftTrayNotifier(client: client, receiver: 'host', effects: effects, roomId: 'live_42');

room.dispose(); // leaves the room (also closes the socket)
```

- Transport: a `dart:io` `WebSocket` with the subprotocols `['gs.v1', token]` (no new dependency).
  The package compiles for Flutter web (the `dart:io` transport is only imported where it exists), but
  the default socket does not exist there: `GiftRoom(socket: ...)` takes your own `RoomSocketFactory`
  (for example around `package:web`'s `WebSocket`); without it the default throws an
  `UnsupportedError` that says so. `url` must be `wss://` unless the host is `localhost`, `127.0.0.1`,
  `::1` or `10.0.2.2`, or you pass `allowInsecure: true`.
- Reconnect rules (SPEC 18.3): `reconnectNow()` never skips a 4008/4009 wait (the platform named the
  time).
- It reconnects with backoff and resumes from the last event id (a replay never plays twice), refreshes
  the token before the 60 minute limit, and keeps an app heartbeat (`heartbeatMs`, 45 s). Close codes
  4003, 4004, 4010, 4400 and "replaced" are final (`status` is `closed` and `state.code` says why).
- The app going to the background keeps the socket for 60 s (`pauseAfter`), then closes it; coming
  back reconnects with resume. `observeLifecycle: false` turns that off. (The room design says 30 s;
  60 s is kept on purpose, as on the web, so a short app switch does not cost a reconnect and a
  join against the per-user limits of SPEC 17.7. Pass `pauseAfter: Duration(seconds: 30)` for 30.)
- Pure logic (`giftingstack_core.dart`): `parseRoomFrame`, `roomHelloFrame`, `roomUrl`, `roomTokenUser`,
  `roomRetryDecision`, `RoomEventFilter`, `roomGiftToEffect`, `RoomClient` (socket, clock, timers,
  random and token are injected). `SendGiftInput(roomId:)` and `GiftTrayOptions(roomId:)` name the room
  in the send body (`room_id`).
- Rooms connect to `wss://rt.giftingstack.com` by default; point `url:` at a local server for development.

### Battle bar (versus)

`GiftBattleBar` draws a battle round of the room (SPEC 18.7): both receivers with their scores, a
countdown, and a bar whose boundary slides as gifts arrive. It draws `battleView` only; your server
starts and ends rounds. Nothing is drawn while the room has no round with two sides.

```dart
GiftBattleBar(
  room: room,                                   // follows its battle and ticks the clock by itself
  users: {                                      // names and pictures by id (fallback: the id)
    'ava': BattleBarUser(name: 'Ava', avatarUrl: 'https://...'),
    'mateo': BattleBarUser(name: 'Mateo'),
  },
  theme: darkTheme,                             // accent against coin colour, 4.5:1 text on both
  sideColors: const [Color(0xFFE0457B), Color(0xFF3A8DFF)], // optional override
  labels: const BattleBarLabels(finalText: 'Bitti', wins: '{name} kazandı'),
  reducedMotion: null,                          // null: follows MediaQuery.disableAnimations
);
```

Without a room pass `view: myBattleView`. The pure model (`battleBarModel`, `formatBattleScore`,
`formatBattleClock`, `battleSideColors`) is in `giftingstack_core.dart`; the numbers are the shared
fixture `battle-bar.json`. Reduced motion: no sliding, counting or pulse.

## Limits

- At most 6 small, 2 medium and 1 large effect on screen at once. Extra small/medium gifts show only
  the notice. Large gifts queue (5 waiting); a 6th waiting one silently drops the oldest.
- `quantity` 1 to 1000, `message` up to 280 characters (API limits).
- One quiet retry on 5xx, one token refresh on 401, 3 requests at most per call (4 for `sendGift`); 429
  and other 4xx are not retried; no backoff. A lost connection ends the call at once (`status` 0,
  `network_error`); only `sendGift` repeats it once, with the same idempotency key (a timeout is not
  repeated).
- `http://` and `ws://` URLs are refused (an `ArgumentError`) unless the host is `localhost`, `127.0.0.1`,
  `::1` or `10.0.2.2` (the Android emulator) or you pass `allowInsecure: true`.
- A combo is the same sender and gift again within 2500 ms of the previous one.
- The layer must be in a `Stack` (or any parent with bounded size). It draws only once it has a size.
- The notice position is `noticeBottom` dp from the bottom edge (default 150); with the sheet pass
  `inset + 16` from `onInsetChange`.
- The balance in the tray uses en-US grouping (`1,234`) whatever the locale (as the reference).
- Names: the spec table calls the error `GiftingException`; `GiftingError` is a typedef of it. The
  spec lists `GiftTrayController extends ChangeNotifier`; here the pure controller has no Flutter
  import and `GiftTrayNotifier` is the `ChangeNotifier`.

## Verification

What is proven by which test, and what only a person with a phone can judge.

| what                                                                                                                                                                                                                                                                                                                                     | proven by                                                                                                                               | level         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| every constant and recipe equals `recipes.json`; generated file has not drifted                                                                                                                                                                                                                                                          | `test/spec_data_test.dart`, `dart run tool/generate_spec_data.dart --check`                                                             | L1            |
| client: URLs, headers, bodies, retries, errors, `encodeURIComponent`, idempotency keys                                                                                                                                                                                                                                                   | `conformance/client.json` (29 scenarios) in `test/conformance_test.dart`                                                                | L2            |
| tiers, low-quality recipes, combo window                                                                                                                                                                                                                                                                                                 | `tiers.json` (24), `combo.json` (10)                                                                                                    | L2            |
| `EffectScheduler`: caps, large queue, drops, notice text and ids, cancel, clear, reduced                                                                                                                                                                                                                                                 | `effects.json` scenarios (20)                                                                                                           | L2            |
| `GiftTrayController`: optimistic balance, refund, cancel, reconcile, dispose, prefetch order                                                                                                                                                                                                                                             | `tray.json` scenarios (14)                                                                                                              | L2            |
| send button state                                                                                                                                                                                                                                                                                                                        | `tray.json#sendButton` (9)                                                                                                              | L2            |
| picture gate: effect and notice start at the load, the error or `pictureWaitMs`, within 16 ms                                                                                                                                                                                                                                            | `test/picture_gate_test.dart` (8 cases, fake clock, rendered)                                                                           | L3            |
| effect on screen until 1600 / 2100 / 3850 ms; caps and queue drawn; cancel and clear; no timers left                                                                                                                                                                                                                                     | `test/gift_effect_layer_test.dart`, `test/core_unit_test.dart` (timeline math)                                                          | L3            |
| notice: bottom-left, combo counter, golden for large, 2400/2800 ms, slide out                                                                                                                                                                                                                                                            | `test/gift_effect_layer_test.dart`                                                                                                      | L3            |
| reduced motion (system and prop), quality low, touches pass through                                                                                                                                                                                                                                                                      | `test/gift_effect_layer_test.dart`                                                                                                      | L3            |
| tray: selection, send, "Get coins", "Not enough coins", disabled, count-up, labels, prefetch, scroll                                                                                                                                                                                                                                     | `test/gift_tray_test.dart`                                                                                                              | L3            |
| tray + notifier + layer together: tap plays, failure takes back coins and effect                                                                                                                                                                                                                                                         | `test/gift_tray_test.dart`                                                                                                              | L3            |
| sheet snap heights, drag, release, flick (600 px/s), toggle, steps, layout change, nested-scroll decision (pure)                                                                                                                                                                                                                         | `conformance/sheet.json` (12 heights + 22 scenarios) in `test/sheet_conformance_test.dart`                                              | L2            |
| theme: WCAG contrast ratio, both presets and `themeFromAccent` (9 accents x 2 modes + 300 pseudo-random) meet the 4.5:1 rule; bad input throws                                                                                                                                                                                           | `conformance/theme.json` in `test/theme_conformance_test.dart`                                                                          | L2            |
| remote recipes: parse, clamp (limits table equals SPEC 13.3), merge order, version URLs                                                                                                                                                                                                                                                  | `conformance/remote-recipes.json` (33 + 5 + 9) in `test/remote_recipes_conformance_test.dart`                                           | L2            |
| remote recipes loader: cache, 6 h refresh, 1 min..6 h backoff, 3 s timeout and abort, one request at a time, storage that throws, `remoteRecipes: false` = no request, scheduler uses the set (app beats remote, running effects keep their recipe)                                                                                      | `test/recipes_loader_test.dart` (fake fetch, storage and clock), `test/gift_effect_layer_remote_test.dart`                              | L3            |
| `placement.json` (popover, inline) is web only: the runner acknowledges and skips it; a new unknown fixture file fails the suite                                                                                                                                                                                                         | `test/fixture_coverage_test.dart`                                                                                                       | L2            |
| rooms: protocol parse/hello/url/token user, reconnect policy, event filter (incl. `batch`), mapping, session traces                                                                                                                                                                                                                      | `test/rooms_conformance_test.dart` (5 fixtures: 24 + 22 + 12 + 5 + 21 cases)                                                            | L2            |
| `GiftRoom`: fake socket, real effect layer, 60 s background pause and resume with `last`, `roomId` on the send path, the real `dart:io` transport against a local WebSocket server                                                                                                                                                       | `test/gift_room_test.dart` (10 tests)                                                                                                   | L3            |
| the tray as a sheet: measured peek/default/expanded heights, 90 % expanded, inset callback, drag, flick, handle tap, nested scroll (grid scrolls only when fully open and not at the top), no grid fling after a sheet drag, a drag is not a tap, touches above the sheet pass through, screen reader actions, themed colours, icon size | `test/gift_tray_sheet_test.dart` (27 widget tests)                                                                                      | L3            |
| picture scale in a wide layer (same numbers as the web test) and passed to the effect                                                                                                                                                                                                                                                    | `test/picture_scale_test.dart`                                                                                                          | L3            |
| example app: Get coins ADDS coins, Reset (demo) goes back to 60,000, catalog of about 90 gifts from `library.json` with the 12-gift fallback, Incoming gift "same as tray"                                                                                                                                                               | `example/test/widget_test.dart` (25 tests in all now; not run by CI, only `flutter test` in `example/`)                                 | L3            |
| gift wall logic: chips (max, overflow SUM, order, stable ties), `formatCount` (floors), `GiftWallLoader` (50 ms window, 25 per call, 60 s cache, in-flight dedupe, invalidate)                                                                                                                                                           | `conformance/wall.json` (12 + 22 + 8 + 4 client scenarios) in `test/components_conformance_test.dart`, `test/components_core_test.dart` | L2            |
| away: replay plan (<= maxEffects, budget, biggest last), sender label, `AwayController` (ack once, ack timing shown/finished/manual, retry once, foreground throttle), cursor PUT with a 204                                                                                                                                             | `conformance/away.json` (16 + 10 + 15 + 5 client scenarios)                                                                             | L2            |
| leaderboard: rank label, pinning rule, per-tab cache and 30 s revalidation, medal tokens and their 4.5:1 contrast, query order                                                                                                                                                                                                           | `conformance/leaderboard.json` (6 + 10 + 14 + 5 client scenarios + rankColors)                                                          | L2            |
| `GiftWall` widget: skeleton, empty, error (silent), data, max/order/size/theme/labels, ONE batched request for several walls, cache, `refreshKey`, accessibility label, 44 dp tappable chips, fade and reduced motion                                                                                                                    | `test/gift_wall_test.dart` (26 widget tests)                                                                                            | L3            |
| `GiftAwaySummary` widget: card content, replay through `GiftEffectController` at the planned times, at most `maxEffects` within the budget, ack timing for `ackOn` shown / finished / manual, auto and tap dismissal, `resolveUsers` (1.5 s cap), reduced motion, focus, foreground throttle                                             | `test/gift_away_summary_test.dart` (44 widget tests, fake clock)                                                                        | L3            |
| `GiftLeaderboard` widget: loading / ready / empty / error, medals with `noticeBigText`, highlight and pinned row (`#417`, `1,000+`), tabs and their keyboard (arrows, Home, End, wrap), metric switch, stale rows and spinner, polling, row labels, `onPressUser`, names                                                                 | `test/gift_leaderboard_test.dart` (47 widget tests)                                                                                     | L3            |
| `GiftBattleBar` widget: hidden states, sides, clock urgency, boundary, crown and banner, short scores, labels, theme and `sideColors`, count-up, reduced motion, spoken label, follows a `GiftRoom`                                                                                                                                      | `test/gift_battle_bar_test.dart`                                                                                                        | L3            |
| Battle bar model: split, clock, urgent, winner, short scores, side colours (`battle-bar.json`)                                                                                                                                                                                                                                           | `test/battle_bar_conformance_test.dart` (40 cases)                                                                                      | L1            |
| example app: gift wall under the post counts what you send, Away summary (demo), Leaderboard (demo) with ties and a pinned viewer, debug bar stays in one Wrap (the demo buttons are pressed by calling their handler: in the test font the sheet covers the third row)                                                                  | `example/test/widget_test.dart` (15 tests in total)                                                                                     | L3            |
| how the wall, the card, the replay and the leaderboard LOOK and FEEL on a phone (chip size, card slide, 44 dp cells in a feed, tab wrapping on a 360 dp phone, real fonts); the new demo on a device                                                                                                                                     | nothing: only read from the code and the widget tree; nothing was run on a phone or an emulator                                         | L4            |
| smoothness on a mid and a low-end phone, frame rate, heat                                                                                                                                                                                                                                                                                | nothing: a person on a device                                                                                                           | L4            |
| easing feel, overshoot, spark and coin spread, ray look                                                                                                                                                                                                                                                                                  | nothing: side by side with `examples/expo-demo`                                                                                         | L4            |
| notice slide and the combo pop (spring is a physical match of React Native's, not pixels)                                                                                                                                                                                                                                                | nothing: by eye                                                                                                                         | L4            |
| no flicker of the previous picture, no late first frame on a real network                                                                                                                                                                                                                                                                | nothing: on a device, cold cache                                                                                                        | L4            |
| example app builds and runs on the Android emulator (API 35, software GPU); tray, small/medium/large effects, combo x3 notice, "Get coins", real pictures from assets.giftingstack.com, touches pass through the layer                                                                                                                   | by eye, screenshots in `docs/screenshots/` (see below)                                                                                  | L4 (emulator) |
| the example app on a real phone, iOS                                                                                                                                                                                                                                                                                                     | nothing                                                                                                                                 | L4            |
| how the sheet drag, flick and nested scroll FEEL on a phone (the slop of 6 dp against Flutter's own scroll and tap recognizers, fling, the spring), and the sheet on the Android emulator                                                                                                                                                | nothing: the gestures are tested with synthetic pointer events only                                                                     | L4            |
| the live `library.json` catalog, the live pictures and the new demo layout on a device                                                                                                                                                                                                                                                   | nothing: the loader is tested with a fake HTTP client; the emulator was NOT started for this change                                     | L4            |

Test counts (`flutter test` in this folder runs 642, `flutter analyze` reports no issues; the example's
25 tests run with `flutter test` in `example/`): components fixtures 129, components core 24, gift wall 26, gift
away summary 44, gift leaderboard 47, and the earlier ones: conformance runner 107, sheet 36, theme 36,
remote recipes 50 (fixture + limits), loader and scheduler 20, layer with remote recipes 4, tray sheet 27,
fixed tray 16, layer 25, picture gate 8, picture scale 6, core unit 25, spec data 10, fixture coverage 2.

The contract moved after 0.1.0 (new fixtures `sheet.json`, `theme.json`, `placement.json`,
`remote-recipes.json`). Against the new sdk-spec the old suite was still green (nothing read the new
files; the generated `spec_data.g.dart` had not drifted); the gap was that nothing ran them. The
fixture coverage test now fails when a conformance file has no runner.

### Mutation checks

Each rule was broken on purpose, the tests were run, the failures listed, and the change reverted.

| mutation                                                | failed                                                                                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| retry sends a new idempotency key                       | client.json: 4 scenarios (401 repeat, 500 retry, 503 twice, 401+500)                                                                       |
| combo window inclusive (`<` to `<=`)                    | combo.json: "exactly 2500 ms", "custom window 2000 ms"                                                                                     |
| full large queue drops the newest, not the oldest       | effects.json "drops the OLDEST"; widget test "large queue holds 5"                                                                         |
| no coin refund when a send fails                        | tray.json: 4 scenarios                                                                                                                     |
| no `cancel` of the effect played at the tap             | tray.json: 3 scenarios; widget test "failure takes both back"                                                                              |
| reconcile applies `getMe` while another send is pending | tray.json "reconcile answer is ignored ..."                                                                                                |
| `Uri.encodeFull` instead of `encodeURIComponent`        | client.json "encodes the user id like encodeURIComponent"                                                                                  |
| notice uses `image` instead of `icon ?? image`          | effects.json: 10 scenarios                                                                                                                 |
| picture wait 300 ms becomes 400 ms                      | picture_gate_test: "never loads", "loads late"                                                                                             |
| start the effect inside the build (no deferral)         | 21 layer widget tests (setState during build)                                                                                              |
| `holdMs` 1600 becomes 1700 in the generated file        | spec_data_test: drift test, recipe large/high, recipe large/low                                                                            |
| low quality keeps coins                                 | tiers.json "recipe large/low"; spec_data_test                                                                                              |
| reduced motion ignored                                  | 5 widget tests                                                                                                                             |
| layer takes touches (no `IgnorePointer`)                | widget test "touches pass through" (found first as a surviving mutation: the test tapped empty space; now taps the notice and the picture) |
| sheet: flick `>=` 600 becomes `>`                       | sheet.json: "a flick of exactly 600 px/s ..."                                                                                              |
| sheet: toggle from expanded goes to peek                | sheet.json: "toggle: default -> peek -> default; expanded -> default"                                                                      |
| sheet: ties go to the less open state                   | sheet.json: 2 scenarios (nearest tie, few gifts)                                                                                           |
| sheet: `scrollOwner` ignores the grid's scroll position | sheet.json: nested scroll scenario                                                                                                         |
| sheet: drag clamps per step (no raw position)           | sheet.json: "the drag follows the finger ... over-drag"                                                                                    |
| sheet: `contentHeight` does not cap expanded            | 5 tests (sheet.json heights, tray sheet widget test)                                                                                       |
| sheet: expanded fraction 0.9 becomes 0.75               | 22 tests (sheet.json, tray sheet widget tests)                                                                                             |
| tray: sheet slop 6 becomes 40                           | 2 gesture widget tests                                                                                                                     |
| remote: clamp removed                                   | 5 tests (remote-recipes.json, loader test)                                                                                                 |
| remote: `sparks` limit 120 becomes 200                  | 3 tests, incl. "the limits table equals SPEC.md section 13.3"                                                                              |
| remote: no rounding of integer fields                   | remote-recipes.json "integer fields are rounded half up"                                                                                   |
| remote: threshold order not checked                     | 2 remote-recipes.json cases                                                                                                                |
| remote: other major accepted                            | 4 tests                                                                                                                                    |
| remote: unknown stage accepted                          | 2 remote-recipes.json cases                                                                                                                |
| merge: app thresholds ignored                           | 4 tests (merge fixture, scheduler, layer)                                                                                                  |
| loader: `remoteRecipes: false` ignored                  | `recipes_loader_test`: "makes no request, no cache read or write"                                                                          |
| loader: backoff not capped at 6 hours                   | `recipes_loader_test`: "backs off after failures ..."                                                                                      |
| scheduler: combo window not taken from the set          | `recipes_loader_test`: "the combo window is the set's ..."                                                                                 |

The components (SPEC 14-16) were mutated the same way on 2026-10-12 (each change in `lib/`, the whole suite run, the change reverted; 32 mutations, 30 caught by one or more tests, 2 survivors that are redundant defences and are caught together):

| mutation                                                               | failed                                                                                                                 |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| wall: `formatCount` rounds instead of flooring                         | 5 tests (wall.json formatCount, unit)                                                                                  |
| wall: overflow chip carries the number of kinds, not the SUM           | 5 tests (wall.json chips, unit, widget)                                                                                |
| wall: no tie-break by catalog order (unstable sort)                    | 1 test (40 equal counts keep their order; the fixtures' ties are too small to catch it: Dart sorts short lists stably) |
| wall: overflow chip even when the gifts exactly fit                    | 5 tests                                                                                                                |
| loader: answer still fresh at exactly 60,000 ms                        | 3 tests (wall.json, unit)                                                                                              |
| loader: a wall in flight is asked again                                | 1 test (wall.json)                                                                                                     |
| loader: an invalidated in-flight answer is cached                      | 1 test (wall.json invalidate)                                                                                          |
| away: replay budget not enforced                                       | 5 tests (away.json plan, unit, widget)                                                                                 |
| away: an end equal to the budget no longer fits (`>` to `>=`)          | 2 tests                                                                                                                |
| away: build-up sorted by units descending                              | 5 tests                                                                                                                |
| away: a summary is acknowledged more than once                         | 5 tests (away.json, widget)                                                                                            |
| away: a failed ack's cursor is never cleared (retried again and again) | 2 tests                                                                                                                |
| away: `ackOn: shown` logic inverted                                    | 5 tests                                                                                                                |
| away: `check()` allowed while playing                                  | 2 tests                                                                                                                |
| away: foreground throttle inclusive at 60,000 ms                       | 1 test                                                                                                                 |
| away: card tail 1500 becomes 1000                                      | 4 tests                                                                                                                |
| away: dismiss no longer stops the timers (alone)                       | SURVIVED: the play is also guarded by the status, so the two defences cover each other                                 |
| away: plays not guarded by the status (alone)                          | SURVIVED for the same reason                                                                                           |
| away: both of the above removed                                        | 2 tests (away.json 'plays not started yet are dropped', widget 'a tap on the body dismisses')                          |
| pinning: rank equal to the limit pinned (`>` to `>=`)                  | 1 test (leaderboard.json pin)                                                                                          |
| pinning: a tie at the cut not handled                                  | 2 tests                                                                                                                |
| cache: a tab exactly 30,000 ms old is not stale                        | 2 tests                                                                                                                |
| cache: `refresh()` does not force a request                            | 5 tests                                                                                                                |
| cache: a failed revalidation hides the stale rows                      | 2 tests                                                                                                                |
| leaderboard: `include_me=false` not sent                               | 1 test (leaderboard.json controller)                                                                                   |
| leaderboard: rank label loses "1,000+"                                 | 5 tests (also the pinned-row widget tests)                                                                             |
| client: `max_groups` sent as `maxGroups`                               | 1 test (away.json client)                                                                                              |
| client: a 204 is parsed as JSON                                        | 3 tests (away.json ackAway, unit)                                                                                      |
| widgets: wall touch target 44 becomes 24                               | 1 test                                                                                                                 |
| widgets: wall ignores reduced motion                                   | 3 tests                                                                                                                |
| widgets: card waits 3 s for `resolveUsers` instead of 1.5 s            | 1 test                                                                                                                 |
| widgets: tab arrow right does not wrap                                 | 1 test                                                                                                                 |
| widgets: medal number drawn in `text` instead of `noticeBigText`       | 1 test                                                                                                                 |

### Example app and build

`example/` is "Pixel", one example integration (a fake social app, not part of the SDK) on a mock client
(250 ms latency, 60,000 coins): bottom tabs Feed / Top / Inbox / Me, a Gift button per post that opens the
tray for the post's author (`reference` = post id; the tray closes after a send), one `GiftWall` per post,
`GiftLeaderboard` on Top, the away card shown the first time only, a mock coin store ("Get coins" ADDS
coins; nothing is charged), an offline banner, and a catalog of about 90 gifts loaded from
`https://assets.giftingstack.com/library.json` (12-gift fallback). No debug buttons: the only debug surface
is the "Developer menu (not part of the SDK)", opened by a 1 s long-press on the Pixel logo (play an
incoming gift, x5 combo, away summary again, wall +5, quality, theme, motion, mock failure, reset). Gifts
from others do not arrive by themselves (`liveFeed` is `false`). It passes `flutter analyze`. Run it
(the `android/` and `ios/` folders are committed):

```sh
cd example
flutter run
```

Verified on 2026-10-10 on the Android emulator (EmulatorX, API 35, software GPU), with the OLD fixed tray
and the old demo (before the sheet, the themes and the new demo). Screenshots in
`docs/screenshots/`: `1-tray`, `2-medium-effect`, `3-large-effect`, `4-notice-combo-x3`,
`5-get-coins-large-fading`. Small effect: only the notice was caught (the float-up is too short for
`adb screencap`, about 1 s per shot). Large effect and Get coins look like the Android Compose demo.
A tap on "Reset coins" during a large effect worked (the layer takes no touches). Smoothness: the
GPU here is software; Flutter draws into a SurfaceView, so `dumpsys gfxinfo` shows 0 frames. Via
SurfaceFlinger while spamming Send (every 300 ms, medium gift): median frame gap 62 ms, p90 102 ms,
p99 158 ms (about 14 fps). That says nothing about a real phone.

### iPhone through TestFlight (no Mac)

The workflow `.github/workflows/sdk-flutter-ios-testflight.yml` ("SDK Flutter iOS TestFlight",
manual) builds `example/` on a GitHub macOS runner, signs it with the same App Store Connect API key
as the Swift demo and uploads it to TestFlight. Setup: `TESTFLIGHT.md` (only the differences from
`../sdk-ios/TESTFLIGHT.md`). Untested: written on Windows without Xcode.

## Development

```sh
flutter pub get
flutter analyze
flutter test                                  # fixtures are read from ../sdk-spec/conformance
dart run tool/generate_spec_data.dart         # regenerate lib/src/core/spec_data.g.dart
dart run tool/generate_spec_data.dart --check # exit 1 when it drifted (CI)
```

The tests fail loudly when `../sdk-spec` is missing: run them from `packages/sdk-flutter` inside the
monorepo.

On Windows, Gradle needs `JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=C:/tmp-gs -Djdk.net.unixdomain.tmpdir=C:/tmp-gs"`
(otherwise: `Unable to establish loopback connection`).

## License

MIT, see [LICENSE](LICENSE). The licence covers this package's code only. The GiftingStack
name and logo, the GiftingStack service and API, and the ready-made gift library
(`assets.giftingstack.com`) are not part of it; the gift library has its own terms.
