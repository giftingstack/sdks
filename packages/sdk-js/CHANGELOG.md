# Changelog

All notable changes to `@giftingstack/sdk`. The shared contract (`packages/sdk-spec`) has its own
version (`SPEC_VERSION`); this package states which one it passes.

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
