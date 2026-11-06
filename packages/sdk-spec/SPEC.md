# GiftingStack SDK specification

Version 1.0.0 (`recipes.json#specVersion`). Reference implementation: `packages/sdk-js`
(`@giftingstack/sdk`, TypeScript core + React Native), tested on an iPhone 13.

This document is the contract for the Web, Flutter, Android and iOS SDKs. It is written for an
engineer who has not read the TypeScript. The key words MUST, MUST NOT, SHOULD and MAY are used
as in RFC 2119. Every number here comes from the reference code; where the reference is odd, this
document says what it does and lists the oddity under "Open questions" instead of fixing it.

Files in this package:

| file                        | what                                                                                                                  |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `SPEC.md`                   | this document                                                                                                         |
| `recipes.json`              | the shared numbers (thresholds, combo window, caps, effect recipes). Generated from the reference; never edit by hand |
| `conformance/*.json`        | language-neutral test cases every platform MUST pass                                                                  |
| `conformance/README.md`     | the exact fixture formats and matching rules                                                                          |
| `scripts/build-recipes.mjs` | regenerates `recipes.json` (`npm run build:recipes` in `packages/sdk-spec`)                                           |
| `scripts/build-remote.mjs`  | writes the hosted copies `dist/recipes.json` and `dist/recipes.<specVersion>.json` (section 13.6)                     |

A platform conforms when (1) its constants equal `recipes.json`, (2) its test suite runs every
fixture in `conformance/` and passes, and (3) a human has checked the device-only items of
section 11.

## 1. Architecture

Every SDK has the same layers. Only the last one differs per platform.

1. **Models and client**: `Gift`, `Me`, `ReceivedGift`, `GiftTransaction`, `SendGiftInput`,
   `GiftEffectEvent`, `GiftingError`, `GiftingClient` (section 3).
2. **Pure logic** (no UI, no timers, no network of its own): `tierFor`, `recipeFor`,
   `allRecipes`, the combo tracker (section 4), `EffectScheduler` (section 6),
   `GiftTrayController` and `sendButtonState` (section 8), `TraySheetController` and
   `resolveSheetHeights` (section 9.1), `parseRemoteRecipes`, `mergeRecipeSet` and
   `remoteRecipesUrl` (section 13), `wallChips`, `formatCount` and `GiftWallLoader` (section 14),
   `planAwayReplay`, `awaySenderLabel` and `AwayController` (section 15), `pinnedMe`,
   `leaderboardRankLabel` and `LeaderboardController` (section 16), `inboxTimeLabel`, `inboxRows` and `inboxUnread` (section 19). This is what the fixtures test. Port it line by line from
   `packages/sdk-js/src/core`; it is small (about 600 lines).
3. **UI**: the effect layer (draws effects and the notice, section 7), the tray (section 9 and the
   bottom sheet of 9.1).

The UI layer MUST NOT contain decisions that the pure layer makes (caps, queue, combo, notice
text, optimistic balance, button state, sheet snapping). It only draws what the pure layer says and reports back
when a picture is ready (`started`) and when an animation ends (`finished`).

## 2. Public API and naming

Same concepts, platform idioms. Names in this table are normative.

| concept           | Web / TypeScript                                                                                           | Flutter (Dart)                                                                                     | Android (Kotlin, Compose)                                                                                                       | iOS (Swift, SwiftUI)                                                                                                           |
| ----------------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| package           | `@giftingstack/sdk` (+ `/web`)                                                                             | `giftingstack`                                                                                     | `com.giftingstack.sdk`                                                                                                          | `GiftingStack` (SwiftPM)                                                                                                       |
| models            | interfaces `Gift`, `Me`, `ReceivedGift`, `GiftTransaction`, `SendGiftInput`, `GiftEffectEvent`             | immutable classes, same names, `fromJson`/`toJson`                                                 | `data class`es, same names                                                                                                      | `struct`s, same names, `Codable`, `Sendable`                                                                                   |
| error             | `class GiftingError extends Error`                                                                         | `class GiftingException implements Exception`                                                      | `class GiftingException : Exception`                                                                                            | `struct GiftingError: Error`                                                                                                   |
| client            | `createGiftingClient(options): GiftingClient`                                                              | `GiftingClient({getToken, baseUrl, httpClient})`                                                   | `GiftingClient(getToken, baseUrl, transport)`                                                                                   | `GiftingClient(getToken:baseURL:transport:)`                                                                                   |
| client calls      | `Promise<T>`                                                                                               | `Future<T>`                                                                                        | `suspend fun`                                                                                                                   | `async throws`                                                                                                                 |
| token provider    | `({ forceRefresh }) => Promise<string>`                                                                    | `Future<String> Function({required bool forceRefresh})`                                            | `suspend (forceRefresh: Boolean) -> String`                                                                                     | `@Sendable (_ forceRefresh: Bool) async throws -> String`                                                                      |
| tiers, recipes    | `tierFor`, `recipeFor`, `allRecipes`                                                                       | top-level functions, same names                                                                    | top-level functions, same names                                                                                                 | free functions, same names                                                                                                     |
| combo             | `createComboTracker(windowMs?)`                                                                            | `ComboTracker([windowMs])`                                                                         | `ComboTracker(windowMs)`                                                                                                        | `ComboTracker(windowMs:)`                                                                                                      |
| scheduler         | `class EffectScheduler`                                                                                    | `class EffectScheduler`                                                                            | `class EffectScheduler`                                                                                                         | `final class EffectScheduler`                                                                                                  |
| effect layer      | `<gift-effect-layer>` custom element (class `GiftEffectLayerElement`) with `play`/`cancel`/`clear` methods | `GiftEffectLayer(controller: GiftEffectController)` widget; controller has `play`/`cancel`/`clear` | `@Composable GiftEffectLayer(state: GiftEffectLayerState)`, `rememberGiftEffectLayerState()`; state has `play`/`cancel`/`clear` | `GiftEffectLayer(controller: GiftEffectController)` view; `GiftEffectController: ObservableObject` has `play`/`cancel`/`clear` |
| tray state holder | `class GiftTrayController` (`getState`, `subscribe`)                                                       | `class GiftTrayController extends ChangeNotifier` (`state` getter)                                 | `class GiftTrayController` with `val state: StateFlow<GiftTrayState>`                                                           | `@MainActor final class GiftTrayController: ObservableObject` with `@Published private(set) var state`                         |
| tray view         | `<gift-tray>` custom element, events `send`, `topup`                                                       | `GiftTray` widget                                                                                  | `@Composable GiftTray(...)`                                                                                                     | `GiftTray` view                                                                                                                |
| send button logic | `sendButtonState(input)`                                                                                   | `sendButtonState(...)`                                                                             | `sendButtonState(...)`                                                                                                          | `sendButtonState(...)`                                                                                                         |
| sheet logic       | `class TraySheetController`, `resolveSheetHeights(layout)`                                                 | same names; a `ChangeNotifier` wrapper may observe it                                              | same names; expose the state as `StateFlow`                                                                                     | same names; an `ObservableObject` wrapper may observe it                                                                       |
| gift wall logic   | `wallChips`, `formatCount`, `class GiftWallLoader`                                                         | same names                                                                                         | same names                                                                                                                      | same names                                                                                                                     |
| away logic        | `planAwayReplay`, `awaySenderLabel`, `class AwayController` (`getState`, `subscribe`)                      | same names; a `ChangeNotifier` wrapper may observe it                                              | same names; expose the state as `StateFlow`                                                                                     | same names; an `ObservableObject` wrapper may observe it                                                                       |
| leaderboard logic | `pinnedMe`, `leaderboardRankLabel`, `class LeaderboardController` (`getState`, `subscribe`)                | same names; a `ChangeNotifier` wrapper may observe it                                              | same names; expose the state as `StateFlow`                                                                                     | same names; an `ObservableObject` wrapper may observe it                                                                       |
| component views   | `GiftWall`, `GiftAwaySummary` (`<gift-away-summary>`), `GiftLeaderboard` (pending, sections 14-16)         | same names (pending)                                                                               | same names (pending)                                                                                                            | same names (pending)                                                                                                           |
| React Native only | `useGiftTray(options)` hook (wraps `GiftTrayController`)                                                   | n/a                                                                                                | n/a                                                                                                                             | n/a                                                                                                                            |

Rules for every platform:

- Model properties use the platform's case (`iconUrl`, `animationUrl`, `sortOrder`, `unitPrice`,
  `senderBalanceAfter`, `createdAt`); the JSON keys stay the API's snake_case. TypeScript keeps
  the snake_case keys on API models (that is what the reference does).
- `created_at` stays a string (ISO 8601) in v1. A platform MAY add a parsed date beside it.
- JSON decoding MUST ignore unknown fields. Nullable API fields (`description`, `icon_url`,
  `animation_url`, `message`, `reference`, `gift.icon_url`) MUST be nullable in the model.
- The HTTP transport MUST be injectable (the conformance runner replaces it). Web: a `fetch`
  function; Dart: `http.Client`; Kotlin and Swift: a small `GiftingTransport` protocol/interface
  `send(request) -> response` with a default implementation (OkHttp/Ktor, `URLSession`).
- The web package is framework-free: plain classes plus custom elements, no React, no build-time
  framework. Its pure layer IS the reference core; the web UI reuses it.
- The effect controller's `play` returns an `Int` id; ids start at 1 and increase by 1 per `play`
  call, for the lifetime of the layer (never reused, not reset by `clear`).

### Model fields

```text
Gift            id, name, description?, price:int, icon_url?, animation_url?, sort_order:int
Me              user, balance:int
ReceivedGift    gift { id, name, icon_url? }, count:int
GiftTransaction id, sender, receiver, gift { id, name, icon_url? }, quantity:int, unit_price:int,
                total:int, message?, reference?, status ("completed" | "reversed"), created_at,
                sender_balance_after:int
SendGiftInput   receiver, giftId, quantity?, message?, reference?, idempotencyKey?
GiftEffectEvent gift { id, name, price, image?, icon? }, sender?, quantity?
GiftWall        receiver, reference?, gifts: ReceivedGift[]                 (section 14)
AwaySummary     see section 15.1
Leaderboard     see section 16.1
```

`GiftEffectEvent.gift.image` is the big picture shown in the effect (the gift's 512 px
`animation_url`, falling back to `icon_url`). `icon` is the small picture for the notice (the 256 px
`icon_url`); it falls back to `image`. `sender` defaults to `"Someone"`, `quantity` to 1.

## 3. Client

### 3.1 Construction

- Options: `getToken` (required), `baseUrl` (default `https://api.giftingstack.com`), `allowInsecure`
  (default false), `timeoutMs` (default 20,000; 0 = no timeout; section 3.4), transport.
- **Plain-text base URLs (decided 2026-11-03, audit R-07).** A token travels in every request, so
  constructing a client with a `baseUrl` that starts with `http://` (any case) MUST fail at once,
  with the platform's argument error (a programmer error, never a `GiftingError`; JS `Error`, Dart
  `ArgumentError`, Kotlin `IllegalArgumentException`, Swift a thrown/`precondition` failure the
  app cannot miss in development), unless the host is loopback or `allowInsecure` is true. Loopback
  hosts are exactly `localhost`, `127.0.0.1`, `::1` and `10.0.2.2` (the Android emulator's alias of
  the host machine); the host is read without userinfo, port and IPv6 brackets, compared in lower
  case (so `localhost.evil.com` and `127.0.0.2` are NOT loopback). `https://` always passes; so does
  a URL with another scheme or none (the transport fails it later). The message names the option
  (`allowInsecure`) and shows only scheme and host, never userinfo. The same rule applies to the
  rooms URL (`ws://` vs `wss://`, section 18.5, option `url`/`allowInsecure`) when a room client is
  created or its options are replaced. Pure helpers: `urlHost`, `isLoopbackHost`, `isInsecureUrl`,
  `assertSecureUrl`. Tests: JS `test/insecure-urls.test.ts`, Flutter `test/insecure_urls_test.dart`.
- The base URL MUST have all trailing `/` removed (regex `/+$`). A path in the base URL is kept:
  `http://localhost:8787/proxy/` + `/v1/client/gifts` = `http://localhost:8787/proxy/v1/client/gifts`.

### 3.2 Endpoints

| call                                | request                                                                                 | returns                                |
| ----------------------------------- | --------------------------------------------------------------------------------------- | -------------------------------------- |
| `getGifts()`                        | `GET {base}/v1/client/gifts`                                                            | the response's `data` array            |
| `getMe()`                           | `GET {base}/v1/client/me`                                                               | the body `{ user, balance, livemode }` |
| `getReceivedGifts(user)`            | `GET {base}/v1/client/users/{enc(user)}/received-gifts`                                 | the response's `data` array            |
| `sendGift(input)`                   | `POST {base}/v1/client/gift-transactions`                                               | the body (a `GiftTransaction`)         |
| `getReceivedGifts(user, reference)` | `GET {base}/v1/client/users/{enc(user)}/received-gifts?reference={enc(reference)}`      | the response's `data` array (14.1)     |
| `queryGiftWalls(items)`             | `POST {base}/v1/client/gift-walls/query`                                                | the response's `data` array (14.1)     |
| `getAway(query)`                    | `GET {base}/v1/client/me/away?since=&max_groups=`                                       | the body (15.1)                        |
| `ackAway(cursor)`                   | `PUT {base}/v1/client/me/away/cursor`                                                   | nothing (204, 15.1)                    |
| `getLeaderboard(board, query)`      | `GET {base}/v1/client/leaderboards/{enc(board)}?period=&metric=&at=&limit=&include_me=` | the body (16.1)                        |

- `enc` is exactly JavaScript `encodeURIComponent`: UTF-8 percent-encoding of every byte except
  `A-Z a-z 0-9 - _ . ! ~ * ' ( )`. Space is `%20` (never `+`), `/` is `%2F`, `:` is `%3A`. Hex
  digits upper case. Do not use form/query encoders (Kotlin `URLEncoder`, Swift
  `urlQueryAllowed`) as they are; check against `client.json`.
- List responses also carry `has_more` (always `false` for these endpoints); it is ignored.
- Query strings (sections 14-16 only): parameters in the order the section lists them, each only
  when given (never `key=` or `key=null`), `key=enc(value)` joined by `&`; no `?` when none.

### 3.3 Headers and body

- Every request: `Authorization: Bearer {token}`.
- With a body (`sendGift`, `queryGiftWalls`, `ackAway`): `Content-Type: application/json`. GET
  requests send no body and no `Content-Type`. Only `sendGift` sends an `Idempotency-Key`.
- `sendGift` body: `{ receiver, gift_id, quantity, message, reference }` with every field whose
  input value is absent left OUT of the JSON (not `null`). `idempotencyKey` is never in the body.
- `sendGift` header `Idempotency-Key`: `input.idempotencyKey` verbatim when given, else a new key
  generated once per `sendGift` call. Generated keys SHOULD be UUID v4 (the reference uses
  `crypto.randomUUID()`, falling back to 128 random bits from `crypto.getRandomValues` written as
  four groups of 8 hex digits joined by `-`, and only without any crypto to `Math.random`). The
  same key MUST be used for every attempt of that call (401 repeat and 5xx retry). GET requests
  send no `Idempotency-Key`.

### 3.4 Attempts (exact order)

```text
token = getToken(forceRefresh: false)
res   = attempt(token)
if res.status == 401:            # an expired token, usually
    token = getToken(forceRefresh: true)
    res   = attempt(token)
if res.status >= 500:            # one quiet retry, same token, same key, no delay
    res   = attempt(token)
# attempt(token) itself, for sendGift only: one transport failure per call is repeated at once,
# same token, same key (see below)
if res.status not in 200..299:   # raise GiftingError (3.5)
return decode(res.body)
```

Consequences, all covered by `client.json`: at most one refresh and at most 3 HTTP requests per
call (4 for `sendGift`, see the lost-connection repeat below); 401 then 5xx then retry is possible (3 requests); a 401 that arrives on the 5xx retry is not
refreshed; 429 and all other 4xx are never retried; there is no backoff and `Retry-After` is
ignored. `getToken` is called once per client call, plus once more after a 401.

A transport failure (no response: DNS, offline, TLS, connection reset) or a **timeout** on ANY
attempt ends the call at once with `GiftingError(status 0, type "network_error", message "Could not reach
GiftingStack. Check your connection.", requestId null)`. A **GET or a POST without a key** is
never retried after a transport failure. **`sendGift` repeats one lost connection** (decided
2026-11-03, audit R-18): the first attempt that gets no response at all (DNS, offline, TLS, reset;
**not** our own timeout) is repeated once, at once, with the same token and the same
`Idempotency-Key`; if the first request did arrive the server replays it, so nothing is charged
twice. Only one such repeat per call (it can follow a 401 repeat or a 5xx retry, so a send makes at
most 4 requests); a second transport failure ends the call as above. Fixtures: `client.json`
(the scenarios named "sendGift: ... lost connection ..." and the 500 one).

**Timeout** (`timeoutMs`, default 20,000, 0 = off): each HTTP attempt (not the whole call: a 401
repeat or a 5xx retry gets its own) has this long from sending the request until its response is
read. A slower attempt is cancelled and is a transport failure as above (`status 0`,
`network_error`, same message, not repeated even for a send), so a hanging connection cannot keep a
tray on "loading" or a send on its spinner forever. Platforms that cannot bound the whole attempt use their
closest equivalent (iOS: the default `URLSessionTransport` makes its own session with
`timeoutIntervalForRequest` and `timeoutIntervalForResource` set to the timeout, 0 keeps the
URLSession defaults; Android keeps its 15 s connect / 30 s read timeouts and does not take the
option). `getToken` has no timeout of its
own here: it is the app's function.

### 3.5 Errors

For a non-2xx final response, parse the body as JSON (failure = no body) and build:

| field       | value                                                                                             |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `status`    | the HTTP status                                                                                   |
| `type`      | `body.error.type` if present, else `"unknown_error"`                                              |
| `message`   | `body.error.message` if present, else `"Request failed ({status})."` e.g. `Request failed (404).` |
| `requestId` | `body.error.request_id` if present, else the `X-Request-Id` response header, else `null`          |

A **2xx response whose body cannot be read** (not JSON, cut off, or JSON the typed model cannot
decode) is `GiftingError(status, "invalid_response", "Invalid response ({status}).", requestId)`
with `requestId` = the `X-Request-Id` response header, else `null`. It carries NO part of the
body (a proxy's login page or an HTML error must never reach an error screen or a log), is never
retried and has `retryable false` (the status is below 500). A 204 has no body and is not read.
Fixture cases: `client.json` ("2xx that is not JSON", "2xx with a cut-off JSON body").

Derived, read-only:

- `retryable` = `status == 0 || status == 429 || status >= 500`.
- `insufficientBalance` = `type == "insufficient_balance"`.

The API's error body is `{ "error": { "type", "message", "request_id", "retryable", "details"? } }`
(the API's error format). The SDK computes `retryable` itself; it does not read the
body's `retryable`. Errors the API returns on these endpoints include `invalid_client_token` (401),
`invalid_request` (400), `room_not_allowed` (403, a `room_id` outside the token's `rooms`),
`not_found` (404), `payload_too_large` (413), `insufficient_balance`,
`gift_inactive`, `self_gift_not_allowed`, `user_deleted`, `idempotency_key_reused` (422),
`rate_limited` (429), `temporarily_unavailable` (503), `internal_error` (500).

Errors thrown by `getToken` itself propagate unchanged (they are not wrapped). See Open questions.

## 4. Tiers, recipes, combo

### 4.1 Tiers

`tierFor(price, thresholds?)`: thresholds `{ mediumFrom: 100, largeFrom: 10000 }` by default; a
partial object overrides only the given fields. `price >= largeFrom` is `large` (checked first),
else `price >= mediumFrom` is `medium`, else `small`. Prices are in the customer's own coin units.

### 4.2 Recipes

`recipeFor(tier, quality = "high")` returns a fresh copy of the tier's recipe. `quality "low"`
(old or slow phones) changes three fields: `sparks = floor(sparks / 3)`, `coins = 0`,
`rays = false`. Everything else (timings, scale, dim, notice) is unchanged.
`allRecipes(quality)` returns `{ small, medium, large }`.

The values are in `recipes.json` (`recipes.high`, `recipes.low`). For reading convenience:

| field (unit)           | small    | medium | large    |
| ---------------------- | -------- | ------ | -------- |
| `peakScale` (x 100 dp) | 0.9      | 1.5    | 2.8      |
| `flyInMs`              | 700      | 800    | 900      |
| `holdMs`               | 0        | 700    | 1600     |
| `flyOutMs`             | 600      | 600    | 550      |
| `stage`                | float-up | center | center   |
| `sparks` high / low    | 0 / 0    | 24 / 8 | 50 / 16  |
| `sparkSpread` (dp)     | 0        | 130    | 230      |
| `coins` high / low     | 0 / 0    | 0 / 0  | 34 / 0   |
| `dim`                  | no       | no     | yes      |
| `rays` high / low      | no       | no     | yes / no |
| `noticeMs`             | 2400     | 2400   | 2800     |
| `noticeBig`            | no       | no     | yes      |

Units: lengths in dp (Android dp, iOS points, Flutter logical pixels, CSS px). Times in ms.

### 4.3 Combo

A combo tracker counts the same gift sent again and again by the same person ("x2, x3").

- `hit(sender, giftId, now)` returns the run length, starting at 1. Every pair `(sender, giftId)`
  has its own run. It continues the pair's run (count + 1) only if that pair's previous hit
  satisfies `now - previousHitTime < windowMs` (strictly less). Otherwise it starts a new run at
  1. Every hit, continuing or not, becomes that pair's "previous hit".
- Default `windowMs` is 2500. The gap is measured from the previous hit, not the first, so hits
  every 2000 ms continue forever. A gap of exactly 2500 ms starts over.
- Pairs do not interrupt each other: A, B, A gives 1, 1, 2 (when A's second hit is inside the
  window). A run that paused for the window or more is forgotten; at most 64 runs are remembered
  (the one that hit longest ago is dropped).
- The pair compares both strings exactly; ids containing separators never collide (the reference
  keys on the JSON array `[sender, giftId]`).
- `reset()` forgets every run.
- `now` is milliseconds. The reference uses the wall clock (`Date.now()`); a negative gap (clock
  went back) counts as inside the window. Native platforms SHOULD use a monotonic clock.

## 5. What a gift looks like (overview)

| price (default) | effect                                                                     |
| --------------- | -------------------------------------------------------------------------- |
| under 100       | the picture floats up from the bottom; the notice slides in with a counter |
| 100 to 9,999    | the picture flies to the middle and bursts into sparks                     |
| 10,000 and up   | the screen dims, light rays and a glow, sparks, coin rain, a golden notice |

## 6. Effect scheduler (pure, fixture-tested)

`EffectScheduler` decides what is on screen. Reference: `packages/sdk-js/src/core/effects.ts`.

Constants (`recipes.json`): `maxConcurrentEffects = { small: 6, medium: 2, large: 1 }`,
`maxQueuedLarge = 5`, `defaultSenderName = "Someone"`.

State: next id (starts at 1), running count per tier, the large queue (FIFO), the map of effects
on screen (insertion order), a combo tracker (window fixed at construction), and the notice
(`key`, `noticeId` counter starting at 0, `owner` play id starting at 0, last `NoticeData`,
`visible`).

Construction: `comboWindowMs` (default 2500) and a clock `now()`. Options that MAY change at any
time and are read at each `play`: `thresholds`, `quality` (default `high`), `reducedMotion`.

Listener (the UI implements it): `enter(effect)`, `exit(effect)`, `end(effect)`,
`notice(data, durationMs)`, `noticeHide()`, `clear()`. A `ScheduledEffect` is
`{ id, event, recipe, count }`.

`play(event) -> id`:

1. `tier = tierFor(event.gift.price, thresholds)`, `recipe = recipeFor(tier, quality)`.
2. `sender = event.sender ?? "Someone"`, `quantity = event.quantity ?? 1`, `id = nextId++`.
3. `run = combo.hit(sender, gift.id, now())`. `count = quantity > 1 ? quantity : run` (the run
   still advances when a quantity is given).
4. If `reducedMotion`: show the notice for this item now (below), return `id`. Nothing enters.
5. Large: if a large effect is running, queue the item; if the queue already holds 5, first
   remove the OLDEST waiting item (it is dropped silently: no notice, no `end`, its id becomes
   unknown). Otherwise start it.
6. Small or medium: if `running[tier] < cap`, start it; else show only the notice for it. `cap` is
   `recipes.json#maxConcurrentEffects` unless the app passes its own (`maxConcurrent`, whole numbers
   1 to 12, small and medium only; web and React Native today). Conformance uses the defaults.
7. Return `id`.

Start: `running[tier]++`, add to the on-screen map, `enter(effect)`. The notice of a started
effect is NOT shown yet; it shows when the UI calls `started(id)` (picture ready, section 7.2).

`started(id)`: if `id` is on screen, show its notice. Unknown ids are ignored.

`finished(id)`: if `id` is on screen: release it, then `end(effect)`. Unknown ids are ignored.

Release: remove from the map, `running[tier] = max(0, running[tier] - 1)`, `exit(effect)`; if the
tier is large and the queue is not empty, start the oldest waiting item (`enter`). So the order
of events for a finishing large effect is `exit`, `enter` (next), `end`.

`cancel(id)`: remove `id` from the queue if waiting; if on screen, release it (no `end`); then if
`owner == id`, hide the notice. A cancelled effect that had not started never showed a notice.

`clear()`: empty the queue and the map, reset running counts, `clear()`, hide the notice, reset
the combo tracker. Effects still animating MUST be removed without `end`.

Show notice for item `{ id, event, recipe, count }`:

- `key = sender + "|" + gift.id`; `owner = id`. Every key keeps its own `noticeId` while it is
  remembered (at most 32 keys, the one used longest ago is dropped): a known key reuses its id,
  a new key gets `++noticeId`. So a combo returns to its own line even when other people sent
  gifts in between.
- `data = { id: <the key's noticeId>, senderName: sender, giftName: gift.name, image: gift.icon ?? gift.image
(either may be null), count, big: recipe.noticeBig }`; `visible = true`;
  `notice(data, recipe.noticeMs)`.
- The UI shows the notices as a stack of at most 3 lines (newest at the bottom, older above). A
  `notice` call whose `data.id` is already shown updates that line in place and restarts THAT
  line's own timer of `durationMs`; any other id adds a line at the bottom (a 4th line removes the
  oldest at once). When a line's timer fires only that line slides out. The UI does not call
  `noticeExpired()` for stack lines (it hides everything); an expired id returning is simply a new
  line.

Hide notice (cancel, clear): `visible = false`, the owner's key is forgotten (`clear()` forgets
every key), `noticeHide()` (the UI removes the NEWEST line; `clear` removes every line first).
`noticeExpired()`: `visible = false`, every key is forgotten, `noticeHide()`. The last
`NoticeData` stays readable after hiding. Because the key is forgotten, the next notice after a
hide gets a new `noticeId` even for the same sender and gift.

## 7. Effect layer (UI)

### 7.1 Layer

- One layer covers the screen (or the area the app gives it), above content, and MUST NOT take
  touches (pass-through).
- It owns an `EffectScheduler` and implements its listener. `play`/`cancel`/`clear` delegate to
  the scheduler.
- Props/parameters and defaults: `thresholds`, `quality "high"`, `reducedMotion` (default: follow
  the OS setting: iOS Reduce Motion, Android "Remove animations" / animator duration scale 0,
  `prefers-reduced-motion` on the web; changes are picked up live), `comboWindowMs 2500`,
  `origin { x: 0.5, y: 0.86 }` (fractions of the layer), `pictureWaitMs 300`,
  `noticeBottom 150` (dp from the bottom edge), `theme`, `onEffectEnd(event, tier)` (called from
  the scheduler's `end`).
- The reference draws effects only once the layer has a non-zero size.

### 7.2 Picture gate

When an effect enters, it waits for its picture (`event.gift.image`) before it starts:

- No picture, or `pictureWaitMs <= 0`: start at once.
- Else start when the picture reports loaded or failed, or when `pictureWaitMs` has passed since
  the effect entered, whichever comes first. Start exactly once.
- "Start" = call `scheduler.started(id)` (which shows the notice) and begin the timeline (7.3).
  So the dim, the notice and the gift appear together.
- Until it starts the effect draws nothing visible (picture opacity 0).
- Pictures MUST be shown without any fade-in of their own (Android's `Image` fades in over 300 ms
  by default; the reference turns this off everywhere). Prefetch and decode ahead (section 8, 9).

Fixture: `effects.json#pictureGate` (start may lag a load by at most one frame, 16 ms).

### 7.3 Timeline of one effect

Coordinates are in the layer, origin top-left, `W` x `H` its size. The picture is a `100 x 100`
dp box drawn centred on its position, scaled. Only transform (translate, scale, rotate) and
opacity are animated, so the native animation thread can run it; nothing re-lays-out per frame.

Fixed when the effect is created (never change while it runs, even on resize):

- Start point `O = (origin.x * W, origin.y * H)`.
- Stage point `S`: `center` = `(W / 2, 0.38 H)`; `float-up` =
  `(O.x + r * 0.2 W, O.y - 0.32 H)` with `r` uniform in `[-0.5, 0.5)`.
- Sparks (n = `recipe.sparks`): spark i has angle `i / max(1, n) * 2 PI + u * 0.6` rad, distance
  `sparkSpread * (0.4 + u * 0.8)`, diameter `5 + u * 6` dp, colour `accent` when `i % 3 == 0`,
  else `glow` (`u` = a new uniform random in `[0, 1)` each time).
- Coins (n = `recipe.coins`): x `u * W`, diameter `10 + u * 8` dp, start fraction `u * 0.35`,
  fall fraction `0.45 + u * 0.2`.

Phases (`tail = holdMs + flyOutMs`):

| phase | starts at          | duration         | easing                             | what moves                                                                                                                                                               |
| ----- | ------------------ | ---------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| fly   | 0                  | `flyInMs`        | ease-out with overshoot, back(1.3) | picture from `O` to `S`; scale 0.3 to `peakScale`; opacity 0 to 1 over the first 6 % of the progress, then 1                                                             |
| dim   | 0                  | 300              | linear                             | (if `dim`) full-screen black, opacity 0 to 0.62                                                                                                                          |
| rays  | 0                  | `flyInMs + tail` | linear                             | (if `rays`) see below                                                                                                                                                    |
| burst | `flyInMs`          | 900              | ease-out cubic                     | each spark from `S` by `(dx, dy)`; scale 1 to 0.2; opacity 0 to 1 at 12 %, then to 0 at 100 %                                                                            |
| coins | `flyInMs`          | `tail + 800`     | linear progress p                  | (if `coins > 0`) coin opacity 0 until its start, ramping to 1 by start + 0.02; it falls from y = -24 by `H + 48` between p = start and p = min(1, start + fall), clamped |
| hold  | `flyInMs`          | `holdMs`         | none                               | the picture stays at `S` at `peakScale`                                                                                                                                  |
| leave | `flyInMs + holdMs` | `flyOutMs`       | ease-in quad                       | picture rises by `0.07 H`, its scale is multiplied 1 to 0.55, opacity 1 to 0; (if `dim`) dim 0.62 to 0                                                                   |

The effect is finished (`scheduler.finished(id)`) when every phase has ended:
`flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`, which gives small 1600 ms, medium 2100 ms,
large 3850 ms (high) or 3050 ms (low quality, no coins).

Rays and glow (large, high quality): `R = min(W, H) * 1.6`. Two sets of 12 thin triangles from the
stage centre to radius `R / 2`, colour `glow`, in a square of `R` centred on `S`:
wide set half-width `0.075 R`, opacity 0.34, turning 0 to 60 degrees; thin set half-width
`0.028 R`, opacity 0.42, turning 15 to -35 degrees. Both fade with `raysFade` = progress mapped
`[0, 0.1, 0.85, 1] -> [0, 1, 1, 0]`. Glow: 5 concentric discs of diameter `340 * k` dp for
`k = 1, 0.78, 0.58, 0.4, 0.24`, colour `glow`, opacity `0.16 * raysFade`, scaled 0.4 to 1 with the
fly progress. Rays never delay the end.

Drawing order, back to front: dim, rays, glow, sparks, coins, picture. The picture is drawn with
"contain" fitting. Without a picture the reference draws a `coin`-coloured disc.

### 7.4 Notice

"ayla sent Rose x3", bottom-left.

- Position: `left 12`, `bottom noticeBottom` (150), max width 92 % of the layer; a pill (fully
  rounded) row with gap 8, padding left 5, right 16, vertical 5 (big: 7).
- Content: avatar disc 28 (big: 34) in `accent` with the sender's first character upper-cased
  (12, bold, `accentText`); two lines `senderName` (12.5, bold, line height 15) and
  `sent {giftName}` (12.5, opacity 0.92); the picture (`data.image`) 36 (big: 46), contain, only if
  not null; the counter `x{count}` only if `count > 1` (28, weight 800, italic, min width 40,
  centred).
- Colours: background `noticeBackground` (big: `noticeBigBackground`), text `noticeText` (big:
  `noticeBigText`), counter `comboText` (big: `noticeBigText`).
- Slide: visible animates a progress to 1 over 380 ms (ease-out back 1.2); hidden animates it to 0
  over 260 ms (ease-in quad). Progress maps to translateX -260 to 0 dp and opacity 0 to 1.
- Counter pop: when a notice with the SAME `id` gets a larger `count` (and count > 1), the
  counter's scale jumps to 1.9 and springs back to 1 (React Native `Animated.spring` with friction 4, tension 160: an underdamped,
  visibly bouncy spring; match it by eye, it is an L4 item).
- A new picture URL MUST get a fresh image element (never show the previous gift's bitmap while
  the next one loads).
- Accessibility: announced politely as an alert/live region.

### 7.6 Pictures: which URLs, how big, what happens on failure (audit R-08, 2026-11-03)

Every picture the SDK draws (gift icons and big pictures, notice pictures, avatars, effect
pictures) goes through the same three rules. Fixtures: `pictures.json`.

1. **Which URLs.** `isPictureUrl(url)`: `https://` always; `http://` only to a loopback host (the
   list of 3.1: `localhost`, `127.0.0.1`, `::1`, `10.0.2.2`); `data:image/...`; nothing else
   (`javascript:`, `file:`, `blob:`, `ftp:`, `//host/x`, empty). A URL without a scheme is a path on
   the app's own origin: the web and React Native web allow it, native SDKs have no origin and refuse
   it. A refused URL is **never requested**: the UI draws the placeholder (the coin disc, the
   initial letter, no notice picture) exactly as for a gift without a picture. Why: gift art comes
   from the API (and from custom URLs the project set), so a hostile or mistaken value must not make
   a phone call an arbitrary scheme or send a request over plain text.
2. **How big.** At most 5 MiB (`PICTURE_MAX_BYTES` = 5,242,880) per picture, enforced where the
   platform lets the SDK stop the download: Flutter (`GiftNetworkImage` counts the streamed bytes and
   refuses a longer `Content-Length`), Android and iOS with their loaders. A `data:image` URL longer
   than `ceil(5 MiB x 4 / 3) + 256` characters is refused on every platform. The browser's `<img>`
   and React Native's `Image` cannot be capped: the web and React Native SDKs rely on the CDN
   (the SDK's own assets are a few KB) and say so in their README.
3. **Failures are remembered for 60 s.** A picture that failed (refused, too big, network, not an
   image, decode error) is recorded in `PictureFailures` (`pictureFailureMemoryMs` = 60,000,
   at most 200 URLs, the oldest forgotten first). Until 60 s have passed the same URL is not
   requested again by prefetch, by a rebuilt grid or by the next effect: the placeholder is drawn at
   once. A new failure restarts the 60 s. Without this a broken URL in a 40-gift tray is
   re-requested on every rebuild.

**Prefetch policy** (with section 8 step 2 and section 9): the tray fetches the small `icon_url` of
every gift as soon as the catalog arrives (they are on screen), and a gift's big picture
(`animation_url`, 512 px) only for the **selected** gift, when the selection changes; the other big
pictures load when their effect first plays (the picture gate, 7.2, waits up to `pictureWaitMs`).

### 7.5 Reduced motion and quality

- Reduced motion: no effect at all; only the notice, shown at `play` time (scheduler step 4). The
  notice keeps its slide and its counter pop (7.4) on every platform: it is the only motion left.
  The web layer used to fade it instead; aligned on 2026-10-11.
- `quality "low"`: the low recipes (fewer sparks, no coins, no rays). The gift and the notice are
  unchanged. Apps choose it (for example on old devices); the SDK does not detect it.

## 8. Tray state holder (pure, fixture-tested)

`GiftTrayController` does everything a tray needs besides drawing. Reference:
`packages/sdk-js/src/core/tray.ts`; React Native's `useGiftTray` only wraps it.

Options (read again at every use, so they may change): `client`, `receiver`, `effects` (the
effect layer's controller, may be absent), `playOn` (`"tap"` default, or `"success"`),
`reference`, `onSent(tx)`, `onError(error)`, `prefetch(url)`.

State: `gifts` (empty), `balance` (0), `user` (null), `loading` (true), `error` (null), `testMode`
(false). Every change notifies observers (Flutter `notifyListeners`, Kotlin `StateFlow`, Swift `@Published`).

Lifecycle: the UI calls `refresh()` when the screen opens (and again when the client changes) and
`dispose()` when it closes. After `dispose`, no answer changes the state (see `send` for the
exact callbacks that still run).

`refresh()`:

1. `getGifts()` and `getMe()` in parallel; wait for both (the first failure fails both).
2. If disposed, stop. Call `prefetch` for every non-null `icon_url`, gift by gift, in the server's
   order. The big pictures (`animation_url`) are NOT prefetched here (audit R-08, 2026-11-03): a
   catalog of 40 gifts would download 40 x 512 px pictures nobody may ever play. The tray warms the
   selected gift's big picture (section 9, "Prefetch"); every other one loads when it first plays
   (the picture gate of 7.2 waits for it).
3. Set `gifts` sorted by `sort_order` ascending (stable), `balance = me.balance`,
   `user = me.user`, `error = null`, `testMode = (me.livemode == false)`: true only when the server
   says `livemode: false` (a token made with a test key); `true` and an absent `livemode` (an older
   server) are false. A failed refresh keeps the last `testMode`. Fixtures: `tray.json` ("testMode ...").
4. On failure (if not disposed): `error = asError(failure)`.
5. Finally (if not disposed): `loading = false`. `loading` never becomes true again.

`send(gift)` (optimistic):

1. Capture `client`, `receiver`, `reference`, `effects` and `user` now. `pending++`.
   `balance -= gift.price` (no affordability check here; the button does that).
2. The effect event: `{ gift: { id, name, price, image: animation_url ?? icon_url, icon: icon_url },
sender, quantity }`.
3. `playOn "tap"`: play it now with `sender = user ?? "You"`, `quantity = 1`; keep the returned id.
4. `tx = client.sendGift({ receiver, giftId: gift.id, reference })` (absent reference stays absent).
5. Success: if disposed, skip to 7. `error = null`. `playOn "success"`: play now with
   `sender = user ?? tx.sender`, `quantity = tx.quantity`. Then `onSent(tx)`. The balance is NOT
   taken from `tx.sender_balance_after`. The play call and `onSent` are app code: whatever they
   throw is ignored and never reaches step 6 (the send succeeded, the coins are spent).
6. Failure: `e = asError(failure)`. If an effect was played at the tap, `effects.cancel(id)`
   (even if disposed). If not disposed: `balance += gift.price`, `error = e`. Then `onError(e)`
   (even if disposed); a throw from `onError` is ignored too.
7. Finally: `pending--`; if `pending == 0`, reconcile.

Reconcile: `getMe()`; when it answers, if not disposed AND `pending == 0` (no send started
meanwhile), `balance = me.balance`. Failures are ignored (the optimistic number stays).

`asError(x)`: `x` itself if it is the SDK error; otherwise `GiftingError(0, "unknown_error",
x.message or "Something went wrong.")`.

What the notice shows for a local send: the gift's `icon_url` (via `event.gift.icon`), so the
notice uses the picture the tray already shows and appears complete.

### 8.1 Send button state

`sendButtonState({ gifts, selectedId, balance, disabled = false, canTopUp = false })`:

```text
selected  = gift with id == selectedId, else gifts[0], else none
broke     = selected exists and selected.price > balance
canSend   = selected exists and not disabled and not broke
label     = broke ? (canTopUp ? "getCoins" : "notEnough") : "send"
pressable = canSend or (broke and canTopUp and not disabled)
action    = not pressable ? "none" : broke ? "topUp" : "send"
```

Fixtures: `tray.json`.

## 9. Tray (UI)

Presentational: the app passes data and callbacks (usually from `GiftTrayController`). The tray is
a bottom sheet by default (section 9.1); this section describes the parts both forms share and the
fixed tray (`sheet: false`).

Parameters and defaults: `gifts`, `balance`, `onSend(gift)`, `onTopUp?` (enables "+ Coins" and the
"Get coins" state), `title "Send a gift"`, `coinName "coins"`, `sendLabel "Send"`,
`notEnoughLabel "Not enough coins"`, `getCoinsLabel "Get coins"`, `columns 4`,
`gridMaxHeight 230` (the grid scrolls beyond it), `defaultSelectedId` (default: the first gift),
`disabled false`, `testMode` (default: follows the tray state, see below), `testModeLabel "Test mode"`, `theme`, and the sheet parameters of 9.1 (`sheet true`, `initialSnap`,
`snaps`, `onSnapChange`, `onInsetChange`) and the scrim and open parameters of 9.4 (`scrim`,
`scrimTap`, `onDismiss`, `open`, `onOpenChange`). Web only: the placements of 9.3 (`placement`,
`anchor`, `onPlacementChange`; `onOpenChange` also reports the popover).

Layout intent (dp): a bottom sheet with top corners 24, hairline border (`border`), padding 14,
vertical gap 12, background `surface`.

- Header row (gap 10): title (15, bold, `text`, takes the free width); balance pill
  (`background`, padding 4 x 10, a 14 dp `coin` disc, the number 13 bold tabular digits); "+ Coins"
  (13 bold, `coin`) only when `onTopUp` is given; it calls `onTopUp`.
- Test mode badge (after the title, only when `testMode`): `testModeLabel` in capitals, 11
  extra bold, text `#1a1300` on `#f5a524`, padding 2 x 8, corners 6. The state's `testMode`
  (section 8: `me.livemode === false`, an absent `livemode` is no badge) shows it **by itself**: a
  host does not have to wire it. Web (`createGiftTray`, `<gift-tray>`) takes it from its controller.
  The components that are only handed data take the tray state as one parameter and read
  `gifts`, `balance`, `send` and `testMode` from it: React Native `GiftTray tray={useGiftTray(...)}`,
  Flutter `GiftTray(tray: GiftTrayNotifier)`, Android and iOS the same with their state holder
  (`tray`). The explicit `testMode` parameter is an override and is tri-state: unset follows the
  state, `false` forces the badge off, `true` forces it on (also without a tray state); explicit
  `gifts`, `balance` and `onSend` win over the tray state too. Demos are test environments: their
  mock `getMe` answers `livemode: false`, so the badge shows there. End users of an app running on a
  test key see it. The test environment allows 50 users and 5,000 operations a
  month (403 `test_limit_reached`). Every SDK: web, React Native, Flutter, Android, iOS.
- Grid: `columns` cells per row, each `100 / columns` % wide with padding 4. Cell: centred column,
  vertical padding 8, corners 14, border 1.5; selected = background `selected` and border `accent`;
  others = background `background`, transparent border. Icon 48 x 48 contain (no icon: a 48 dp
  rounded square in `border`). Price row: a 9 dp `coin` disc and the price (11.5 bold, tabular).
  Tapping a cell selects it.
- Send button: full width pill, vertical padding 13, label 15 bold. Background: `accent` when it
  can send, `coin` when it shows "Get coins", `border` when not pressable. Label colour `coinText`
  on the coin background, else `accentText`. State and press action from `sendButtonState`
  (`label` key mapped to the three label strings): "send" calls `onSend(selected)`, "topUp" calls
  `onTopUp()`, "none" does nothing.
- Selection: initial `defaultSelectedId ?? first gift's id` when the tray is created; afterwards
  the user's choice. If the selected id is not in `gifts`, the first gift is shown as selected.
- Balance count-up: the shown number animates from the old to the new balance over 600 ms
  (ease-out cubic), rounded to an integer each frame; the accessible label uses the target value.
- Number format: always en-US grouping (`1,234`), whatever the device locale (as the reference).
- Prefetch (7.6): every icon when `gifts` changes; the selected gift's big picture
  (`animation_url ?? icon_url`) whenever the selection changes, and no other big picture. The reference also draws that big
  picture invisibly (opacity 0, off-screen, at the effect's 100 dp size) so the platform decodes it
  before the tap; platforms SHOULD do the equivalent (decode/warm the bitmap cache).
- Accessibility labels: cell `"{name}, {price} {coinName}"` as a radio item with checked state;
  balance `"Balance: {balance} {coinName}"`; "+ Coins" `"Get more {coinName}"`; send button
  `"{label}: {selected name}"`.

Theme tokens (all colours, any may be overridden; defaults):

| token                 | default                     | used for                                                       |
| --------------------- | --------------------------- | -------------------------------------------------------------- |
| `background`          | `#14141f`                   | balance pill, cells                                            |
| `surface`             | `#1e1e2e`                   | tray                                                           |
| `border`              | `#2d2d44`                   | tray border, disabled button, icon placeholder                 |
| `text`                | `#f4f2ff`                   | title, numbers                                                 |
| `muted`               | `#a3a1c2`                   | (reserved)                                                     |
| `accent`              | `#8b7bff`                   | send button, selected cell, avatar, sparks                     |
| `accentText`          | `#ffffff`                   | text on accent                                                 |
| `coin`                | `#ffd27a`                   | coin discs, "+ Coins", Get coins button, coin rain             |
| `danger`              | `#ff8fa3`                   | (reserved)                                                     |
| `noticeBackground`    | `rgba(123, 107, 255, 0.92)` | notice                                                         |
| `noticeText`          | `#ffffff`                   | notice                                                         |
| `noticeBigBackground` | `#e8a93a`                   | large-gift notice                                              |
| `noticeBigText`       | `#2a1600`                   | large-gift notice                                              |
| `glow`                | `#ffdc8c`                   | rays, glow, most sparks                                        |
| `coinText`            | `#2a1600`                   | label on the "Get coins" button (was a fixed colour)           |
| `selected`            | `#221f45`                   | selected cell background (was a fixed colour)                  |
| `comboText`           | `#fff3c4`                   | combo counter on a small or medium notice (was a fixed colour) |

### 9.1 Tray as a bottom sheet (default)

Since 2026-10-11 the tray is a draggable bottom sheet by default. Pull it up to see more gifts,
push it down to see more of the screen behind it. `sheet: false` keeps the fixed-height tray of
section 9 exactly as before (layout, `gridMaxHeight`, no handle, no footer).

New parameters (all platforms): `sheet` (default `true`, read once when the tray is created),
`initialSnap` (`"peek" | "default" | "expanded"`, default `"default"`), `snaps` (fractions, see
below), `onSnapChange(snap)`, `onInsetChange(height)`. React Native also has `containerHeight`
(skip the measurement) and `bottomInset` (safe area under the Send button; native platforms
SHOULD offer the same or respect the system inset). The web tray adds `getSheetState()`,
`snapTo(snap)` and `measure()`.

#### Three states

| state      | shows                                                                              | height (default)                                  |
| ---------- | ---------------------------------------------------------------------------------- | ------------------------------------------------- |
| `peek`     | drag handle, header (title, balance, + Coins) and the footer (selected gift, Send) | exactly that content (`peekMinHeight`)            |
| `default`  | peek plus up to two rows of gifts: the old tray                                    | that content (`defaultMinHeight`)                 |
| `expanded` | as many rows as fit; the grid scrolls inside                                       | 90 % of the container, capped at the full content |

#### Layout (dp)

- The sheet fills the bottom of its container (the screen area), absolutely positioned; touches
  above the sheet reach the screen. Web: `position: absolute` at the bottom of the container (a
  `static` container is made `relative` until `destroy()`). React Native: the tray renders an
  `absoluteFill` box (`pointerEvents="box-none"`), so it must be a child of the screen's root view.
- It is laid out ONCE at its tallest (the `expanded` height) and moved with `translateY(offset)`.
  Height and layout MUST NOT be animated per frame.
- Two parts. The **body** moves: handle, header, grid; background `surface`, hairline border,
  top corners 24, horizontal padding 14, gap 12. The **footer** stays put at the container's
  bottom and is drawn above the body: the selected gift (icon 36 contain, name 12.5 bold one line,
  price row as in the cells; max 45 % wide; hidden from screen readers, the Send label already
  names the gift) and the Send button (flex 1); padding 10 top, 14 sides, 14 bottom (+ safe area),
  side borders. The body slides down behind the footer.
- Handle: a button the full width of the sheet, padding 8 top and 4 bottom, no negative margin (the header starts right below it, so the Test mode badge never touches the pill); a
  pill 36 x 5, radius 3, `muted` at opacity 0.7. Focus ring on the pill (web).
- Grid: fills the rest of the body (no `gridMaxHeight`). It scrolls only when `gridScrollable`.
- In `peek` (settled) the grid is out of sight and MUST be out of the tab order and the
  accessibility tree (web: `inert` + `aria-hidden`; RN: `accessibilityElementsHidden`,
  `importantForAccessibility="no-hide-descendants"`).

Content floors, measured by the UI after layout and on every resize or gift change:

```text
peekMinHeight    = (top of the grid inside the body: handle + header + gap) + footer height
rowHeight        = height of one grid row (a cell plus its 4 + 4 margin or padding)
rows             = ceil(gifts / columns)
defaultMinHeight = peekMinHeight + min(2, rows) * rowHeight
contentHeight    = peekMinHeight + rows * rowHeight
```

#### Pure controller: `TraySheetController` (fixture-tested)

Reference `packages/sdk-js/src/core/sheet.ts`, no UI import; port it line by line. All lengths are
the platform's layout unit; velocity is units per second, positive = finger moving down.

Constants: `SHEET_SNAPS = [peek, default, expanded]` (closed to open), `SHEET_FLICK_VELOCITY = 600`,
`SHEET_DEFAULT_FRACTIONS = { peek: 0, default: 0, expanded: 0.9 }`.

`resolveSheetHeights({ containerHeight, snaps?, peekMinHeight?, defaultMinHeight?, contentHeight? })`:

```text
H        = containerHeight if finite and > 0, else 0
f(s)     = snaps[s] if a finite number, clamped to 0..1; else SHEET_DEFAULT_FRACTIONS[s]
           (null or missing = default)
floor(x) = x if finite and > 0, else 0
peek     = max(round(f(peek) * H), floor(peekMinHeight))
default  = max(round(f(default) * H), floor(defaultMinHeight), peek)
expanded = round(f(expanded) * H)
expanded = min(expanded, contentHeight)      only when floor(contentHeight) > 0
expanded = max(expanded, default)
each     = min(each, H)                       so 0 <= peek <= default <= expanded <= H
```

`round` is round-half-up on the product (the fixtures avoid exact halves). A fraction of 0 means
"fit the content".

State (`getState()`, observers notified only when a field changes):

```text
snap           the settled state, or the target of a running snap; unchanged during a drag
offset         translateY of the body from fully open; offsetOf(s) = heights.expanded - heights[s]
visibleHeight  heights.expanded - offset: the sheet's top edge from the container's bottom
dragging       a drag is running
heights        { peek, default, expanded }
gridScrollable offset == 0 and not dragging
```

Operations:

- `constructor({ initialSnap = "default", layout?, onSnapChange? })`; `setOnSnapChange(cb)`.
- `setLayout(layout)`: new heights. Not dragging: `offset = offsetOf(snap)`. Dragging: `offset =
clamp(raw)`. The state is kept.
- `dragStart()`: no-op while dragging; else `dragging = true`, `raw = offset`.
- `drag(dy)`: starts a drag if none runs; `raw += dy`; `offset = clamp(raw)` with
  `clamp(v) = min(offsetOf(peek), max(0, v))`. The raw position is kept, so after an over-drag the
  sheet stays under the finger (no rubber band).
- `release(velocity = 0)`: without a drag returns `snap` and changes nothing. Else `dragging =
false`, picks the target (below) and settles there; returns it.
- `cancel()`: ends a drag and returns to `offsetOf(snap)`; `onSnapChange` is not called.
- `snapTo(s)`: ends any drag and settles on `s`.
- `toggle()` (tap on the handle): `default` -> `peek`; `peek` and `expanded` -> `default`. Returns it.
- `step(+1 | -1)` (keyboard, accessibility): one state more open / more closed, clamped at the ends.
- Settle: `snap = s`, `offset = offsetOf(s)`, notify; then `onSnapChange(s)` only if `s` differs
  from the previous `snap`.

Release target (`pick`), with `o = offset`. States are compared from the most open to the most
closed, and a later state replaces the current best only when it is strictly better, so **ties go
to the more open state**:

1. Flick, `|velocity| >= 600`: up (`velocity < 0`): among states with `offsetOf(s) < o`, the one
   with the largest offset (the next state above the current position). Down: among states with
   `offsetOf(s) > o`, the one with the smallest offset. If there is none, go to 2.
2. Otherwise the state with the smallest `|offsetOf(s) - o|`.

So a flick moves exactly one state beyond where the sheet is now (a fast flick up from peek opens
`default`, not `expanded`; dragged past default first, it opens `expanded`), and a slow release
goes to the nearest state.

Nested scroll, `scrollOwner(dy, gridScrollTop)`, asked once per gesture for a drag that starts on
the grid, with its first movement `dy` (positive = down) and the grid's scroll position:

```text
dragging or offset > 0           -> "sheet"   (below fully open every grid drag moves the sheet)
dy > 0 and gridScrollTop <= 0    -> "sheet"   (fully open, grid at the top, pulled down: collapse)
otherwise                        -> "grid"    (the grid scrolls; dy == 0 too)
```

A drag that starts on the handle or the header always belongs to the sheet. The decision is not
revisited inside the gesture.

#### UI rules

- Slop: a press becomes a drag after 6 dp of mostly vertical movement (`|dy| > |dx|`); a mostly
  horizontal movement is ignored. The slop already travelled is applied when the drag starts, so
  the sheet does not lag behind the finger. A drag MUST NOT end in a click on what is under the
  finger (cell, handle); a press below the slop stays a tap.
- Velocity: from the platform's tracker (RN `vy * 1000`, Android `VelocityTracker`, iOS
  `velocity(in:)`, Flutter `DragEndDetails.velocity`). Web: samples of the last 100 ms before the
  release, `(y_last - y_first) / (t_last - t_first)`; a pointer that rested 100 ms has speed 0.
- Snap animation: `translateY` only, ease-out (web: CSS `transition: transform 280ms
cubic-bezier(0.22, 1, 0.36, 1)`) or a critically damped spring without overshoot (RN:
  `Animated.spring` stiffness 320, damping 36, mass 1, `overshootClamping`, native driver). During a
  drag the body follows directly (no transition). Reduced motion: jump to the snap, no animation.
- Inset: `onInsetChange(visibleHeight)` when it changes: live during a drag and the TARGET when a
  snap is chosen (not every animation frame). Apps pass `inset + gap` as the effect layer's
  `noticeBottom` so the notice sits above the sheet.
- Web: pointer events. `pointerdown` on the body starts a press; its moves and end are followed on
  the document; the body takes pointer capture only when the drag starts (capturing at
  `pointerdown` would retarget the click away from the cell). `touch-action: none` on the handle
  and the header; on the grid `none` below fully open, `pan-down` when fully open at scroll top
  (the browser keeps scrolling up, the pull down is ours), `pan-y` otherwise. A `pointercancel`
  (the browser took the touch for native scrolling) calls `cancel()`. Mouse drags on the scrolling
  grid scroll it by hand.
- Web keyboard and accessibility: the handle is a `<button>` labelled "Gift tray" with
  `aria-expanded` (`false` only in `peek`) and `aria-keyshortcuts="ArrowUp ArrowDown"`; ArrowUp =
  `step(+1)`, ArrowDown = `step(-1)`, Enter/Space/click = `toggle()`.
- Native accessibility: the handle is a button ("Gift tray", expanded state, value = the state
  name) with the actions `activate` (toggle), `increment`/`decrement` and the custom actions
  "Show more gifts"/"Show fewer gifts" (step +1/-1). Flutter: `Semantics(onIncrease, onDecrease,
onTap)`; Android: `semantics { expand/collapse, customActions }`; iOS:
  `accessibilityAdjustableAction` or custom actions.
- React Native gestures: one `PanResponder` on the body. Bubble `onMoveShouldSetPanResponder`:
  vertical beyond the slop and (not on the grid or `scrollOwner == "sheet"`). Capture
  `onMoveShouldSetPanResponderCapture`: the same, but only on the grid while `gridScrollable` (to
  take the pull-down from a scrolling `ScrollView`). Termination requests are refused during a
  drag. The grid's `scrollEnabled = gridScrollable`.

Fixtures: `sheet.json`. Component checks (L3): `test/web-sheet.test.ts`,
`test/react-native-sheet.test.tsx`.

### 9.2 Theming

Every colour the tray and the notice draw is a token of `GiftTheme` (table above: 14 tokens from
1.0 plus `coinText`, `selected` and `comboText`, which were fixed colours before and keep those
values as defaults). Apps pass a partial theme; missing tokens take `defaultTheme`. Reference:
`packages/sdk-js/src/core/theme.ts` (pure, port it).

- `defaultTheme`: unchanged, the 1.0 look. Its Send label (white on `#8b7bff`) is only 3.3:1.
- `darkTheme`: `defaultTheme` with `accent #6d5cf0` and `noticeBackground rgba(109, 92, 240,
0.92)`, so white on the accent is 4.7:1.
- `lightTheme`: background `#f1eff8`, surface `#ffffff`, border `#dcd8ea`, text `#1c1a2e`,
  muted `#5f5b78`, accent `#6a54e8`, accentText `#ffffff`, coin `#9a6300` (a dark gold that reads
  on white), coinText `#ffffff`, selected `#e6e1ff`, danger `#c4204a`, noticeBackground
  `rgba(106, 84, 232, 0.94)`, noticeText `#ffffff`, comboText `#fff3c4`, noticeBigBackground
  `#e8a93a`, noticeBigText `#2a1600`, glow `#ffcf66`.
- `themeFromAccent(accent, mode = "dark")`: `accent` is `#rgb` or `#rrggbb` (anything else
  throws); it is kept as given (lower-case `#rrggbb`). The other tokens are derived:

```text
mix(a, b, t)          channel-wise a + (b - a) * t, rounded
contrast(a, b)        WCAG 2: (L1 + 0.05) / (L2 + 0.05), L = relative luminance (sRGB)
readableOn(bg)        #ffffff if contrast(white, bg) >= contrast(black, bg), else #000000
ensure(fg, bg, 4.5)   fg if it reaches 4.5:1, else fg mixed towards black (bg luminance > 0.18)
                      or white in 5 % steps until it does; at the end pure black or white
dark:   surface = mix(#17171f, accent, .10), background = mix(#0d0d14, accent, .06),
        selected = mix(surface, accent, .22), border = mix(#2a2a35, accent, .25),
        text = mix(#ffffff, accent, .05), muted = mix(#b0afc0, accent, .15), coin = #ffd27a,
        danger = #ff8fa3
light:  surface = #ffffff, background = mix(#f4f4f7, accent, .06), selected = mix(#ffffff,
        accent, .16), border = mix(#dedee6, accent, .20), text = mix(#16151f, accent, .08),
        muted = mix(#5c5b6b, accent, .15), coin = #9a6300, danger = #c4204a
text, muted (and coin in light mode) are passed through ensure() against surface, then
background, then selected
accentText = noticeText = readableOn(accent); coinText = readableOn(coin)
noticeBackground = accent at alpha 0.92; comboText = #fff3c4 if accentText is white, else accentText
noticeBigBackground #e8a93a, noticeBigText #2a1600, glow #ffdc8c
```

Contract (fixture `theme.json`, also checked on 300 random accents in the reference): for every
accent and mode, and for `darkTheme` and `lightTheme`, these pairs are at least 4.5:1: text on
surface, background and selected; muted on surface; coin on surface; accentText on accent; coinText
on coin; noticeText on accent; noticeBigText on noticeBigBackground. Exact derived colours are not
part of the contract (a port may round differently), only the rule and the kept accent.

Switching live: the web tray's `update({ theme })` and the layer's `setOptions({ theme })` REPLACE
the previous theme (tokens not given go back to the defaults; an update without `theme` keeps it).
Web tokens are CSS variables `--gs-<kebab-case token>` on the tray and the layer roots.

### 9.3 Web placements: sheet, popover, inline (web only)

Added on 2026-10-11 for desktop web pages, where a full-width bottom sheet looks wrong (huge
columns, a stretched Send bar). **Web only**: React Native, Flutter, Android and iOS keep the
bottom sheet of 9.1 and do not implement this section.

New web parameters: `placement` (`"sheet" | "popover" | "inline" | "auto"`, default `"auto"`, read
once), `anchor` (the app's gift button, read once), `onOpenChange(open)`, `onPlacementChange(p)`.
New methods: `getPlacement()` (`null` for `sheet: false`), `open()`, `close()`, `toggle()`,
`isOpen()` (popover only; the other placements are always shown and return `true`). `sheet: false`
wins: the fixed tray of section 9, whatever `placement` says.

Pure logic, reference `packages/sdk-js/src/core/placement.ts`, fixture `conformance/placement.json`:

```text
resolveTrayPlacement({ placement, containerWidth, hasAnchor })
  placement "popover"            -> "popover" if hasAnchor, else "inline" (nothing to open from)
  placement "sheet" | "inline"   -> as given
  otherwise ("auto", missing, unknown):
    w = containerWidth if finite, clamped to >= 0; else 0
    w < 600                      -> "sheet"       (600 itself is wide: the threshold is inclusive)
    hasAnchor                    -> "popover"
    else                         -> "inline"

positionPopover({ anchor: {left, top, right, bottom}, panel: {width, height}, viewport,
                  gap 8, margin 8, maxHeightFraction 0.7 })      viewport px, integers out
  width     = min(panel.width, viewport.width - 2 * margin)
  cap       = round(viewport.height * 0.7);  wanted = min(panel.height, cap)
  above     = max(0, anchor.top - gap - margin)
  below     = max(0, viewport.height - anchor.bottom - gap - margin)
  side      = below if below >= wanted; else above if above >= wanted;
              else the side with more room (ties: below)
  maxHeight = min(cap, room on that side);  height = min(wanted, maxHeight)
  top       = anchor.bottom + gap (below) or anchor.top - gap - height (above)
  align     = "end" (right edges line up) if the anchor's centre x >= viewport.width / 2,
              else "start" (left edges line up)
  left      = clamped to [margin, viewport.width - margin - width]
```

`auto` is resolved from the CONTAINER's width when the tray is created and again on every resize
of the container (ResizeObserver). A switch tears the old placement down completely (listeners,
inline styles, ARIA) and builds the new one on the same elements; an open popover reports
`onOpenChange(false)`; leaving the sheet reports `onInsetChange(0)` once, so a notice moved above
the sheet comes back down. An explicit placement does not follow resizes.

All placements share the sheet's structure (body: header and grid; footer: selected gift and
Send). Only the sheet has the handle and the snap states.

**Popover.**

- Panel 380 px wide (narrower on a small viewport), corners 16, hairline border, a shadow; grid of
  4 columns (`columns` overrides), scrolling inside; header and footer stay visible. Height at
  most 70 % of the viewport and the room on its side.
- It is appended to `document.body` (so no ancestor's `overflow` or `transform` clips or moves
  it), `position: fixed`, and moved with `transform: translate(left, top)` only. Its content
  height is measured on open, on a gift change and on window resize; on scroll (capture, passive)
  it is only re-placed. Scroll and resize work is throttled to one per animation frame.
- Starts closed (`hidden`). Clicks on the anchor toggle it. Closes on Escape (keydown on the
  document while open), on a `pointerdown` outside both the panel and the anchor, and on
  `close()`. Sending a gift does NOT close it, so people can send several in a row.
- Focus: on open, the selected cell (the grid's one tab stop), else the panel. On Escape, an
  anchor click and `close()`, focus returns to the anchor if it was inside the panel (or
  nowhere); an outside click does not move focus (the person moved on to what they clicked).
- ARIA: the anchor gets `aria-haspopup="dialog"`, `aria-expanded` and `aria-controls` (its own
  previous values come back on destroy); the panel has `role="dialog"` and `aria-label` = the
  title. Not modal (no focus trap): Tab can leave it.
- The notice: the popover has `z-index: 999`, one below the effect layer's 1000, so in a page
  without extra stacking contexts the effects and the notice draw over the popover, never under
  it. No inset is reported for the popover (it floats next to its button and does not cover a
  fixed band of the layer's container). An app with other stacking contexts can move the notice
  with `noticeBottom` or its own CSS.

**Inline.** The tray fills its container (`height: 100%`, so the container needs a height),
corners 16 and a full hairline border. The grid takes the free height and scrolls inside; the
header and the footer stay visible. Columns: `repeat(auto-fill, minmax(84px, 1fr))` (as many
tiles of at least 84 px as fit), unless `columns` is given. No inset is reported. The anchor is
ignored.

**Desktop details (all placements).** Each cell has a `title` tooltip `"{name}, {price}
{coinName}"` (the same text as its label). Hover states under `@media (hover: hover)` (cell
border, Send brightness, "+ Coins" underline); `:focus-visible` rings on cells and buttons. Arrow
keys, Home and End move the selection as in section 9 in every placement; in the popover and
inline the newly selected cell is scrolled into view (`block: nearest`). The mouse wheel scrolls
the grid natively in the popover and inline (the sheet keeps open question 12d). Theme and
`quality` work as before. The web sheet handle now also carries the label "Gift tray" of 9.1.

Fixtures: `placement.json`. Component checks (L3): `test/web-placement.test.ts`.

### 9.4 Scrim, open state and the Gift button (all platforms; web: the sheet placement)

Added 2026-11-04. Until now every demo drew a dim behind the sheet, decided what a tap outside
does and showed or removed the tray from its own Gift button in app code. These three things are
SDK features now, so a host writes `scrim: true` and `onTap: tray.toggle()` and nothing else.
Everything is **off or unchanged by default**: no existing app changes.

Reference: `packages/sdk-js/src/core/scrim.ts` (pure), `src/web/GiftTray.ts` + `src/web/sheet.ts`,
`src/react-native/GiftTray.tsx` + `useGiftTray.ts`; Flutter `lib/src/core/scrim.dart`,
`lib/src/ui/gift_tray.dart`, `gift_tray_notifier.dart`.

#### Names (use these, in the platform's idiom)

| concept                               | web                                                                                          | React Native                                      | Flutter                                             | Android (Kotlin)                                  | iOS (Swift)                                       |
| ------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- |
| draw the dim (default `false`)        | option `scrim`                                                                               | `GiftTray` prop `scrim`                           | `GiftTray(scrim:)`                                  | `scrim`                                           | `scrim`                                           |
| what a tap on it does (default lower) | option `scrimTap: "lower"` or `"dismiss"`                                                    | prop `scrimTap` (same strings)                    | `ScrimTap.lower` / `ScrimTap.dismiss`               | `ScrimTap.Lower` / `ScrimTap.Dismiss`             | `ScrimTap.lower` / `.dismiss`                     |
| the tap asked to close                | option `onDismiss()`                                                                         | prop `onDismiss()`                                | `onDismiss`                                         | `onDismiss: () -> Unit`                           | `onDismiss: (() -> Void)?`                        |
| start closed (default open)           | option `open: false`                                                                         | `useGiftTray({ open: false })`                    | `GiftTrayNotifier(open: false)`                     | holder `open = false`                             | holder `open: false`                              |
| host-owned open state                 | none (the web tray owns it)                                                                  | `GiftTray` prop `open` (wins over the holder)     | `GiftTray(open:)` (wins over the notifier)          | `open: Boolean?`                                  | `open: Bool?`                                     |
| open, close, toggle, is open          | `tray.open()` `close()` `toggle()` `isOpen()`; the `createGiftTray` handle has the same four | holder `open()` `close()` `toggle()` and `isOpen` | notifier `open()` `close()` `toggle()` and `isOpen` | holder `open()` `close()` `toggle()` and `isOpen` | holder `open()` `close()` `toggle()` and `isOpen` |
| it opened or closed                   | option `onOpenChange(open)` (sheet and popover)                                              | `useGiftTray({ onOpenChange })`                   | `GiftTrayNotifier(onOpenChange:)`                   | `onOpenChange`                                    | `onOpenChange`                                    |

Pure core (all platforms port it; fixture `tray-scrim.json`): the constants `SCRIM_FADE_MS = 200`
and `SCRIM_OPACITY = 0.4`; `scrimVisible({ scrim, open, snap, placed })`;
`scrimFadeMs(reducedMotion)`; `scrimTapOutcome({ scrim, scrimTap = lower, open, snap })`; the
class `TrayOpenState({ open = true, onChange })`. Dart names: `kScrimFadeMs`, `kScrimOpacity`,
`scrimVisible`, `scrimFadeMs`, `scrimTapOutcome` (returns `ScrimTapOutcome.ignored`, `.lower` or
`.dismiss`), `TrayOpenState`.

#### Pure functions

```text
scrimVisible = scrim AND open AND placed AND snap != peek
   snap   = TraySheetState.snap (the settled state, or the target of a running snap; it does not
            change during a drag)
   placed = the sheet is measured and drawn where it belongs (web: phase "placing" or "live";
            RN: its `ready` after the placing jump; Flutter: `_shown`)

scrimFadeMs(reducedMotion) = reducedMotion ? 0 : 200

scrimTapOutcome:
   not scrim or not open                      -> "ignored"
   scrimTap == lower and snap != peek         -> "lower"
   otherwise                                  -> "dismiss"
      (lower from peek dismisses; dismiss mode dismisses from every state)
```

`TrayOpenState`: `isOpen`, `open()`, `close()`, `toggle()`; each method returns the new state. A
call that changes nothing returns the state, notifies nobody and does not call `onChange`. A
change updates the state, then notifies subscribers, then calls `onChange(open)`. `toggle()` =
open if closed, close if open. The initial state is `open` (default `true`: a tray that exists
is shown, as before).

#### The scrim (UI)

- Only for the sheet (web: `placement` resolves to `"sheet"`; the popover and the inline tray
  ignore `scrim`, they keep their own outside-click and Escape behaviour of 9.3). With `scrim` off
  nothing is added and touches above the sheet reach the screen behind, as before.
- It covers the whole box the sheet fills (the container), **behind the sheet and the footer**
  and **above the screen content**. The effect layer and the notice stay above both. Web: a
  `div.gs-scrim[data-gs-scrim][aria-hidden="true"]` inserted into the container immediately
  before the tray element, `position: absolute; inset: 0; z-index: 1` (the sheet is also
  `z-index: 1` and comes later in the document), `background: #000`. RN: the first child of the
  tray's `absoluteFill` box. Flutter: the first child of a `Stack` around the sheet (needs a
  bounded parent: the box the tray fills, the same one the sheet uses).
- Colour: black. Its opacity animates between 0 (not visible) and `SCRIM_OPACITY` 0.4 (visible)
  over `scrimFadeMs(reducedMotion)` ms, ease-out, in **both** directions. It starts fading in
  when `scrimVisible` becomes true, that is when the sheet is placed (the dim and the sheet appear
  together, never a dim over an unplaced sheet). Reduced motion (the same source as the sheet's:
  web `prefers-reduced-motion`, RN `AccessibilityInfo`, Flutter `reducedMotion`, else the
  system "remove animations" setting, Android and iOS the system setting): 0 ms, it is there or
  gone at once.
- It is hidden while the sheet is at `peek` (the page or stream stays in sight). `snap` is what
  counts, so the dim goes away the moment a snap TO peek is chosen (the target), not when the
  animation ends, and comes back when a snap to `default` or `expanded` is chosen.
- Touches: it takes touches **only while `scrimVisible` is true**. While visible it takes every
  touch above the sheet (the sheet and the footer above it keep theirs); an activation (click,
  press, tap) is a "scrim tap". While hidden or fading out it takes none: they reach the screen
  behind (web `pointer-events: none`, RN `pointerEvents="none"`, Flutter `IgnorePointer`).
- Accessibility: web `aria-hidden="true"` (keyboard users have the handle and `close()`);
  native: a button labelled `"Close gift tray"` while visible, excluded from the accessibility
  tree while hidden.
- Markers for tests. Web: `data-gs-scrim` on the element, `data-gs-visible` while visible, an
  inline `transition-duration` of `"200ms"` or `"0ms"`. Flutter: the `GestureDetector` has
  `ValueKey('tray-scrim')` and an `AnimatedOpacity` below it (`opacity` 0 or 0.4, `duration`
  200 ms or zero). RN: `testID="gift-scrim"` (the dim) and `"gift-scrim-press"` (the button).

#### A tap on the scrim

`outcome = scrimTapOutcome(...)`, then:

- `"lower"`: `snapTo(peek)` (animated like any snap; the dim fades out). `onSnapChange(peek)`
  follows. Nothing else is called.
- `"dismiss"`: (1) the tray closes itself, unless the host owns the open state (an explicit
  `open` parameter on RN, Flutter, Android, iOS): web `tray.close()` (so `onOpenChange(false)`
  runs); holder platforms call the holder's `close()` when a holder is passed and `open` is not;
  (2) then `onDismiss()` is called. A host that wants the tray gone only needs
  `scrimTap: "dismiss"`; a host with its own state reacts in `onDismiss` or `onOpenChange`.
- `"ignored"`: nothing (a closed tray has no visible scrim, so this is only reachable by calling
  the function).

#### Open state, `toggle()` and the Gift button

- A sheet tray is **open** by default and shows as before. `open()`, `close()` and `toggle()`
  change it (see `TrayOpenState`); the web tray and the holder (RN `useGiftTray`, Flutter
  `GiftTrayNotifier`, the Android and iOS state holders) own the state. `isOpen` reflects it. The
  host's Gift button is one line: `tray.toggle()` (web: `handle.toggle()` or `tray.toggle()`).
  The web popover keeps its own `open()`, `close()`, `toggle()`, `isOpen()` of 9.3 (Escape,
  outside click, the anchor); for the inline tray they do nothing and `isOpen()` is `true`.
- **Closed** means: the sheet, the footer and the scrim are invisible (web `hidden` on the tray
  root; RN opacity 0; Flutter opacity 0 over 180 ms), take no touches (RN `pointerEvents="none"`,
  Flutter `IgnorePointer`) and are out of the accessibility tree. The tray's data (gifts,
  balance, selection, loading) keeps working. `onInsetChange(0)` is called once when it closes
  (and once at the start when `open` is false), so the notice drops to its base position. While
  closed `onInsetChange` only ever says 0.
- When it closes, the sheet goes back to `initialSnap` **with a jump** (it is invisible), so
  nothing glides on the next open. `onSnapChange(initialSnap)` is called if that changes the
  snap. The person's selected gift stays.
- When it opens, the sheet is placed again at `initialSnap` without a glide (web: the
  "measuring" and "placing" phases run again, so it is invisible until measured, at most 700 ms;
  RN: placed with a jump, shown in the next render; Flutter: it fades in over 180 ms),
  `scrimVisible` turns true once placed, and `onInsetChange(visibleHeight)` is called with the
  new inset.
- `onOpenChange(open)` (the web option, the holders) runs after every change and never for a call
  that changes nothing.

#### Host patterns (what the demos do)

- Feed and live room: `scrim: true`, `scrimTap: "dismiss"`, `collapseOnSelect: true`. Picking a
  gift lowers the sheet to peek and the dim goes away; the page or stream is in sight; a tap
  outside the open sheet closes the tray; the Gift button (`toggle()`) closes it too; a send
  leaves it open (combos).
- A Gift button for another recipient while the tray is open for someone else: the host
  switches the receiver and calls `open()`; the same recipient's button calls `toggle()`.
- Tabs: the tray belongs to the screen it was opened on; the host calls `close()` when the tab
  changes.

Fixtures: `tray-scrim.json` (format in `conformance/README.md`). Component checks (L3):
`test/web-sheet.test.ts` ("scrim, toggle, open and close"), `test/react-native-sheet.test.tsx` and
`test/react-native.test.tsx` (the holder), Flutter `test/gift_tray_sheet_test.dart` and
`test/gift_tray_test.dart`.

## 10. Threading and timing

- `EffectScheduler`, `GiftTrayController` state and all UI callbacks run on the main/UI thread
  (Flutter: the UI isolate; Android: `Dispatchers.Main`; iOS: `@MainActor`; web: the page).
- Client calls run off the main thread where the platform requires it, and resume on the main
  thread before touching controller state.
- Timers (picture wait, notice) are UI timers on the main thread.

## 11. Verification levels

| level               | what                                                                                                                                                                                                                                                                                                                                                                                                                                      | how                                                                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| L1 constants        | thresholds, combo window, caps, queue size, default sender, all recipe fields                                                                                                                                                                                                                                                                                                                                                             | compare with `recipes.json` in a unit test                                                                              |
| L2 logic            | client (headers, bodies, retries, errors), tiers, combo, scheduler traces, tray controller, send button, sheet snapping, placement, remote recipes (parse, clamp, merge, URL), gift wall (chips, `formatCount`, loader), away (replay plan, sender label, controller), leaderboard (rank label, pinning, controller, medal contrast), the component client calls, rooms (frames, reconnect policy, event filter, mapping, session traces) | `conformance/*.json` in the platform's runner                                                                           |
| L3 component timing | picture gate (effect + notice start together), notice timer, effect end time from 7.3, layer passes touches through, labels and a11y                                                                                                                                                                                                                                                                                                      | component/UI tests with a fake clock, as the reference does in `test/react-native.test.tsx`; `effects.json#pictureGate` |
| L4 device feel      | smoothness (frame rate) on a mid and a low-end device, easing feel, overshoot, spark and coin spread, ray look, notice slide and pop, no flicker of the previous picture, no late first frame, heat, sheet drag and flick feel, nested scroll on a phone                                                                                                                                                                                  | a person on a real device, side by side with the React Native reference app                                             |

L1 and L2 are machine-checked and binary. L3 is checked by tests that each platform writes from
sections 7 and 9. L4 cannot be automated: random spark/coin layouts and easing curves differ per
animation system, so "identical" there means "looks the same to a person", not pixel-equal.

## 12. Mutation evidence

Each rule below was broken on purpose in the reference, the conformance suite was run, and the
change was reverted (rooms: 45 mutations of `rooms.ts`, all caught, 2026-10-12). Every mutation was caught. One was not and is listed as such: skipping
`ensureContrast` for text and muted in `themeFromAccent` changes nothing for the fixture accents
nor for 300 random accents (the base colours already pass); it stays as a safety net.

| mutation (reference code)                                           | failing fixtures                                                                                                                                                                                   |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 5xx retry sends a NEW idempotency key (`client.ts`)                 | client: "500 then success ...", "503 twice ...", "401, refresh, then 500, then retry ..."                                                                                                          |
| every attempt gets a new key (broader variant of the above)         | client: the three above + "401 on a send: the repeat carries the SAME idempotency key", "sendGift uses the caller's idempotency key verbatim ..."                                                  |
| refresh asks for `forceRefresh: false`                              | client: "401 then success ...", "401 twice ...", "401 on a send ...", "401, refresh, then 500 ..."                                                                                                 |
| refresh repeated while the answer is 401 (`if` to `while`)          | client: "401 twice: gives up after one refresh"                                                                                                                                                    |
| `encodeURI` instead of `encodeURIComponent`                         | client: "getReceivedGifts encodes the user id like encodeURIComponent"                                                                                                                             |
| X-Request-Id header preferred over the body's `request_id`          | client: "request id: the body wins over the header"                                                                                                                                                |
| combo window inclusive (`<` to `<=`)                                | combo: "a gap of exactly 2500 ms starts over ...", "custom window of 2000 ms"                                                                                                                      |
| full large queue drops the NEWEST instead of the oldest             | effects: "at most 5 large gifts wait; a new one drops the OLDEST waiting one, silently"                                                                                                            |
| large queue cap 6 instead of 5                                      | effects: same scenario (and `spec.test.ts`, since `recipes.json` says 5)                                                                                                                           |
| notice uses `image` instead of `icon ?? image`                      | effects: 10 scenarios, e.g. "each tier enters at once; the notice waits for started()"                                                                                                             |
| no balance refund when a send fails                                 | tray: "playOn tap: a failed send takes the effect back ...", "playOn success: a failed send ...", "a burst of taps ...", "without an effect layer ...", "a failure that is not a GiftingError ..." |
| no `cancel` of the effect played at the tap                         | tray: "playOn tap: a failed send takes the effect back ...", "a burst of taps ...", "dispose during a send ..."                                                                                    |
| reconcile applies `getMe` even while another send is pending        | tray: "the reconcile answer is ignored when another send started meanwhile"                                                                                                                        |
| a recipe value changed (`holdMs` 1600 to 1700) without regenerating | `spec.test.ts` ("matches the reference code")                                                                                                                                                      |
| sheet: flick threshold exclusive (`>=` to `>`, `sheet.ts`)          | sheet: "a flick of exactly 600 px/s up moves one state; 599 does not"                                                                                                                              |
| sheet: `toggle` from expanded goes to peek                          | sheet: "toggle: default -> peek -> default; expanded -> default"                                                                                                                                   |
| sheet: ties go to the less open state                               | sheet: "a slow release goes to the nearest state; an exact tie ...", "few gifts: expanded equals default ..."                                                                                      |
| sheet: `scrollOwner` ignores the grid's scroll position             | sheet: "nested scroll: fully open, the grid scrolls unless it is at the top ..."                                                                                                                   |
| sheet: drag clamps per step (no raw position)                       | sheet: "the drag follows the finger, is clamped at the top, and stays under the finger after an over-drag"                                                                                         |
| sheet: `contentHeight` does not cap expanded                        | sheet: "the content height caps expanded", "content just shorter than 90 % ...", "expanded never goes below default ...", "few gifts: ..."                                                         |
| sheet: default `expanded` fraction 0.9 back to 0.75                 | sheet: "no floors and the default fractions ...", "phone (800 high, content 900) ...", "content just shorter than 90 % ...", every `phone` scenario; `web-sheet.test.ts` "expanded is 90 % ..."    |
| theme: `readableOn` always returns white                            | theme: "themeFromAccent(#ff4f9a, dark) ..." and 9 more accent/mode cases                                                                                                                           |
| placement: threshold exclusive (`w < 600` to `w <= 600`)            | placement: "auto, exactly 600 px with an anchor ...", "... without an anchor"; `web-placement.test.ts` "from 600 px (inclusive) ..."                                                               |
| popover: no exact-fit (`below >= wanted` to `>`)                    | placement: "exactly enough room below (inclusive): opens below"                                                                                                                                    |
| popover: Escape not recognised (`popover.ts`)                       | `web-placement.test.ts`: "Escape closes it and returns focus to the anchor"                                                                                                                        |
| popover: focus not given back to the anchor on close                | `web-placement.test.ts`: "the anchor toggles it ...", "Escape closes it ...", "close() returns focus only when ..."                                                                                |
| remote: clamp removed (`remote-recipes.ts`)                         | remote-recipes: "numbers above the limits ...", "numbers below the limits ...", "thresholds are clamped ..." (5)                                                                                   |
| remote: `sparks` limit 120 to 200 in code only                      | remote-recipes: "numbers above the limits ..."; `remote-recipes.test.ts` "the clamp table in SPEC.md section 13.3 equals ..."                                                                      |
| remote: no rounding of integer fields                               | remote-recipes: "integer fields are rounded half up ..."                                                                                                                                           |
| remote: threshold order not checked                                 | remote-recipes: "largeFrom not above mediumFrom drops both", "one field alone that breaks the order ..."                                                                                           |
| remote: other major accepted                                        | remote-recipes: "another major is ignored as a whole", "major 0 ..." (5)                                                                                                                           |
| remote: unknown stage accepted                                      | remote-recipes: "an unknown stage keeps the tier's embedded stage ..."                                                                                                                             |
| merge: remote `comboWindowMs` beats the app's                       | remote-recipes merge: "app beats remote, field by field", "app values are not clamped ..."                                                                                                         |
| merge: app thresholds ignored                                       | remote-recipes merge: "app beats remote ...", "an ignored remote document ..."; scheduler "app thresholds beat remote thresholds"                                                                  |
| merge: embedded beats remote                                        | remote-recipes merge: "remote beats embedded" and 5 scheduler/layer tests                                                                                                                          |
| remote: version pin ignored                                         | remote-recipes urls: "pinned", "self-hosted and pinned" and the no-network cases; layer "recipesVersion requests ..."                                                                              |
| web loader: `remoteRecipes: false` ignored                          | `remote-recipes.test.ts` "remoteRecipes: false makes no request at all"; `web-conformance.test.ts` (timer left behind)                                                                             |
| web loader: cache not read before the first effect                  | `remote-recipes.test.ts` "uses the cached copy at once ...", "re-validates the cached copy ..."                                                                                                    |
| web loader: no backoff / backoff not capped at 6 h                  | `remote-recipes.test.ts` "backs off after failures: 1 min, 2 min, 4 min ... capped at 6 hours"                                                                                                     |
| web loader: refresh on every layer (no 6 h)                         | `remote-recipes.test.ts` "refreshes at most once per 6 hours", "uses the cached copy at once ..."                                                                                                  |
| web loader: no timeout race / no abort                              | `remote-recipes.test.ts` "gives up after 3 s and aborts the request" (both variants)                                                                                                               |
| web loader: no single flight                                        | `remote-recipes.test.ts` "... concurrent refreshes share one request", "all layers share one request ..."                                                                                          |
| scheduler: a started effect re-reads the newest set                 | `remote-recipes.test.ts` "effects already running or queued keep their recipe ..."                                                                                                                 |

| wall: `formatCount` rounds instead of floors | wall formatCount: "1099 -> 1K", "1999 -> 1.9K", "9999 -> 9.9K" and 4 more |
| wall: overflow chip counts the hidden kinds, not the sum of counts | wall chips: "more than max ...", "default max is 6 ...", "max 1 with two gifts ..." (5) |
| wall: counts of 0 kept | wall chips: "counts of 0 or less are dropped", "zero counts are dropped before max ..." |
| wall loader: window inclusive (timer at 51 ms) | wall loader: "requests within 50 ms share one batch ...", "a request at exactly 50 ms starts the next batch ..." (7) |
| wall loader: batch size 26 | wall loader: "26 walls make two calls of 25 and 1 ..." |
| wall loader: cache still fresh at 60,000 ms (`<` to `<=`) | wall loader: "an answer is reused for 60,000 ms ..." |
| wall loader: no de-dup of a wall in flight | wall loader: "the same wall asked again while queued or in flight ..." |
| wall loader: an invalidated request's answer is cached | wall loader: "invalidate: the next load asks again ..." |
| away planner: budget ignored | away plan: "budget 7000 ...", "budget 6000 ...", "a lone large item longer than the budget ..." |
| away planner: budget drop removes the largest non-large item | away plan: "budget 7000 ...", "budget 6000 ..." |
| away planner: two large groups allowed | away plan: "two large groups: only the first (highest units) plays" |
| away planner: no 300 ms pause before the large effect | away plan: the worked example and 9 more |
| away planner: equal units not ordered by gift id | away plan: "all small: 450 ms apart, units ascending, equal units by gift id" |
| away sender label: 2 people with one name says `a and b` | away senderLabel: "[ayla] x2 -> ayla and 1 other", "[a] x2 oneOther" |
| away controller: ack sent more than once per summary | away controller: "ackOn shown (default) ...", "ackOn manual ..." and 3 more |
| away controller: failed ack not retried / retried forever | away controller: "a failed ack is reported, retried once ...", "a retried ack that succeeds ..." |
| away controller: `check()` allowed while playing | away controller: "check() is ignored while loading, ready or playing ..." |
| away controller: throttle exclusive at 60,000 ms | away controller: "foreground() checks at most once per 60,000 ms ..." |
| away controller: card tail 1000 instead of 1500 ms | away controller: "ackOn shown (default) ...", "ackOn finished: the automatic dismissal ..." |
| away controller: dismiss acknowledges only in `finished` mode | away controller: "dismiss() before start() ..." |
| leaderboard pin: the doc-only rule (`rank > limit`), tie at the cut not pinned | leaderboard pin: "tie at the cut: rank within the limit but outside the rows: pinned" |
| leaderboard pin: `rank >= limit` pinned | leaderboard pin: "rank equal to the limit and in the rows: not pinned" |
| leaderboard pin: hidden users pinned | leaderboard pin: "hidden: never pinned" |
| leaderboard: revalidate only when older than 30,000 ms (`>=` to `>`) | leaderboard controller: "a cached tab 30,000 ms old ... revalidates ..." |
| leaderboard: a cached tab is never / always refetched | leaderboard controller: "a cached tab 30,000 ms old ...", "a cached tab younger than 30,000 ms ..." (and 2 more) |
| leaderboard: no request de-dup | leaderboard controller: "a tab already being fetched is not asked again ..." |
| leaderboard: a failed revalidation hides the stale rows | leaderboard controller: "a failed revalidation keeps the stale rows visible" |
| leaderboard: receivers default to units (F.11 broken) | leaderboard controller: "the receivers board defaults to the gifts metric" |
| leaderboard: rank label without grouping | leaderboard rankLabel: "1000 -> #1,000" |
| client: `include_me=true` sent by default | leaderboard client: "getLeaderboard with no query ...", "includeMe true is the default ..." (4) |
| client: a 204 body parsed as JSON | away client: "ackAway: PUT with the cursor ...", "ackAway: 500 then 204 ..." |
| client: a `null` wall reference sent | wall client: "queryGiftWalls: a POST with the items ..." |
| rooms filter: staleness `>=` to `>`, live gifts aged on the local clock | rooms-filter: "replay: staleness boundary ...", "live gifts are aged with the server clock ...", "maxReplayAgeMs 3000 ..." |
| rooms filter: no own-skip / token claim ignored / claim beats the `user` option | rooms-filter and rooms-session: "join: ...", "the user option wins ..." |
| rooms filter: no dedup, dedup of 257, `last` only for played gifts | rooms-filter: "dedup keeps the last 256 tx", "dedup survives a reconnect", "a duplicate ... moves the resume point" |
| rooms policy: 4009 `replaced`, 4003 or 4400 retried; 6 limited waits; no 30 s minimum | rooms-reconnect (cases of each code) and rooms-session "room full ...", "4003 ...", "4009 replaced ..." |
| rooms policy: 4001 without refresh or never immediate; first drop not 0-5 s; cap 32 s | rooms-reconnect and rooms-session "4001 ...", "drop: ..." |
| rooms session: attempt never resets / resets at 59,999 ms | rooms-session: "backoff grows ... and resets after 60 s open" |
| rooms session: heartbeat pings after traffic, no pong or welcome deadline, `heartbeatMs: 0` pings (hangs) | rooms-session: "heartbeat: ...", "no welcome within 10 s ...", "heartbeatMs 0 ..." |
| rooms session: refresh at ttl, no 60 minute cap, refresh without `forceRefresh` | rooms-session: "refresh ahead of welcome.ttl ..." |
| rooms session: hello without `last`, pause forgets `last`, stale token answer opens a socket, frames after leave handled | rooms-session: "drop: ...", "pause ...", "join: ..." |
| rooms session: reconnectNow ignored, bad room id not checked, batch ignored, replay not flagged, onGap not called, token failure final | rooms-session: the scenario of each rule |
| rooms mapping: event icon before the catalog picture, resolveName before the claim, catalog price | rooms-mapping (all 5 cases) |
| rooms protocol: unknown fields kept, quantity 0, welcome without `now`, unknown `t` passed, hello `v` 2 | rooms-protocol parse and hello cases |

## 13. Remote recipes

Effect numbers can change without an app update: the SDK fetches a copy of `recipes.json` from
`https://assets.giftingstack.com/recipes.json` and uses it for new effects. The embedded values
(`recipes.json` in this package, the platform's constants) stay the fallback and remain the source
of truth for conformance: every other fixture runs against the embedded values only. Reference:
`packages/sdk-js/src/core/remote-recipes.ts` (pure) and `packages/sdk-js/src/web/recipes-loader.ts`
(network and cache). Fixture: `conformance/remote-recipes.json`.

**Hosting:** the document is served from `assets.giftingstack.com`. If the request fails (network, 404) the SDKs silently use the embedded values. The host MUST send `Access-Control-Allow-Origin: *`
for the web SDK.

Status: implemented in the web layer only. The React Native layer and the Flutter, Android and
iOS SDKs do not load remote recipes yet (they use the embedded values, which is conformant); when
they port it, they run `conformance/remote-recipes.json` and follow 13.5.

### 13.1 Document

The document has the shape of `recipes.json` (the reference's `specData()` output):
`{ specVersion, thresholds, comboWindowMs, maxConcurrentEffects, maxQueuedLarge,
defaultSenderName, recipes: { high: {small, medium, large}, low: {...} } }`. Any key may be missing.

- The whole document is ignored (as if it did not exist) when it is not a JSON object, or when
  `specVersion` is not a string of the form `<int>.<int>.<int>` (no suffix), or when its major
  number differs from the major of the SDK's own `specVersion` (today 1). A higher minor or patch
  of the same major is accepted.
- Otherwise the result is always a full set: every field the document does not give correctly
  keeps its embedded value.

### 13.2 What may be overridden

ONLY `thresholds.mediumFrom`, `thresholds.largeFrom`, `comboWindowMs` and, for each quality
(`high`, `low`) and tier (`small`, `medium`, `large`), the recipe fields `peakScale`, `flyInMs`,
`holdMs`, `flyOutMs`, `stage`, `sparks`, `sparkSpread`, `coins`, `dim`, `rays`, `noticeMs`,
`noticeBig`.

NEVER taken from the document: `maxConcurrentEffects`, `maxQueuedLarge`, `defaultSenderName`, a
recipe's `tier` (always the key it sits under), new stage kinds, new tiers or qualities, and unknown
keys. `low` is read on its own: a document that changes only `high` leaves `low` embedded (it is
NOT derived from the remote `high`).

### 13.3 Validation and clamping

Per field, independently (a bad field never discards its neighbours or the document):

- A number field whose value is not a finite JSON number (string, boolean, null, array, object,
  NaN, Infinity) keeps the embedded value of THAT field.
- A finite number is clamped to the table below; then, when "integer" is yes, rounded half up
  (`floor(x + 0.5)`; every range is non-negative, so this is unambiguous).
- `dim`, `rays`, `noticeBig` must be JSON booleans; anything else keeps the embedded value.
- `stage` must be exactly `"float-up"` or `"center"` (case-sensitive); anything else keeps the
  embedded stage of that tier. Switching a tier between the two known kinds is allowed.
- A quality, a tier, `recipes` or `thresholds` that is not an object counts as missing.
- Thresholds: each field is checked and clamped as above, then if `largeFrom <= mediumFrom` BOTH
  take the embedded values (a single given field is compared with the other's embedded value).

The limits (code: `REMOTE_RECIPE_LIMITS`; a test compares this table with the code):

| field           | min | max        | integer |
| --------------- | --- | ---------- | ------- |
| `peakScale`     | 0.5 | 4          | no      |
| `flyInMs`       | 0   | 10,000     | yes     |
| `holdMs`        | 0   | 10,000     | yes     |
| `flyOutMs`      | 0   | 10,000     | yes     |
| `sparks`        | 0   | 120        | yes     |
| `sparkSpread`   | 0   | 400        | yes     |
| `coins`         | 0   | 120        | yes     |
| `noticeMs`      | 500 | 8,000      | yes     |
| `mediumFrom`    | 1   | 1,000,000  | yes     |
| `largeFrom`     | 2   | 10,000,000 | yes     |
| `comboWindowMs` | 500 | 10,000     | yes     |

Only remote values are clamped. Values the app passes itself are used as given.

### 13.4 Merge order

`embedded < remote < app options`. Parsing already fills the remote set from the embedded one;
then the app's `thresholds` (field by field: a partial object overrides only the fields it gives)
and the app's `comboWindowMs` win over the remote set. Quality (`high`/`low`) only picks which
table is read. Reference: `mergeRecipeSet(embedded, remote | null, app)`.

The scheduler (section 6) takes the set as an option (`recipes`) read at each `play`, like
`thresholds`; without it the embedded set applies, exactly as before. The tier and the recipe are
fixed at `play`: effects already on screen or waiting in the large queue keep the recipe they were
scheduled with when a new document arrives; effects played afterwards use the new one. When the
app gave no `comboWindowMs`, the combo window is the set's value at the time of each `play` (so it
can change during a session).

### 13.5 Fetching and caching (platform loader)

- Address: `recipesUrl` option, default `https://assets.giftingstack.com/recipes.json`. With
  `recipesVersion` (a string of 1-64 characters from `A-Z a-z 0-9 . _ -`) the SDK requests the
  pinned file instead: the LAST `.json` in the URL becomes `.<version>.json`
  (`recipes.json` -> `recipes.1.0.0.json`). A version outside that alphabet, or a URL without
  `.json`, turns remote recipes off (no network). Pure helper: `remoteRecipesUrl(url?, version?)`.
- `remoteRecipes: false` (default true): no request, no cache read or write, embedded values only.
- One loader per URL per process, shared by every layer; at most one request in flight
  (concurrent callers share it).
- Cache: the raw document and the time it was fetched, keyed by URL, in the platform's small
  key-value store (web `localStorage` under `giftingstack:recipes:<url>`; native platforms their
  usual preferences store, or memory). The cached document is parsed again on read (new limits
  apply to old copies). Storage that is missing, full or throws means memory only; it MUST NOT
  break effects.
- Use the cached copy immediately. A refresh runs in the background when there is no copy yet or
  the copy is 6 hours old or more (or its time lies in the future: the clock went back). It is
  started when a layer is created and never awaited by `play`: the first effect never waits for
  the network.
- Fetch timeout 3 s for the whole response (headers and body); then abort. Web requests omit
  credentials.
- A response that is not 2xx, not JSON, or ignored by 13.1 counts as a failure: the current copy
  (cached or none) stays, nothing is written, and nothing reaches the app (no throw, no callback).
- Backoff: after the n-th failure in a row, no new attempt for `min(6 h, 60 s * 2^(n-1))`; a
  success resets n. There are no retry timers: an attempt only happens when a layer is created
  (or a platform's equivalent trigger) and one is due.
- A successful fetch replaces the in-memory copy at once and is written to the cache with its time.

### 13.6 Publishing

`npm run build:remote` in `packages/sdk-spec` writes `dist/recipes.json` and
`dist/recipes.<specVersion>.json` (gitignored) from `recipes.json`, or from a tuned file given as
the first argument, after running it through `parseRemoteRecipes`: it refuses a document the SDK
would ignore and refuses values that would be clamped. Uploading `dist/` to
`assets.giftingstack.com` is a separate, manual deploy step.

## 14. Gift wall

Added on 2026-10-11. A row of chips (gift icon +
count) under a post or on a profile: `[rose 12] [heart 3] [dragon 1] [+37]`. Read-only, no senders,
no messages. Reference: `packages/sdk-js/src/core/wall.ts` (pure). Fixture: `conformance/wall.json`.

**Status:** pure logic and client calls in the reference only. The web and React Native
components and the Flutter, Android and iOS ports are not done yet; those platforms acknowledge
`wall.json` as "components pending native port" in their fixture coverage test.

### 14.1 Client calls

- `getReceivedGifts(user, reference?)`: as 3.2, plus `?reference={enc(reference)}` when given
  (counters for gifts sent with that `reference` only). No query string without it.
- `queryGiftWalls(items)`: `POST {base}/v1/client/gift-walls/query`, body
  `{ "items": [{ "receiver", "reference"? }] }` where a missing or `null` reference is left OUT.
  Returns the response's `data` array (`GiftWall { receiver, reference: string | null, gifts:
ReceivedGift[] }`), in request order. It is a read: no `Idempotency-Key`. An empty `items` list
  returns `[]` without any request. The API accepts 1-25 items (more is a 400; the loader below
  never sends more). Unknown users answer `gifts: []`.

### 14.2 Chips: `wallChips(items, { max = 6, order = "count" })`

`items` are `ReceivedGift`s in catalog order (as the API sends them). Exactly:

```text
max  = max(1, floor(max))
kept = items with count > 0                      (input order kept)
if order == "count": stable sort kept by count descending (equal counts keep the input order)
if len(kept) <= max: one gift chip per kept item
else: gift chips for kept[0 .. max-2], then ONE overflow chip:
      count  = SUM of the counts of kept[max-1 ..]   (gifts, not kinds)
      hidden = len(kept) - (max - 1)                 (kinds it stands for)
```

Chip type: `{ type: "gift", gift, count } | { type: "overflow", count, hidden }`. So `max = 1`
with two gifts shows only the overflow chip carrying every count.

### 14.3 `formatCount(n, labels?)`

Never overstate: always round DOWN. `v = trunc(n)` (non-finite: 0). Labels `thousand` (`"K"`),
`million` (`"M"`), `decimal` (`"."`).

```text
v < 1,000          -> "{v}"                                   999 -> "999"
v < 10,000         -> t = floor(v / 100); "{t / 10}{K}" with one decimal, ".0" left out
                                                              1000 -> "1K", 1099 -> "1K", 1100 -> "1.1K", 1999 -> "1.9K"
v < 1,000,000      -> "{floor(v / 1000)}{K}"                  10000 -> "10K", 999999 -> "999K"
v < 10,000,000     -> t = floor(v / 100,000); "{t / 10}{M}", ".0" left out
                                                              1000000 -> "1M", 1250000 -> "1.2M"
otherwise          -> "{floor(v / 1,000,000)}{M}"             12345678 -> "12M"
```

Use integer arithmetic (no float formatting, no locale grouping). Negative input below 1,000 is
written as is; counts are never negative.

### 14.4 `GiftWallLoader` (pure, injected clock and timer)

Shares the wall requests of a whole screen (a feed shows many walls). Options: `query(items)`
(the batch call, normally `client.queryGiftWalls`), `now`, `setTimeout`, `windowMs = 50`,
`batchSize = 25`, `ttlMs = 60,000`. Key of a wall: `(user, reference)`; a missing and a `null`
reference are the same (profile wall), a profile wall and a post wall are different.

- `load(user, reference?) -> Promise<ReceivedGift[]>`:
  1. A cached answer younger than `ttlMs` (`now - at < ttlMs`) resolves at once, no request.
  2. A wall already queued or in flight returns that same promise (no second request).
  3. Else the wall is queued. If no window is open, one opens: a timer of `windowMs` is set and,
     when it fires, every queued wall is sent. So walls asked within `[t0, t0 + 50)` share a batch;
     a wall asked at exactly `t0 + 50` (after the timer fired) starts the next window.
- Sending: the queued walls in the order first asked, cut into chunks of `batchSize` (26 walls ->
  a call of 25, then a call of 1). Each chunk is one `query` call; the calls do not wait for each
  other. Item `i` of the answer belongs to item `i` of the chunk.
- Success: each wall's promise resolves with its `gifts`; the answer is cached with `at = now`
  at arrival. Failure: every wall of that chunk rejects with the error; nothing is cached; the next
  `load` asks again.
- `peek(user, reference?)`: the fresh cached answer or nothing (lets a wall draw at once).
- `invalidate(user, reference?)` (the component's `refreshKey`, e.g. after the viewer sent a
  gift): drops the cached answer; a request already in flight for that wall is let go (its callers
  still get its answer, but it is NOT cached, even if it arrives last) and the next `load` asks
  again. A wall still queued simply goes out with its window.
- `clear()`: drops every cached answer.

### 14.5 Component (UI, not fixture-tested)

`GiftWall` props: `client`, `user`, `reference?`, `max 6`, `order "count"`, `size "md"` (`sm`
icon 16 / text 11, chip height 20; `md` icon 20 / text 12.5, height 24), `data?` (preloaded, no
request), `refreshKey?`, `onPressChip(gift)?`, `onError(error)?`, `theme` (`surface`, `border`,
`text`, `muted`), `labels`. Loading: 3 static skeleton chips; empty: nothing (or `emptyText`);
error: nothing + `onError` (a wall never shows an error). One wrapping row, gap 6, radius full,
padding 4/8, icon "contain", the count without an `x`; a 120 ms opacity-in when data arrives
(none under reduced motion). The row is one accessible element labelled like `"Gifts: 12 Roses,
3 Hearts, and 37 more"`; with `onPressChip` each chip is a button `"Rose, 12"` with a 44 dp touch
target. Overflow chip: `+{formatCount(count)}`.

## 15. Away summary ("while you were away")

Added on 2026-10-11 (design A.3 and D). When the receiver opens the app, a card summarises the
gifts that arrived since they last looked (at most 7 days back) and the effect layer replays up to
5 gift groups as one short sequence (<= 8 s), biggest last. One GET at app open and on return to
the foreground (throttled); nothing is realtime. Reference: `packages/sdk-js/src/core/away.ts`.
Fixture: `conformance/away.json`. Status as section 14.

### 15.1 Client calls and model

- `getAway({ since?, maxGroups? })`: `GET {base}/v1/client/me/away`, query `since` then
  `max_groups`, each only when given, values `enc`-encoded. Returns the body (`AwaySummary`).
- `ackAway(cursor)`: `PUT {base}/v1/client/me/away/cursor`, body `{ "cursor": cursor }`
  (`Content-Type: application/json`, no `Idempotency-Key`). Success is `204` with no body: the
  client MUST NOT parse a body (it returns nothing). Retries as 3.4 (the PUT is idempotent and
  monotonic on the server).

```text
AwaySummary  user, since, until, cursor?, truncated:bool, total_gifts:int, total_units:int,
             sender_count:int, groups: AwayGroup[], top_senders: (AwaySender + units:int)[]
AwayGroup    gift { id, name, price:int, icon_url?, animation_url? }, count:int, units:int,
             sender_count:int, senders: AwaySender[] (<= 3)
AwaySender   user? (null = deleted senders, merged), count:int
```

`groups` come sorted by `units` desc, then gift id. `truncated: true` means the totals are lower
bounds (show "2,000+"). An empty summary has `total_gifts: 0` and its `cursor` unchanged.

### 15.2 `awaySenderLabel(names, senderCount, labels?)`

`names` = the group's `senders` mapped to display names, in order (a `null` user is
`labels.someone`, default `"Someone"`). Exactly:

```text
a = names[0] or someone
senderCount <= 1                         -> a
senderCount == 2 and len(names) >= 2     -> pair     "{a} and {b}"        (b = names[1])
senderCount - 1 == 1                     -> oneOther "{a} and 1 other"
otherwise                                -> others   "{a} and {n} others" (n = senderCount - 1)
```

### 15.3 `planAwayReplay(groups, options)`: the exact algorithm

Options: `maxEffects 5`, `budgetMs 8000`, `thresholds` and `quality` (as the layer's),
`reducedMotion false`, `resolveName(user)` (default: the id itself; deleted senders never reach
it), `labels`. Result `{ items, endMs }`, each item `{ atMs, durationMs, tier, group, event }`.

```text
if reducedMotion: return { items: [], endMs: 0 }          (also used when there is no effect layer)
considered = groups[0 .. maxEffects-1]                     (server order)
tier(g)    = tierFor(g.gift.price, thresholds)
large      = the FIRST considered group whose tier is large (or none); other large groups are dropped
rest       = considered groups that are not large, sorted by units ascending, ties by gift id
             ascending (plain code-unit string comparison)
duration(tier) = flyInMs + max(900, holdMs + flyOutMs, coins > 0 ? holdMs + flyOutMs + 800 : 0)
             of recipeFor(tier, quality) = small 1600, medium 2100, large 3850 (low: 3050)

layout(rest, large):
  at = 0; end = 0
  for g in rest:  item(g, at); end = max(end, at + duration); at += 450 if small else 1100
  if large:       start = (rest empty) ? 0 : end + 300; item(large, start); end = start + duration
  return items, end

plan = layout(rest, large)
while plan.end > budgetMs and plan has items:
    if rest not empty: rest = rest without its FIRST element (lowest units)
    else: large = none                     (a lone large effect longer than the budget goes too)
    plan = layout(rest, large)
```

An end exactly equal to `budgetMs` fits. Each item's `event` is a `GiftEffectEvent`:
`gift { id, name, price, image: animation_url ?? icon_url, icon: icon_url }`,
`quantity = group.count`, `sender = awaySenderLabel(names, group.sender_count, labels)`.

Worked example (fixture): dragon 1 (40,000 units), hat 20 (7,000), rose 50 (500), star 3 (15) ->
star at 0, rose at 450, hat at 900 (medium, ends 3000), dragon at 3300, end 7150.

Card duration: `awayCardDurationMs(plan) = max(4000, plan.endMs + 1500)`.

### 15.4 `AwayController` (pure, injected clock and timers)

Options: `client` (`getAway`, `ackAway`), `effects()` (the layer's `play`, read at each play;
absent = card only), `reducedMotion()` (read at `start`), `ackOn` (`"shown"` default |
`"finished"` | `"manual"`), `maxGroups` (sent as `max_groups` only when given), `minGifts` (default 1), `maxEffects`,
`budgetMs`, `thresholds`, `quality`, `resolveName`, `labels`, `throttleMs 60,000`, `onShow(summary)`,
`onDone()`, `onError(error)`, `now`, `setTimeout`, `clearTimeout`. State `{ status, summary, plan }`
with `subscribe`/`getState` like `GiftTrayController`.

```text
status: idle -> loading -> empty | ready -> playing -> done
check():      only from idle, empty or done (the resting states); ignored otherwise.
              lastCheckAt = now; status = loading; summary = plan = null
              if a retry cursor is stored: clear it, await ackAway(it) (failure -> onError only)
              getAway(maxGroups given ? { maxGroups } : {})
                failure -> status = idle, onError(e)   (never shown to the person)
                total_gifts <= 0 -> status = empty
                total_gifts < minGifts (default 1) -> status = empty and the cursor is acknowledged at once
                  (ackAway; one retry on failure like ack()), so the small summary does not come back
                else -> status = ready, summary = it; the summary is not acknowledged yet
foreground(): check() unless lastCheckAt exists and now - lastCheckAt < throttleMs (60,000
              itself checks)
start():      only from ready (the UI calls it when the card is on screen).
              plan = planAwayReplay(summary.groups, ..., reducedMotion: no effects() or reducedMotion())
              status = playing; for each item: timer at item.atMs -> effects()?.play(item.event)
              (only while still playing); timer at awayCardDurationMs(plan) -> dismiss()
              onShow(summary); if ackOn == shown: ack()
dismiss():    only from ready or playing (tap, close button, or the timer).
              cancel every pending timer (effects already playing finish naturally; the
              controller never calls the layer's cancel or clear); status = done;
              if ackOn != manual: ack(); onDone()
ack():        if this summary was already acknowledged (or its one attempt made) or its cursor
              is null: nothing. Else mark it, ackAway(summary.cursor); on failure store the cursor
              for ONE retry at the next check() and onError(e). A summary is acknowledged at most
              once; a stored cursor is retried at most once.
dispose():    timers stop; answers that arrive later change nothing.
```

The ack sends the cursor of the summary that was shown, never "now", so gifts that arrived during
the replay are shown next time. `ackOn: "shown"` gives at-least-once display (a crash before the
card appears shows it again).

### 15.5 Component (UI, not fixture-tested)

`GiftAwaySummary` (web `<gift-away-summary>`): props `client`, `effects?`, `resolveUsers(ids)`
(`Promise<Record<id, { name, avatarUrl? }>>`; fallback the id, `null` = `labels.someone`),
`minGifts 1` (the card shows only from that many gifts; fewer is `empty` and acknowledged, see 15.4; not yet in the native fixtures), `autoCheck true` (`check()` on mount, `foreground()` on return to the foreground), `ackOn`,
`maxEffects`, `budgetMs`, `thresholds`, `quality`, `onShow`, `onDone`, `onError`, `focusOnShow`,
`theme` (`surface`, `text`, `muted`, `accent`, `accentText`), `labels`. Card: centred, max width 360,
radius 20, "While you were away: 37 gifts from 12 people", top 3 senders with initial avatars, gift
icons with counts; non-modal `role="dialog"` with a "Dismiss" button; it calls `start()` once it is
on screen and `dismiss()` on tap. Reduced motion: no slide-in; the live region announces "You
received 37 gifts from 12 people while you were away".

## 16. Leaderboard

Added on 2026-10-11 (design A.4). Top senders or receivers, by units or gift count, for today, this
week (Monday-Sunday, UTC), this month or all time; up to 100 rows; the viewer's own row is
highlighted, or pinned under the list when it is not shown. Reference:
`packages/sdk-js/src/core/leaderboard.ts`. Fixture: `conformance/leaderboard.json`. Status as
section 14.

### 16.1 Client call and model

`getLeaderboard(board, { period?, metric?, at?, limit?, includeMe? })`: `GET
{base}/v1/client/leaderboards/{enc(board)}` with the query parameters in this fixed order, each
only when given: `period`, `metric`, `at`, `limit`, `include_me` (sent only as `include_me=false`
when `includeMe` is false; `true` is the default and is left out). Values are `enc`-encoded.
Returns the body.

```text
Leaderboard       board ("senders"|"receivers"), period ("day"|"week"|"month"|"all"),
                  metric ("units"|"gifts"), label, starts_at?, ends_at?, as_of,
                  data: LeaderboardEntry[], has_more:bool, me: LeaderboardMe?
LeaderboardEntry  rank:int, user, gifts:int, units:int
LeaderboardMe     user, rank:int? (null beyond the top 1,000, without a score, or hidden),
                  gifts:int, units:int, hidden:bool
```

Ranks are competition ranks (1, 2, 2, 4), computed by the server; the SDK never re-ranks. A `503
leaderboard_building` (only during the one-time backfill, with `Retry-After: 30`) is handled like
every 5xx in 3.4: one immediate retry, then the error (`retryable: true`); the controller shows it
as an error with "Try again".

### 16.2 Labels and pinning

- `leaderboardRankLabel(rank, { overflow = "1,000+" })`: `null` -> `overflow`; else `"#"` + the
  rank with `,` every three digits (`#1`, `#417`, `#1,000`).
- `groupThousands(n, separator = ",")`: whole number with a separator every three digits.
- `pinnedMe(board, limit)`: the `me` block to pin under the list, or none:

```text
none if board or board.me is missing, or me.hidden
none if me's score on board.metric (gifts or units) <= 0
me   if me.rank is null or me.rank > limit
me   if no row of board.data has user == me.user     (a tie at the cut left them out)
none otherwise                                        (they are in the list: highlight that row)
```

- Medal colours for ranks 1-3, new tokens used only by this component (not part of `GiftTheme` or
  `theme.json`): `rank1 #e8a93a`, `rank2 #b8bcc8`, `rank3 #c07a45` (`RANK_COLORS`), the number on
  them in the theme's `noticeBigText`; contract >= 4.5:1 against `noticeBigText` of
  `defaultTheme`, `darkTheme` and `lightTheme` (fixture `leaderboard.json#rankColors`).

### 16.3 `LeaderboardController` (pure, injected clock)

Options: `client` (`getLeaderboard`), `board "senders"`, `periods` (default day, week, month, all;
an empty list counts as the default), `initialPeriod "week"` (when not in `periods`: `periods[0]`),
`metric` (default `"gifts"` for receivers, `"units"` for senders: decision F.11), `limit 10`,
`includeMe true`, `staleMs 30,000`, `now`, `onError`. State `{ periods, period, metric, status,
data, refreshing, error, pinned }` with `subscribe`/`getState`.

```text
tab key        (period, metric); one cache entry per key: { value, at }
show(force):   hit = cache[key]
               stale = no hit, or now - hit.at >= staleMs           (30,000 itself is stale)
               if (force or stale) and no request for key is in flight: fetch(key)
               render()
fetch(key):    mark in flight; getLeaderboard(board, { period, metric, limit,
               includeMe: false only when includeMe is false })
               success -> cache[key] = { value, at: now }; forget key's error
               failure -> errors[key] = e; onError(e)
               then clear in flight and render()  (an answer for another tab fills its cache only)
render():      data = cache[current key]?.value
               refreshing = data exists and a request for the key is in flight
               status = data ? (data.data empty ? empty : ready)
                             : (errors[key] and nothing in flight ? error : loading)
               error = errors[key] or none;  pinned = pinnedMe(data, limit)
start():       show(false)
setPeriod(p), setMetric(m): ignored when unchanged; else switch the tab and show(false)
refresh():     show(true)   (pull to refresh, "Try again", a poll)
dispose():     answers that arrive later change nothing
```

So a cached tab shows at once and, if 30 s old or more, revalidates in the background while its
rows stay visible; a failed revalidation keeps the rows (status stays ready/empty, `error` is set).
There is no polling inside the controller: an app that wants `refreshIntervalMs` calls `refresh()`
on its own timer.

### 16.4 Component (UI, not fixture-tested)

`GiftLeaderboard` props: `client`, `board`, `periods`, `initialPeriod`, `metric`, `metricToggle`,
`limit`, `resolveUsers(ids)`, `highlightUser` (default: the token user = `me.user`),
`refreshIntervalMs 0` (a value above 0 is at least 5,000 ms: `leaderboardPollMs`, audit R-17,
fixture `leaderboard.json` "pollMs"), `onPressUser(id)`, `theme`, `labels`, `coinName`. Loading: `limit` skeleton
rows; empty: `labels.empty[period]` ("No gifts yet this week"); error: inline message + "Try
again" (`refresh()`); stale rows stay visible while refreshing (small header spinner, none under
reduced motion). Row height 52: rank (1-3 on a medal disc), avatar (image or initial disc),
name, score (`formatCount` + coin icon for units; plain number + "gifts" for gifts); the
highlighted row uses `selected`. Pinned row: "You: #417" / "You: 1,000+". Tabs are a `tablist`;
rows are labelled `"Rank 1, ayla, 54,000 coins"`, the pinned row `"Your rank: 417, 120 coins"`. No
rank-change animation in v1.

### 16.5 Render slots (all SDKs; no fixtures)

Added on 2026-10-12 (product principle: the customer decides how a feature looks). Optional
render hooks replace the INSIDE of a component part; the SDK keeps loading, ordering, dedup,
names, the part's container, its accessibility role and label, press handling, focus and
effects. A hook that returns `null`, `undefined` (React Native also `false`) draws the default;
on the web a throw also draws the default and goes to `onError`. Web hooks return a DOM node or a
string (text, never HTML); React Native hooks return a node.

- `GiftWall.renderChip({ gift, count, countText })`: the inside of each gift chip (the "+N"
  overflow chip is not passed).
- `GiftLeaderboard.renderRow({ entry, rank, name, avatarUrl, metric, score, scoreText, isMe })`:
  the inside of each ranked row (the pinned "You" row stays the default).
- `GiftAwaySummary.renderSummary({ summary, title, headline, senders, dismiss, ack })` (web also
  `gifts`, `people`): the body of the card. With a custom body a tap does not dismiss (the
  default card dismisses on tap): the hook calls `dismiss()`. The card keeps `role="dialog"` with
  the title as its label (web) and announces the arrival.

On the web they are plain options (`<gift-wall>` and the other elements take them through the
`options` property). Native (added 2026-10-18), same names and context fields (plus `theme`, the
resolved theme; the away context also has `gifts` and `people`): Flutter builders
`Widget? Function(BuildContext, Context)` (null = default); Kotlin nullable `@Composable` lambdas
(null parameter = default, `context.Default()` keeps the default for one item); Swift closures
returning `AnyView?` (nil = default). A custom away body has no close button and a tap does not
dismiss. A custom chip or row may be taller than the default.

## 17. Rooms (realtime)

Status: **the server is live at `wss://rt.giftingstack.com`; the TypeScript core, web, React Native,
Flutter, Android and iOS implement the client (section 18).** The server is a Worker with one Room
Durable Object per room. This section is the wire contract; section 18 the client rules, pinned by
the fixtures `conformance/rooms-*.json`.

A room is "everyone watching one stream / audio room / chat". When a gift send names a `room_id`
and commits, every socket connected to that room gets a `gift` event (about 50-400 ms later). Best
effort: no history, no delivery guarantee, the ledger stays the record.

### 17.1 Sending into a room

Both send endpoints take an optional `room_id`:

- `POST /v1/client/gift-transactions` (client token) and `POST /v1/gift-transactions` (secret
  key): body field `room_id`, `^[A-Za-z0-9_.:-]{1,64}$`, case sensitive.
- `room_id` is part of the idempotency body hash: a retry with the same `Idempotency-Key` MUST
  send the same `room_id` (another room, or none, is `422 idempotency_key_reused`).
- On the client endpoint the token's `rooms` must allow the room (17.2), else
  `403 room_not_allowed` before anything is sent. The secret-key endpoint takes any room id.
- While the project's "Gift rooms" switch is off the send still succeeds, but nothing is
  published (no Room object is woken).
- The response is unchanged and never delayed by the room. The event is published after the
  commit, and again on an idempotent replay (the room drops the duplicate by `tx`).
- A failed send publishes nothing.

### 17.2 Tokens

`POST /v1/client-tokens` takes two optional fields that become token claims:

| body field | claim | rule                                                                                                                                                                |
| ---------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rooms`    | `r`   | 1-8 entries, each a room id or a prefix ending in `*` (`"match_*"`). Required for rooms (below)                                                                     |
| `name`     | `n`   | 1-32 characters, no control, invisible (zero-width, bidi, other format) or line-separator characters. Shown to viewers as `sender.name` of this user's client sends |

Rooms are deny by default (security audit, 2026-10-12): a token without `rooms` can neither join
any room (close 4003 `room_forbidden`) nor send with `room_id` (`403 room_not_allowed`, nothing is
sent). With `rooms`, a room is allowed when an entry equals its id or is a prefix entry the id
starts with; the same rule decides joins and client sends. Sends with the secret key may name any
room of the project.

The SDK never builds tokens; it passes the app's token through. The only thing it reads from one
is the user claim `u` (to skip the user's own gifts, 18.2), and only when the app did not name the
user itself.

### 17.3 Connecting

```
GET wss://rt.giftingstack.com/v1/rooms/{room_id}
Sec-WebSocket-Protocol: gs.v1, <client token>
```

- The token goes ONLY in `Sec-WebSocket-Protocol` (browsers cannot set headers; a token in the
  URL would land in logs). The server answers with the subprotocol `gs.v1` alone.
- Without `gs.v1` and a token the server answers plain HTTP `401` (no WebSocket). Every other
  refusal completes the handshake and closes at once with a close code (17.6), so every platform
  can read the reason.
- Right after `open` the client MUST send `hello`. Events are delivered only after `welcome`.

### 17.4 Messages

All frames are text. Server frames are JSON objects with a type `t`. Clients MUST ignore unknown
`t` values and unknown fields (forward compatible).

Client to server (nothing else is allowed: any other frame closes with 4400):

| frame                                   | when                                                                                                      |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `{"t":"hello","v":1,"last":<id\|null>}` | first frame after open; `last` = id of the last `gift` this client saw in this room (resume), else `null` |
| `ping` (literal text, not JSON)         | app heartbeat on platforms without protocol pings (web, React Native); answered `pong` (literal text)     |

Limits: frames of at most 1,024 bytes, at most 5 client frames per 10 s per socket (auto-answered
`ping`s are not counted), `v` MUST be `1`, `last` a non-negative integer or `null`.

Server to client:

| `t`       | fields                                                                                    |
| --------- | ----------------------------------------------------------------------------------------- |
| `welcome` | `v` (1), `viewers` (int), `gap` (bool), `replay` (array of `gift`), `ttl` (s), `now` (ms) |
| `gift`    | see below                                                                                 |
| `viewers` | `n` (int): approximate viewer count, at most one message per 5 s                          |
| `batch`   | `events` (array of `gift`, in id order): several gifts at once under load (see below)     |
| `scores`  | `battle` (a round, or `null`): battle scores, see 17.8                                    |

`welcome` also carries `battle` (17.8) while the room has a battle round; absent otherwise.

`batch` (coalescing under load; server since 2026-10-12): above 10 gifts per second
in a room, the server holds gifts for 250 ms and sends them as one `batch` (a hot room, where a
broadcast took over 200 ms, batches every gift every 1 s for at least 60 s). Below that rate
gifts go out at once as `gift` frames. Inside a batch, consecutive gifts with the same
`sender.id`, `gift.id`, `gift.price` and `receiver.id` are collapsed into ONE gift: the last gift
of the run (its `id`, `tx`, `at`, names) with `quantity` = the sum. So a collapsed gift is an
ordinary `gift` (its `tx` is real, its `id` is at or after every merged gift), the effect shows
the summed count once (`xN`: a quantity above 1 wins over the combo run), and clients handle a batch exactly like its gifts arriving one by
one: same filter, dedup and own-skip, `last` = id of the batch's last gift (18.2). The merged
gifts' other `tx` ids are never sent live. A batch carries only gifts published after the
socket's `welcome`, like live `gift` frames. `welcome.replay` is never collapsed: a resume from an
id inside a collapsed run replays the remaining gifts one by one.

`gift`:

```json
{
  "t": "gift",
  "id": 1760180000123001,
  "at": 1760180000123,
  "tx": "gtx_01JA0Q8X2M4N6P8R0T2V4W6Y8Z",
  "gift": {
    "id": "rose",
    "name": "Rose",
    "price": 50,
    "icon_url": "https://assets.giftingstack.com/gifts/rose/256.webp"
  },
  "quantity": 3,
  "sender": { "id": "user_123", "name": "Ayse" },
  "receiver": { "id": "user_456" }
}
```

| field                      | meaning                                                                                                   |
| -------------------------- | --------------------------------------------------------------------------------------------------------- |
| `id`                       | per-room event id, increasing, about `epoch ms x 1000`; the resume point (`last`)                         |
| `at`                       | commit time of the gift transaction, epoch ms (server clock)                                              |
| `tx`                       | gift transaction id: the dedup key                                                                        |
| `gift.price`               | unit price at send time: drives the tier (section 4.1)                                                    |
| `gift.icon_url`            | may be `null`; the big picture comes from the cached catalog by `gift.id` (`GET /v1/client/gifts`)        |
| `sender.name`              | optional (token claim `n` of the sender); absent: the app's name resolver, else the scheduler's "Someone" |
| `sender.id`, `receiver.id` | external ids                                                                                              |

Never present: the gift `message`, balances, `total`, `reference`, metadata.

`welcome.ttl` is the number of seconds until the server closes the socket with 4001 (token expiry or
the 60 minute socket lifetime, whichever is first). `welcome.now` is the server time used for
staleness (17.5).

### 17.5 Resume, gaps, dedup

- The server keeps the last 100 events or 15 s, whichever is smaller, in memory only.
- `hello.last = null`: `replay` is empty, `gap` is `false` (a new viewer does not see old gifts).
- `hello.last` = an id still in the buffer: `replay` = the buffered events after it, `gap: false`.
- `gap: true` when `last` is not in the buffer and events may have been lost: it was evicted, or
  it was issued before the room's buffer was reset (hibernation after about 10 s without events,
  restart, deploy). `replay` then holds whatever is buffered after `last`.
- On `gap` a client does nothing visible (there is nothing to fetch); it MAY call an `onGap`
  callback.
- Clients play a replayed or live event only if `welcome.now - at` (for replays) is under
  `maxReplayAgeMs` (default 10,000); older ones are dropped silently.
- Dedup: the server drops a repeated `tx`; clients MUST also keep the last 256 `tx` and drop
  repeats (the server's set is lost on hibernation). A lower `id` with a new `tx` is still played.
- Own gifts: by default (`skipOwn: true`) a client skips events whose `sender.id` is its token
  user (the sender already played the effect on tap).

### 17.6 Close codes

| code                | meaning                                                                                                       | client action                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 4001                | token expired, or the 60 minute socket lifetime reached                                                       | get a fresh token, reconnect now with `last` |
| 4003                | token invalid, its API key revoked, or the `r` claim missing or excluding this room                           | closed, no retry                             |
| 4004                | bad room id                                                                                                   | closed, no retry                             |
| 4008                | rate limited; reason is JSON `{"retry_after":s}`                                                              | wait and retry (18.3)                        |
| 4009                | room full (plan cap; reason `{"retry_after":30}`), or reason `replaced`: a 4th socket of the same user opened | full: as 4008; `replaced`: closed, no retry  |
| 4010                | rooms not available for the project's plan                                                                    | closed, no retry                             |
| 4011                | project suspended (a live project; read with the minting key)                                                 | closed, `reconnectNow()` may restart (18.3)  |
| 4400                | protocol error (a frame other than `hello`/`ping`, binary, too big), or `hello_timeout`: no `hello` in 15 s   | closed, no retry (a bug)                     |
| 1011                | server could not send                                                                                         | backoff and reconnect                        |
| 1006, 1012, network | dropped, server restart or deploy                                                                             | backoff (18.3), resume                       |

Reconnect backoff: full jitter, `random(0, min(30 s, 0.5 s x 2^attempt))` with a floor, at most 12
retries in a row, the attempt counter resets after 60 s open (design 5.2; the exact rules are 18.3).

### 17.7 Limits (server)

Viewers per room: Free 50, Starter 1,000, Growth 5,000 (live); 20 in the test environment on every
plan. At most 3 sockets per user per room (the oldest closes with 4009 `replaced`). Joins: 10 per
10 s per user, 200 per second per room (burst 1,000), 100 upgrades per 10 s per IP. New rooms: 20
per minute per user (a rejoin of a room the user joined in the last minute usually does not
count); joins per project and environment: 1,000 per minute (test environment and Starter), 3,000 (Growth, live environment), 15,000 (Scale, live environment). Both close with 4008
`{"retry_after":60}`. Rate limits are per Cloudflare location and approximate.

### 17.8 Battle scores (versus)

Status: **server and every SDK (TypeScript core, web, React Native, Flutter, Android, iOS)**; the server
part was built 2026-10-14. Fixture: `conformance/rooms-battle.json`.

A battle round makes the room add up, per receiver, the gifts sent into it: two (up to 8) hosts in
one live room, viewers pick a side by choosing the receiver of their gift (`receiver` on the send,
as always), and every viewer sees a live score bar.

Rounds are controlled only by the customer's server with the secret key; a client token can
neither start, end nor clear one (deny by default: those routes refuse client tokens with 401, and
no socket frame controls a round):

| request                               | effect                                                                                         |
| ------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `POST /v1/rooms/{room_id}/battle`     | start a round: every score back to 0. Body: `round`, `receivers` (both required), `duration_s` |
| `POST /v1/rooms/{room_id}/battle/end` | stop counting now; scores stay                                                                 |
| `DELETE /v1/rooms/{room_id}/battle`   | remove the round; viewers get `battle: null`                                                   |
| `GET /v1/rooms/{room_id}/battle`      | the round now                                                                                  |

Each answers `200 {"battle": <round or null>}`. `round` (required since 2026-10-20, audit M3) is
your id for the round and makes retries safe: a start that names the current round changes nothing
and adds `"replayed": true`; one that names an earlier round among the room's last 16 (replaced or
removed) answers `409 round_superseded` and changes nothing, so a late retry never resets a newer
round. Use a new id for each round. `receivers` (required since 2026-10-20, audit M4): 1 to 8
distinct user ids, listed at 0 from the start in this order; only gifts to them count. There are no
open rounds: an empty or missing list is a `400`, so no viewer can take a round's places with cheap
gifts to made-up ids. `duration_s`: 1 to 86,400 (default 86,400). Same gates as a publish:
`403 rooms_disabled`, `403 plan_required` (live rooms need a paid plan),
`503 rooms_unavailable`.

The round object (`welcome.battle`, `scores.battle`, the API's `battle`):

```json
{
  "round": "match_42_r1",
  "started": 1760180000000,
  "ends": 1760180300000,
  "scores": [
    { "id": "ava", "units": 1250, "gifts": 9 },
    { "id": "mateo", "units": 800, "gifts": 14 }
  ]
}
```

Counting rules (server):

- A gift counts when the room accepted it (not a duplicate, stale or invalid event, 17.5), its
  commit time `at` is in `[started, ends)`, and its receiver is one of the start's `receivers`.
  Gifts to anyone else still play; they do not count.
- `units += gift.price x quantity` (the unit price at send time), `gifts += quantity`. Counters
  only, never balances; they stop at 2^53 - 1.
- A `tx` counts once per round, also after the room's memory was reset (hibernation): counted ids
  are kept in storage for the 15 s in which a repeat can still be accepted.
- Scores survive hibernation (stored with the room). Only an open round writes storage.
- `scores` frames are whole snapshots, never deltas, sent at most once per coalescing window (250
  ms; 1 s while the room is hot, 17.4), never once per gift. A start, end or clear sends one too.
  Nothing is sent when `ends` passes: clients compare it with the server clock.

## 18. Joining a room (client)

Status: TypeScript reference `packages/sdk-js/src/core/rooms.ts` (pure), web `joinRoom`, React
Native `useGiftRoom` (2026-10-12). Native platforms port the core against the fixtures in phase 4;
until then their fixture-coverage tests acknowledge `rooms-*.json` as "rooms pending native port".

Everything below is pure logic with an injected socket factory, clock, timers, random source and
token function, so the five fixtures pin it. A platform adds only the socket transport and the app
lifecycle hooks.

### 18.1 Protocol helpers

- `parseRoomFrame(text)` returns the message, or nothing for a frame to ignore: not JSON, not an
  object, an unknown `t`, a known `t` with a required field missing or mistyped. Unknown fields
  are dropped. Required: `gift`: `id`, `at` (non-negative integers), `tx` (non-empty), `gift.id`,
  `gift.name`, `gift.price` (integer >= 0), `quantity` (integer >= 1), `sender.id`; `icon_url`
  missing or not a string is `null`; `sender.name` that is empty or not a string is absent;
  `receiver` without a string `id` is `null`. `welcome`: `viewers` (integer >= 0), `gap` (bool),
  `ttl` (number >= 0), `now` (integer >= 0), `replay` (missing = empty; its invalid entries are
  dropped alone; `v` is not checked). `viewers`: `n` (integer >= 0). `batch`: `events` (a list,
  invalid entries dropped alone). The literal text `pong` is a pong. `ping` from the server is
  ignored.
- `roomHelloFrame(last)`: `{"t":"hello","v":1,"last":<id|null>}`.
- `roomUrl(room, baseUrl = "wss://rt.giftingstack.com")`: trailing slashes of the base removed,
  room id percent-encoded like `encodeURIComponent`.
- `roomTokenUser(token)`: the `u` claim of `gs_ct_<base64url(JSON)>.<sig>` (not verified), else
  nothing. A malformed token is nothing, never an error.

### 18.2 Event filter (`RoomEventFilter`)

Options: `user` (the signed-in user's external id), `skipOwn` (default true), `maxReplayAgeMs`
(default 10,000), `minTier` (default `small`), `thresholds` (section 4.1). State that survives
reconnects: `last` (null at first) and the last 256 `tx` ids. For each gift of a `welcome.replay`,
a live `gift` or a `batch`, in order:

1. `last = id` (every gift received, whatever happens next; ids are not compared, so a server
   whose ids went back after a restart still resumes correctly).
2. A `tx` already remembered: dropped. Else the `tx` is remembered (the oldest of 257 forgotten).
3. `serverNow - at >= maxReplayAgeMs`: dropped (stale). `serverNow` is `welcome.now` for the
   replay and `welcome.now + (localNow - local time when that welcome arrived)` for live gifts.
4. `skipOwn` and `sender.id == user`: dropped (the sender's tray already played it at the tap).
5. `tierFor(gift.price, thresholds)` below `minTier`: dropped.

A live gift before any `welcome` is ignored entirely (`last` unchanged). `welcome.gap` is reported
once per welcome (`onGap`); nothing else happens on a gap.

A `batch` is its gifts in order (all of them in one `live` call): after it, `last` is the id of
the batch's last gift even when that gift was dropped, and a collapsed gift (17.4) passes or drops
as one gift with its summed `quantity`. There is nothing to un-collapse on the client.

### 18.3 Reconnect policy (`roomRetryDecision`)

Input: close `code`, `reason`, `attempt` (failed connections in a row before this one: a socket that
stayed open 60,000 ms after its `welcome` starts the count again from 0), `limited` (4008/4009
waits in a row). `random` is in [0, 1) and is called at most once.

- `jitter(cap) = 500 + floor(random() x max(0, cap - 500))`: a jittered wait is never below the
  **floor** of 500 ms (`ROOM_RETRY_FLOOR_MS`), so a draw of 0 cannot start a tight reconnect loop
  and a deploy cannot bring every viewer back in the same instant.
- `backoff = jitter(min(30,000, 500 x 2^attempt))` (attempt 0: the cap is the floor, 500 ms).
- `roomRateLimitedDelayMs(retry_after, limited)`: `d = min(300,000, max(30,000, retry_after x 1000)
x 2^limited)`; the wait is `min(300,000, d + floor(random() x d / 4))`.
- **Ceiling** (`ROOM_MAX_ATTEMPTS` = 12): when `attempt >= 12`, every code that would retry by
  backoff (4001, 1006, 1012, anything else) is **stop, resumable, exhausted** instead.

| close                                     | decision                                                                                                                                              |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 4003, 4004, 4010, 4400, 4009 `replaced`   | stop, final (no retry; `reconnectNow()` does nothing)                                                                                                 |
| 4011 (project suspended)                  | stop, resumable (no automatic retry)                                                                                                                  |
| 4008 with `retry_after` > 0 in its reason | wait `roomRateLimitedDelayMs`, counts as limited, never gives up (not counted against the ceiling)                                                    |
| 4008 without it, 4009 (other reasons)     | `limited >= 5`: stop, resumable; else wait `max(30,000, retry_after x 1000)` (`retry_after` of the JSON reason, else 0), no random, counts as limited |
| `attempt >= 12` (codes below)             | stop, resumable, exhausted                                                                                                                            |
| 4001                                      | fresh token (`forceRefresh: true`); wait 0 when `attempt == 0`, else `backoff`                                                                        |
| 1006, 1012                                | `attempt == 0`: `jitter(5,000)`; else `backoff`                                                                                                       |
| anything else (1000, 1011, unknown codes) | `backoff`                                                                                                                                             |

The decision is `{ retry: true, delayMs, refreshToken, limited }` or `{ retry: false }`; the
resumable stops are `{ retry: false, resumable: true }` and the ceiling is `{ retry: false,
resumable: true, exhausted: true }`. `rooms-reconnect.json` compares exactly these keys.

**Why these rules (decided 2026-11-03, audit R-03).**

- _Ceiling._ The first version retried forever on every unknown code, on `token_failed` and while a
  deleted or misconfigured project kept refusing. Twelve retries cover about 3.5 minutes at the
  longest (caps 0.5, 1, 2, 4, 8, 16 s, then 30 s; about half of that on average with full jitter):
  enough for a tunnel, a deploy or a flaky token endpoint, little enough that a viewer left on a
  screen does not keep joining (and spending the per-user and per-project join limits of 17.7) all
  night. The count is the existing `attempt`: a `welcome` alone does not reset it, only a socket
  that stayed open 60 s does, so a server that accepts and drops every few seconds also ends. After
  the ceiling the state is `closed` with `code` = the last close code seen and `reason` =
  `retries_exhausted`; the app can show "Connection lost" and a button that calls `reconnectNow()`.
- _Platform limit._ A 4008 with `retry_after` is the platform saying when to come back (a rooms
  deploy makes every viewer rejoin at once). It never ends the session; its waits grow to 5 minutes
  with 25 % jitter, so a viewer costs one join per 5 minutes at most.
- _4011._ A suspension is a billing or administrative state that lasts hours or days, not a blip.
  Retrying, even slowly, only burns battery and join limits, so the client stops and leaves the
  decision to the app: `closed` with `code 4011` and the server's reason, resumable. A deleted or
  revoked key is already final (4003 `key_invalid`).
- _Auth-type failures._ `token_failed` (the app's token endpoint failed or timed out) is a 1006
  like any other and counts toward the ceiling, so a signed-out user does not keep asking forever.
  A repeating 4001 is the same (its second repeat already backs off).

**Resumable stops.** `reconnectNow()` on a `closed` state that came from a resumable stop (the
ceiling, 4011, the 4008/4009 limit) starts again at once: `connecting`, `attempt` 0, `limited` 0,
`getToken({ forceRefresh: false })`. It does nothing after a final close or after `leave()`. Web
calls it on `online` and when the page becomes visible; the native wrappers call it when the app
returns to the foreground (after `resume()`) and when the platform reports the network back, where
the platform has such a signal.

The `retry_after` growth and the refresh spread were JS-only from 2026-10-21 to 2026-11-03; all
five SDKs have them now, pinned by `rooms-reconnect.json` and `rooms-session.json`. The unit tests
of the JS helpers are in `packages/sdk-js/test/rooms-ratelimit.test.ts`.

### 18.4 Mapping (`roomGiftToEffect`)

A gift becomes a `GiftEffectEvent` with extra fields, passed as is to the effect layer's `play`:
`gift { id, name, price }` from the event (the price at send time drives the tier); `image` = the
catalog gift's `animation_url`, else its `icon_url`, else the event's `icon_url`; `icon` = the
event's `icon_url`, else the catalog's `icon_url`, else `null`; `sender` = `sender.name`, else
`resolveName(sender.id)` (empty or failing counts as nothing), else absent (the layer's
"Someone"); `quantity`; plus `id`, `tx`, `at`, `senderId`, `senderName` (the name claim or null),
`receiverId` (or null), `replayed` (came in a `welcome`).

### 18.5 Session (`RoomClient`)

States: `idle`, `connecting`, `open`, `reconnecting` (with `attempt` and `retryInMs`), `paused`,
`closed` (with `code` and `reason`; terminal). `viewers` is the last count from `welcome` or
`viewers` (null before the first).

1. `start()` (only from idle): a room id that breaks the rule of 17.1 is `closed` 4004
   `bad_room_id` at once, nothing is asked. Else `connecting`: ask `getToken({ forceRefresh })`
   (`true` only after a 4001 or a proactive refresh), then open `roomUrl(room)` with protocols
   `["gs.v1", token]`. The user for own-skip is the `user` option, else `roomTokenUser(token)`.
   The dead timer of step 2 is armed at the start of the attempt, before the token is asked for,
   and lasts 20,000 ms (`ROOM_TOKEN_MS`) while no socket exists: a `getToken` that does not answer
   in time is a close 1006 `token_timeout` (a failed attempt; a late answer is ignored). Once the
   socket is created the timer restarts with 10,000 ms.
2. On open send `hello` with `last`. No `welcome` within 10,000 ms of creating the socket: close it
   (1000, `timeout`) and continue as a close 1006 `timeout`.
3. `welcome`: `open`; `viewers`; the filtered replay with `replayed: true`; `onGap` if `gap`.
   Schedule a refresh at `min(ttl x 1000, 3,600,000) - 30,000 - spread` ms (none when that is not
   above 0): close the socket (1000) and connect again with `forceRefresh: true` (attempt
   unchanged). With `left = min(ttl x 1000, 3,600,000) - 30,000`, `spread = floor(random() x
min(refreshJitterMs, floor(left / 2)))`; `random` is called only when that minimum is above 0.
   `refreshJitterMs` defaults to 0 in the core (exact timing, as in most fixtures) and every platform
   entry point (web `joinRoom`, React Native `useGiftRoom`, Flutter `GiftRoom`, Android
   `rememberGiftRoom`, iOS `GiftRoomModel`) sets 120,000, so viewers that joined together do not
   reconnect in the same second.
4. Heartbeat (`heartbeatMs`, default 45,000; 0 = off, for native transports with protocol pings):
   every frame received counts as life. When `heartbeatMs` passed since the last frame, send the
   text `ping`; no frame within 10,000 ms: close (1000, `timeout`) and continue as 1006 `timeout`.
5. A close: when the socket had been open (after `welcome`) for at least 60,000 ms, `attempt` and
   `limited` start again from 0. Then apply 18.3: closed, or `reconnecting` with
   `attempt = attempt + 1` and the wait, then `connecting`; or `closed` (final, or resumable by
   18.3, the ceiling giving the reason `retries_exhausted`). A failed `getToken` is a close 1006
   `token_failed`.
6. `pause()` (app in background): close (1000), `paused`, nothing scheduled; `last` and the dedup
   set stay. `resume()`: connect now. `reconnectNow()` (network back, page visible): while
   `reconnecting` after a backoff, skip the wait; **never skip a 4008/4009 wait** (the platform said
   when to come back; skipping it would send every viewer back at once and defeat the limit; audit
   R-15); after a resumable stop (18.3), start again; else nothing. `leave()`: close (1000), `closed` 1000 `left`.
7. A socket, a token answer or a timer that belongs to an earlier connection is ignored. The
   client never throws into the app; app callbacks that throw are ignored. The socket the client
   closes itself is closed with code 1000 and the reason `client` or `timeout`.

Platform wrappers: web `joinRoom` (browser `WebSocket`; pauses after the page is hidden for 60 s,
resumes when visible; `online` calls `reconnectNow`), React Native `useGiftRoom` (global
`WebSocket`; `AppState` `background` pauses, `active` resumes). Both prefetch the catalog once
(`getGifts`) for the big picture and play every passed gift in the given effect layer. Sending into
the room: `roomId` on `sendGift`, `GiftTrayController`, `createGiftTray` and `useGiftTray`.

### 18.6 Battle scores (client)

Fixture `conformance/rooms-battle.json`. The state is headless on every SDK; the drawn bar is 18.7.
Native names: Flutter `RoomClient.getBattle()/subscribeBattle()/serverNow()/getBattleView()`,
`RoomClientOptions.onBattle`, `GiftRoom.battle/battleView()`; Android `RoomClient.battle` (and the
room state holder), iOS `GiftRoomModel.battle/battleView()`. The pure `battleView(battle, serverNow)`
and `RoomBattle` model exist on each.

- `parseRoomFrame`: `scores` with `battle: null` is `{ t: "scores", battle: null }`; with a valid
  round it is that round; a missing or malformed round ignores the frame. A round needs `round`
  (non-empty string), `started`, `ends` (non-negative integers) and a `scores` list; inside it
  entries without a string `id` and non-negative integer `units` and `gifts` are dropped alone;
  unknown fields are dropped. `welcome.battle` is parsed the same way; a malformed one is left out
  and the welcome stays valid.
- `RoomClient` keeps the last round: set by every `welcome` (absent = none), replaced by every
  `scores` frame. It survives a reconnect until the next welcome. `getBattle()`,
  `subscribeBattle(listener)`, option `onBattle(battle)`, `serverNow()` (local clock + the last
  welcome's offset, null before one) and `getBattleView()`.
- `battleView(battle, serverNow)`: `open` = `started <= serverNow < ends`; `remainingMs` =
  `max(0, ends - serverNow)`; `total` = sum of `units`; `sides` = the scores in server order, each
  with `share` = `units / total` (an equal `1 / n` while `total` is 0); `leader` = the id with
  the most units, `null` when nobody scored or the top is tied. `serverNow` null reads as
  `started`.
- Web: `joinRoom(...).battle`, `.battleView()`, `.onBattle(listener)` and the `onBattle` option.
  React Native: `useGiftRoom(...).battle` and `useBattleScore(controller, { tickMs = 1000 })`
  (the view, re-rendered on every frame and every `tickMs` while the round is open).

### 18.7 Battle bar (drawn)

A drawn versus bar on all five SDKs (web `GiftBattleBar`, React Native `BattleBar`, Flutter
`GiftBattleBar`, Android `GiftBattleBar`, iOS `GiftBattleBar`). Fixture `conformance/battle-bar.json`.
It draws `battleView` and decides nothing about the round. Hidden (nothing drawn) while the room has
no round with two sides; a third side is ignored.

Model (pure, ported from `core/battleBar.ts`): `pct` = first side's `share x 100` clamped to 6..94;
`clock` = `m:ss` of `remainingMs` rounded up (`Final` once the round is not open); `urgent` = open and
at most 10 whole seconds left (rounded up); `winner` = the leader once the round ended; `banner` =
`{name} wins the round` / `Draw: nobody wins this round` once ended, else empty; side score = full
number up to 9,999, then `10K` / `1.2M` (`formatCount`); spoken = `{name} {score with thousands}`
per side joined by `, `. Labels: `vs`, `final`, `wins`, `draw`, `spoken`, `side`, `thousand`, `million`.
Side colours: the theme's accent and coin colour, each with the theme's own text colour on it (4.5:1 in
both presets); an override pair takes black or white text, whichever contrasts more (an unreadable
colour string counts as white text).

Drawing (every platform the same): a top row, side A | middle | side B (side B mirrored); a side is a
40 px avatar (picture or the name's first letter on the side colour) in a 2 px ring in the side
colour (gold `#ffc83d` for the winner, with a crown above), then the name (13, bold) over the score
(20, extra bold, tabular figures). The loser is drawn at 50 % opacity. The middle is the label `vs`
(10, black weight, letter-spaced, muted) over a pill with the clock (13, bold): open = background
fill with a border; urgent = danger border and text; final = accent fill with the accent text colour.
Under it a 16 px high bar (radius 8, 1 px border): side B colour as the base, side A colour from the
left up to `pct`, and a 4 x 26 px white spark on the boundary. Under that the banner (13, bold,
centred, only when not empty). A screen reader reads one element: `spoken`, then the banner.

Motion (skipped entirely under reduced motion: no slide, count or pulse): the boundary slides to a
new `pct` in 800 ms (ease out cubic); a score counts to its new value in 650 ms (ease out cubic,
shown with the same short form); a side that gained score pulses (scale 1.07 in 200 ms, back in 300
ms) but never on the first frame of a round.

## 19. Gift inbox

Added on 2026-11-02: a list of who sent the signed-in user which gift and when,
over the last 24 hours, one row per gift, newest first. Read only: there is no server-side "read"
state; an app keeps the time of the newest row it showed and asks `inboxUnread` for a badge.
Reference: `packages/sdk-js/src/core/inbox.ts`. Fixture: `conformance/inbox.json`.

### 19.1 Client call and model

- `getInbox({ cursor?, limit? })`: `GET {base}/v1/client/me/inbox`, query `cursor` then `limit`,
  each only when given, values `enc`-encoded. Returns the body (`Inbox`). `limit` 1 to 100
  (server default 20). The next (older) page is `getInbox({ cursor: page.next_cursor })`.

```text
Inbox      user, since, until, data:[InboxItem], has_more:bool, next_cursor?
InboxItem  id, created_at (ISO time), sender? (null = deleted), gift { id, name, price:int,
           icon_url?, animation_url? }, quantity:int, units:int, status: completed | reversed
```

The body never carries the gift's message, metadata or reference.

### 19.2 Pure helpers (fixture-tested)

- `inboxTimeLabel(createdAtMs, nowMs)`: `d = nowMs - createdAtMs`. `d < 60 000` (also negative,
  a clock that went back) → `"now"`; `d < 3 600 000` → `floor(d / 60 000) + "m"`;
  `d < 86 400 000` → `floor(d / 3 600 000) + "h"`; else `floor(d / 86 400 000) + "d"`.
- `inboxRows(items, nowMs, names)`: drops `status = reversed`; keeps the order. Each row:
  `{ id, senderName, giftName, quantity, time, iconUrl, sender }` where `senderName` is
  `"Someone"` for a `null` sender, else `names[sender]`, else the sender id; `time` is
  `inboxTimeLabel(parse(created_at), nowMs)`.
- `inboxUnread(items, lastSeenMs?)`: the number of rows with `status = completed` whose
  `created_at` is strictly later than `lastSeenMs` (all completed rows when it is null).

### 19.3 UI: `GiftInbox`

A list (newest first) of rows: the sender's initial avatar, "**Name** sent you Gift" with "xN"
when the quantity is above 1, the gift icon, and the time label on the right. It loads the first
page itself (`pageSize` default 20), shows "Show more" while `has_more` and appends the next page,
and shows "No gifts in the last 24 hours" when empty and "Could not load gifts" with "Try again"
on an error. `resolveUsers(ids)` (optional, as the away card) turns sender ids into names.
`refresh()` reloads from the first page. `onLoaded(items)` hands the rows to the app (for its own
badge with `inboxUnread`). Follows the theme tokens of section 9 and the accessibility rules of
the leaderboard (each row one element with its full sentence and time).

## Open questions

These are behaviours of the reference that look unintended or are under-specified. The fixtures
pin the CURRENT behaviour; a change needs a decision, a spec version bump and new fixtures.

1. **Notice "slide-in plays again" does not happen while it is visible.** `NoticeData.id`
   changes for a new sender/gift and the comment says the slide-in replays, but the reference
   only animates the slide progress towards 1; when the notice is already fully in, nothing
   visible happens (the content just changes). After a hide, it does slide in again. Platforms:
   copy the code (no replay while visible) until this is decided.
2. **Some failures are not `GiftingError`.** An exception from `getToken` propagates unchanged (a 2xx
   whose body is not JSON became `invalid_response` on 2026-11-03, section 3.5). `GiftTrayController` turns any
   such failure into `status 0, unknown_error`, which then reports `retryable: true` (status 0),
   even for a programming error.
3. **Empty caller key.** `idempotencyKey: ""` is used as given, and an empty key means no
   `Idempotency-Key` header at all; the API then rejects the send (400). Should an empty key be
   replaced by a generated one, or rejected early?
4. **Two different key schemes.** The combo keys on the pair `[sender, giftId]`; the notice keys
   on the string `sender + "|" + giftId`, so `("a|b", "c")` and `("a", "b|c")` share a notice id.
   Cosmetic (the slide-in would not restart).
5. **Balance after a successful send stays optimistic** until the reconcile `getMe`;
   `sender_balance_after` in the response is ignored. `refresh()` overwrites the balance even
   while sends are in flight (the number can jump back briefly), and `loading` never becomes true
   again on later refreshes.
6. **`send()` does not check affordability**; only the tray's button does. Calling `send` directly
   with too little balance shows the effect (tap mode), makes the number negative, then refunds
   on the 422.
7. **Retry policy.** The 5xx retry is immediate (no backoff); 429 is never retried and
   `Retry-After` is ignored; a 401 that arrives on the 5xx retry is not refreshed. (Since 2026-11-03 a
   send also repeats one lost connection, 3.4.)
8. **Dropped large gifts are silent.** The 6th waiting large gift pushes out the oldest waiting
   one with no notice and no `onEffectEnd`; its `play` id becomes a no-op for `cancel`.
9. **Effects wait for the layer's size.** The reference only draws once the layer is measured;
   gifts played before that count against the caps and start when the layer is measured.
10. **Wall clock for combos.** The reference uses `Date.now()`; a clock change can extend or end a
    run. Native platforms are asked (SHOULD) to use a monotonic clock, which can differ from the
    reference only when the wall clock jumps.
11. **Extraction differences (this change, not product behaviour):** the scheduler and tray logic
    moved from the React Native components into `src/core` (`EffectScheduler`,
    `GiftTrayController`, `sendButtonState`). Two tiny differences from the old hook: `send` now
    reads the signed-in user from the latest state instead of the last render, and `send` /
    `refresh` keep the same identity across renders. `started`/`finished` for an effect no longer
    on screen are explicitly ignored (before, the unmounted component simply never called them).

12. **Bottom sheet (new on 2026-10-11).** (a) The tray is now a sheet by default, so an app that
    upgrades sees the tray overlay its parent instead of taking space in the layout; `sheet: false`
    restores the old tray. (b) `onInsetChange` reports the snap target at once, so the notice jumps
    to its new place while the sheet is still animating (about 280 ms). (c) A drag that starts
    while the sheet is still animating starts from the target position, so the sheet can jump by
    the remaining distance. (d) On the web a mouse wheel does not move the sheet, and below fully
    open the grid does not scroll by wheel either. (e) iOS Safari does not support `touch-action:
pan-down`; there the fully open grid at its top is scrolled by hand from pointer events (no
    momentum) instead of natively. None of these are pinned by fixtures.

13. **Web placements (new on 2026-10-11, web only).** (a) `auto` follows only CONTAINER resizes;
    a viewport change that leaves the container width alone keeps the placement. (b) Effects and
    the notice drawing over the popover relies on the page not putting the effect layer in a
    stacking context below `z-index` 999; no overlap is computed. (c) The popover is not modal:
    Tab can leave it without closing it. (d) Arrow keys move one gift at a time (ArrowDown = next,
    not one row down) in every placement, as before. (e) In the `sheet` and `inline` placements a
    click on `anchor` does nothing. (f) The popover lives in `document.body`, not in the
    container: CSS that targets the container's descendants does not reach it.

14. **Components (new on 2026-10-11).** (a) `formatCount` drops a `.0` (`1000 -> "1K"`) and
    groups nothing; locales that write `1,9 B` pass `labels`. (b) `pinnedMe` adds two cases to the
    design's rule (pin when `rank` is null or above `limit`): a tie at the cut also pins, and a
    viewer without a score or hidden is never pinned (a "1,000+" for someone with 0 would
    mislead). (c) `check()` runs from `empty` and `done` too (resting states), not only `idle`, so
    the foreground check works after a first summary. (d) The planner uses the embedded recipe
    durations even when the layer uses a remote recipe set (13); a tuned remote set can make the
    real replay end earlier or later than `budgetMs`. (e) `leaderboard_building` is retried once at
    once like every 5xx (3.4); `Retry-After` is still ignored. (f) The away GET for an empty
    summary is not acknowledged (its cursor is unchanged anyway).

## Platform notes (accepted deviations, 2026-10-10)

The first implementations on each platform made these choices. They keep the behaviour of the
fixtures and are accepted as part of the contract.

- **Naming.** Dart and Kotlin call the error class `GiftingException`; `GiftingError` is an alias.
  Kotlin uses the packages `com.giftingstack.core` and `com.giftingstack.ui` (not
  `com.giftingstack.sdk`).
- **Pure controller plus a state holder.** The pure `GiftTrayController` has no UI import. The
  object the UI observes is a thin wrapper: `GiftTrayNotifier` (Dart, a `ChangeNotifier`),
  `GiftTrayState` (Kotlin, `StateFlow`), `GiftTrayModel` (Swift, `ObservableObject`). The web layer
  uses plain classes; the `<gift-effect-layer>` and `<gift-tray>` custom elements named in section
  2 are not implemented yet (classes only).
- **Swift listener names** differ from the spec (for example not `effectDidEnter`) so they cannot
  clash with the controller's `clear()`.
- **Kotlin:** `GiftTrayController.send` awaits its reconcile `getMe` instead of firing it and
  moving on; the states are the same. A `GiftingApi` interface exists so the tray can take test
  doubles. The zero-wait picture gate needs two frames (compose the effect, then the notice), not
  one; the fixtures allow it.
- **Flutter:** an unattached `GiftEffectController.play` returns 0 and shows nothing. The effect and
  the notice start one frame after `play`, because a cached picture reports synchronously and the
  start is deferred out of the build phase.
- **Errors that are not GiftingErrors** become `unknown_error` with the platform's description as
  the message (Swift) or status 0 (reference); both report `retryable: true`.
- **Reduced motion.** Aligned on 2026-10-11: the web notice now slides and pops under reduced
  motion too, as on React Native (section 7.5).
