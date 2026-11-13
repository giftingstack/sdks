/**
 * "Pixel": a fake social app around the web SDK, on a mock client. Open http://localhost:5800/web.html
 * (phone width: tab bar and sheet tray; wide: rail, feed, right column, popover tray).
 *
 * What a customer would write: the effect layer, the tray, one `GiftWall` per post, one
 * `GiftAwaySummary` over the screen, one `GiftLeaderboard` and one `GiftInbox`. Everything else (the feed, the tabs,
 * the developer menu behind the logo, the incoming gifts) is only the demo's own pretend app.
 *
 * "Example integration" (developer menu) shows the three ways to use the away data: the SDK card,
 * a badge on Inbox with a plain box (headless `AwayController`, no SDK card), and the card with
 * your own body (`renderSummary`). See "Integration patterns" and "Render slots" in the README.
 */
import {
  type AwaySummaryContext,
  GiftAwaySummary,
  type GiftAwaySummaryOptions,
  GiftBattleBar,
  GiftButton,
  type TrayReceiver,
  battleSidePalette,
  GiftEffectLayer,
  GiftInbox,
  GiftLeaderboard,
  GiftWall,
  type GiftTheme,
  type RoomHandle,
  joinRoom,
  type GiftTrayHandle,
  createGiftTray,
  darkTheme,
  lightTheme,
  themeFromAccent,
} from "../src/web";
import {
  AwayController,
  type Gift,
  type GiftTransaction,
  type InboxItem,
  inboxUnread,
} from "../src/core";
import { postArt } from "./art";
import { openCoinStore } from "./coinStore";
import { demoRoomToken, fakeRoomSocket } from "./fakeRoom";
import {
  type AwayPattern,
  type DemoTheme,
  type IncomingMode,
  attachDevTrigger,
  createDevMenu,
} from "./devMenu";
import { type Incoming, pickIncoming, startIncoming } from "./incoming";
import {
  POSTS,
  type Post,
  SENDERS,
  createMockClient,
  displayName,
  firstName,
  loadGifts,
  resolveDemoUsers,
  userColor,
} from "./shared";

const THEMES: Record<DemoTheme, GiftTheme> = {
  dark: darkTheme,
  light: lightTheme,
  pink: themeFromAccent("#ff4f9a", "dark"),
};
/**
 * Keeps `el` in sight by scrolling only this page. `scrollIntoView` also scrolls every parent
 * page, so inside the iframe on giftingstack.com it dragged the whole site down to the demo.
 */
function keepInView(el: HTMLElement): void {
  let box: HTMLElement | null = el.parentElement;
  while (box && box !== document.body && box !== document.documentElement) {
    if (
      box.scrollHeight > box.clientHeight &&
      /(auto|scroll)/.test(getComputedStyle(box).overflowY)
    )
      break;
    box = box.parentElement;
  }
  const own = box && box !== document.body && box !== document.documentElement ? box : null;
  const rect = own ? own.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
  // Like scrollIntoView: the scroller's scroll-padding is room that is covered (the open sheet).
  const pad = own ? getComputedStyle(own) : null;
  const bounds = {
    top: rect.top + (Number.parseFloat(pad?.scrollPaddingTop ?? "") || 0),
    bottom: rect.bottom - (Number.parseFloat(pad?.scrollPaddingBottom ?? "") || 0),
  };
  const r = el.getBoundingClientRect();
  const delta =
    r.bottom > bounds.bottom
      ? r.bottom - bounds.bottom
      : r.top < bounds.top
        ? r.top - bounds.top
        : 0;
  if (delta === 0) return;
  (own ?? window).scrollBy({ top: delta, behavior: "smooth" });
}

const fmt = (n: number): string => n.toLocaleString("en-US");
const esc = (s: string): string =>
  s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
const q = <T extends HTMLElement>(root: ParentNode, sel: string): T => root.querySelector<T>(sel)!;
const avatar = (id: string, size = 40): string =>
  `<span class="av" style="--s:${size}px;--c:${userColor(id)}" aria-hidden="true">${esc([...displayName(id)][0]!.toUpperCase())}</span>`;
const GIFT_ICON =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11h16v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1zM3 7h18v4H3zM12 7v14M12 7C10 7 8 6 8 4.5S10 3 12 7zm0 0c2 0 4-1 4-2.5S14 3 12 7z"/></svg>';
const HEART =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/></svg>';

async function main(): Promise<void> {
  const gifts = await loadGifts();
  const client = createMockClient(gifts);
  // Embedded on giftingstack.com (?embed=1): tell the page which API call each send makes, so it
  // can show "the call behind the button". Mock data only; nothing secret crosses.
  if (new URLSearchParams(location.search).get("embed") === "1" && window.parent !== window) {
    const post = (call: Record<string, unknown>): void =>
      window.parent.postMessage({ type: "giftingstack-demo-call", call }, "*");
    // The app is up: the page can show the frame now, without waiting for every picture to load.
    window.parent.postMessage({ type: "giftingstack-demo-ready" }, "*");
    const send = client.sendGift.bind(client);
    client.sendGift = async (input) => {
      const body = {
        receiver: input.receiver,
        gift_id: input.giftId,
        quantity: input.quantity ?? 1,
        ...(input.reference ? { reference: input.reference } : {}),
        ...(input.roomId ? { room_id: input.roomId } : {}),
      };
      const call = { method: "POST", path: "/v1/client/gift-transactions", body };
      try {
        const tx = await send(input);
        post({ ...call, status: 201, response: tx });
        return tx;
      } catch (err) {
        const e = err as { status?: number; type?: string; message?: string };
        post({
          ...call,
          status: e.status ?? 500,
          response: { error: { type: e.type, message: e.message } },
        });
        throw err;
      }
    };
    const credit = client.credit.bind(client);
    client.credit = (coins) => {
      credit(coins);
      post({
        method: "POST",
        path: "/v1/users/ava/credit",
        body: {
          amount: coins,
          reason: "purchase",
          reference: `order_${Date.now()}`,
          price: "4.99",
          currency: "USD",
        },
        status: 201,
        response: { user: "ava", type: "credit", amount: coins },
      });
    };
  }
  const app = q(document, "#app");
  const main = q(app, "#main");
  // A comment bar scrolls with the page: the notice follows it.
  main.addEventListener("scroll", () => placeNoticeSoon(), { passive: true });
  window.addEventListener("resize", () => placeNoticeSoon());
  const right = q(app, "#right");
  const banner = q(app, "#banner");
  const panels = Object.fromEntries(
    ["feed", "live", "chat", "top", "inbox", "me"].map((n) => [n, q(app, `[data-panel="${n}"]`)]),
  ) as Record<string, HTMLElement>;

  let theme: GiftTheme = THEMES.dark;
  let reduced: boolean | undefined;
  let quality: "high" | "low" = "high";
  let offline = false;
  let balance = 0;
  let received = 214;
  let selectedId = "sun-dragon";

  // ---- effect layer over the whole app. The notice sits above the tab bar (phone) or low (wide).
  const wide = window.matchMedia("(min-width: 1000px)");
  const baseNotice = (): number => (wide.matches ? 24 : 78);
  const effects = new GiftEffectLayer(app, {
    maxConcurrent: { medium: 4 },
    noticeBottom: baseNotice(),
    theme,
  });
  /** The open sheet's top edge from the app's bottom (0: no sheet on screen). */
  let trayInset = 0;
  /**
   * The gift notice's place: above the tab bar, above an open sheet, and above a message bar on
   * screen (the Chat tab's, a stream's comment bar), so the pill never covers what you type. The
   * bar is the app's own, so the app places the notice (`noticeBottom`): bar top + 8 px.
   */
  const placeNotice = (): void => {
    let px = trayInset > 0 ? trayInset + 16 : baseNotice();
    const bar = [...app.querySelectorAll<HTMLElement>(".dm-bar, .live-bar")].find(
      (b) => b.getClientRects().length > 0,
    );
    if (bar) {
      const a = app.getBoundingClientRect();
      const b = bar.getBoundingClientRect();
      // Only a bar that is on screen (a comment bar scrolled out of sight does not count).
      if (b.bottom > a.top && b.top < a.bottom) px = Math.max(px, Math.round(a.bottom - b.top + 8));
    }
    effects.setOptions({ noticeBottom: px });
  };
  let noticeTimer = 0;
  /** After a layout change (the bar moves with the sheet, the page scrolls): once, after layout. */
  const placeNoticeSoon = (): void => {
    window.clearTimeout(noticeTimer);
    noticeTimer = window.setTimeout(placeNotice, 0);
  };

  // ---- balance (header chip, profile)
  const setBalance = (n: number): void => {
    balance = n;
    q(app, "#coin-chip-n").textContent = fmt(n);
    const big = app.querySelector("#me-balance");
    if (big) big.textContent = fmt(n);
  };
  const syncBalance = async (): Promise<void> => {
    try {
      setBalance((await client.getMe()).balance);
    } catch {
      /* offline: keep the last number */
    }
  };
  void syncBalance();

  // ---- walls: one per post (they ask together, in one request) and one on the profile
  const walls: { user: string; reference?: string; key: number; wall: GiftWall }[] = [];
  const addWall = (
    slot: HTMLElement,
    user: string,
    reference: string | undefined,
    onPressChip?: (g: { id: string }) => void,
  ): void => {
    walls.push({
      user,
      reference,
      key: 0,
      wall: new GiftWall(slot, {
        client,
        user,
        reference,
        theme,
        max: reference ? 6 : 8,
        onPressChip,
      }),
    });
  };
  const refreshWalls = (): void => {
    for (const w of walls) w.wall.update({ refreshKey: ++w.key });
  };

  // ---- the gift tray: made when a Gift button is pressed, gone after a send
  let handle: GiftTrayHandle | null = null;
  let anchorOf: HTMLElement | null = null;
  const closeTray = (): void => {
    const h = handle;
    if (!h) return;
    handle = null;
    anchorOf = null;
    selectedId = h.tray.getSelected()?.id ?? selectedId;
    h.destroy();
    app.style.removeProperty("--tray-inset");
    trayInset = 0;
    placeNoticeSoon();
  };
  const store = (): void =>
    void openCoinStore(app, (coins) => {
      client.credit(coins);
      void syncBalance();
      void handle?.refresh();
    });
  type TrayExtra = {
    /** The message bar's text field: the SDK swaps the tray with the keyboard (spec 20). */
    input?: HTMLInputElement;
    onSent?: (tx: GiftTransaction) => void;
    /** A battle: the sides, for the tray's "Send to" row (spec 21). */
    receivers?: TrayReceiver[];
  };
  const openTray = (
    post: Post,
    anchor: HTMLElement,
    giftId?: string,
    roomId?: string,
    extra: TrayExtra = {},
  ): void => {
    const sheet = app.clientWidth < 600;
    if (handle && anchorOf === anchor && !giftId) {
      // The popover anchor's own click closes it; on a phone the Gift button toggles the sheet.
      if (sheet) handle.toggle();
      return;
    }
    makeTray(post, anchor, giftId, roomId, extra);
    if (!sheet) handle!.tray.open();
  };
  /**
   * A message bar's gift button (the chat screen, the live comment bar): the tray is made for the
   * bar, closed, before the first press, and the SDK does the rest (spec 20): the button closes the
   * keyboard and opens the tray in its place, a tap on the field closes the tray, the button again
   * brings the keyboard back. Other trays (the feed's) replace it, so it is made again whenever the
   * person reaches for the bar.
   */
  const giftBar = (
    bar: HTMLElement,
    input: HTMLInputElement,
    button: GiftButton,
    post: () => Post,
    extra: () => {
      roomId?: string;
      onSent?: (tx: GiftTransaction) => void;
      receivers?: TrayReceiver[];
    },
  ): (() => GiftTrayHandle | null) => {
    const arm = (): GiftTrayHandle | null => {
      if (!(handle && anchorOf === button.element))
        makeTray(post(), button.element, undefined, extra().roomId, { ...extra(), input });
      return handle;
    };
    bar.addEventListener("pointerdown", arm, true);
    bar.addEventListener("focusin", arm);
    return arm;
  };
  const barButtons: GiftButton[] = [];
  const makeTray = (
    post: Post,
    anchor: HTMLElement,
    giftId: string | undefined,
    roomId: string | undefined,
    extra: TrayExtra,
  ): void => {
    const sheet = app.clientWidth < 600;
    closeTray();
    anchorOf = anchor;
    // What is behind the tray stays in sight (the feed and a live room alike): picking a gift
    // lowers the sheet to the picked gift and Send and the dim goes away while it is low; a tap
    // outside the open sheet closes it, and so does the Gift button (handle.toggle()).
    const h = createGiftTray({
      container: app,
      client,
      receiver: post.author,
      reference: post.id,
      roomId,
      // In a battle your own gift says who got it too (the room knows the sides).
      receiverOf: (u) => room?.receiverFor(u),
      effects,
      theme,
      anchor,
      input: extra.input,
      receivers: extra.receivers,
      defaultSelectedId: giftId ?? selectedId,
      onTopUp: store,
      onInsetChange: (px) => {
        trayInset = px;
        placeNoticeSoon();
        // The page keeps its Gift button above the sheet: room for the sheet, and the button in view.
        app.style.setProperty("--tray-inset", `${sheet ? px : 0}px`);
        if (sheet && px > 0) keepInView(anchor);
      },
      // A pick makes the tray small everywhere; the SDK draws the dim and closes on a tap on it.
      collapseOnSelect: true,
      // The chat's message bar keeps its conversation in full view: no dim there (the SDK's default
      // with `input`). A live room's comment bar has the dim, so a tap on the stream closes the tray.
      scrim: !extra.input || roomId !== undefined,
      scrimTap: "dismiss",
      onOpenChange: (open) => {
        // A bar's tray stays (closed) for the next press; the others go when they close.
        if (!open && !extra.input) queueMicrotask(() => handle === h && closeTray());
      },
      onSent: (tx: GiftTransaction) => {
        setBalance(tx.sender_balance_after);
        extra.onSent?.(tx);
        const w = walls.find((x) => x.user === tx.receiver && x.reference === tx.reference);
        if (w) w.wall.update({ refreshKey: ++w.key });
        // The tray stays open after a send, like a live app: tap again for a combo, the Gift
        // button again to close it.
      },
    });
    handle = h;
  };

  // ---- chat: a one-to-one messaging screen. The conversation, the input and the bubbles are the
  // app's OWN chat (GiftingStack carries no chat); what comes from the SDK is the gift tray and the
  // effects. The gift button sits in the message bar like an emoji button: it puts the tray where
  // the keyboard was (the keyboard closes), and a tap on the text field brings the keyboard back.
  {
    const DM: Post = { ...POSTS[0]!, id: "dm_ava_mateo", author: "mateo" };
    const panel = panels.chat!;
    panel.innerHTML = `
      <div class="dm-head">${avatar(DM.author, 36)}<div><b>${esc(displayName(DM.author))}</b><small>online</small></div></div>
      <p class="dm-note">The conversation is your app's chat. The gift button opens the GiftingStack tray in the keyboard's place.</p>
      <ol class="dm-list" aria-live="polite"></ol>
      <form class="dm-bar">
        <div class="dm-field">
          <input type="text" placeholder="Message" aria-label="Message" autocomplete="off" />
        </div>
        <button class="dm-send" type="submit" aria-label="Send">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12l16-8-6 16-3-7z" /></svg>
        </button>
      </form>`;
    const list = q<HTMLOListElement>(panel, ".dm-list");
    const input = q<HTMLInputElement>(panel, "input");
    // The gift button is the SDK's GiftButton, in the app's own message bar like an emoji button.
    const giftBtn = new GiftButton(q(panel, ".dm-field"), { theme });
    barButtons.push(giftBtn);
    let thanks = 0;
    const say = (from: "me" | "them", html: string): void => {
      const li = document.createElement("li");
      li.className = `dm-msg ${from}`;
      li.innerHTML = html;
      list.append(li);
      // Only this page scrolls (scrollIntoView would also scroll a page that embeds the demo).
      main.scrollTop = main.scrollHeight;
    };
    say("them", "Did you catch my stream last night?");
    say("me", "Yes! The ending was wild 😄");
    say("them", "Right?? Going live again on Friday");
    // A tap on the conversation puts the tray (or the keyboard) away, as chat apps do; no dim over
    // the chat.
    list.addEventListener("click", () => {
      if (handle && anchorOf === giftBtn.element) handle.tray.close();
      input.blur();
    });
    q<HTMLFormElement>(panel, ".dm-bar").addEventListener("submit", (e) => {
      e.preventDefault();
      const text = input.value.trim();
      if (!text) return;
      say("me", esc(text));
      input.value = "";
    });
    giftBar(
      q(panel, ".dm-bar"),
      input,
      giftBtn,
      () => DM,
      () => ({
        onSent: (tx: GiftTransaction) => {
          // Quick repeats of the same gift (a combo) add up in one bubble, like the gift notice. The
          // running bubble is found wherever it is (a thank-you in between does not cut the count)
          // while its last gift is under 5 s old; it stays where it is, above its thank-you.
          const running = ([...list.children] as HTMLElement[])
            .reverse()
            .find((b) => b.dataset.gift === tx.gift.id && Date.now() - Number(b.dataset.at) < 5000);
          // A combo that goes on after its thank-you (the bubble is not the last) gets no second one.
          const thanked = running !== undefined && running !== list.lastElementChild;
          if (running) {
            const count = Number(running.dataset.count) + tx.quantity;
            running.dataset.count = String(count);
            running.dataset.at = String(Date.now());
            q(running, ".dm-n").textContent = ` ×${count}`;
          } else {
            const img = tx.gift.icon_url
              ? `<img src="${esc(tx.gift.icon_url)}" alt="" width="44" height="44" />`
              : "";
            const n = tx.quantity > 1 ? ` ×${tx.quantity}` : "";
            say(
              "me",
              `<span class="dm-giftmsg">${img}<span>You sent <b>${esc(tx.gift.name)}</b><span class="dm-n">${n}</span></span></span>`,
            );
            const bubble = list.lastElementChild as HTMLElement;
            bubble.dataset.gift = tx.gift.id;
            bubble.dataset.count = String(tx.quantity);
            bubble.dataset.at = String(Date.now());
          }
          main.scrollTop = main.scrollHeight;
          // One thank-you after the sending stops, not one per tap.
          if (!thanked) {
            window.clearTimeout(thanks);
            thanks = window.setTimeout(() => say("them", "Thank you!! 😍"), 1800);
          }
        },
      }),
    );
  }

  // ---- feed
  for (const post of POSTS) {
    const card = document.createElement("article");
    card.className = "post";
    card.dataset.post = post.id;
    card.innerHTML = `
      <div class="post-head">${avatar(post.author)}<div><b>${esc(displayName(post.author))}</b><small>${post.ago}</small></div></div>
      <div class="art">${postArt(post)}</div>
      <p class="post-text">${esc(post.text)}</p>
      <div class="post-actions">
        <button class="pill like" type="button" aria-pressed="false">${HEART}<span>${fmt(post.likes)}</span></button>
        <button class="pill gift" type="button">${GIFT_ICON}Gift</button>
      </div>
      <div class="wall-slot"></div>`;
    const giftBtn = q<HTMLButtonElement>(card, ".gift");
    giftBtn.addEventListener("click", () => openTray(post, giftBtn));
    const like = q<HTMLButtonElement>(card, ".like");
    like.addEventListener("click", () => {
      const on = like.getAttribute("aria-pressed") !== "true";
      like.setAttribute("aria-pressed", String(on));
      q(like, "span").textContent = fmt(post.likes + (on ? 1 : 0));
    });
    panels.feed!.append(card);
    // Pressing a chip of the wall opens the tray with that gift picked.
    addWall(q(card, ".wall-slot"), post.author, post.id, (g) => openTray(post, giftBtn, g.id));
  }

  const opts = new URLSearchParams(location.search);

  // ---- live: a room. Everyone watching sees every gift sent with this room id.
  // The demo has no rooms server, so a pretend one (fakeRoom.ts) speaks the real protocol and the
  // SDK's real `joinRoom` runs against it. In a real app: `joinRoom({ room, getToken, effects })`.
  // Two kinds of stream share the tab: a plain live room (one host, everyone sees the gifts, with
  // combos) and a battle (versus): Mia and Theo, viewers pick a side by whom they gift. Your
  // server starts each round (`POST /v1/rooms/{room_id}/battle`); the SDK only shows the scores.
  const LIVE_HOST = "mia";
  const LIVE_RIVAL = "theo";
  // "Battle 4+": a free-for-all of four sides, round after round (the bar draws one cell per side).
  const LIVE_FFA = [LIVE_HOST, LIVE_RIVAL, "sofia", "kai"];
  const livePost: Post = {
    id: "live-1",
    author: LIVE_HOST,
    text: "Evening stream",
    art: "neon",
    ago: "live",
    likes: 0,
  };
  const postOf = (id: string): Post => ({ ...livePost, author: id });
  const watchers = SENDERS.filter((id) => !LIVE_FFA.includes(id));
  const rooms = {
    live: {
      id: "pixel-live",
      socket: fakeRoomSocket({ gifts, senders: watchers, nameOf: displayName }),
    },
    battle: {
      id: "pixel-battle",
      socket: fakeRoomSocket({
        gifts,
        senders: watchers,
        nameOf: displayName,
        battle: { receivers: [LIVE_HOST, LIVE_RIVAL] },
      }),
    },
    battle4: {
      id: "pixel-battle4",
      socket: fakeRoomSocket({
        gifts,
        senders: watchers,
        nameOf: displayName,
        battle: { receivers: LIVE_FFA },
      }),
    },
  } as const;
  // The rooms with a score bar.
  const BATTLES = ["battle", "battle4"] as const;
  type RoomMode = keyof typeof rooms;
  // What the API does after a send with `room_id` (the demo has no server): the room gets it.
  const sendToApi = client.sendGift.bind(client);
  client.sendGift = async (input) => {
    const tx = await sendToApi(input);
    const gift = gifts.find((g) => g.id === input.giftId);
    const target = Object.values(rooms).find((r) => r.id === input.roomId);
    if (target && gift) target.socket.publish("ava", gift, input.quantity ?? 1, input.receiver);
    return tx;
  };
  // A battle's sides, for the tray's "Send to" row (spec 21): one gift button for every side. The
  // colours are left to the SDK: the same palette as the score bar.
  const SIDES: Record<RoomMode, string[]> = {
    live: [LIVE_HOST],
    battle: [LIVE_HOST, LIVE_RIVAL],
    battle4: LIVE_FFA,
  };
  const receiversOf = (mode: RoomMode): TrayReceiver[] | undefined =>
    mode === "live" ? undefined : SIDES[mode].map((id) => ({ id, name: firstName(id) }));
  /** A battle gift line takes the receiving side's colour (the bar's palette). */
  const sideColor = (mode: RoomMode, to?: string): { color: string; text: string } | undefined => {
    const i = to ? SIDES[mode].indexOf(to) : -1;
    return i < 0 ? undefined : battleSidePalette(theme, SIDES[mode].length)[i];
  };
  // The stream's own chat (the app's, not GiftingStack's) runs over the video, bottom left, like
  // live apps do; the room's gifts land in the same column, so chat and gifts read as one stream.
  const stage = (): string =>
    `<div class="live-stage"><div class="art">${postArt(livePost)}</div>
        <span class="live-tag">LIVE</span><span class="live-viewers">...</span>
        <ol class="live-chat" aria-live="polite"></ol></div>`;
  // The comment bar under the stream: type a comment, or the gift button for the tray (it takes
  // the keyboard's place, as on the chat screen).
  // The gift button in the bar is the SDK's GiftButton (added below): one for every stream, also
  // a battle (the tray's "Send to" row picks the side).
  const commentBar = (withGift: boolean): string =>
    `<form class="live-bar"${withGift ? " data-gift" : ""}><input type="text" placeholder="Say something..." aria-label="Comment" autocomplete="off" /></form>`;
  panels.live!.innerHTML = `<h2>Live</h2>
    <div class="seg" role="group" aria-label="Stream">
      <button type="button" data-mode="live" aria-pressed="true">Live room</button>
      <button type="button" data-mode="battle" aria-pressed="false">Battle</button>
      <button type="button" data-mode="battle4" aria-pressed="false">Battle 4+</button>
    </div>
    <article class="card" data-block="live">
      ${stage()}
      <div class="post-head">${avatar(LIVE_HOST)}<div><b>${esc(firstName(LIVE_HOST))}</b><small>Evening stream</small></div></div>
      ${commentBar(true)}
      <p class="live-state">Connecting...</p>
    </article>
    <article class="card" data-block="battle" hidden>
      ${stage()}
      <div class="post-head">${avatar(LIVE_HOST)}<div><b>${esc(firstName(LIVE_HOST))} vs ${esc(firstName(LIVE_RIVAL))}</b><small>Evening stream battle</small></div></div>
      <div class="battle"></div>
      ${commentBar(true)}
      <p class="live-state">Connecting...</p>
    </article>
    <article class="card" data-block="battle4" hidden>
      ${stage()}
      <div class="post-head">${avatar(LIVE_HOST)}<div><b>${LIVE_FFA.map((id) => esc(firstName(id))).join(", ")}</b><small>Four creators in one round: every side has its own colour</small></div></div>
      <div class="battle"></div>
      ${commentBar(true)}
      <p class="live-state">Connecting...</p>
    </article>`;
  const block = (mode: RoomMode): HTMLElement => q(panels.live!, `[data-block="${mode}"]`);
  // One line in the stream's chat column: a comment, or a gift (highlighted). The newest at the
  // bottom; only the last few stay, the older ones fade out at the top.
  const chatLine = (mode: RoomMode, html: string, gift = false): void => {
    const list = q(block(mode), ".live-chat");
    const li = document.createElement("li");
    li.className = gift ? "gift" : "";
    li.innerHTML = html;
    list.append(li);
    while (list.children.length > 6) list.firstElementChild?.remove();
  };
  const giftLine = (sender: string, giftName: string, quantity: number, to?: string): string =>
    `<b>${esc(sender)}</b> sent ${esc(giftName)}${quantity > 1 ? ` ×${quantity}` : ""}${
      to ? ` to ${esc(firstName(to))}` : ""
    } ${GIFT_ICON}`;
  // A gift line; the same sender sending the same gift again within a few seconds (a combo) adds
  // up on that line ("×5") instead of a new line per tap, like the SDK's gift notice.
  const giftChat = (
    mode: RoomMode,
    sender: string,
    giftName: string,
    quantity: number,
    to?: string,
  ): void => {
    const list = q(block(mode), ".live-chat");
    const key = `${sender}|${giftName}|${to ?? ""}`;
    // The running combo of this sender and gift, wherever it is in the column: a comment that comes
    // in between must not cut the count. It moves to the bottom, so a combo in progress stays in
    // sight under the newest comments.
    const running = ([...list.children] as HTMLElement[])
      .reverse()
      .find((l) => l.dataset.key === key && Date.now() - Number(l.dataset.at) < 5000);
    if (running) {
      const total = Number(running.dataset.n) + quantity;
      running.dataset.n = String(total);
      running.dataset.at = String(Date.now());
      running.innerHTML = giftLine(sender, giftName, total, to);
      list.append(running);
      return;
    }
    chatLine(mode, giftLine(sender, giftName, quantity, to), true);
    const li = list.lastElementChild as HTMLElement;
    const side = sideColor(mode, to);
    if (side) {
      li.style.setProperty("--side", side.color);
      li.style.setProperty("--side-text", side.text);
      li.classList.add("side-gift");
    }
    li.dataset.key = key;
    li.dataset.n = String(quantity);
    li.dataset.at = String(Date.now());
  };
  const ownGift = (mode: RoomMode) => (tx: GiftTransaction) =>
    giftChat(mode, "You", tx.gift.name, tx.quantity, mode === "live" ? undefined : tx.receiver);
  /** Each stream's comment bar tray, made (closed) when first needed. */
  const armBar: Partial<Record<RoomMode, () => GiftTrayHandle | null>> = {};
  for (const mode of Object.keys(rooms) as RoomMode[]) {
    const bar = q<HTMLFormElement>(block(mode), ".live-bar");
    const input = q<HTMLInputElement>(bar, "input");
    bar.addEventListener("submit", (e) => {
      e.preventDefault();
      const text = input.value.trim();
      if (!text) return;
      chatLine(mode, `<b>You</b> ${esc(text)}`);
      input.value = "";
    });
    if (bar.hasAttribute("data-gift")) {
      const giftBtn = new GiftButton(bar, { theme, filled: true });
      barButtons.push(giftBtn);
      armBar[mode] = giftBar(
        bar,
        input,
        giftBtn,
        () => postOf(LIVE_HOST),
        () => ({
          roomId: rooms[mode].id,
          onSent: ownGift(mode),
          receivers: receiversOf(mode),
        }),
      );
    }
  }
  // Pretend viewers chat while you watch (the app's chat; the demo has no chat server).
  const COMMENTS = [
    "hiii from São Paulo 👋",
    "this is so good",
    "❤️❤️❤️",
    "first time here!",
    "lol 😂",
    "how long have you been streaming?",
    "the vibes tonight 🔥",
    "hello everyone",
  ];
  let chatter = 0;
  let room: RoomHandle | null = null;
  const modeParam = opts.get("mode");
  let liveMode: RoomMode = (Object.keys(rooms) as RoomMode[]).includes(modeParam as RoomMode)
    ? (modeParam as RoomMode)
    : "live";
  // The score bars are the SDK's: each follows the joined room by itself.
  const bars = Object.fromEntries(
    BATTLES.map((m) => [
      m,
      new GiftBattleBar(q(block(m), ".battle"), {
        resolveUsers: resolveDemoUsers,
        reducedMotion: reduced,
        theme,
        // A tap on a side opens the comment bar's tray with that side picked (spec 21.4).
        onPressSide: (id) => {
          const h = armBar[m]?.();
          h?.selectReceiver(id);
          h?.open();
        },
      }),
    ]),
  ) as Record<(typeof BATTLES)[number], GiftBattleBar>;
  const leaveRoom = (): void => {
    for (const bar of Object.values(bars)) {
      bar.update({ room: undefined });
      bar.setView(null);
    }
    room?.leave();
    room = null;
    window.clearInterval(chatter);
    for (const list of panels.live!.querySelectorAll(".live-chat")) list.replaceChildren();
  };
  const joinLive = (): void => {
    if (room) return;
    const mode = liveMode;
    const here = block(mode);
    const stateEl = q(here, ".live-state");
    const viewersEl = q(here, ".live-viewers");
    chatter = window.setInterval(() => {
      const who = watchers[Math.floor(Math.random() * watchers.length)]!;
      const text = COMMENTS[Math.floor(Math.random() * COMMENTS.length)]!;
      chatLine(mode, `<b>${esc(displayName(who))}</b> ${esc(text)}`);
    }, 2600);
    const show = (): void => {
      const st = room?.getState();
      if (!st) return;
      stateEl.textContent =
        st.status === "open"
          ? "You are in the room: everyone watching sees every gift."
          : st.status === "closed"
            ? "Left the room."
            : "Connecting...";
      viewersEl.textContent = st.viewers === null ? "..." : `${fmt(st.viewers)} watching`;
    };
    room = joinRoom({
      room: rooms[mode].id,
      getToken: async () => demoRoomToken("ava"),
      client,
      effects,
      resolveName: displayName,
      WebSocket: rooms[mode].socket,
      // Every gift of the room lands in the chat column, between the comments.
      onEvent: (e) =>
        giftChat(
          mode,
          e.sender ?? "Someone",
          e.gift.name,
          e.quantity,
          mode === "live" ? undefined : (e.receiverId ?? undefined),
        ),
      onViewers: show,
      onState: show,
    });
    if (mode !== "live") bars[mode].update({ room });
    show();
  };
  const showMode = (mode: RoomMode): void => {
    liveMode = mode;
    for (const b of panels.live!.querySelectorAll<HTMLElement>("[data-mode]"))
      b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
    for (const m of Object.keys(rooms) as RoomMode[]) block(m).hidden = m !== mode;
  };
  for (const b of panels.live!.querySelectorAll<HTMLElement>("[data-mode]"))
    b.addEventListener("click", () => {
      const mode = b.dataset.mode as RoomMode;
      if (mode === liveMode) return;
      const joined = room !== null;
      leaveRoom();
      showMode(mode);
      if (joined) joinLive();
    });
  showMode(liveMode);

  // ---- top: gifters or creators
  panels.top!.innerHTML = `<h2>Top</h2>
    <div class="seg" role="group" aria-label="Board">
      <button type="button" data-board="senders" aria-pressed="true">Top gifters</button>
      <button type="button" data-board="receivers" aria-pressed="false">Top creators</button>
    </div>
    <div class="card board-slot"></div>`;
  const board = new GiftLeaderboard(q(panels.top!, ".board-slot"), {
    client,
    resolveUsers: resolveDemoUsers,
    highlightUser: "ava",
    metricToggle: true,
    theme,
  });
  for (const b of panels.top!.querySelectorAll<HTMLButtonElement>("[data-board]")) {
    b.addEventListener("click", () => {
      for (const o of panels.top!.querySelectorAll("[data-board]"))
        o.setAttribute("aria-pressed", String(o === b));
      board.update({ board: b.dataset.board as "senders" | "receivers" });
    });
  }

  // ---- inbox: the SDK's GiftInbox (gifts received over the last 24 hours, newest first)
  panels.inbox!.innerHTML = `<h2>Inbox</h2><div class="card inbox-slot"></div>`;
  /** The newest row the person has seen: the badge counts the gifts after it (`inboxUnread`). */
  let inboxItems: InboxItem[] = [];
  let lastSeen: number | null = Date.now();
  const inbox = new GiftInbox(q(panels.inbox!, ".inbox-slot"), {
    client,
    resolveUsers: resolveDemoUsers,
    pageSize: 8,
    theme,
    onLoaded: (items) => {
      inboxItems = items;
      if (inboxOnScreen()) markInboxSeen();
      else unread = inboxUnread(items, lastSeen);
      refreshBadge();
    },
  });
  const markInboxSeen = (): void => {
    const times = inboxItems
      .filter((i) => i.status === "completed")
      .map((i) => Date.parse(i.created_at));
    if (times.length) lastSeen = Math.max(lastSeen ?? 0, ...times);
    unread = 0;
  };

  // ---- me
  panels.me!.innerHTML = `
    <div class="card">
      <div class="cover"></div>
      <div class="me-head">${avatar("ava", 84)}<div><h3>Ava Carter</h3><p>@ava</p></div></div>
      <div class="stats">
        <div><b id="me-received">${fmt(received)}</b><span>Gifts received</span></div>
        <div><b>1.2K</b><span>Followers</span></div>
        <div><b>318</b><span>Following</span></div>
      </div>
      <div class="balance"><div><small>Your coins</small><strong id="me-balance">${fmt(balance)}</strong></div><button class="btn" type="button" id="get-coins">Get coins</button></div>
      <div class="sec">Gifts received</div>
      <div class="wall-slot" id="me-wall"></div>
      <div class="row"><div>Hide me from leaderboards<small>Others will not see your rank</small></div>
        <button class="switch" type="button" role="switch" aria-checked="false" aria-label="Hide me from leaderboards" id="hide"></button></div>
    </div>`;
  addWall(q(panels.me!, "#me-wall"), "ava", undefined);
  q(app, "#get-coins").addEventListener("click", store);
  q(app, "#coin-chip").addEventListener("click", store);
  const hide = q<HTMLButtonElement>(app, "#hide");
  hide.addEventListener("click", () => {
    const on = hide.getAttribute("aria-checked") !== "true";
    hide.setAttribute("aria-checked", String(on));
    client.setHidden(on);
    board.refresh();
  });

  // ---- address options, for pages that embed the demo (giftingstack.com shows each feature):
  // ?tab=feed|live|top|inbox|me opens that tab (?mode=battle|battle4: the Live tab shows the battle, or the four-way battle), ?away=1 shows the away card now (0: never),
  // ?tray=1 opens the gift tray on the first post, ?embed=1 hides the demo's footer.
  if (opts.get("embed") === "1") document.documentElement.classList.add("embed");
  const TABS = ["feed", "live", "chat", "top", "inbox", "me"];

  // ---- tabs and layout
  let tab = TABS.includes(opts.get("tab") ?? "") ? opts.get("tab")! : "feed";
  let unread = 0;
  const inboxOnScreen = (): boolean => wide.matches || tab === "inbox";
  /** Gifts of a badge-pattern away summary that the person has not seen yet (see the away section). */
  let awayPending = 0;
  /** Called when the Inbox is on screen: the badge pattern acknowledges its summary here. */
  let awayOpened: () => void = () => {};
  const badge = q(app, "#badge");
  const refreshBadge = (): void => {
    const n = unread + awayPending;
    badge.hidden = n === 0;
    badge.textContent = String(n);
  };
  const place = (): void => {
    const isWide = wide.matches;
    const centre = tab === "me" || tab === "live" || tab === "chat" ? tab : "feed";
    // Wide: both sit in the right column; the one the page asked for (?tab=) comes first.
    for (const name of tab === "inbox" ? ["inbox", "top"] : ["top", "inbox"]) {
      const p = panels[name]!;
      if (isWide) right.append(p);
      else main.insertBefore(p, q(main, ".foot"));
    }
    for (const [name, p] of Object.entries(panels))
      p.hidden = isWide
        ? (name === "feed" || name === "me" || name === "live" || name === "chat") &&
          name !== centre
        : name !== tab;
    for (const t of app.querySelectorAll<HTMLElement>("[data-tab]")) {
      const on = t.dataset.tab === (isWide ? centre : tab);
      if (on) t.setAttribute("aria-current", "page");
      else t.removeAttribute("aria-current");
    }
    if (isWide || tab === "inbox") markInboxSeen();
    if ((isWide ? centre : tab) === "live") joinLive();
    else leaveRoom();
    awayOpened();
    refreshBadge();
    placeNoticeSoon();
  };
  for (const t of app.querySelectorAll<HTMLElement>("[data-tab]"))
    t.addEventListener("click", () => {
      tab = t.dataset.tab!;
      place();
      main.scrollTop = 0;
    });
  wide.addEventListener("change", place);
  place();

  // ---- the away data, in one of three example integrations (developer menu: "Example integration").
  // Shown the first time in this browser, then only from the menu (a real app shows it once, until
  // new gifts arrive; this demo's data resets on every load).
  const awaySeenKey = "pixel-away-seen";
  const awaySeen = ((): boolean => {
    try {
      return localStorage.getItem(awaySeenKey) === "1";
    } catch {
      return false;
    }
  })();
  const markAwaySeen = (): void => {
    try {
      localStorage.setItem(awaySeenKey, "1");
    } catch {
      // private mode: it simply shows again next time
    }
  };
  interface AwayUi {
    /** Ask the server what arrived (a summary that is still up is closed first). */
    check(): void;
    /** Live changes of theme, quality, motion (only the SDK card has any). */
    update(patch: Partial<GiftAwaySummaryOptions>): void;
    destroy(): void;
  }

  // (a) The SDK card. (c) The same card with our own body: `renderSummary` draws the inside, the SDK
  // keeps the check, names, dialog, focus, replay and acknowledgement.
  const customAwayBody = (c: AwaySummaryContext): HTMLElement => {
    const el = (tag: string, cls: string, text = ""): HTMLElement => {
      const e = c.doc.createElement(tag);
      e.className = cls;
      e.textContent = text;
      return e;
    };
    const box = el("div", "away-custom");
    const head = el("div", "away-custom-head");
    head.append(
      el("span", "away-big", String(c.summary.total_gifts)),
      el("span", "", "gifts waited for you"),
    );
    const strip = el("div", "away-custom-strip");
    for (const g of c.summary.groups.slice(0, 5)) {
      const item = el("span", "away-custom-gift");
      if (g.gift.icon_url) {
        const img = c.doc.createElement("img");
        img.src = g.gift.icon_url;
        img.alt = g.gift.name;
        item.append(img);
      }
      item.append(el("small", "", `x${g.count}`));
      strip.append(item);
    }
    const top = c.senders[0];
    const who = el("p", "away-custom-who", top ? `Most from ${top.name}` : c.headline);
    const thanks = el("button", "btn", "Say thanks") as HTMLButtonElement;
    thanks.type = "button";
    thanks.addEventListener("click", c.dismiss);
    box.append(head, strip, who, thanks);
    return box;
  };
  const sdkAway = (custom: boolean, autoCheck: boolean): AwayUi => {
    const card = new GiftAwaySummary(app, {
      client,
      effects,
      resolveUsers: resolveDemoUsers,
      theme,
      quality,
      reducedMotion: reduced,
      autoCheck,
      renderSummary: custom ? customAwayBody : undefined,
      onShow: markAwaySeen,
    });
    return {
      check: () => void card.check(),
      update: (patch) => card.update(patch),
      destroy: () => card.destroy(),
    };
  };

  // (b) Badge on Inbox plus a plain box: no SDK card, only the headless controller. `ackOn: "manual"`
  // and no `start()`: it stops at `ready`; the cursor moves when the Inbox is opened.
  const awayBox = document.createElement("div");
  awayBox.className = "card away-box";
  awayBox.hidden = true;
  panels.inbox!.querySelector("h2")!.after(awayBox);
  const badgeAway = (autoCheck: boolean): AwayUi => {
    const ctl = new AwayController({ client, ackOn: "manual" });
    let seen = false;
    const draw = (): void => {
      const { status, summary } = ctl.getState();
      if (status === "loading") seen = false;
      const ready = status === "ready" && !!summary;
      awayPending = ready && !seen ? summary.total_gifts : 0;
      awayBox.hidden = !ready;
      if (ready) {
        const items = summary.groups
          .map(
            (g) =>
              `<li><img src="${esc(g.gift.icon_url ?? "")}" alt="" /><span>${g.count} x ${esc(g.gift.name)}</span><small>${g.sender_count} ${g.sender_count === 1 ? "person" : "people"}</small></li>`,
          )
          .join("");
        const from = summary.top_senders
          .slice(0, 3)
          .map((t) => (t.user === null ? "Someone" : firstName(t.user)))
          .join(", ");
        awayBox.innerHTML = `<h3>While you were away</h3><p>${summary.total_gifts} gifts from ${summary.sender_count} people${from ? `, most from ${esc(from)}` : ""}</p><ul>${items}</ul><button class="btn" type="button">Got it</button>`;
        awayBox.querySelector("button")!.addEventListener("click", () => {
          void ctl.ack();
          ctl.dismiss();
        });
      }
      refreshBadge();
    };
    const unsubscribe = ctl.subscribe(() => {
      draw();
      awayOpened();
    });
    awayOpened = (): void => {
      if (!(wide.matches || tab === "inbox")) return;
      if (ctl.getState().status !== "ready" || seen) return;
      seen = true;
      void ctl.ack();
      markAwaySeen();
      draw();
    };
    if (autoCheck) void ctl.check();
    return {
      check: () => {
        ctl.dismiss();
        void ctl.check();
      },
      update: () => {},
      destroy: () => {
        unsubscribe();
        ctl.dispose();
        awayOpened = () => {};
        awayBox.hidden = true;
        awayPending = 0;
        refreshBadge();
      },
    };
  };

  const mountAway = (pattern: AwayPattern, autoCheck: boolean): AwayUi =>
    pattern === "badge" ? badgeAway(autoCheck) : sdkAway(pattern === "custom", autoCheck);
  const awayOpt = opts.get("away");
  let awayUi = mountAway("card", awayOpt === "1" ? true : awayOpt === "0" ? false : !awaySeen);

  // ---- incoming gifts
  const deliver = (inc: Incoming, withSender?: string): void => {
    const sender = withSender ?? inc.sender;
    const g = inc.gift;
    effects.play({
      gift: { id: g.id, name: g.name, price: g.price, image: g.animation_url, icon: g.icon_url },
      sender: displayName(sender),
      quantity: inc.quantity,
    });
    client.addToWall("ava", g.id, inc.quantity);
    received += inc.quantity;
    const n = document.getElementById("me-received");
    if (n) n.textContent = fmt(received);
    client.addToInbox(sender, g.id, inc.quantity);
    inbox.refresh();
    const mine = walls.find((w) => w.user === "ava");
    if (mine) mine.wall.update({ refreshKey: ++mine.key });
  };
  // Off by default (a gift that arrives by itself confuses a test): add ?live to the address
  // to see the app as a live feed, with a gift from someone else every 20-40 s.
  if (new URLSearchParams(location.search).has("live")) {
    startIncoming({
      gifts,
      senders: SENDERS,
      onGift: (inc) => {
        if (!offline) deliver(inc);
      },
    });
  }

  // ---- the hidden developer menu
  const chosen = (mode: IncomingMode): Gift => {
    const byPrice = [...gifts].sort((a, b) => a.price - b.price);
    if (mode === "cheapest") return byPrice[0]!;
    if (mode === "priciest") return byPrice.at(-1)!;
    if (mode === "random") return gifts[Math.floor(Math.random() * gifts.length)]!;
    return handle?.tray.getSelected() ?? gifts.find((g) => g.id === selectedId) ?? gifts[0]!;
  };
  const menu = createDevMenu(app, {
    playIncoming: (mode) => {
      const base = pickIncoming(gifts, SENDERS, Math.random);
      deliver({ ...base, gift: chosen(mode), quantity: 1 });
    },
    combo: (mode) => {
      const base = pickIncoming(gifts, SENDERS, Math.random);
      const gift = chosen(mode);
      for (let i = 0; i < 5; i++)
        setTimeout(() => deliver({ ...base, gift, quantity: 1 }, base.sender), i * 250);
    },
    awayAgain: () => {
      client.rearmAway();
      awayUi.check();
    },
    wallPlus: () => {
      for (const p of POSTS) client.addToWall(p.author, chosen("random").id, 5, p.id);
      client.addToWall("ava", chosen("random").id, 5);
      refreshWalls();
    },
    setAwayPattern: (p) => {
      awayUi.destroy();
      awayUi = mountAway(p, false);
      // The summary was acknowledged by the last pattern: bring the data back for this one.
      client.rearmAway();
      awayUi.check();
    },
    setQuality: (v) => {
      quality = v;
      effects.setOptions({ quality });
      awayUi.update({ quality });
    },
    setTheme: (name) => {
      theme = THEMES[name];
      document.documentElement.dataset.theme = name;
      app.dataset.theme = name;
      effects.setOptions({ theme });
      handle?.tray.update({ theme });
      for (const b of barButtons) b.update({ theme });
      for (const w of walls) w.wall.update({ theme });
      board.update({ theme });
      inbox.update({ theme });
      awayUi.update({ theme });
      for (const bar of Object.values(bars)) bar.update({ theme });
    },
    setMotion: (m) => {
      reduced = m === "reduced" ? true : undefined;
      effects.setOptions({ reducedMotion: reduced });
      awayUi.update({ reducedMotion: reduced });
      for (const bar of Object.values(bars)) bar.update({ reducedMotion: reduced });
    },
    reset: () => {
      closeTray();
      client.reset();
      received = 214;
      q(app, "#me-received").textContent = fmt(received);
      hide.setAttribute("aria-checked", "false");
      lastSeen = Date.now();
      unread = 0;
      inbox.refresh();
      refreshWalls();
      board.refresh();
      void syncBalance();
      awayUi.check();
    },
    setOffline: (on) => {
      offline = on;
      client.setOffline(on);
      banner.hidden = !on;
      if (!on) {
        refreshWalls();
        board.refresh();
        void syncBalance();
        void handle?.refresh();
      }
    },
  });
  attachDevTrigger(q(app, "#logo"), () => menu.open());
  // ?tray=1: the first post's gift tray, open, as if the person tapped Gift.
  if (opts.get("tray") === "1" && tab === "feed")
    setTimeout(() => app.querySelector<HTMLButtonElement>(".post .gift")?.click(), 500);
}

void main();
