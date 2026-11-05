/**
 * App callbacks `onSent` / `onError` run outside the send's failure handling: a callback that
 * throws must not refund a charged send nor turn it into an error (audit R-14).
 */
import { describe, expect, it, vi } from "vitest";
import {
  GiftTrayController,
  GiftingError,
  type Gift,
  type GiftTransaction,
  type GiftingClient,
} from "../src/core";

const ROSE = {
  id: "rose",
  name: "Rose",
  description: null,
  price: 100,
  icon_url: null,
  animation_url: null,
  sort_order: 1,
} as Gift;

const TX: GiftTransaction = {
  id: "gtx_1",
  sender: "alice",
  receiver: "bob",
  gift: { id: "rose", name: "Rose", icon_url: null },
  quantity: 1,
  unit_price: 100,
  total: 100,
  message: null,
  reference: null,
  status: "completed",
  created_at: "2026-10-10T00:00:00.000Z",
  sender_balance_after: 900,
};

function setup(sendGift: GiftingClient["sendGift"], callbacks: object) {
  let balance = 1000;
  const client = {
    getGifts: async () => [ROSE],
    getMe: async () => ({ user: "alice", balance, livemode: true }),
    sendGift: async (...args: Parameters<GiftingClient["sendGift"]>) => {
      const tx = await sendGift(...args);
      balance -= 100;
      return tx;
    },
  } as unknown as GiftingClient;
  const tray = new GiftTrayController({ client, receiver: "bob", ...callbacks });
  return tray;
}

describe("tray callbacks never undo a charged send", () => {
  it("a throwing onSent keeps the balance charged and sets no error", async () => {
    const onSent = vi.fn(() => {
      throw new Error("app bug");
    });
    const tray = setup(async () => TX, { onSent });
    await tray.refresh();
    await expect(tray.send(ROSE)).resolves.toBeUndefined();
    expect(onSent).toHaveBeenCalledTimes(1);
    expect(tray.getState().balance).toBe(900);
    expect(tray.getState().error).toBeNull();
  });

  it("a throwing onSent does not call onError", async () => {
    const onError = vi.fn();
    const tray = setup(async () => TX, {
      onSent: () => {
        throw new Error("app bug");
      },
      onError,
    });
    await tray.refresh();
    await tray.send(ROSE);
    expect(onError).not.toHaveBeenCalled();
  });

  it("a throwing effect layer on a playOn success send does not refund either", async () => {
    const tray = setup(async () => TX, {
      playOn: "success",
      effects: () => ({
        play: () => {
          throw new Error("renderer bug");
        },
        cancel: () => {},
      }),
    });
    await tray.refresh();
    await tray.send(ROSE);
    expect(tray.getState().balance).toBe(900);
    expect(tray.getState().error).toBeNull();
  });

  it("a throwing onError is ignored and the refund still happens", async () => {
    const failure = new GiftingError(500, "internal_error", "boom");
    const onError = vi.fn(() => {
      throw new Error("app bug");
    });
    const tray = setup(async () => Promise.reject(failure), { onError });
    await tray.refresh();
    await expect(tray.send(ROSE)).resolves.toBeUndefined();
    expect(onError).toHaveBeenCalledTimes(1);
    expect(tray.getState().balance).toBe(1000);
    expect(tray.getState().error).toBe(failure);
  });
});
