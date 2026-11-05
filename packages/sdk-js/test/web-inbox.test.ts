import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftingClient,
  GiftingError,
  type Inbox,
  type InboxItem,
  type InboxQuery,
} from "../src/core";
import { GiftInbox, type GiftInboxOptions } from "../src/web";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const NOW = Date.parse("2026-11-02T10:00:00.000Z");
const item = (id: string, over: Partial<InboxItem> = {}): InboxItem => ({
  id,
  created_at: "2026-11-02T09:58:00.000Z",
  sender: "ayla",
  gift: { id: "rose", name: "Rose", price: 10, icon_url: null, animation_url: null },
  quantity: 1,
  units: 10,
  status: "completed",
  ...over,
});
const body = (data: InboxItem[], more: string | null = null): Inbox => ({
  user: "me",
  since: "2026-11-01T10:00:00.000Z",
  until: "2026-11-02T10:00:00.000Z",
  data,
  has_more: more !== null,
  next_cursor: more,
});

function fakeClient(answer: (q: InboxQuery) => Inbox | Error) {
  const getInbox = vi.fn<GiftingClient["getInbox"]>(async (q = {}) => {
    const r = answer(q);
    if (r instanceof Error) throw r;
    return r;
  });
  const client: GiftingClient = {
    getGifts: async () => [],
    getMe: async () => ({ user: "me", balance: 0 }),
    getReceivedGifts: async () => [],
    sendGift: async () => {
      throw new Error("not used");
    },
    ...componentCallStubs,
    getInbox,
  };
  return { client, getInbox };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;
let made: GiftInbox[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS, "setInterval", "clearInterval"] });
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  for (const b of made) b.destroy();
  made = [];
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const mk = (options: GiftInboxOptions) => {
  const b = new GiftInbox(page, { now: () => NOW, ...options });
  made.push(b);
  return b;
};
const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const $ = (sel: string) => page.querySelector(sel) as HTMLElement;
const $$ = (sel: string) => [...page.querySelectorAll<HTMLElement>(sel)];
const rows = () => $$(".gs-rows > li");

describe("web GiftInbox", () => {
  it("loads the first page with the page size, newest first", async () => {
    const { client, getInbox } = fakeClient(() =>
      body([item("g2", { created_at: "2026-11-02T09:59:30.000Z" }), item("g1")]),
    );
    mk({ client, pageSize: 7 });
    expect($$(".gs-row-skeleton").length).toBeGreaterThan(0);
    expect(getInbox).toHaveBeenCalledWith({ limit: 7 });
    await advance(0);
    expect(rows().map((r) => r.dataset.gsInboxRow)).toEqual(["g2", "g1"]);
  });

  it("the default page size is 20", async () => {
    const { client, getInbox } = fakeClient(() => body([]));
    mk({ client });
    await advance(0);
    expect(getInbox).toHaveBeenCalledWith({ limit: 20 });
  });

  it("a row is one element with the full sentence and the time", async () => {
    const { client } = fakeClient(() =>
      body([item("g1", { quantity: 3, created_at: "2026-11-02T07:00:00.000Z" }), item("g2")]),
    );
    mk({ client, resolveUsers: async () => ({ ayla: { name: "Ayla K." } }) });
    await advance(0);
    await advance(0);
    const [first, second] = rows();
    expect(first!.getAttribute("aria-label")).toBe("Ayla K. sent you Rose x3, 3h");
    expect(second!.getAttribute("aria-label")).toBe("Ayla K. sent you Rose, 2m");
    expect(first!.querySelector("b")!.textContent).toBe("Ayla K.");
    expect(first!.querySelector(".gs-row-main")!.getAttribute("aria-hidden")).toBe("true");
    expect(first!.querySelector("time")!.textContent).toBe("3h");
    expect(first!.querySelector(".gs-avatar-letter")!.textContent).toBe("A");
    // No "xN" for a single gift.
    expect(second!.querySelector(".gs-inbox-text")!.textContent).toBe("Ayla K. sent you Rose");
  });

  it("shows the gift icon, and Someone for a deleted sender, the id when unnamed", async () => {
    const { client } = fakeClient(() =>
      body([
        item("g1", {
          sender: null,
          gift: {
            id: "r",
            name: "Rose",
            price: 1,
            icon_url: "https://x.test/r.webp",
            animation_url: null,
          },
        }),
        item("g2", { sender: "user_42" }),
      ]),
    );
    mk({ client });
    await advance(0);
    const [a, b] = rows();
    expect(a!.getAttribute("aria-label")).toBe("Someone sent you Rose, 2m");
    expect(a!.querySelector("img.gs-chip-icon")!.getAttribute("src")).toBe("https://x.test/r.webp");
    expect(b!.getAttribute("aria-label")).toBe("user_42 sent you Rose, 2m");
  });

  it("hides reversed gifts", async () => {
    const { client } = fakeClient(() => body([item("g1", { status: "reversed" }), item("g2")]));
    mk({ client });
    await advance(0);
    expect(rows().map((r) => r.dataset.gsInboxRow)).toEqual(["g2"]);
  });

  it("empty shows the text", async () => {
    const { client } = fakeClient(() => body([]));
    mk({ client });
    await advance(0);
    expect($(".gs-board-empty").textContent).toBe("No gifts in the last 24 hours");
  });

  it("error shows the message and Try again reloads", async () => {
    let fail = true;
    const { client, getInbox } = fakeClient(() =>
      fail ? new GiftingError(500, "server_error", "boom") : body([item("g1")]),
    );
    const onError = vi.fn();
    mk({ client, onError });
    await advance(0);
    expect($(".gs-board-message").textContent).toBe("Could not load gifts");
    expect(onError).toHaveBeenCalledTimes(1);
    fail = false;
    $(".gs-retry").click();
    await advance(0);
    expect(getInbox).toHaveBeenCalledTimes(2);
    expect(rows()).toHaveLength(1);
  });

  it("Show more appends the next page with the cursor and disappears at the end", async () => {
    const { client, getInbox } = fakeClient((q) =>
      q.cursor === "c1" ? body([item("g2")]) : body([item("g1")], "c1"),
    );
    mk({ client, pageSize: 1 });
    await advance(0);
    expect($(".gs-inbox-more").textContent).toBe("Show more");
    $(".gs-inbox-more").click();
    await advance(0);
    expect(getInbox).toHaveBeenLastCalledWith({ cursor: "c1", limit: 1 });
    expect(rows().map((r) => r.dataset.gsInboxRow)).toEqual(["g1", "g2"]);
    expect(page.querySelector(".gs-inbox-more")).toBeNull();
  });

  it("onLoaded gets every loaded item, reversed ones included", async () => {
    const { client } = fakeClient((q) =>
      q.cursor ? body([item("g2")]) : body([item("g1", { status: "reversed" })], "c1"),
    );
    const onLoaded = vi.fn();
    mk({ client, onLoaded });
    await advance(0);
    expect(onLoaded.mock.calls[0]![0].map((i: InboxItem) => i.id)).toEqual(["g1"]);
    $(".gs-inbox-more").click();
    await advance(0);
    expect(onLoaded.mock.calls[1]![0].map((i: InboxItem) => i.id)).toEqual(["g1", "g2"]);
  });

  it("refresh() reloads from the first page and keeps the rows meanwhile", async () => {
    let n = 0;
    const { client, getInbox } = fakeClient(() => body([item(`g${++n}`)]));
    const box = mk({ client });
    await advance(0);
    expect(rows()[0]!.dataset.gsInboxRow).toBe("g1");
    box.refresh();
    expect(rows()).toHaveLength(1);
    await advance(0);
    expect(getInbox).toHaveBeenCalledTimes(2);
    expect(getInbox).toHaveBeenLastCalledWith({ limit: 20 });
    expect(rows().map((r) => r.dataset.gsInboxRow)).toEqual(["g2"]);
  });

  it("labels can be translated", async () => {
    const { client } = fakeClient(() => body([item("g1", { quantity: 2 })]));
    mk({
      client,
      labels: { inboxSentMany: "{name} -> {gift} (x{n})", inboxSpoken: "{sentence} / {time}" },
    });
    await advance(0);
    expect(rows()[0]!.getAttribute("aria-label")).toBe("ayla -> Rose (x2) / 2m");
  });

  it("destroy removes it and ignores a late answer", async () => {
    const { client } = fakeClient(() => body([item("g1")]));
    const box = mk({ client });
    box.destroy();
    await advance(0);
    expect(page.querySelector("[data-gs-inbox]")).toBeNull();
  });
});
