# @giftingstack/sdk

A gift tray, gift effects, a gift wall, an inbox, a leaderboard and live gift rooms for apps that
use GiftingStack, for the web, React Native and Expo.

```bash
npm install @giftingstack/sdk
```

React Native and Expo need `react` 19.1 or newer and `react-native` 0.80 or newer (both are optional
peers: the web and core entry points need neither).

- `@giftingstack/sdk`: effect recipes, combo counter and a small API client. No framework needed.
- `@giftingstack/sdk/web`: `GiftEffectLayer`, `GiftTray` and `createGiftTray` for the browser, no framework.
- `@giftingstack/sdk/react-native`: `GiftEffectLayer`, `GiftTray` and `useGiftTray` for React Native and Expo.

## API or SDK?

The API runs on your server, the SDK runs in your app. They are two ends of one system.

|      | API (secret key)                                                                                    | SDK (client token)                                                                                  |
| ---- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Runs | on your server                                                                                      | in your app                                                                                         |
| Does | credit and debit coins, reverse gifts, manage gifts and users, receive webhooks, mint client tokens | show the tray and balance, send a gift as the signed-in user, show received gifts, play the effects |

```text
1. The user buys coins   your server confirms the payment, then POST /v1/users/{id}/credit
2. The app opens         your server calls POST /v1/client-tokens (secret key) and gives the
                         app the token (gs_ct_…, one hour by default)
3. Tray, send, effects   the SDK works with that token
4. A gift is sent        your server gets a gift.sent webhook
```

The secret API key never goes into the app. A client token belongs to one user: it reads the
catalog and that user's own balance, and sends gifts **as that user**. It cannot credit coins.

You can skip the SDK if a server sends the gifts or you draw your own screens: the API does
everything the SDK does. You always sell coins and call `credit` yourself.

## React Native

```tsx
import { useRef, useState } from "react";
import { createGiftingClient } from "@giftingstack/sdk";
import {
  GiftEffectLayer,
  GiftTray,
  useGiftTray,
  type GiftEffectLayerHandle,
} from "@giftingstack/sdk/react-native";

const client = createGiftingClient({
  // Ask YOUR server for a token. It calls POST /v1/client-tokens with the secret key.
  getToken: async ({ forceRefresh }) => (await fetch("https://your.app/api/gift-token")).text(),
});

function PostScreen({ post }) {
  const effects = useRef<GiftEffectLayerHandle>(null);
  const tray = useGiftTray({ client, receiver: post.authorId, effects, reference: post.id });
  const [inset, setInset] = useState(300);

  return (
    <View style={{ flex: 1 }}>
      {/* ...your post... */}
      {/* A bottom sheet over the screen. Drag it up for more gifts, down for more of the post. */}
      <GiftTray
        tray={tray} // gifts, balance, send and the "Test mode" badge (a test key) come from the hook
        onTopUp={openCoinStore}
        onInsetChange={setInset}
      />
      {/* One layer over the screen. It never blocks touches. The notice sits above the sheet. */}
      <GiftEffectLayer ref={effects} noticeBottom={inset + 16} />
    </View>
  );
}
```

### The tray is a bottom sheet

`GiftTray` fills its parent and sits at the bottom as a sheet with three states: **peek** (handle,
title, balance and the Send bar with the selected gift; the screen is almost free), **default** (two
rows of gifts, the old tray) and **expanded** (up to 90 % of the screen, the gifts scroll). Drag the
handle or the header, flick (600 px/s moves one state), or tap the handle (default and peek). When it
is fully open and the gifts are scrolled to the top, pulling the gifts down closes it.

| prop                    | default     | what                                                                    |
| ----------------------- | ----------- | ----------------------------------------------------------------------- |
| `sheet`                 | `true`      | `false`: the old fixed tray in the normal layout (uses `gridMaxHeight`) |
| `initialSnap`           | `"default"` | `"peek"`, `"default"` or `"expanded"`                                   |
| `snaps`                 | fit content | heights as fractions of the screen, e.g. `{ expanded: 0.6 }`            |
| `onSnapChange(snap)`    |             | after a release, tap or accessibility action                            |
| `onInsetChange(height)` |             | the sheet's top edge from the bottom: use it for `noticeBottom`         |
| `bottomInset`           | 0           | safe area under the Send button (`useSafeAreaInsets().bottom`)          |

#### Scrim, outside tap and the Gift button

Three options, all off by default, so an existing app does not change:

| prop / method   | default   | what                                                                                                                                                            |
| --------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scrim`         | `false`   | a dim behind the sheet over the whole screen: fades in over 200 ms (at once with reduced motion), is hidden while the sheet is at peek, takes the taps above it |
| `scrimTap`      | `"lower"` | what a tap on the dim does: `"lower"` lowers the sheet to peek (from peek it dismisses), `"dismiss"` closes the tray from every state                           |
| `onDismiss()`   |           | a tap on the dim asked to close; with `tray` it is already closed when this runs                                                                                |
| `tray.toggle()` |           | open if closed, close if open: your Gift button is one line. Also `tray.open()`, `tray.close()`, `tray.isOpen`; `useGiftTray({ open: false })` starts closed    |

```tsx
const tray = useGiftTray({ client, receiver: post.authorId, open: false });
// <Pressable onPress={tray.toggle}><Text>Gift</Text></Pressable>
<GiftTray tray={tray} scrim scrimTap="dismiss" collapseOnSelect />;
```

While the tray is closed the sheet and the dim are invisible and take no touches, `onInsetChange`
says `0`, and opening shows the sheet again at `initialSnap`. Pass `open` to `GiftTray` yourself
to own the state (the dim then only calls `onDismiss`). The rules are SPEC 9.4.

Pass the hook's result as `tray`: the tray takes `gifts`, `balance`, `onSend` and the **Test mode**
badge from it. The badge shows by itself while the token was made with a test key (the server
answers `livemode: false`); `testMode={false}` forces it off, `testMode` forces it on. You can still
pass `gifts`, `balance` and `onSend` yourself; they win over `tray`.

Render it as a direct child of the screen's root view (it is absolutely positioned and lets touches
above it through). The snapping logic is the pure `TraySheetController` from the core.

The gift shows the moment the person taps (the send runs in the background) and is taken back if the
send fails. Pass `playOn: "success"` to `useGiftTray` to wait for the server first instead. Tap Send
again and again for a combo ("x2, x3…"). To show a gift someone else sent you, call
`effects.current?.play({ gift, sender })` when your own event arrives (push, socket or webhook).

### What it does

| Price (default) | Effect                                                                    |
| --------------- | ------------------------------------------------------------------------- |
| under 100       | the gift floats up, a notice slides in from the left with a combo counter |
| 100 to 9,999    | the gift flies to the middle and bursts into sparks                       |
| 10,000 and up   | the screen dims, light rays and a glow, coin rain, a golden notice        |

- Change the price limits with `thresholds={{ mediumFrom, largeFrom }}`.
- Large gifts play one at a time (up to five wait their turn). Small and medium ones overlap, with a cap.
- `quality="low"` for slow phones: fewer sparks, no coin rain, no rays.
- Follows the phone's "reduce motion" setting: then only the notice shows.
- Colors: pass `theme` to `GiftEffectLayer` and `GiftTray`: `darkTheme`, `lightTheme`, or
  `themeFromAccent("#ff4f9a", "light")` to build a readable theme (4.5:1 text contrast) from your brand colour.

### Gift wall, while you were away and leaderboard (React Native)

Three more components with the same `client`, `theme` and `labels` conventions as the tray.
Every word they show or speak is in `labels` (any subset; the rest stays English).

```tsx
import {
  GiftAwaySummary,
  GiftEffectLayer,
  GiftLeaderboard,
  GiftWall,
} from "@giftingstack/sdk/react-native";

// Under a post (or a profile, without `reference`). Walls on one screen share one request.
<GiftWall client={client} user={post.authorId} reference={post.id} refreshKey={giftsSent}
  onPressChip={() => openGiftTray(post)} />

// Once, at the top of your screen, next to the effect layer you already have.
<GiftAwaySummary client={client} effects={effects} resolveUsers={lookUpNames} />
<GiftEffectLayer ref={effects} />

// A screen of its own: put it in your ScrollView.
<GiftLeaderboard client={client} board="senders" metricToggle limit={20}
  resolveUsers={lookUpNames} onPressUser={openProfile} />
```

- **`GiftWall`**: `client`, `user`, `reference?`, `max` (6, the "+37" overflow chip counts),
  `order` (`"count"` or `"catalog"`), `size` (`"md"` or `"sm"`), `data?` (no request), `refreshKey?`,
  `onPressChip?`, `renderChip?` (see "Render slots"), `onError?`, `reducedMotion?`, `theme`, `labels`. It draws nothing when there is
  nothing to show or the request failed (a wall never shows an error; `onError` hears it). Chips are
  buttons (44 dp touch target) only with `onPressChip`; otherwise the row is one labelled element
  ("Gifts: 12 Roses, 3 Hearts, and 37 more"). Requests made within 50 ms share one call, an answer
  is kept for 60 s.
- **`GiftAwaySummary`**: `client`, `effects?` (the ref of your `GiftEffectLayer`; none = card only),
  `resolveUsers?(ids)` (the card waits for it at most 1.5 s), `autoCheck` (true: checks on mount and
  when the app returns to the foreground, once a minute at most), `ackOn` (`"shown"`, `"finished"`,
  `"manual"`), `minGifts` (1: fewer gifts show no card but are still acknowledged), `maxEffects` (5), `budgetMs` (8000), `thresholds`, `quality`, `focusOnShow`, `onShow`,
  `onDone`, `onError`, `reducedMotion?`, `theme`, `labels`. A ref gives `check()`, `ack()`,
  `dismiss()`. Nothing new or any failure draws nothing. The card is not modal: it shows, replays
  the biggest gift groups through your effect layer (biggest last, all within the budget), and
  goes after a tap or `max(4 s, replay + 1.5 s)`. With reduced motion, or without `effects`, only
  the card shows and it is announced to screen readers.
- **`GiftLeaderboard`**: `client`, `board`, `periods`, `initialPeriod`, `metric`, `metricToggle`,
  `limit` (10), `resolveUsers?`, `highlightUser?` (default: you), `refreshIntervalMs` (0: no polling),
  `onPressUser?`, `renderRow?`, `onError?`, `reducedMotion?`, `theme`, `labels`, `coinName`. A ref gives
  `refresh()`. Tabs are a `tablist`; ranks 1 to 3 sit on medal discs; your own row is highlighted, or
  pinned underneath ("You: #417", "You: 1,000+") when you are not in the rows. Loading shows `limit`
  skeleton rows; empty shows a message per period; an error shows a message and "Try again". A tab
  seen less than 30 s ago shows at once; older ones show their rows while they refresh.
- Hooks, when you draw your own: `useGiftWall`, `useGiftAway`, `useGiftLeaderboard`. The logic is
  in the shared core (`wallChips`, `planAwayReplay`, `AwayController`, `LeaderboardController`).
- Not tested on a real phone yet: the tests run on react-native-web.

## Web (browser)

Framework-free TypeScript: plain classes, no React. It reuses the core, so it plays exactly the same
effects (same timings, caps, queue, combo and notice) as React Native.

```ts
import { createGiftingClient } from "@giftingstack/sdk";
import { GiftEffectLayer, createGiftTray } from "@giftingstack/sdk/web";

const client = createGiftingClient({
  getToken: async ({ forceRefresh }) => (await fetch("/api/gift-token")).text(),
});

// One layer over the area where gifts should fly. It never takes clicks.
const screen = document.querySelector("#screen")!;
const effects = new GiftEffectLayer(screen);

// The tray: loads gifts and balance, sends, keeps the balance right, plays each gift in `effects`.
// It is a bottom sheet at the bottom of `container` (use the screen area, not a slot in the flow).
const tray = createGiftTray({
  container: screen,
  client,
  receiver: post.authorId,
  reference: post.id,
  effects,
  onTopUp: openCoinStore,
  // Keep the notice above the sheet as it moves.
  onInsetChange: (px) => effects.setOptions({ noticeBottom: px + 16 }),
});

// A gift someone else sent you (push, socket, webhook):
effects.play({ gift: { id, name, price, image, icon }, sender: "ayla" });

// When the screen goes away:
tray.destroy();
effects.destroy();
```

- `GiftEffectLayer(container, options)`: `play(event): number`, `cancel(id)`, `clear()`, `destroy()`,
  `setOptions()`. Options: `thresholds`, `quality` (`"low"` for slow devices), `reducedMotion`,
  `comboWindowMs`, `origin`, `pictureWaitMs`, `noticeBottom` (px), `theme`, `onEffectEnd`,
  `remoteRecipes`, `recipesVersion`, `recipesUrl` (see Remote recipes below). The
  container should cover the area you want (for the whole page use a `position: fixed; inset: 0`
  element); a `position: static` container is made `relative` until `destroy()`.
- `GiftTray(container, options)` is the presentational tray (`update`, `getSelected`, `destroy`,
  and for the sheet `getSheetState`, `snapTo`, `measure`). Sheet options as in React Native:
  `sheet` (`false` = the old fixed tray in the page flow), `initialSnap`, `snaps`, `onSnapChange`,
  `onInsetChange`. Drag with mouse, touch or pen (pointer events); the handle is a button with
  `aria-expanded`: Enter toggles, ArrowUp and ArrowDown change the size.
  `createGiftTray` wires it to the core `GiftTrayController` and returns `{ tray, controller,
refresh, open, close, toggle, isOpen, destroy }`. Callbacks: `onSend`, `onTopUp`, `onSent`,
  `onError`, `onState`.
- Scrim and the Gift button (sheet placement, SPEC 9.4): `scrim: true` draws a dim behind the
  sheet (fades in over 200 ms, hidden at peek, black at 0.4, takes the taps above the sheet);
  `scrimTap` is `"lower"` (default: lowers the sheet to peek) or `"dismiss"` (closes the tray);
  `onDismiss()` and `onOpenChange(open)` tell you. `handle.toggle()` (or `tray.toggle()`) is your
  Gift button: it opens a closed sheet and closes an open one (`open()`, `close()`, `isOpen()`;
  `open: false` starts closed). The popover keeps its own Escape and outside-click behaviour.

  ```ts
  const h = createGiftTray({
    container: screen,
    client,
    receiver,
    scrim: true,
    scrimTap: "dismiss",
  });
  giftButton.onclick = () => h.toggle();
  ```

- Desktop: `placement` (`"auto"` by default) picks where the tray sits from the container's width,
  now and on every resize. Below 600 px it is the bottom sheet (exactly as before). From 600 px it
  is a **popover** when you pass `anchor` (your gift button: its clicks open and close a 380 px
  panel, 5 columns, at most 70 % of the viewport tall, below the button or above it when there is
  no room; Escape and a click outside close it, sending keeps it open; `open()`, `close()`,
  `toggle()`, `isOpen()`, `onOpenChange`), otherwise **inline** (fills the container, as many
  columns as fit, the grid scrolls inside). Force one with `placement: "sheet" | "popover" |
"inline"`; `onPlacementChange` reports switches. The popover is drawn just under the effect
  layer (`z-index` 999 vs 1000), so gifts and the notice stay on top of it.

  ```ts
  createGiftTray({ container: playerColumn, anchor: giftButton, client, receiver, effects });
  ```

- Colors: `theme` on both (`darkTheme`, `lightTheme`, `themeFromAccent(accent, mode)`; switch live
  with `tray.update({ theme })` and `effects.setOptions({ theme })`), or override the CSS variables (`--gs-accent`, `--gs-coin`,
  `--gs-surface`, ...) from your own CSS. The layer injects its own small style sheet once and
  removes it when the last layer or tray is destroyed; there is no CSS file to load.
- **HTML elements** (no JavaScript classes to call): `import "@giftingstack/sdk/elements"` registers
  `<gift-effect-layer>` and `<gift-tray>` (or call `defineGiftElements()` from `/web`; nothing is
  registered on a plain import of `/web`, and importing on a server is safe).

  ```html
  <gift-effect-layer id="fx"></gift-effect-layer>
  <gift-tray receiver="mert" reference="post-42" effects="#fx" top-up></gift-tray>
  <script type="module">
    import "@giftingstack/sdk/elements";
    import { createGiftingClient } from "@giftingstack/sdk";
    document.querySelector("gift-tray").client = createGiftingClient({ getToken });
    document.querySelector("gift-tray").addEventListener("gift-topup", openCoinStore);
  </script>
  ```

  `<gift-tray>` stays empty until it is on the page and has a `receiver` and a `client` (a property,
  never an attribute). Attributes: `receiver`, `reference`, `effects` (CSS selector of the layer;
  default the first `<gift-effect-layer>`), `play-on`, `tray-title`, `coin-name`, `send-label`,
  `not-enough-label`, `get-coins-label`, `columns`, `grid-max-height`, `default-selected-id`,
  `disabled`, `sheet="false"`, `placement`, `anchor` (selector), `initial-snap`, `top-up`. A change
  rebuilds the tray (several at once: one rebuild); `disabled` updates in place. Properties: `client`,
  `theme`, `player` (any effect player instead of the layer), `options` (what attributes cannot say,
  e.g. `snaps`), `tray`, `controller`; methods `refresh()`, `open()`, `close()`, `toggle()`. Events (they
  bubble): `gift-sent`, `gift-error`, `gift-state`, `gift-topup`, `gift-open-change`, `gift-snap-change`,
  `gift-placement-change`, `gift-inset-change`. As a sheet, the tray keeps the linked layer's notice above
  it (unless that layer has its own `notice-bottom`) and lets clicks through outside the sheet.
  `<gift-effect-layer>` covers its nearest positioned ancestor (override with CSS) and takes
  attributes `quality`, `reduced-motion`, `picture-scale`, `notice-bottom`, `combo-window-ms`,
  `remote-recipes`, `recipes-version`, `recipes-url`; methods `play()`, `cancel()`, `clear()`; property
  `options` (`thresholds`, `theme`, `origin`...); event `gift-effect-end`. Give `<gift-tray>` the size of
  the area it belongs to, like the container of `GiftTray`.

- Only `transform` and `opacity` are animated (Web Animations API), so the effects run on the
  compositor. The layer has `pointer-events: none`.
- Reduced motion follows `prefers-reduced-motion` live: no effect, only the notice (it still slides
  in, as on React Native). Override with `reducedMotion`. The sheet then snaps without animating.
- Accessibility: the notice is a polite live region; the tray is a radio group (arrow keys, one tab
  stop), the balance is a live region that announces the final number, and every button has a label.

Limits: the flying effects need the Web Animations API (all current browsers). Without it the layer
shows only the notice, as with reduced motion, and does not break. Gifts played while the layer has no size
(hidden container) wait until it has one. Not measured on a low-end phone or in older WebViews: check
the frame rate there and use `quality: "low"`. In a background tab browsers pause animations.

### Gift wall, while you were away and leaderboard (web)

Three more components, framework-free like the tray: `GiftWall`, `GiftAwaySummary`,
`GiftLeaderboard` (from `@giftingstack/sdk/web`), or the tags `<gift-wall>`, `<gift-away-summary>`
and `<gift-leaderboard>`. They use the same theme tokens as the tray (`theme`, or the `--gs-*`
variables), one shared style sheet, and the same `client`.

```ts
import { GiftAwaySummary, GiftLeaderboard, GiftWall } from "@giftingstack/sdk/web";

// Under every post of a feed. Walls created together share ONE request (calls within 50 ms are
// batched, 25 walls per call) and each answer is reused for 60 s.
const wall = new GiftWall(slot, {
  client,
  user: post.authorId,
  reference: post.id, // the id you pass as `reference` when sending; none = the profile wall
  onPressChip: (gift) => openTray(), // optional: chips become buttons
});
wall.update({ refreshKey: n }); // after the person sent a gift to it: asks again

// "While you were away": a card over the screen plus a short replay in the effect layer.
const away = new GiftAwaySummary(screen, {
  client,
  effects, // your GiftEffectLayer; leave it out for the card only
  resolveUsers: async (ids) => ({ [ids[0]]: { name: "Ayla", avatarUrl } }), // ids are rarely names
});

// Top senders or receivers.
const board = new GiftLeaderboard(panel, {
  client,
  board: "senders",
  metricToggle: true,
  limit: 10,
});
```

- `GiftWall`: `client`, `user`, `reference`, `max` (6, the overflow chip included), `order`
  (`"count"` | `"catalog"`), `size` (`"sm"` | `"md"`), `data` (counters you already have: no
  request), `refreshKey`, `onPressChip`, `renderChip`, `onError`, `theme`, `labels`. It draws nothing while empty or
  when the request failed (a wall is decoration: errors only reach `onError`). Counts are written
  short and rounded down (`1999` is `1.9K`). The row is one labelled element ("Gifts: 12 Roses, 3
  Hearts, and 37 more"); with `onPressChip` each chip is a button ("Rose, 12") with a 44 px target.
- `GiftAwaySummary(container, options)`: `client`, `effects`, `resolveUsers`, `autoCheck` (true: checks on
  mount and when the page comes back, at most once a minute), `ackOn` (`"shown"` | `"finished"` |
  `"manual"`; then call `ack()`), `minGifts` (1; fewer gifts: no card, still acknowledged), `maxEffects` (5), `budgetMs` (8000), `thresholds`, `quality`,
  `reducedMotion`, `focusOnShow`, `onShow`, `onDone`, `onError`, `theme`, `labels`; methods `check()`,
  `ack()`, `dismiss()`, `update()`, `destroy()`. The card is a non-modal dialog, centred, 360 px
  wide at most; a tap, the Dismiss button or Escape closes it, and it closes itself when the replay
  has ended. With reduced motion there is no replay and no slide-in; a live region says "You
  received 37 gifts from 12 people while you were away". Deleted senders show as "Someone".
  The container becomes `position: relative` if it is static, like the effect layer's.
- `GiftLeaderboard(container, options)`: `client`, `board`, `periods` (tabs; one = no tabs),
  `initialPeriod`, `metric`, `metricToggle`, `limit`, `resolveUsers`, `highlightUser` (default: the
  signed-in person), `refreshIntervalMs` (0), `onPressUser`, `renderRow`, `onError`, `theme`, `labels`, `coinName`;
  methods `refresh()`, `update()`, `destroy()`. Tabs are a `tablist` (arrow keys, Home and End),
  each tab keeps its last answer for 30 s and the rows stay while it refreshes. Ranks 1 to 3 sit
  on a medal disc; the viewer's row is highlighted, or pinned under the list ("You: #417",
  "You: 1,000+") when they are outside the rows. A failed first load shows a message and a Try again
  button. Rows wait up to 2 s for `resolveUsers`, then show the ids.
- `labels` (all three): every visible and spoken word, for translations, with `{x}` places; the same
  keys as React Native. `defaultLabels` and `resolveLabels` are exported.
- Tags: `<gift-wall user reference max order size refresh-key pressable>`, `<gift-away-summary effects
auto-check ack-on max-effects budget-ms quality reduced-motion focus-on-show>` (put it inside the
  screen area, with `effects="#fx"` or the first `<gift-effect-layer>`), `<gift-leaderboard board
periods="day,week,all" initial-period metric metric-toggle limit highlight-user refresh-interval-ms
coin-name pressable>`. `client` (and `resolveUsers`, `theme`, `labels`, `data`) are properties.
  Bubbling events: `gift-chip-press`, `gift-user-press`, `gift-away-show`, `gift-away-done`,
  `gift-error`.
- `<gift-room room effects min-tier skip-own max-replay-age-ms>` joins a room and plays its gifts (no
  picture of its own; `getToken` is a property). Events: `gift-room-event`, `gift-room-viewers`,
  `gift-room-gap`, `gift-room-state`.

### Headless use (draw it yourself)

You do not have to use our components. The logic is in the core, exported from
`@giftingstack/sdk`: `GiftWallLoader`, `wallChips`, `formatCount`, `AwayController`,
`planAwayReplay`, `LeaderboardController`, `pinnedMe`. You subscribe and draw; we never dictate
a flow.

```ts
// Gift wall: your own chips.
import { GiftWallLoader, formatCount, wallChips } from "@giftingstack/sdk";

const loader = new GiftWallLoader({ query: (items) => client.queryGiftWalls(items) });
loader.load(userId).then((gifts) => {
  slot.replaceChildren(
    ...wallChips(gifts, { max: 4 }).map((chip) => {
      const el = document.createElement("span");
      el.textContent =
        chip.type === "gift"
          ? `${chip.gift.name} ${formatCount(chip.count)}`
          : `+${formatCount(chip.count)}`; // overflow chip
      return el;
    }),
  );
});
```

```ts
// While you were away: your own card.
import { AwayController } from "@giftingstack/sdk";

const away = new AwayController({ client, ackOn: "manual", minGifts: 3 });
const stop = away.subscribe(() => {
  const { status, summary } = away.getState(); // idle | loading | empty | ready | ...
  if (status !== "ready" || !summary) return;
  render(`${summary.total_gifts} gifts from ${summary.sender_count} people while you were away`);
  void away.ack(); // when YOU decide it was seen
  away.dismiss();
});
void away.check(); // at app open; away.foreground() when the app returns (throttled)
// later: stop(); away.dispose();
```

```ts
// Leaderboard: your own rows.
import { LeaderboardController, formatCount } from "@giftingstack/sdk";

const lb = new LeaderboardController({ client, board: "senders", periods: ["week", "all"] });
const stop = lb.subscribe(() => {
  const { status, data, pinned } = lb.getState(); // pinned = your row when you are outside the list
  if (status === "loading") return render("Loading...");
  if (status === "empty" || !data) return render("Nobody yet");
  const rows = data.data.map((e) => `#${e.rank} ${e.user} ${formatCount(e.units)}`);
  if (pinned) rows.push(`You: #${pinned.rank}`);
  render(rows.join("\n"));
});
lb.start(); // lb.setPeriod("all"), lb.refresh()
```

On React Native the hooks `useGiftWall`, `useGiftAway` and `useGiftLeaderboard` wrap the same
controllers and return `{ state, controller, ... }`.

### Integration patterns

The same page is on the docs site (`/integration-patterns/`). To see all three on one screen, open the
GiftingStack demo (`/web.html` or `/react-native.html`), long-press the logo for a second and use the
"Example integration" row: Card, Badge + box, Custom.

The same three ways to show "While you were away" and the leaderboard. Pick one per screen.

**(a) Card at app open.** One line; the component checks, shows, replays and acknowledges.
`minGifts` keeps small summaries quiet (they are still acknowledged, so they do not come back).

```ts
// web
new GiftAwaySummary(screen, { client, effects, minGifts: 3 });
new GiftLeaderboard(panel, { client, board: "senders", limit: 10 });
```

```tsx
// React Native
<GiftAwaySummary client={client} effects={effects} minGifts={3} />
<GiftLeaderboard client={client} board="senders" limit={10} />
```

**(b) Badge and inbox list.** No card. `ackOn: "manual"` and never `start()`: the controller stops
at `ready` with the summary (`total_gifts`, `groups`, `top_senders`); you draw a badge and a list,
and acknowledge when the person opens the inbox. (`autoCheck: false` plus `check()` on the
component works too when you want the card later.)

```ts
// web
const away = new AwayController({ client, ackOn: "manual" });
away.subscribe(() => {
  const { status, summary } = away.getState();
  badge.hidden = status !== "ready";
  badge.textContent = String(summary?.total_gifts ?? 0);
  if (status === "ready" && summary)
    list.replaceChildren(
      ...summary.groups.map((g) => {
        const li = document.createElement("li");
        li.textContent = `${g.count} x ${g.gift.name}, ${g.sender_count} people`;
        return li;
      }),
    );
});
void away.check();
badge.onclick = () => {
  openInbox();
  void away.ack();
  away.dismiss();
};
```

```tsx
// React Native
function InboxBadge() {
  const { state, ack, dismiss } = useGiftAway({ client, ackOn: "manual" });
  if (state.status !== "ready" || !state.summary) return null;
  return (
    <Pressable
      onPress={() => {
        openInbox();
        void ack();
        dismiss();
      }}
    >
      <Text>{state.summary.total_gifts}</Text>
      {state.summary.groups.map((g) => (
        <Text key={g.gift.id}>
          {g.count} x {g.gift.name}
        </Text>
      ))}
    </Pressable>
  );
}
```

For the leaderboard, a badge is the viewer's own place: `state.pinned` (or the row with your id
in `state.data.data`) from `LeaderboardController` / `useGiftLeaderboard`.

```tsx
// React Native: your own list, our logic
const { state, setPeriod } = useGiftLeaderboard({ client, board: "senders", limit: 5 });
// state.data?.data.map((e) => <Text key={e.user}>#{e.rank} {e.user} {formatCount(e.units)}</Text>)
// state.pinned && <Text>You: #{state.pinned.rank}</Text>;  setPeriod("all") for a tab
```

**(c) Fully custom.** Use the controllers as in "Headless use" above (web or React Native, the
code is the same; on React Native call them from your own hook). You own the timing, the look and
the acknowledgement. To still get our replay, call `away.start()` when your card is on screen and
pass `effects: () => layer`.

### Render slots (draw the inside, keep our behaviour)

Between "use the card as it is" and "build it yourself" there is a middle way: keep the component
and draw only its inside. Each component takes one optional render hook. We keep loading,
ordering, deduplication, names, the container, the accessibility role and label, press handling,
focus and effects; you draw what is inside. The hook gets the already computed data. Returning
nothing draws the default, so you can customise some rows and leave the rest. Web and React
Native only; the native SDKs do not have render slots yet (pending native port).

| Component         | Web option / React Native prop | You draw                      | The hook receives                                                                         |
| ----------------- | ------------------------------ | ----------------------------- | ----------------------------------------------------------------------------------------- |
| `GiftWall`        | `renderChip`                   | the inside of each gift chip  | `{ gift, count, countText }` (web also `doc`; RN also `theme`)                            |
| `GiftLeaderboard` | `renderRow`                    | the inside of each ranked row | `{ entry, rank, name, avatarUrl, metric, score, scoreText, isMe }`                        |
| `GiftAwaySummary` | `renderSummary`                | the body of the card          | `{ summary, title, headline, senders, dismiss, ack }` (web also `gifts`, `people`, `doc`) |

```ts
// web: return a DOM node, or a string (text, never HTML)
new GiftWall(el, {
  client,
  user: "mert",
  renderChip: ({ gift, count, doc }) => {
    const b = doc.createElement("b");
    b.textContent = `${gift.name} x${count}`;
    return b;
  },
});

new GiftLeaderboard(panel, {
  client,
  renderRow: ({ rank, name, scoreText }) => `#${rank} ${name} (${scoreText})`,
});

new GiftAwaySummary(screen, {
  client,
  effects,
  renderSummary: ({ headline, senders, dismiss }) => {
    const box = document.createElement("div");
    const p = document.createElement("p");
    p.textContent = `${headline}. Top: ${senders[0]?.name ?? "-"}`;
    const close = document.createElement("button");
    close.textContent = "OK";
    close.onclick = dismiss;
    box.append(p, close);
    return box;
  },
});
```

```tsx
// React Native: return a node
<GiftWall client={client} user="mert" renderChip={({ gift, count }) => <Text>{gift.name} x{count}</Text>} />
<GiftLeaderboard client={client} renderRow={({ rank, name, scoreText }) => <Text>#{rank} {name} {scoreText}</Text>} />
<GiftAwaySummary
  client={client}
  effects={effects}
  renderSummary={({ headline, dismiss }) => (
    <Pressable onPress={dismiss}><Text>{headline}</Text></Pressable>
  )}
/>
```

The custom `<gift-wall>`, `<gift-leaderboard>` and `<gift-away-summary>` elements take the same
functions through their `options` property: `el.options = { renderChip: ... }`.

What stays ours, so you do not have to rebuild it:

- **Wall:** the chip element (a button with its spoken label when `onPressChip` is set), the
  order and the `+N` chip, the loading skeleton and the fade.
- **Leaderboard:** the row element with its spoken label (`"Rank 1, ayla, 54,000 coins"`), the
  highlight of the viewer's row, the press, tabs, loading and error states, and the pinned
  "You: #417" row. Your row is drawn inside `.gs-row-main`; on the web it is hidden from screen
  readers behind the row label unless rows are pressable, so keep the meaning in the data, not
  only in your drawing.
- **Away card:** the check, the names (`resolveUsers`), the container and its slide-in, the
  dialog role (web: labelled with the title; React Native: the arrival is announced), Escape to
  close (web), `focusOnShow`, the replay and the acknowledgement. With your own body a tap on the
  card does not dismiss it (the default card does): put a button that calls `dismiss()` in it.
  `ack()` is there for `ackOn: "manual"`.

A hook that throws on the web draws the default and reports to `onError`.

### Remote recipes

The web and React Native layers fetch the effect numbers (durations, sparks, coins, scale, notice time, price
thresholds, combo window) from `https://assets.giftingstack.com/recipes.json`, so we can tune the
effects without you shipping an update. Caps and the queue never come from the network.

- Never blocks: the first effect uses the cached copy, or the built-in numbers when there is none.
  The fetch runs in the background (3 s timeout, at most once per 6 hours, backs off after
  failures) and is shared by every layer on the page. Failures are silent.
- Every value is checked and clamped to a safe range (spec `packages/sdk-spec/SPEC.md`, section
  13); a broken field falls back to the built-in value for that field only.
- Your own options win: `thresholds` and `comboWindowMs` you pass beat the remote ones.
- Gifts already on screen keep their numbers; new gifts use the new ones.
- `remoteRecipes: false`: no network at all. `recipesVersion: "1.0.0"` pins a document
  (`recipes.1.0.0.json`). `recipesUrl`: host the file yourself.
- Cached in `localStorage` on the web (`giftingstack:recipes:<url>`); works without storage.
- React Native: the same props on `GiftEffectLayer` (`remoteRecipes`, `recipesVersion`, `recipesUrl`).
  The copy is kept in memory; pass `recipesStorage` (anything with `getItem` and `setItem` on
  strings, sync or async, so `AsyncStorage` fits) to keep it between app starts:
  `<GiftEffectLayer recipesStorage={AsyncStorage} />`. No dependency is added.

The file is live at `https://assets.giftingstack.com/recipes.json`. To prepare the hosted files, run
`npm run build:remote` in `packages/sdk-spec`: it writes `dist/recipes.json` and
`recipes.<specVersion>.json` and does not upload anything.

### Content-Security-Policy

The web SDK works under a strict policy. It adds no inline script, no `eval` and no `style`
attributes (positions and colours are set through the CSSOM, which `style-src` does not govern). What
a policy has to allow:

| directive     | needs                                                                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `connect-src` | `https://api.giftingstack.com` (the API; your own host if you proxy it), `wss://rt.giftingstack.com` (gift rooms only), `https://assets.giftingstack.com` (remote recipes; not needed with `remoteRecipes: false`) |
| `img-src`     | `https://assets.giftingstack.com` (the gift library) and the hosts of your own gift and avatar pictures; `data:` if you use data URLs                                                                              |
| `style-src`   | nothing in current browsers (see below)                                                                                                                                                                            |
| `script-src`  | nothing from the SDK (it is your bundle)                                                                                                                                                                           |

**Styles.** The stylesheet is added as a constructable stylesheet (`document.adoptedStyleSheets`),
which `style-src` does not govern: no nonce and no `'unsafe-inline'`. A browser without them (before
Chrome 73, Firefox 101 or Safari 16.4) gets a `<style>` element instead, and that one needs your
page's nonce. Call this once at start-up, before the first component is created:

```ts
import { configureStyles } from "@giftingstack/sdk/web"; // also exported by "@giftingstack/sdk/elements"

configureStyles({
  nonce: document.querySelector<HTMLMetaElement>('meta[name="csp-nonce"]')?.content,
});
// configureStyles({ adoptedStyleSheets: false }) always uses the <style> element (with the nonce)
```

Without the call the SDK reads the nonce from `<meta name="csp-nonce" content="...">` when the page has
one. A policy such as
`default-src 'self'; connect-src 'self' https://api.giftingstack.com wss://rt.giftingstack.com https://assets.giftingstack.com; img-src 'self' https://assets.giftingstack.com data:; style-src 'self' 'nonce-RANDOM'`
is enough. Gift pictures only load from `https://` (or `http://` to localhost), `data:image/` and your
own origin; any other URL is not requested and shows the placeholder.

### Safe URLs and pictures

- `createGiftingClient({ baseUrl })` and a room `url` refuse `http://` and `ws://` (the call throws)
  unless the host is `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` (the Android emulator), or you pass
  `allowInsecure: true`. The token travels in every request.
- Pictures: only `https://`, `data:image/`, `http://` to localhost and paths on your own origin are
  loaded. A picture that fails (network, not an image) is not requested again for 60 seconds and
  the placeholder is drawn. The browser and React Native cannot cap the download size; the gift
  library's pictures are a few KB. The tray downloads every gift's small icon at once and the big
  picture of the selected gift only; other big pictures load when their gift is first played.
- A `sendGift` that gets no answer at all (the connection dropped) is sent once more with the same
  idempotency key, so a gift is never charged twice; a timeout is not repeated.

## Gift rooms: everyone watching sees the gift (beta)

A room is everyone watching one live stream, audio room or chat. Join it on the viewer screen and
every gift sent with that `roomId` plays on every viewer's screen, about 0.1-0.4 s after it was
sent. No realtime server of your own: the SDK opens one WebSocket to `rt.giftingstack.com`,
reconnects, resumes and refreshes the token by itself. Gift events only: no chat, no media, no
history (a gift missed while offline for more than 10 s is simply not played). SPEC sections 17-18.

**1. Your server mints the token with the rooms and the name.** Same endpoint as always, two
more fields: `rooms` (room ids or prefixes ending in `*` this user may join and send into, at
most 8; **required for rooms**: a token without it cannot join any room, and a send with
`roomId` fails with `403 room_not_allowed`) and `name` (optional, what viewers see as the sender,
1-32 characters).

```ts
// Your server (Node). The secret key never leaves it.
app.get("/api/gift-token", async (req, res) => {
  const r = await fetch("https://api.giftingstack.com/v1/client-tokens", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.GS_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ user: req.user.id, rooms: ["live_*"], name: req.user.displayName }),
  });
  res.send((await r.json()).token);
});
```

**2. Web.** Your own gifts already play on tap and are not played twice.

```ts
import { createGiftingClient } from "@giftingstack/sdk";
import { GiftEffectLayer, createGiftTray, joinRoom } from "@giftingstack/sdk/web";

const getToken = async () => (await fetch("/api/gift-token")).text();
const client = createGiftingClient({ getToken });
const effects = new GiftEffectLayer(document.getElementById("stage")!);
const room = joinRoom({ room: "live_123", getToken, client, effects }); // room gifts play in `effects`
room.subscribe(() => (viewersLabel.textContent = `${room.viewers ?? "-"} watching`));
createGiftTray({ container: trayEl, client, receiver: hostId, effects, roomId: "live_123" });
// Leaving the stream page:
room.leave();
```

`joinRoom` disconnects after the page has been hidden for 60 s and reconnects when it is visible
again or the network comes back. Options: `onEvent`, `onViewers`, `onGap`, `onState`, `skipOwn`
(default true), `minTier` (`"medium"` shows only medium and large gifts), `resolveName` (a name for
senders whose token has no `name`), `maxReplayAgeMs`.

**3. React Native.** The socket closes when the app goes to the background and rejoins on return.

```tsx
import {
  GiftEffectLayer,
  GiftTray,
  useGiftRoom,
  useGiftTray,
} from "@giftingstack/sdk/react-native";

function LiveScreen({ stream }) {
  const effects = useRef<GiftEffectLayerHandle>(null);
  const room = useGiftRoom({ room: stream.id, getToken, client, effects });
  const tray = useGiftTray({ client, receiver: stream.hostId, effects, roomId: stream.id });
  return (
    <View style={{ flex: 1 }}>
      <Text>{room.viewers ?? "-"} watching</Text>
      <GiftTray tray={tray} />
      <GiftEffectLayer ref={effects} />
    </View>
  );
}
```

`room: null` keeps the screen out of any room. A room is visible to everyone whose token's `rooms`
allows it: keep `rooms` as narrow as the screen needs (`live_123` rather than `live_*` for a
private room), and use opaque user and room ids.

## Other platforms (Swift, Kotlin, Flutter…)

The API and the pictures work everywhere. For the effects, `allRecipes()` returns the three recipes
as plain JSON (durations, scales, particle counts), so you can draw them with your own animation
code and get the same look.

SDK authors: the shared contract is `packages/sdk-spec` (`SPEC.md`, `recipes.json` and JSON
conformance fixtures that every platform runs). The pure logic every platform ports lives in
`src/core`: `EffectScheduler`, `GiftTrayController`, `sendButtonState` and `TraySheetController`.

## Try it

```bash
cd packages/sdk-js
npm install
npm test         # unit tests, including every conformance fixture of packages/sdk-spec
npm run build    # ESM and types in dist
```

The interactive demo (a pretend app on a mock client) needs gift pictures that live in
GiftingStack's own repository, so it does not run from this repository.

## Honest limits

- Tried on an iPhone 13 through Expo Go (smooth, with the effects and the tray) and in a browser through
  `react-native-web`, plus unit tests. **Not measured on an older or low-end phone**: check frame rate there
  before you rely on it, and use `quality="low"` if needed.
- The pictures are still images. The effect is drawn around them.
- Version 0.1.3 is a preview: the API can still change before 1.0. The package is ESM with types
  (`npm run build`); `npm run prepublishOnly` (tests, typecheck, build) runs before every publish.

## License

MIT, see [LICENSE](LICENSE). The licence covers this package's code only. The GiftingStack
name and logo, the GiftingStack service and API, and the ready-made gift library
(`assets.giftingstack.com`) are not part of it; the gift library has its own terms.
