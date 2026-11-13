# Conformance fixtures

Every GiftingStack SDK (Web, React Native, Flutter, Android, iOS) runs these JSON files in its
own test framework. A platform conforms to spec version `recipes.json#specVersion` when its runner
passes every case in every file. The reference runner is
`packages/sdk-js/test/conformance.test.ts`; port it, do not reinterpret it.

General rules for all files:

- Fixtures are UTF-8 JSON. Keys you do not recognise (`description`, `note`, `name`) are
  documentation; ignore them.
- "Deep equal" means: same JSON type, same keys, same values. Objects compare without key order.
  Arrays compare in order. `null` and a missing key are different, except where stated.
- Integers in fixtures are exact. No fixture uses floats except `tiers.json` (`99.5`) and the
  snap fractions in `sheet.json`, and `input-swap.json` (`0.6`, `291.6`).
- Steps run in order. A failed check must name the scenario and the 1-based step number.

## tiers.json

```json
{
  "cases": [{ "price": 99, "thresholds": { "mediumFrom": 5 }, "tier": "small" }],
  "recipes": [{ "tier": "large", "quality": "low", "expect": { "sparks": 16 } }]
}
```

- `cases[]`: call `tierFor(price, thresholds)`; `thresholds` may be missing or partial (missing
  fields take the defaults). The result must equal `tier`.
- `recipes[]`: call `recipeFor(tier, quality)`; every key in `expect` must equal the recipe's
  field of the same name. The full recipe table is `../recipes.json`; a platform SHOULD also
  compare its built-in recipes against that file field by field.

## combo.json

```json
{
  "scenarios": [
    { "windowMs": 2000, "steps": [{ "hit": ["ayla", "rose", 0], "count": 1 }, { "reset": true }] }
  ]
}
```

- Create a tracker with `windowMs` (missing: the default, 2500).
- `{ "hit": [sender, giftId, atMs], "count": n }`: `hit(sender, giftId, atMs)` must return `n`.
- `{ "reset": true }`: call `reset()`.

## client.json

One scenario = one client call against a scripted HTTP transport and a scripted token provider.

```json
{
  "name": "...",
  "baseUrl": "https://api.example.test///",
  "call": { "method": "sendGift", "args": { "input": { "receiver": "bob", "giftId": "rose" } } },
  "tokens": [{ "forceRefresh": false, "returns": "tok_1" }],
  "exchanges": [
    {
      "request": {
        "method": "POST",
        "url": "https://api.giftingstack.com/v1/client/gift-transactions",
        "headers": { "Authorization": "Bearer tok_1", "Idempotency-Key": "<any-uuid-like>" },
        "absentHeaders": [],
        "body": { "receiver": "bob", "gift_id": "rose" }
      },
      "response": { "status": 201, "headers": {}, "body": { "id": "gtx_..." } }
    }
  ],
  "result": { "id": "gtx_..." }
}
```

Set-up:

- `baseUrl` missing: construct the client without one (the default base URL applies).
- `tokens`: the exact sequence of token-provider calls. On call k the runner checks that
  `forceRefresh` equals `tokens[k].forceRefresh` and returns `tokens[k].returns`. A call beyond
  the list fails the scenario. After the call under test, all tokens must have been used.
- `exchanges`: the exact sequence of HTTP requests. The transport answers request k with
  `exchanges[k]`. A request beyond the list fails the scenario. After the call, all exchanges must
  have been used (so a missing retry also fails).

The call under test (`call.method`, `call.args`):

| method             | args                 | platform call                  |
| ------------------ | -------------------- | ------------------------------ |
| `getGifts`         | none                 | `getGifts()`                   |
| `getMe`            | none                 | `getMe()`                      |
| `getReceivedGifts` | `{ "user": string }` | `getReceivedGifts(user)`       |
| `sendGift`         | `{ "input": {...} }` | `sendGift(SendGiftInput(...))` |

`input` uses the SDK field names (`receiver`, `giftId`, `quantity`, `message`, `reference`,
`idempotencyKey`). A key missing from `input` means the optional field is not given (`null`/`nil`
in typed languages).

Request matching (each request k):

- `method`: exact, upper case.
- `url`: the full URL, exact string comparison (scheme, host, path, percent-encoding). No query.
- `headers`: every listed header must be present with the given value. Header names compare
  case-insensitively, values case-sensitively. Headers not listed are allowed, except:
- `absentHeaders`: each named header must NOT be sent.
- `body`: `null` means the request has no body (and, for the reference, no `Content-Type`).
  Otherwise the request body must parse as JSON and deep-equal `body`. Omitted optional fields
  must be absent keys, not `null`.

Header value placeholders (only inside `request.headers`):

- `"<any-uuid-like>"`: the value must match `^[0-9A-Fa-f-]{16,255}$` (a UUID in any case, or the
  reference's fallback of four 8-digit hex groups).
- `"<same-as-request:N>"`: the value must equal the value of the same header in request N of this
  scenario (1-based), as actually sent.

Responses:

- `response.status`, `response.headers` (name to value), and the body: `bodyText` (send these
  exact characters, may be empty) if present, else `body` serialised as JSON. A 2xx `bodyText` that
  is not valid JSON must produce `invalid_response` (SPEC 3.5).
- `"networkError": true` instead of `response`: the transport fails as if the host could not be
  reached (throw / return the platform's connection error) after the request was checked.

Outcome:

- `result`: the call must succeed. Convert the returned value back to wire JSON (snake_case
  keys, as the API sent them) and deep-equal it with `result`. `getGifts` and
  `getReceivedGifts` return the `data` array; response fields the SDK model does not have
  (`has_more`) are ignored.
- `error`: the call must fail with the SDK's error type, and its six fields must equal the
  fixture: `status` (0 for network), `type`, `message`, `requestId` (`null` when absent),
  `retryable`, `insufficientBalance`.

## effects.json

### scenarios: the EffectScheduler

Drives the platform's `EffectScheduler` (spec section 6) directly. No rendering, no timers.

- `gifts`: named `GiftEffectEvent.gift` objects. A missing `icon` key means the field is not
  given; `"icon": null` means it is given as null. Both fall back to `image`.
- `options` (optional): `thresholds`, `quality` (default `"high"`), `reducedMotion` (default
  false), `comboWindowMs` (default 2500). Apply them before the first step.
- The runner keeps a virtual clock that starts at 0 and gives it to the scheduler as its `now`.

Steps:

| step                                                                                          | action                                                                                                                                                           |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{ "atMs": t, "play": { "gift": key, "sender"?, "quantity"?, "receiver"? }, "returns"?: id }` | set the clock to `t`, call `play(event)`; it must return `id`. Missing `sender`/`quantity`/`receiver`: not given. `receiver` is `{ name, side?, color? }` (7.4). |
| `{ "started": id }`                                                                           | `started(id)`: the effect's picture is ready                                                                                                                     |
| `{ "finished": id }`                                                                          | `finished(id)`: its animation ran to the end                                                                                                                     |
| `{ "cancel": id }`                                                                            | `cancel(id)`                                                                                                                                                     |
| `{ "clear": true }`                                                                           | `clear()`                                                                                                                                                        |
| `{ "noticeExpired": true }`                                                                   | `noticeExpired()`: the notice timer fired                                                                                                                        |
| `{ "expect": {...} }`                                                                         | check, then empty the event log                                                                                                                                  |

The runner records the listener calls in an event log, as strings: `enter:<id>`, `exit:<id>`,
`end:<id>`, `notice:<notice id>` (the `NoticeData.id`, not the play id), `noticeHide`, `clear`.

`expect` keys (each optional; check only those present):

- `events`: the event log since the previous `expect` (or the start), exact order.
- `active`: ids of effects on screen, in the order they entered. `activeTiers`: their tiers.
- `queued`: ids of waiting large effects, oldest first.
- `ended`: every id passed to `end` so far in this scenario, in order.
- `notice`: the last notice written, deep equal: `{ id, senderName, giftName, image, count, big }`
  plus `receiver: { name, side, color }` (`color` null when none was given) only for a play with a
  receiver, or `null` when none has been written yet. The data stays after the notice hides.
- `noticeVisible`, `noticeOwner` (the play id that wrote the notice; 0 before any),
  `noticeDurationMs` (the duration passed with the most recent `notice` call).

### pictureGate

Rendered timing of one effect, checked at component level (the reference renders its
`GiftEffectLayer` with fake timers and a fake image loader). For each case: an effect enters at
time 0 with a picture (`image: true`) or without one; the picture finishes loading at `loadAtMs`
or fails at `errorAtMs` (`null`: never). The effect, and with it the notice, must start
(`started`) at `startsAtMs`: not before, and no later than `startsAtMs + toleranceMs` (16 ms, one
frame, for decoding and the next render). Platforms check "not started at `startsAtMs - 1`" and
"started at `startsAtMs + toleranceMs`"; a `startsAtMs` of 0 means started right after `play`.

## tray.json

### scenarios: the GiftTrayController

Drives `GiftTrayController` (spec section 8) with a scripted client whose every call stays
pending until a step settles it.

- `gifts`, `transactions`: named API objects (wire JSON).
- `options`: `receiver`, `reference` (missing: not given), `playOn` (missing: default `"tap"`),
  `effects` (`false`: no effect player; otherwise the runner's stub player).
- Stub effect player: `play(event)` returns 1, 2, 3, ... in call order and records
  `{ id, event }` (event as wire-style JSON: `{ gift: { id, name, price, image, icon }, sender,
quantity }`); `cancel(id)` records `id`.
- The runner records: every `prefetch(url)`, every `onSent(tx)` (as `tx.id`), every `onError(e)`
  (as `e.type`), and every client call `{ method, args }` (args with absent fields dropped).

Steps:

| step                                         | action                                                  |
| -------------------------------------------- | ------------------------------------------------------- |
| `{ "mount": true }`                          | the screen opens: start `refresh()` (do not wait)       |
| `{ "refresh": true }`                        | start `refresh()` (do not wait)                         |
| `{ "send": key }`                            | start `send(gifts[key])` (do not wait)                  |
| `{ "dispose": true }`                        | `dispose()`: the screen is gone                         |
| `{ "resolve": { "method": m, "value": v } }` | complete the OLDEST pending call of method `m` with `v` |
| `{ "reject": { "method": m, "error": e } }`  | fail the OLDEST pending call of method `m`              |
| `{ "expect": {...} }`                        | check                                                   |

- `resolve` values: for `getGifts` a list of keys into `gifts` (the server's order); for
  `sendGift` a key into `transactions`; otherwise the literal JSON (`getMe`: `{ user, balance }`).
- `reject` errors: `{ status, type, message, requestId }` is the SDK error type with those fields;
  `{ "plain": "boom" }` is any other exception whose message is `boom`.
- After EVERY step the runner lets all pending asynchronous work run until nothing more can run
  (microtasks, coroutines, futures), without advancing any clock. Only then the next step.

`expect` keys (each optional):

- `balance`, `user`, `loading`, `testMode`: exact. `gifts`: ids of the state's gift list, in order.
- `error`: `null`, or the listed fields of the state's error (subset match).
- `played`: deep equal list of `{ id, event }`. `playedCount`: its length. `cancelled`: ids.
- `sent`, `errors`, `prefetched`: the recorded lists, exact.
- `pending`: methods of the calls still pending, in call order.
- `lastCall`: the most recent client call `{ method, args }`. `callCount`: calls per method so far.

### sendButton

`sendButtonState(input)` must deep-equal `expect`. `input.gifts` holds only `id` and `price`;
`selectedId: null` means none chosen.

## sheet.json

Drives the pure `TraySheetController` and `resolveSheetHeights` (spec section 9.1). No rendering,
no clock: velocities are given, not measured.

```json
{
  "layouts": {
    "phone": {
      "containerHeight": 800,
      "peekMinHeight": 150,
      "defaultMinHeight": 330,
      "contentHeight": 900
    }
  },
  "heights": [
    { "layout": { "containerHeight": 800 }, "expect": { "peek": 0, "default": 0, "expanded": 720 } }
  ],
  "scenarios": [
    {
      "layout": "phone",
      "initialSnap": "peek",
      "steps": [{ "drag": -20 }, { "release": -2000, "returns": "default" }]
    }
  ]
}
```

- A layout object has `containerHeight` and optionally `snaps` (`{ peek?, default?, expanded? }`,
  fractions; a `null` value means "not given"), `peekMinHeight`, `defaultMinHeight`,
  `contentHeight`. Missing keys are not given.
- `heights[]`: `resolveSheetHeights(layout)` must deep-equal `expect`.
- `scenarios[]`: create the controller with `layout` (a key into `layouts`, or an inline layout
  object), `initialSnap` (missing: not given, so `"default"`) and an `onSnapChange` that records
  every call. Then run the steps.

Steps (`returns`, when present, is checked against the call's return value):

| step                                                                   | action                                                             |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `{ "dragStart": true }`                                                | `dragStart()`                                                      |
| `{ "drag": dy }`                                                       | `drag(dy)` (positive = finger down)                                |
| `{ "release": v, "returns": snap }`                                    | `release(v)`, `v` in px/s, positive = down                         |
| `{ "cancel": true }`                                                   | `cancel()`                                                         |
| `{ "snapTo": snap }`                                                   | `snapTo(snap)`                                                     |
| `{ "toggle": true, "returns": snap }`                                  | `toggle()`                                                         |
| `{ "step": 1 \| -1, "returns": snap }`                                 | `step(direction)`                                                  |
| `{ "layout": key-or-object }`                                          | `setLayout(layout)`                                                |
| `{ "scrollOwner": { "dy": n, "gridScrollTop": n }, "returns": owner }` | `scrollOwner(dy, gridScrollTop)` must return `"sheet"` or `"grid"` |
| `{ "expect": {...} }`                                                  | check                                                              |

`expect` keys (each optional): `snap`, `offset`, `visibleHeight`, `dragging`, `gridScrollable`
(exact), `heights` (deep equal), `snapChanges` (every `onSnapChange` argument since the scenario
began, in order). All numbers in this file are integers and exact.

## tray-scrim.json

The dim behind the sheet and the open state (spec section 9.4). Pure functions and
`TrayOpenState`; no rendering, no clock.

```json
{
  "constants": { "fadeMs": 200, "opacity": 0.4 },
  "visible": [{ "scrim": true, "open": true, "snap": "default", "placed": true, "expect": true }],
  "fade": [{ "reducedMotion": true, "ms": 0 }],
  "tap": [
    { "scrim": true, "scrimTap": "dismiss", "open": true, "snap": "peek", "expect": "dismiss" }
  ],
  "open": [
    {
      "name": "...",
      "open": false,
      "steps": [
        { "call": "toggle", "returns": true },
        { "expect": { "open": true, "changes": [true] } }
      ]
    }
  ]
}
```

- `constants`: `SCRIM_FADE_MS` and `SCRIM_OPACITY` must equal them.
- `visible[]`: `scrimVisible({ scrim, open, snap, placed })` must equal `expect` (all 24
  combinations of the four inputs, `snap` is `"peek"`, `"default"` or `"expanded"`).
- `takesTouches[]`: `scrimTakesTouches({ scrim, open, placed })` must equal `expect` (all 8
  combinations; the snap does not matter: a peeking sheet still takes the tap).
- `fade[]`: `scrimFadeMs(reducedMotion)` must equal `ms`.
- `tap[]`: `scrimTapOutcome({ scrim, scrimTap, open, snap })` must equal `expect` (`"ignored"`,
  `"lower"` or `"dismiss"`). `scrimTap` may be missing: the default `"lower"`.
- `open[]`: a `TrayOpenState` created with `open` (missing: `true`) and an `onChange` that
  records each value. Steps in order: `{ "call": "open" | "close" | "toggle", "returns": bool }`
  checks the returned new state; `{ "expect": { "open", "changes" } }` checks `isOpen` and that
  the recorded changes equal the list (a call that changes nothing records nothing).

## input-swap.json

The gift button in the app's message bar (spec section 20). Pure functions; no rendering.

- `constants`: `KEYBOARD_PLACE_FALLBACK`, `KEYBOARD_MIN_HEIGHT` and `KEYBOARD_PLACE_MAX_FRACTION`
  must equal `fallback`, `minKeyboard` and `maxFraction`.
- `step[]`: `inputSwapStep(open, event)` must deep-equal `expect` (`{ tray, input }`).
- `place[]`: `keyboardPlaceHeight({ keyboardHeight, containerHeight })` must equal `expect`.
  `null` means the value is unknown (Dart, Kotlin and Swift: `null`/`nil`). `291.6` is a float.
- `sequence[]`: start with `open`; for each step call `inputSwapStep(open, event)`, check
  `expect`, then apply it (`tray: "open"` sets open, `"close"` clears it, `"keep"` keeps it) and
  check `open`.

## receivers.json

The receiver picker of a battle tray (spec section 21). One pure function.

- `resolve[]`: `resolveReceiver(ids, { selected, last, fallback })` must equal `expect` (an id or
  `null`). `selected`, `last` and `fallback` may be missing (= not given).

## placement.json

Web only (spec section 9.3); native platforms skip this file. Pure functions, no rendering.

- `resolve[]`: `resolveTrayPlacement(input)` must equal `expect` (`"sheet"`, `"popover"` or
  `"inline"`). `input.placement` may be missing or an unknown string (both mean `"auto"`);
  `containerWidth` may be `null` (not a number: counts as 0).
- `popover[]`: `positionPopover(input)` with the default gap 8, margin 8 and height fraction 0.7
  must deep-equal `expect` (`left`, `top`, `width`, `maxHeight`, `height`, `side`, `align`). All
  numbers are integers and exact.

## theme.json

Theming (spec section 9.2). Only the contrast rule is pinned, not the colours.

- `contrast[]`: `contrastRatio(a, b)` rounded to two decimals (half up) must equal `ratio`.
  Colours are `#rgb` or `#rrggbb`, any case.
- `rules[]`: token pairs `{ fg, bg, min }`: `contrastRatio(theme[fg], theme[bg]) >= min`.
- `presets`: the named built-in themes (`darkTheme`, `lightTheme`) must meet every rule.
- `accents[]` x `modes`: `themeFromAccent(accent, mode)` must meet every rule, and its
  `accent` must equal `normalized`.
- `invalid`: `themeFromAccent(value, "dark")` must fail (throw / return the platform's error).

## remote-recipes.json

Remote recipes (spec section 13). Pure functions only; the loader (network, cache, backoff) is
checked by each platform's own tests. "The embedded set" is `{ thresholds, comboWindowMs, recipes }`
of `../recipes.json`.

- `parse[]`: call `parseRemoteRecipes(input)`. `input` is any JSON value; the string
  `"@embedded"` stands for the whole of `../recipes.json`.
  - `"expect": null`: the document must be ignored (null / nil / the platform's "none").
  - otherwise `expect` is a PATCH: lay it over the embedded set key by key (objects merge
    recursively, any other value replaces), add `specVersion` = the input's `specVersion`, and
    the result must deep-equal that. `{}` means "exactly the embedded set". The result has no
    other keys (no caps, no queue size, no sender name).
  - Numbers: `peakScale` values are compared as doubles (they are exact in binary or come straight
    from the input); every other number is an integer after rounding and compares exactly.
- `merge[]`: parse `remote` first (`null`: no remote set; a document that parses to null is
  also "no remote set"), then `mergeRecipeSet(embedded, remote, app)`. `app` may hold
  `thresholds` (partial) and `comboWindowMs`. The result must deep-equal `expect`, where
  `"recipes": "embedded"` means the embedded recipe tables and `"remote"` the parsed remote's.
- `urls[]`: `remoteRecipesUrl(url, version)`; a missing key means not given. `expect` is the URL
  string, or `null`: remote recipes are off (no request).

Platforms SHOULD also check that their limits table equals SPEC.md 13.3 and that every embedded
number lies inside it.

## Component fixtures: wall.json, away.json, leaderboard.json

Pure logic of the three components (SPEC sections 14-16). Reference runner:
`packages/sdk-js/test/components-conformance.test.ts`. Platforms that have not ported the
components yet acknowledge these three files in their fixture coverage test ("components pending
native port"); a port adds a runner and removes them from that list.

Shared rules for the three files:

- **`client` sections** use exactly the scenario format of `client.json`, with these calls
  added to its table: `getReceivedGifts` `{ user, reference? }`, `queryGiftWalls` `{ items }`,
  `getAway` `{ query? }` (`query` uses the SDK names `since`, `maxGroups`), `ackAway`
  `{ cursor }`, `getLeaderboard` `{ board, query? }` (`period`, `metric`, `at`, `limit`,
  `includeMe`). A missing key is "not given". Here `request.url` INCLUDES the query string and is
  compared as an exact string (order of parameters, percent-encoding). A call that returns
  nothing (`ackAway`) has `"result": null`. A `204` response has no body (`bodyText: ""`): build
  the response without one.
- **`client` response bodies are exactly what the API sends** (the API's response schemas, SPEC
  14-16): full objects, every field, no `"gift": "<id>"` shorthand, also in `result`. A typed
  client parses them as they are, with nothing rewritten. The gift-id shorthand is allowed ONLY in
  these pure-logic sections: `wall.json` `chips`, `loader` (`respond.walls`, `resolved`) and
  `away.json` `plan[].groups` and `summaries` (which the controller steps resolve). The reference
  runner (`packages/sdk-js/test/client-runner.ts`) checks every 2xx `body` and `result` of every
  client scenario against the typed models and fails on a missing, extra or mistyped field.
- **Fake clock.** Controllers and the loader get the runner's clock (`now`, starts at 0) and timer
  functions. `{ "advance": ms }` moves the clock forward by `ms`; every timer due at or before
  the new time fires, earliest first (equal due times: the order they were set), with the clock set
  to that timer's due time while it runs. After EVERY step the runner lets pending asynchronous
  work run (as in `tray.json`), then fires the timers due at the current time (a timer of 0 ms set
  during a step fires right after that step), and repeats this until nothing changes.
- **Scripted client** (controllers): every client call is recorded as `{ method, args }` and stays
  pending until a step settles it, exactly as in `tray.json`. `{ "resolve": { "method", "value" } }`
  completes the OLDEST pending call of that method; `{ "reject": { "method", "error" } }` fails it
  with the SDK error type built from `{ status, type, message, requestId? }`.
- `expect` keys are each optional; check only those present.

## wall.json

- `gifts`: named `ReceivedGift.gift` objects (`{ id, name, icon_url }`). In `chips` and `loader` a
  received gift is written `{ "gift": "<id>", "count": n }`; build the wire object from
  `gifts[id]`. The `client` section writes full objects.
- `chips[]`: `wallChips(items, options)` (`options` may be missing or partial). Compare the chips
  written as `{ "gift": "<id>", "count": n }` or `{ "overflow": count, "hidden": kinds }`, in order.
- `formatCount[]`: `formatCount(n, labels)` must equal `expect` (`labels` may be missing).
- `loader[]`: a `GiftWallLoader` with the fake clock, `windowMs`/`batchSize`/`ttlMs` defaults, and
  a scripted `query` that records each call's items (wire JSON, a missing reference left out) as
  a "batch" and stays pending.

| step                                          | action                                                                                                         |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `{ "load": [user, reference?], "id": name }`  | `load(user, reference)` and remember its promise as `name`                                                     |
| `{ "advance": ms }`                           | move the clock (see above)                                                                                     |
| `{ "respond": { "batch": n, "walls": [...] }` | answer batch `n` (1-based, in send order): wall `k` of the answer = `{ receiver, reference, gifts: walls[k] }` |
| `{ "fail": { "batch": n, "error": e } }`      | fail batch `n` with the SDK error built from `e`                                                               |
| `{ "invalidate": [user, reference?] }`        | `invalidate(user, reference)`                                                                                  |

`expect`: `batches` (every batch sent so far, each its list of items, exact), `waiting` (the
names of promises not settled yet, in the order they were created, exact), `resolved` (for each
listed name: settled with this list of received gifts), `rejected` (for each listed name: failed
with this error `type`).

## away.json

- `gifts`: named away gift objects `{ id, name, price, icon_url, animation_url }`. In `plan` and
  `summaries` groups are written with `"gift": "<id>"`; build the wire group from `gifts[id]`.
  The `client` section writes full gift objects.
- `plan[]`: `planAwayReplay(groups, options)` with `resolveName(id) = names[id] ?? id` (`names`
  may be missing). `endMs` must equal; `items` must have the same length, and each listed key of an
  expected item must equal the actual item projected as `{ gift: event.gift.id, name, price,
image, icon, atMs, durationMs, tier, quantity: event.quantity, sender: event.sender }`.
- `senderLabel[]`: `awaySenderLabel(names, senderCount, labels)` must equal `expect`.
- `summaries`: named `AwaySummary` bodies (groups written as above).
- `controller[]`: an `AwayController` with the fake clock and timers, a scripted client
  (`getAway` recorded with args = the query object, `{}` when none; `ackAway` with
  `{ cursor }`), and a stub effect player whose `play(event)` records
  `{ atMs: clock now, gift: event.gift.id, quantity, sender }`. `options`: `ackOn`, `maxGroups`,
  `maxEffects`, `budgetMs` (missing: not given), `effects: false` (no player), `reducedMotion:
true` (`reducedMotion()` returns true). The runner counts `onShow` and `onDone` calls and
  records `onError` error types.

| step                                           | action                                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------------------- |
| `{ "check": true }` / `{ "foreground": true }` | start `check()` / `foreground()` (do not wait)                                         |
| `{ "start": true }` / `{ "dismiss": true }`    | `start()` (the card is on screen) / `dismiss()`                                        |
| `{ "ack": true }` / `{ "dispose": true }`      | start `ack()` / `dispose()`                                                            |
| `{ "advance": ms }`                            | move the clock                                                                         |
| `{ "resolve": ... }` / `{ "reject": ... }`     | settle a call; `getAway` values are keys into `summaries`, `ackAway` values are `null` |

`expect`: `status`, `summaryCursor` (`summary.cursor`, `null` without a summary), `planEndMs`
(`plan.endMs`), `played` (exact list), `calls` (every client call so far, exact), `pending`
(methods of the calls still pending, in call order), `shown`, `done` (counts), `errors` (exact).

## leaderboard.json

- `rankLabel[]`: `leaderboardRankLabel(rank, labels)` must equal `expect`.
- `pin[]`: build a `Leaderboard` with `metric`, `data` and `me` (other fields do not matter);
  `pinnedMe(board, limit)` must be non-null exactly when `expect` is true, and then equal `me`.
- `rankColors`: the platform's medal tokens must equal `tokens`, and each token must reach
  `contrastRatio(token, theme[text]) >= min` for every theme named in `themes`.
- `boards`: named `Leaderboard` bodies.
- `controller[]`: a `LeaderboardController` with the fake clock and a scripted client
  (`getLeaderboard` recorded with args `{ board, query }`, `query` as the SDK sends it).
  `options` (missing keys: not given): `board`, `periods`, `initialPeriod`, `metric`, `limit`,
  `includeMe`. Steps: `start`, `setPeriod: p`, `setMetric: m`, `refresh`, `dispose`, `advance`,
  `resolve` (value = a key into `boards`), `reject`.
- `expect`: `status`, `period`, `periods`, `metric`, `rows` (users of `data.data` in order, `null`
  without data), `asOf` (`data.as_of`, `null` without data), `refreshing`, `error` (its `type`
  or `null`), `pinned` (its `user` or `null`), `calls` (exact), `pending` (number of pending
  calls), `errors` (`onError` types, exact).

## Battle scores: rooms-battle.json

Battle scores (SPEC 17.8, 18.6), run by every SDK (TypeScript, Flutter, Android, iOS).
`parse[]`: as rooms-protocol.json (`frame` sent as its JSON text; the expected `scores` frame is
`{ t: "scores", battle }`). `view[]`: `battleView(battle, serverNow)` deep-equals `expect`
(`share` values are exact binary fractions; `serverNow: null` reads as the round's start).

## Battle bar: battle-bar.json

The drawn battle bar (SPEC 18.7), run by every SDK. `score[]`: `formatBattleScore(units, labels)`
equals `expect`. `clock[]`: `formatBattleClock(remainingMs)`. `model[]`: build `battleView(battle,
serverNow)`, then the bar model with `nameOf(id) = names[id] ?? id` and `labels`; `expect: null`
means no model (fewer than two sides); otherwise every key given in `expect` must equal the model
field (`pct` within 1e-6; `sides[i]` compares only the keys given). `gains[]`: `battleGains(before,
after)`. `colors[]`: `battleSideColors(theme, override)` with `theme` the `dark`, `light` or
`default` preset (`override` missing: the theme's accent and coin pair); deep-equal `expect`. `palette[]`: `battleSidePalette(theme, count, override)` (`override` an optional list of colour
strings, shorter or longer than `count`) deep-equals `expect`, a list of `{ color, text }`. A model
`expect` may also give `pcts` (every part within 1e-6, summing to 100); when it gives `sides`, the model
must have exactly that many.

## Rooms fixtures: rooms-protocol, rooms-reconnect, rooms-filter, rooms-mapping, rooms-session

The client side of gift rooms (SPEC sections 17-18). Reference runner:
`packages/sdk-js/test/rooms-conformance.test.ts`. Platforms that have not ported rooms yet
acknowledge these five files in their fixture coverage test ("rooms pending native port"). Frames
written as JSON objects are sent as their JSON text; `text` (protocol) or a string `receive`
(session) is sent exactly as written. Parsed messages compare in the wire names of SPEC 17.4,
with `receiver: null` when it is missing.

Which rooms a token may use is a server rule (SPEC 17.2: deny by default, a token needs `rooms`)
and is not pinned here: these fixtures cover the client only. Their 4003 `room_forbidden` cases
stand for both a token without `rooms` and one whose `rooms` exclude the room; the client
reaction is the same (closed, no retry). The client never reads a token's `r` claim, so no
fixture value depends on it.

**rooms-protocol.json.** `parse[]`: `parseRoomFrame(frame or text)` deep-equals `expect` (`null`:
ignored). `hello[]`: the JSON of `roomHelloFrame(last)` deep-equals `expect`. `url[]`:
`roomUrl(room, baseUrl)` equals `expect` (`baseUrl` missing: the default). `tokenUser[]`:
`roomTokenUser(token)` equals `expect`.

**rooms-reconnect.json.** `cases[]`: `roomRetryDecision({ code, reason, attempt, limited },
random)` deep-equals `expect` (for `retry: false` the keys `resumable` and `exhausted` are part of
the comparison: a final close is exactly `{ "retry": false }`); `random()` returns `random` and may
be called at most once; a case without `random` fails if it is called.

**rooms-filter.json.** `events`: named gift messages. Each scenario builds a `RoomEventFilter`
with `options` and runs its steps; `at` is the local clock of the step:

| step                                              | action                                                                                                                                                                                                   |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{ "welcome": { ..., "replay": [names] }, "at" }` | `welcome(message, at)`, the replay resolved from `events`                                                                                                                                                |
| `{ "live": [names], "at" }`                       | `live(gifts, at)`                                                                                                                                                                                        |
| `{ "batch": [names], "at" }`                      | the JSON text of `{"t":"batch","events":[gifts]}` through `parseRoomFrame`, then `live(its events, at)`                                                                                                  |
| `{ "fill": n, "at" }`                             | `live` with `n` generated gifts: for the k-th fill gift of the scenario (1-based) `id` 1000 + k, `tx` `gtx_fill_<k>`, `at` = step `at` + (last welcome `now` - its `at`), rose price 10, sender `filler` |

`expect` (each key optional): `passed` (`tx` of the gifts the step let through, in order), `last`,
`gap` (of this step's result).

**rooms-mapping.json.** `cases[]`: `roomGiftToEffect(event, { catalog, resolveName, replayed, battle, sideColors })` (`sideColors`: a list of any length; `battle` any number of sides)
deep-equals `expect` (a missing `sender` or `receiver` key means absent). `battle` (optional) is a
`RoomBattle` `{ round, started, ends, scores: [{ id, units, gifts }] }`; `sideColors` (optional) a
pair of colour strings; both missing: not given. `catalog: true` passes the file's
`catalog`; `names` given: `resolveName(id) = names[id]` (missing = nothing); `replayed` missing:
not given.

**rooms-session.json.** Each scenario builds a `RoomClient` with `options` (`room`, `user`,
`skipOwn`, `heartbeatMs`, `refreshJitterMs`: default 0), the fake clock and timers of the component fixtures (settle after every
step the same way), a scripted random source (`random` list consumed in order, a call beyond it
fails; no list: always 0.5), a scripted `getToken` (every call recorded as its `forceRefresh` and
left pending) and a scripted socket factory (every socket recorded as `{ url, protocols, sent,
closed }`; `sent` holds each frame parsed as JSON, or the text when it is not JSON (`"ping"`);
`closed` is `{ code, reason }` of the client's own `close`, else `null`). `onEvent`, `onViewers`
and `onGap` are recorded.

| step                                                    | action                                                         |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| `start` / `leave` / `pause` / `resume` / `reconnectNow` | call it (`reconnectNow` also restarts a resumable `closed`)    |
| `{ "token": "<string>" }` / `{ "tokenFail": true }`     | resolve / fail the OLDEST pending `getToken`                   |
| `{ "open": true }`                                      | the NEWEST socket reports open                                 |
| `{ "receive": frame }`                                  | the newest socket delivers the frame                           |
| `{ "close": { "code", "reason" } }`                     | the newest socket reports a close (even one the client closed) |
| `{ "advance": ms }`                                     | move the clock                                                 |

`expect` (each key optional): `state` (each listed key of the state equals), `tokens` (every
`forceRefresh` so far, exact), `sockets` (exactly this many sockets; per socket, each listed key
equals), `events` (every event so far as `{ tx, sender (null when absent), replayed }`, exact;
plus `quantity` for the entries that list it),
`viewers` (every `onViewers` value so far), `gaps` (`onGap` count).

## pictures.json

Which picture URLs are drawn and how long a failed picture is remembered (SPEC 7.6).

- `maxBytes`, `failureMemoryMs`: the platform's constants must equal them.
- `urls[]`: `isPictureUrl(url)` must equal `allowed`. (A URL without a scheme is not listed: the web
  allows it, native SDKs refuse it.)
- `dataUrlSize.cases[]`: build `"data:image/png;base64," + "A" x n` so the whole URL has
  `totalChars` characters; `isPictureUrl` must equal `allowed`.
- `failures[]`: a `PictureFailures` memory driven by an explicit clock (`atMs`); `{ "fail": url }`
  marks it failed at `atMs`; `{ "failMany": { "prefix", "count" } }` marks `prefix + 0 .. count-1`;
  `{ "failed": { url: bool } }` checks `has(url)` at `atMs`.

## Mutation evidence (reference)

To show the fixtures bite, these rules were broken one at a time in the reference code; each
broken build failed the listed fixtures and passed again once restored. See `SPEC.md`, section
"Mutation evidence".
