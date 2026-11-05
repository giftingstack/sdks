import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftingClient,
  GiftingError,
  type Inbox,
  type InboxItem,
  type InboxQuery,
} from "../src/core";
import { GiftInbox, type GiftInboxHandle } from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";

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

function clientWith(answer: (q: InboxQuery) => Inbox | Error) {
  const get = vi.fn(async (q: InboxQuery = {}) => {
    const r = answer(q);
    if (r instanceof Error) throw r;
    return r;
  });
  return { ...(componentCallStubs as object), getInbox: get, get } as unknown as GiftingClient & {
    get: typeof get;
  };
}

let restoreLayout = () => {};
beforeEach(() => {
  restoreLayout = installPhoneLayout();
  vi.useFakeTimers({
    toFake: [
      "setTimeout",
      "clearTimeout",
      "setInterval",
      "clearInterval",
      "requestAnimationFrame",
      "cancelAnimationFrame",
      "performance",
      "Date",
    ],
  });
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  restoreLayout();
});
async function advance(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}
async function open(ui: React.ReactElement) {
  const r = render(ui);
  await advance(0);
  return r;
}

describe("GiftInbox", () => {
  it("shows skeleton rows while loading, then the rows newest first, with the page size", async () => {
    let release!: (b: Inbox) => void;
    const client = clientWith(() => new Promise<Inbox>((r) => (release = r)) as never);
    render(<GiftInbox client={client} pageSize={7} now={() => NOW} />);
    expect(screen.getAllByTestId("gift-inbox-skeleton-row").length).toBeGreaterThan(0);
    expect(client.get).toHaveBeenCalledWith({ limit: 7 });
    await act(async () => release(body([item("g2"), item("g1")])));
    expect(screen.queryByTestId("gift-inbox-skeleton-row")).toBeNull();
    const rows = screen.getAllByTestId(/gift-inbox-row-/).map((r) => r.dataset.testid);
    expect(rows).toEqual(["gift-inbox-row-g2", "gift-inbox-row-g1"]);
  });

  it("a row is one element with the sentence and the time, xN only above 1", async () => {
    const client = clientWith(() =>
      body([
        item("g1", { quantity: 3, created_at: "2026-11-02T07:00:00.000Z" }),
        item("g2", { sender: null }),
        item("g3", { sender: "user_42" }),
      ]),
    );
    await open(
      <GiftInbox
        client={client}
        now={() => NOW}
        resolveUsers={async () => ({ ayla: { name: "Ayla K." } })}
      />,
    );
    await advance(0);
    expect(screen.getByTestId("gift-inbox-row-g1").getAttribute("aria-label")).toBe(
      "Ayla K. sent you Rose x3, 3h",
    );
    expect(screen.getByTestId("gift-inbox-row-g2").getAttribute("aria-label")).toBe(
      "Someone sent you Rose, 2m",
    );
    expect(screen.getByTestId("gift-inbox-row-g3").getAttribute("aria-label")).toBe(
      "user_42 sent you Rose, 2m",
    );
  });

  it("hides reversed gifts", async () => {
    const client = clientWith(() => body([item("g1", { status: "reversed" }), item("g2")]));
    await open(<GiftInbox client={client} now={() => NOW} />);
    expect(screen.queryByTestId("gift-inbox-row-g1")).toBeNull();
    expect(screen.getByTestId("gift-inbox-row-g2")).toBeTruthy();
  });

  it("empty shows the text", async () => {
    await open(<GiftInbox client={clientWith(() => body([]))} />);
    expect(screen.getByText("No gifts in the last 24 hours")).toBeTruthy();
  });

  it("error shows the message; Try again reloads", async () => {
    let fail = true;
    const client = clientWith(() =>
      fail ? new GiftingError(500, "server_error", "boom") : body([item("g1")]),
    );
    const onError = vi.fn();
    await open(<GiftInbox client={client} onError={onError} now={() => NOW} />);
    expect(screen.getByText("Could not load gifts")).toBeTruthy();
    expect(onError).toHaveBeenCalledTimes(1);
    fail = false;
    fireEvent.click(screen.getByText("Try again"));
    await advance(0);
    expect(screen.getByTestId("gift-inbox-row-g1")).toBeTruthy();
  });

  it("Show more appends the next page and goes away at the end; onLoaded gets all items", async () => {
    const client = clientWith((q) =>
      q.cursor === "c1" ? body([item("g2")]) : body([item("g1")], "c1"),
    );
    const onLoaded = vi.fn();
    await open(<GiftInbox client={client} pageSize={1} onLoaded={onLoaded} now={() => NOW} />);
    fireEvent.click(screen.getByText("Show more"));
    await advance(0);
    expect(client.get).toHaveBeenLastCalledWith({ cursor: "c1", limit: 1 });
    expect(screen.getAllByTestId(/gift-inbox-row-/)).toHaveLength(2);
    expect(screen.queryByText("Show more")).toBeNull();
    expect(onLoaded.mock.calls.at(-1)![0].map((i: InboxItem) => i.id)).toEqual(["g1", "g2"]);
  });

  it("the handle's refresh() reloads from the first page", async () => {
    let n = 0;
    const client = clientWith(() => body([item(`g${++n}`)]));
    const ref = createRef<GiftInboxHandle>();
    await open(<GiftInbox ref={ref} client={client} now={() => NOW} />);
    expect(screen.getByTestId("gift-inbox-row-g1")).toBeTruthy();
    act(() => ref.current!.refresh());
    await advance(0);
    expect(client.get).toHaveBeenLastCalledWith({ limit: 20 });
    expect(screen.getByTestId("gift-inbox-row-g2")).toBeTruthy();
    expect(screen.queryByTestId("gift-inbox-row-g1")).toBeNull();
  });
});
