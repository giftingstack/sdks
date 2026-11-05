# GiftingStack for iOS (Swift, SwiftUI)

Swift Package for GiftingStack: the `/v1/client` API client, the gift effects layer and the gift
tray. It implements the shared contract in `packages/sdk-spec` (spec version 1.0.0) and is a port
of the TypeScript reference in `packages/sdk-js`.

> **Status: preview.** The package builds on macOS and for the iOS Simulator and passes all 156 tests
> (every fixture of the shared contract), checked in CI for every release. The UI has not been tried
> on a physical device since the bottom sheet, themes and the gift wall, away card and leaderboard
> were added: expect rough edges in the sheet drag and scrolling. See [Verification](#verification).

Requirements: iOS 15+, Swift 5.9+ (Xcode 15+). macOS 12+ is declared so the tests run on a Mac.

## Install

Swift Package Manager, in Xcode: File > Add Package Dependencies, enter the repository URL and
pick the `GiftingStack` product. In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/giftingstack/sdks.git", from: "0.1.1"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "GiftingStack", package: "sdks")]),
]
```

The package manifest is at the root of that repository (`Package.swift`), so the repository URL is
all Xcode needs. To work on the SDK itself, clone the repository and add `packages/sdk-ios` as a
local package (File > Add Package Dependencies > Add Local).

## Token flow

The app never holds your secret API key. Your own server creates a short-lived client token for
the signed-in user with `POST /v1/client-tokens`; the SDK asks for it through `getToken`:

```swift
import GiftingStack

let client = GiftingClient(getToken: { forceRefresh in
    // Return a cached token unless forceRefresh is true; then fetch a new one from your server.
    try await MyBackend.shared.giftingToken(forceRefresh: forceRefresh)
})
```

`getToken(false)` is called once per call. When the API answers 401 (usually an expired token),
the client calls `getToken(true)` once and repeats the request once. Errors thrown by `getToken`
reach your code unchanged.

## Usage

```swift
import GiftingStack
import SwiftUI

struct PostScreen: View {
    @StateObject private var effects = GiftEffectController()
    @StateObject private var tray: GiftTrayModel

    init(client: GiftingClient) {
        _tray = StateObject(wrappedValue: GiftTrayModel(client: client, receiver: "mert", reference: "post_42"))
    }

    @State private var noticeBottom: CGFloat = 320

    var body: some View {
        ZStack {
            PostView()
            // A draggable bottom sheet over the screen (spec 9.1); touches above it reach PostView.
            GiftTray(
                tray: tray, // gifts, balance, Send and the "Test mode" badge (a test token) come from the model
                theme: .dark,
                onInsetChange: { noticeBottom = $0 + 16 } // the notice sits above the sheet
            )
            // Once, over the whole screen. It never takes touches.
            GiftEffectLayer(controller: effects, noticeBottom: noticeBottom, theme: .dark)
                .ignoresSafeArea()
        }
        .onAppear {
            tray.effects = effects
            tray.start()
        }
        .onDisappear { tray.stop() }
    }
}
```

Received gifts (for example from your realtime channel) go straight to the layer:

```swift
effects.play(GiftEffectEvent(gift: gift, sender: "zeynep"))
```

Other calls:

| call                                                       | what                                                      |
| ---------------------------------------------------------- | --------------------------------------------------------- |
| `client.getGifts()`                                        | the catalog                                               |
| `client.getMe()`                                           | `{ user, balance }` of the token's user                   |
| `client.getReceivedGifts("mert")`                          | what a user received, per gift                            |
| `client.sendGift(SendGiftInput(...))`                      | one send; one idempotency key per call, reused by retries |
| `effects.play/cancel/clear`                                | the effect layer (ids start at 1, never reused)           |
| `tierFor`, `recipeFor`, `allRecipes`                       | the shared effect numbers, if you draw effects yourself   |
| `EffectScheduler`, `GiftTrayController`, `sendButtonState` | the pure logic, without SwiftUI                           |
| `TraySheetController`, `resolveSheetHeights`               | the bottom sheet logic, without SwiftUI                   |
| `themeFromAccent`, `contrastRatio`, `GiftTheme`            | theme tokens as colour strings                            |

Layer options: `thresholds` (nil: 100 / 10,000 or the remote ones), `quality` (`.high` / `.low`
for old phones: fewer sparks, no coin rain, no rays), `reducedMotion` (default: follows the system
Reduce Motion setting; then only the notice shows), `origin`, `pictureWaitMs` (300),
`noticeBottom` (150), `theme`, `pictureScale` (nil: automatic, about 1 on a phone, up to 2 in a big
layer, like the web), `remoteRecipes` (default true; `false` = no network), `recipesVersion`,
`recipesUrl`, `onEffectEnd`.

Tray options: `onTopUp` ("+ Coins" and "Get coins"), labels, `columns` (4), `defaultSelectedId`,
`disabled`, `bottomPadding` (add the bottom safe area), `theme`, `onSelect`, and the sheet
options of spec 9.1: `sheet` (default true; `false` keeps the fixed tray with `gridMaxHeight`
230), `initialSnap` (`.peek`, `.default`, `.expanded` = 90 % of the area), `snaps` (fractions),
`onSnapChange`, `onInsetChange`. The sheet fills the area it is given (put it in a `ZStack` over
your screen, `.ignoresSafeArea(edges: .bottom)`) and sits at its bottom. Icons are
`min(72 pt, 78 % of the cell)` like the web tray. Drag the handle or the header; below fully open
every drag on the grid moves the sheet, fully open the grid scrolls and a pull down at its top
collapses the sheet. VoiceOver: the handle "Gift tray" toggles, adjusts (swipe up/down) and has
"Show more gifts" / "Show fewer gifts".

Themes (spec 9.2): `GiftingTheme.standard` (the 1.0 look), `.dark`, `.light`,
`GiftingTheme.fromAccent("#ff4f9a", mode: .dark)` (every text pair at least 4.5:1), or any
`GiftingTheme(...)` / `GiftingTheme(GiftTheme(...))`. Pass the same theme to the tray and the layer.

Remote recipes (spec 13): the layer loads `https://assets.giftingstack.com/recipes.json` (cached in
memory, refreshed at most every 6 hours, 3 s timeout, backoff after failures) and new effects use
it; running and queued effects keep their recipe. The document is hosted there, and any failure
(offline, a bad file) fails quietly and the embedded numbers apply. The pure parts are `parseRemoteRecipes`,
`mergeRecipeSet`, `remoteRecipesUrl`; the loader is `RemoteRecipesLoader` (injectable transport and
`RecipesStorage`, default in memory). Web placements (popover, inline) are web only (spec 9.3).

Transport rules: `GiftingClient(baseURL:)` and the rooms `url` must be `https` / `wss`. Plain `http` / `ws` works only for
localhost, 127.0.0.1, ::1 and 10.0.2.2, or with `allowInsecure: true` (`GiftingClient`, `GiftRoomModel`); any other `http://` or
`ws://` URL is a programmer error and stops the app at once with a `precondition` failure (SPEC 3.1).
Pictures load over `https` only (`http` to loopback, `data:image` base64; SPEC 7.6), at most 5 MiB each, decoded as thumbnails of
at most 1024 px; a picture that failed is not requested again for 60 s. The catalog load downloads the small icons; the big picture is fetched for the
selected gift. `GiftTray(tray: tray)` takes the gifts, balance, Send and the "Test mode" badge from the model (what you pass
yourself wins); `testMode` is `nil` by default (follows the token: the model you pass, else any live `GiftTrayModel`), `true` / `false`
force it. The package carries Apple's privacy manifest (`PrivacyInfo.xcprivacy`: no tracking, no collected
data, the uptime clock as a required-reason API).

Errors are `GiftingError` (`status`, `type`, `message`, `requestId`, `retryable`,
`insufficientBalance`). `retryable` is true for network failures (status 0), 429 and 5xx.

### Gift wall, "while you were away", leaderboard (spec 14-16, 0.3.0)

```swift
let walls = GiftWallLoader(client: client)            // one per app or screen: shared batches + cache
GiftWall(loader: walls, user: post.author, reference: post.id, refreshKey: sentCount)

@StateObject var away = GiftAwayModel(client: client, effects: effects, resolveUsers: lookUp)
ZStack { content; GiftAwaySummary(model: away, theme: theme); GiftEffectLayer(controller: effects) }

@StateObject var board = GiftLeaderboardModel(client: client, board: .senders, resolveUsers: lookUp)
ScrollView { GiftLeaderboard(model: board, metricToggle: true, theme: theme) }
```

- Client: `getReceivedGifts(_:reference:)`, `queryGiftWalls` (POST, no idempotency key, empty list
  = no request), `getAway(_:)` / `ackAway(_:)` (PUT, the 204 body is never parsed),
  `getLeaderboard(_:query:)`; protocols `GiftWallAPI`, `GiftAwayAPI`, `GiftLeaderboardAPI` (the
  four-call `GiftingAPI` is unchanged, so existing mocks still compile).
- Pure core (fixture-tested): `wallChips`, `formatCount`, `GiftWallLoader`, `awaySenderLabel`,
  `planAwayReplay`, `awayCardDurationMs`, `AwayController`, `leaderboardRankLabel`,
  `groupThousands`, `pinnedMe`, `LeaderboardController`, `GiftRankColors` (medal tokens, not part
  of `GiftTheme`). Controllers take a `GiftClock` (default `SystemGiftClock`: uptime + `Task.sleep`).
- Platform deviations (Swift): `GiftWall` takes the shared `GiftWallLoader` instead of the client
  (a struct client has no identity to key a shared loader by); the away card and the leaderboard
  are a state holder plus a view (`GiftAwayModel` + `GiftAwaySummary`, `GiftLeaderboardModel` +
  `GiftLeaderboard`), like `GiftTrayModel` + `GiftTray`; wall chips wrap by an estimated chip width
  (iOS 15 has no `Layout`); `GiftLeaderboard` is a plain stack (wrap it in a `ScrollView`).
- Words: `GiftLabels` (same keys and English defaults as web/React Native). Reduced motion: no wall
  fade, no card slide, no replay (card only), no refresh spinner. VoiceOver: one label per wall
  ("Gifts: 12 Roses, 3 Hearts, and 37 more"), chips as buttons with 44 pt targets when
  `onPressChip` is set, rows "Rank 1, ayla, 54,000 coins", pinned "Your rank: 417, 120 coins", an
  announcement when the away card appears, `focusOnShow` moves the focus to it.

### Render slots

Draw the inside of a chip, a row or the card body yourself with a closure returning `AnyView?`. The SDK
keeps loading, order, names, the container, the spoken label, the press and the actions. `nil` draws the default.

```swift
GiftWall(loader: walls, user: post.author, onPressChip: openTray,
         renderChip: { chip in AnyView(Text("\(chip.gift.name) x\(chip.countText)")) })   // WallChipContext
GiftLeaderboard(model: board,
                renderRow: { row in row.isMe ? nil : AnyView(MyRow(row)) })                  // LeaderboardRowContext
GiftAwaySummary(model: away,
                renderSummary: { s in AnyView(MyCard(s.headline, close: s.dismiss)) })       // no close button, a tap does not dismiss
```

The "+37" overflow chip and the pinned "You" row stay the default. Wall chips wrap by an estimated
width, so keep a custom chip about as wide as the default.

### Gift rooms: everyone watching sees the gift (spec 17-18, beta)

A room is everyone watching one live stream, audio room or chat. Join it on the viewer screen and
every gift sent with that `roomId` plays on every viewer's screen, about 0.1-0.4 s after it was
sent. The SDK opens one WebSocket to `rt.giftingstack.com` (`URLSessionWebSocketTask`, protocols
`gs.v1` + the client token), reconnects with backoff, resumes and refreshes the token by itself.
Gift events only: no chat, no media, no history. The rooms server is live at `rt.giftingstack.com` (the project's "Gift rooms" switch must be on).

Your server mints the client token as usual, with `rooms` (room ids or prefixes ending in `*`
this user may join and send into; required: without it the token has no room access) and,
optionally, `name` (what viewers see as the sender). See the
token example in `packages/sdk-js/README.md` ("Gift rooms").

```swift
struct LiveScreen: View {
    let stream: Stream
    @StateObject private var effects = GiftEffectController()
    @StateObject private var room: GiftRoomModel
    @StateObject private var tray: GiftTrayModel

    init(stream: Stream) {
        self.stream = stream
        _room = StateObject(wrappedValue: GiftRoomModel(room: stream.id, getToken: getToken, client: client))
        _tray = StateObject(wrappedValue: GiftTrayModel(client: client, receiver: stream.hostId, roomId: stream.id))
    }

    var body: some View {
        ZStack {
            VStack {
                Text("\(room.viewers ?? 0) watching")
                GiftTray(tray: tray)
            }
            GiftEffectLayer(controller: effects)
        }
        .onAppear {
            room.effects = effects // room gifts play here
            tray.effects = effects
            room.join()
            tray.start()
        }
        .onDisappear {
            room.pause() // closes the socket, keeps the resume point; join() reconnects
            tray.stop()
        }
    }
}
```

- `GiftRoomModel(room:getToken:client:effects:...)`: `getToken` is the same function you give
  `GiftingClient`; `client` loads the catalog once so room gifts show the big picture. Options:
  `skipOwn` (default true: your own gifts already played on tap), `minTier` (`.medium` shows only
  medium and large gifts), `maxReplayAgeMs` (default 10,000), `resolveName` (a name for senders
  whose token has no `name`), `user`, `url`, `onEvent`, `onGap`. Published: `state`
  (`RoomState`: `status`, `attempt`, `retryInMs`, `code`, `reason`, `viewers`) and `viewers`.
- App lifecycle: the socket closes when the app enters the background and reconnects, with
  resume, when it comes back to the foreground (UIKit notifications; an `inactive` app keeps the
  socket). Apps that drive it from SwiftUI pass `pauseInBackground: false` and call
  `scenePhaseChanged(_:)` from `.onChange(of: scenePhase)`. A `pause()` of your own is not undone
  by the foreground. `leave()` leaves for good.
- Sending into the room: `roomId` on `SendGiftInput`, `GiftTrayController` and `GiftTrayModel`
  (sent as `room_id`; an empty string names no room).
- Pure core (fixture-tested, `rooms-*.json`): `parseRoomFrame`, `roomHelloFrame`, `roomUrl`,
  `roomTokenUser`, `roomRetryDecision`, `RoomEventFilter`, `roomGiftToEffect`, `RoomClient`
  (injected socket factory, `GiftClock`, random source, `getToken`). Use `RoomClient` with your own
  `RoomSocket` for a headless integration; `URLSessionRoomSocket` is the real transport.
- Platform deviations (Swift): protocol pings every 30 s (`sendPing`, no pong in 10 s = dropped)
  instead of the `ping` text, so `RoomClient` runs with `heartbeatMs: 0`; `RoomGiftEvent` is a
  struct whose `effectEvent` the layer plays; `subscribeEvents` instead of the reference's
  `onEvent(listener)`.

### Battle bar (versus; spec 18.7)

`GiftBattleBar` draws a battle round of the room: both receivers with their scores, a countdown, and a bar whose boundary slides as gifts arrive. It draws `battleView` only; your server starts and ends rounds. Nothing is drawn while the room has no round with two sides. VoiceOver gets one element (both scores, then the result).

```swift
GiftBattleBar(
    room: room,                                    // GiftRoomModel: follows its battle and ticks the clock
    users: [                                       // names and pictures by id (fallback: the id)
        "ava": BattleBarUser(name: "Ava", avatarUrl: "https://..."),
        "mateo": BattleBarUser(name: "Mateo"),
    ],
    sideColors: ["#e0457b", "#3a8dff"],            // optional: two #rrggbb colours (default: accent and coin)
    reducedMotion: nil,                            // nil: follows Reduce Motion
    theme: .dark,
    labels: BattleBarLabels(finalText: "Bitti", wins: "{name} kazandı")
)
// Or draw a round you hold yourself: GiftBattleBar(view: room.battleView(), ...)
```

The pure model (`battleBarModel`, `formatBattleScore`, `formatBattleClock`, `battleSideColors`) is in the core; the numbers are the shared fixture `battle-bar.json` (`BattleBarConformanceTests`). Reduced motion: no sliding, counting or pulse. The view uses only iOS 15 APIs: `TimelineView`, `AsyncImage`, `Animation.timingCurve`, `Animatable`, `onChange(of:perform:)`, `Task.sleep(nanoseconds:)`, `accessibilityReduceMotion`.

## Limits (from the contract)

- At most 6 small, 2 medium and 1 large effect on screen; up to 5 large gifts wait, a 6th drops
  the oldest waiting one silently. Over the cap, small and medium gifts show only the notice.
- The client retries a 5xx once, at once, with the same token and idempotency key; 429 and other
  4xx are never retried and `Retry-After` is ignored. Network failures are not retried.
- After a send the balance stays optimistic until the reconcile `getMe` answers;
  `sender_balance_after` is not used. `send` does not check affordability, the tray button does.
- Numbers are shown with en-US grouping (`1,234`) whatever the device locale, like the reference.
- `GiftImageCache` keeps up to 80 decoded pictures in memory; files are cached by `URLSession`.

## Demo app

`Demo/Sources` is "Pixel", a pretend social app that is one example integration of the SDK (the
same app as the web demo, `packages/sdk-js/demo/web.ts`; design: `docs/design/demo-app.md`). A
mock client with 250 ms latency and 60,000 coins, about 90 gifts from the live library
(`https://assets.giftingstack.com/library.json`, a 10-gift fallback), mock data in
`PixelData.swift` and `DemoComponentData.swift` (same people, posts, leaderboard and away summary
as the web demo). Tabs: Feed (four posts with drawn pictures; a Gift button opens the tray sheet
for the post's author with `reference` = post id, it closes after a send; each post has its gift
wall), Top (`GiftLeaderboard`, gifters or creators, you pinned at #417), Inbox (gifts from others,
newest first, a badge on the tab), Me (balance, "Get coins", received-gifts wall, "Hide me from
leaderboards"). The coin store ADDS coins. The "While you were away" card shows the first time
after install only (`UserDefaults`). Gifts from others do not arrive by themselves
(`PixelData.liveFeed = false`). No debug buttons on screen: hold the Pixel logo for 1 s for the
developer menu (incoming gift same as tray / random / cheapest / priciest, x5 combo, away summary
again, wall +5, quality, theme, motion, mock failure (offline banner), reset).

Run it on an iPhone, by hand in Xcode:

1. File > New > Project > iOS > App. Name `GiftingStackDemo`, interface SwiftUI, language Swift.
   Save it anywhere (outside the repository is fine).
2. Delete the generated `ContentView.swift` and `GiftingStackDemoApp.swift`.
3. Drag the files of `packages/sdk-ios/Demo/Sources` into the project ("Copy items if needed"
   off, so you run the repository's files).
4. File > Add Package Dependencies > Add Local, choose `packages/sdk-ios`, add the
   `GiftingStack` library to the app target.
5. Set the deployment target to iOS 15.0 or later, pick your team under Signing, select your
   iPhone and Run.

Or with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`, then
`cd packages/sdk-ios/Demo && xcodegen generate && open GiftingStackDemo.xcodeproj`, set your team
and Run.

## Development

```sh
node packages/sdk-ios/tool/generate-spec-data.mjs          # after recipes.json changes
node packages/sdk-ios/tool/generate-spec-data.mjs --check  # CI: fails if the Swift file is stale
cd packages/sdk-ios && swift test                          # on a Mac
```

Layout: `Sources/GiftingStack/Core` is Foundation only (models, client, transport, tiers and
recipes, combo, `EffectScheduler`, `PictureGate`, `EffectTimeline`, `GiftTrayController`,
`TraySheet`, `Theme`, `RemoteRecipes`, `RecipesLoader`, and for 0.3.0 `ComponentModels`,
`GiftWallLogic`, `AwayLogic`, `LeaderboardLogic`, `GiftClock`, `ComponentLabels`);
`Sources/GiftingStack/UI` is SwiftUI (`#if canImport(SwiftUI)`). The tests read the fixtures from
`../sdk-spec/conformance` relative to their own source file, so run them inside the repository.

## Verification

The package is built and tested on a macOS runner in CI for every release:

| step                                       | proves                                                                                                                                                                                     | status                                                                                                                                                                   |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `node tool/generate-spec-data.mjs --check` | `SpecData.generated.swift` is what `recipes.json` generates                                                                                                                                | green                                                                                                                                                                    |
| `swift build`                              | Core and UI compile for macOS (SwiftUI on macOS 12+)                                                                                                                                       | green                                                                                                                                                                    |
| `swift test`                               | 156 tests: the constants equal `recipes.json`, and every fixture of the shared contract (`tiers`, `combo`, `client`, `effects`, `tray`, `sheet`, `theme`, `wall`, `away`, `leaderboard` …) | green                                                                                                                                                                    |
| `xcodebuild ... iOS Simulator`             | the package, including the UIKit-only paths, compiles for iOS                                                                                                                              | green                                                                                                                                                                    |
| A real iPhone                              | the demo runs on a device                                                                                                                                                                  | an early build ran on an iPhone 13. Since then the bottom sheet, themes and the wall, away card and leaderboard were added: they are not tried on a device yet (preview) |

Which test covers what (to trace a red run): `SheetConformanceTests` (sheet.json heights and
scenarios, defaults 600 / 0.9, observers, velocity), `SheetMeasureTests` (measurement to
`SheetLayout`: 90 gifts reach 90 %, the gift count changes the cap, no heights before the floors
are measured, grid scroll range, grid momentum), `ThemeConformanceTests` (theme.json contrast,
presets, accents x modes, invalid; colour helpers), `RemoteRecipesConformanceTests`
(remote-recipes.json parse, merge, urls; the SPEC 13.3 table), `RecipesLoaderTests`
(`remoteRecipes: false`, version pin, cache, 6 h refresh, backoff, ignored documents, single
flight, timeout, throwing storage, recipe fixed at `play`, remote combo window),
`FixtureCoverageTests` (no fixture file without a runner; wall/away/leaderboard are no longer
acknowledged as pending), `ClientConformanceTests` (client.json through the shared
`Support/ClientScenarioRunner.swift`), `WallConformanceTests` (wall.json chips, formatCount,
loader window/batch/dedupe/TTL/failure/invalidate, client section), `AwayConformanceTests`
(away.json plan, senderLabel, controller states/ack/retry/throttle/timers, client section with
the 204), `LeaderboardConformanceTests` (leaderboard.json rankLabel, pin, rankColors tokens and
contrast, controller cache/stale/in-flight/errors, client section with the 503 retry). Every new
runner fails on a fixture key it does not know.

0.3.0 components: what only a device can show: the wall's chip wrapping (estimated widths), the
away card's slide and the replay over it, the leaderboard's tabs and pinned row, VoiceOver labels
and the away announcement, Reduce Motion, and the Pixel demo (tabs, tray per post, developer menu).

What only a person on a device can judge (spec section 11, L3/L4): smoothness on the iPhone 13
and an older phone, easing and overshoot feel, spark/coin spread and the ray look compared side by
side with the React Native demo, the notice slide and counter pop, no flicker of the previous
picture, the effect and notice starting together, the layer passing touches through, VoiceOver
labels and announcements, Reduce Motion, heat; new in 0.2.0: the sheet's drag, flick and snap
feel, the grid's own scrolling and momentum (iOS 15 cannot switch a `ScrollView` off, so the sheet
scrolls the grid itself), the pull-down handoff at the top of the grid, no tap after a drag, the
coin store and the themes.

## License

MIT, see [LICENSE](LICENSE). The licence covers this package's code only. The GiftingStack
name and logo, the GiftingStack service and API, and the ready-made gift library
(`assets.giftingstack.com`) are not part of it; the gift library has its own terms.
