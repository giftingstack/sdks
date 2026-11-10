# Changelog

All notable changes to `@giftingstack/sdk`. The shared contract (`packages/sdk-spec`) has its own
version (`SPEC_VERSION`); this package states which one it passes.

## 0.1.4

- React Native: the gift notice's text shrinks and ends with "…", so the combo count (x2, x3) stays inside the pill (found on a real iPhone through Expo Go; same rule as the web notice).
- The tray title stays on one line and ends with "…" when it does not fit (SPEC 9): a long or translated `title` no longer wraps and pushes the small (peek) tray taller.

## 0.1.3

The React Native layer has the same changes as the web one (jsdom tests only); it was not tried on a device for this release.

- With `scrim` on, a tap on the empty space beside a tray at peek (the small state) now closes it: the dim stays hidden there, but it takes the tap (SPEC 9.4, `scrimTakesTouches`; a tall tray still lowers to peek first with `scrimTap` "lower"). The page behind a peeking tray is no longer touchable while the tray is open; leave `scrim` off for that.
- The web tray (sheet) now fades in over 200 ms and rises from 3 % of its height over 220 ms when it opens, like the Flutter and iOS trays; it was appearing at once (SPEC 9.4). Reduced motion: no entrance.
- A battle can have three to eight sides (SPEC 18.7, a free-for-all: everybody races on their own; teams are not part of it). The battle bar draws every side: two sides look exactly as before, three or more get a row of cells (avatar, name, score) with the clock above and a bar of proportional segments (each side in its colour, none under 6 %, white lines between them); the winner, the banner and the spoken sentence cover every side. `sideColors` is a list with one colour per side (`GiftBattleBar`, `BattleBar`, `joinRoom`, `useGiftRoom`, `<gift-room side-colors>`) (a shorter list keeps the default for the sides it does not name; the default palette is the theme's accent, its coin colour, then teal `#2ec4b6` and pink `#ff5d8f`, then the same four again). The gift notice of a battle names the receiver and borders its pill for every side, not only the first two. New: `battleSidePalette`, `battleSegmentPcts`, `BattleBarModel.pcts`.

- The gift notice of a battle says who got the gift (SPEC 7.4, 18.4): line two reads `sent Rose to Mia` and the pill has a 2 px border in the receiving side's colour (the bar's accent / coin colour, or the new room option `sideColors`, the same pair you give the bar). Only when the room has a battle round with two sides and the receiver is one of them; every other notice looks as before. `GiftEffectEvent.receiver` and `NoticeData.receiver` are new, so an app that plays its own events can set them; `roomGiftToEffect` takes `battle` and `sideColors`. Web: `joinRoom({ sideColors })`, `<gift-room side-colors="#ff3366,#00aa88">`; React Native: `useGiftRoom({ sideColors })`. The user's own gift says who got it too: `createGiftTray({ receiverOf: room.receiverFor })` / `useGiftTray({ receiverOf: room.controller.receiverFor })` (new `RoomClient.receiverFor`, `battleReceiver`). The pill border is a 2 px ring in the side colour plus a 1 px line in the text colour inside it, so it shows on a pill of the same colour (the default accent); a gift only counts as a battle gift inside the round (`started <= at < ends`); a combo counts per receiver.

## 0.1.2

- The tray's "Test mode" badge no longer touches the drag handle: the header starts right below the
  handle (web and React Native; SPEC 9.1). The sheet is a few points taller; its heights are measured,
  so nothing else changes.

## 0.1.1

No code change. The four SDKs (JavaScript, Flutter, Android, iOS) share one version number from now
on; Android and iOS gained the 5,000 ms leaderboard polling minimum this package already had.

## 0.1.0 (preview)

First publishable build: ESM with TypeScript declarations for `@giftingstack/sdk`,
`@giftingstack/sdk/web`, `@giftingstack/sdk/react-native` and `@giftingstack/sdk/elements` (the
last one registers the `<gift-*>` custom elements; everything else is side-effect free).
`react` and `react-native` are optional peer dependencies.

### Test mode badge

- React Native `GiftTray` takes `tray={useGiftTray(...)}` and reads the gifts, the balance, `send`
  and `testMode` from it. The "Test mode" badge now shows by itself while the token was made with a
  test key (`GET /v1/client/me` answers `livemode: false`). `testMode={false}` forces it off,
  `testMode` forces it on. `gifts`, `balance` and `onSend` still work and win over `tray`.
- Every demo's mock client answers `livemode: false`.

### Security and robustness (audit 2026-10-25)

- `createGiftingClient({ baseUrl })` and a room `url` refuse `http://` and `ws://` unless the host is
  `localhost`, `127.0.0.1`, `::1` or `10.0.2.2`, or you pass `allowInsecure: true` (R-07).
  `<gift-room allow-insecure>` for the element.
- Pictures: only `https://`, `data:image/`, `http://` to localhost and paths on your own origin are
  loaded; a picture that fails is not requested again for 60 s; the tray prefetches every gift's
  small icon but only the selected gift's big picture (R-08).
- Web: the stylesheet is a constructable stylesheet (`adoptedStyleSheets`) where the browser has
  them, so a strict `style-src` needs no nonce. `configureStyles({ nonce })` sets the nonce of the
  fallback `<style>` element; see "Content-Security-Policy" in the README (R-11).
- `reconnectNow()` (and so the page becoming visible, or `online`) never skips a 4008/4009 wait (R-15).
- `<gift-room>`: changing `min-tier`, `skip-own`, `max-replay-age-ms`, `effects`, `pause-when-hidden`
  or the `getToken`, `client`, `resolveName`, `thresholds` properties no longer reconnects; the new
  `RoomHandle.setOptions` does the same for `joinRoom` (R-16).
- Leaderboard `refreshIntervalMs` is at least 5,000 ms (R-17).
- `sendGift` repeats a lost connection (no answer at all, not a timeout) once with the same
  idempotency key (R-18). Idempotency keys come from `crypto.getRandomValues` before `Math.random`
  (R-19).
