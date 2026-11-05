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
  const right = q(app, "#right");
  const banner = q(app, "#banner");
  const panels = Object.fromEntries(
    ["feed", "live", "top", "inbox", "me"].map((n) => [n, q(app, `[data-panel="${n}"]`)]),
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
    effects.setOptions({ noticeBottom: baseNotice() });
  };
  const store = (): void =>
    void openCoinStore(app, (coins) => {
      client.credit(coins);
      void syncBalance();
      void handle?.refresh();
    });
  const openTray = (post: Post, anchor: HTMLElement, giftId?: string, roomId?: string): void => {
    const sheet = app.clientWidth < 600;
    if (handle && anchorOf === anchor && !giftId) {
      // The popover anchor's own click closes it; on a phone the Gift button toggles the sheet.
      if (sheet) handle.toggle();
      return;
    }
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
      effects,
      theme,
      anchor,
      defaultSelectedId: giftId ?? selectedId,
      onTopUp: store,
      onInsetChange: (px) => {
        effects.setOptions({ noticeBottom: px > 0 ? px + 16 : baseNotice() });
        // The page keeps its Gift button above the sheet: room for the sheet, and the button in view.
        app.style.setProperty("--tray-inset", `${sheet ? px : 0}px`);
        if (sheet && px > 0) anchor.scrollIntoView({ block: "nearest", behavior: "smooth" });
      },
      // A pick makes the tray small everywhere; the SDK draws the dim and closes on a tap on it.
      collapseOnSelect: true,
      scrim: true,
      scrimTap: "dismiss",
      onOpenChange: (open) => {
        if (!open) queueMicrotask(() => handle === h && closeTray());
      },
      onSent: (tx: GiftTransaction) => {
        setBalance(tx.sender_balance_after);
        const w = walls.find((x) => x.user === tx.receiver && x.reference === tx.reference);
        if (w) w.wall.update({ refreshKey: ++w.key });
        // The tray stays open after a send, like a live app: tap again for a combo, the Gift
        // button again to close it.
      },
    });
    handle = h;
    if (!sheet) h.tray.open();
  };

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
  const livePost: Post = {
    id: "live-1",
    author: LIVE_HOST,
    text: "Evening stream",
    art: "neon",
    ago: "live",
    likes: 0,
  };
  const rivalPost: Post = { ...livePost, author: LIVE_RIVAL };
  const watchers = SENDERS.filter((id) => id !== LIVE_HOST && id !== LIVE_RIVAL);
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
  } as const;
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
  const sideButton = (id: string): string =>
    `<button class="pill gift" type="button" data-side="${id}">${GIFT_ICON}Gift ${esc(firstName(id))}</button>`;
  const stage = (): string =>
    `<div class="live-stage"><div class="art">${postArt(livePost)}</div>
        <span class="live-tag">LIVE</span><span class="live-viewers">...</span></div>`;
  panels.live!.innerHTML = `<h2>Live</h2>
    <div class="seg" role="group" aria-label="Stream">
      <button type="button" data-mode="live" aria-pressed="true">Live room</button>
      <button type="button" data-mode="battle" aria-pressed="false">Battle</button>
    </div>
    <article class="card" data-block="live">
      ${stage()}
      <div class="post-head">${avatar(LIVE_HOST)}<div><b>${esc(firstName(LIVE_HOST))}</b><small>Evening stream</small></div></div>
      <p class="live-state">Connecting...</p>
      <div class="post-actions">${sideButton(LIVE_HOST)}</div>
      <ul class="room-feed"></ul>
    </article>
    <article class="card" data-block="battle" hidden>
      ${stage()}
      <div class="post-head">${avatar(LIVE_HOST)}<div><b>${esc(firstName(LIVE_HOST))} vs ${esc(firstName(LIVE_RIVAL))}</b><small>Evening stream battle</small></div></div>
      <div class="battle"></div>
      <p class="live-state">Connecting...</p>
      <div class="post-actions">${sideButton(LIVE_HOST)}${sideButton(LIVE_RIVAL)}</div>
      <ul class="room-feed"></ul>
    </article>`;
  const block = (mode: RoomMode): HTMLElement => q(panels.live!, `[data-block="${mode}"]`);
  for (const mode of Object.keys(rooms) as RoomMode[]) {
    for (const b of block(mode).querySelectorAll<HTMLButtonElement>("[data-side]")) {
      const post = b.dataset.side === LIVE_RIVAL ? rivalPost : livePost;
      b.addEventListener("click", () => openTray(post, b, undefined, rooms[mode].id));
    }
  }
  let room: RoomHandle | null = null;
  let liveMode: RoomMode = opts.get("mode") === "battle" ? "battle" : "live";
  // The score bar is the SDK's: it follows the joined room by itself.
  const battleBar = new GiftBattleBar(q(block("battle"), ".battle"), {
    resolveUsers: resolveDemoUsers,
    reducedMotion: reduced,
    theme,
  });
  const leaveRoom = (): void => {
    battleBar.update({ room: undefined });
    battleBar.setView(null);
    room?.leave();
    room = null;
  };
  const joinLive = (): void => {
    if (room) return;
    const mode = liveMode;
    const here = block(mode);
    const stateEl = q(here, ".live-state");
    const viewersEl = q(here, ".live-viewers");
    const feed = q(here, ".room-feed");
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
      onEvent: (e) => {
        const li = document.createElement("li");
        const to = e.receiverId && mode === "battle" ? ` to ${esc(firstName(e.receiverId))}` : "";
        li.innerHTML = `<b>${esc(e.sender ?? "Someone")}</b> sent ${e.quantity > 1 ? `${e.quantity} x ` : ""}${esc(e.gift.name)}${to}`;
        feed.prepend(li);
        while (feed.children.length > 30) feed.lastElementChild?.remove();
      },
      onViewers: show,
      onState: show,
    });
    if (mode === "battle") battleBar.update({ room });
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
  // ?tab=feed|live|top|inbox|me opens that tab (?mode=battle: the Live tab shows the battle), ?away=1 shows the away card now (0: never),
  // ?tray=1 opens the gift tray on the first post, ?embed=1 hides the demo's footer.
  if (opts.get("embed") === "1") document.documentElement.classList.add("embed");
  const TABS = ["feed", "live", "top", "inbox", "me"];

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
    const centre = tab === "me" ? "me" : tab === "live" ? "live" : "feed";
    // Wide: both sit in the right column; the one the page asked for (?tab=) comes first.
    for (const name of tab === "inbox" ? ["inbox", "top"] : ["top", "inbox"]) {
      const p = panels[name]!;
      if (isWide) right.append(p);
      else main.insertBefore(p, q(main, ".foot"));
    }
    for (const [name, p] of Object.entries(panels))
      p.hidden = isWide
        ? (name === "feed" || name === "me" || name === "live") && name !== centre
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
    if (!handle) effects.setOptions({ noticeBottom: baseNotice() });
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
      for (const w of walls) w.wall.update({ theme });
      board.update({ theme });
      inbox.update({ theme });
      awayUi.update({ theme });
      battleBar.update({ theme });
    },
    setMotion: (m) => {
      reduced = m === "reduced" ? true : undefined;
      effects.setOptions({ reducedMotion: reduced });
      awayUi.update({ reducedMotion: reduced });
      battleBar.update({ reducedMotion: reduced });
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
