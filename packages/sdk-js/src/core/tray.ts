/**
 * Everything a gift tray does besides drawing, without a framework: loads the catalog and the
 * balance, sends gifts, keeps the balance right while the person taps fast (combos) and plays
 * the effect for each gift. React Native's `useGiftTray` is a thin wrapper around it.
 */
import { GiftingError, type GiftingClient } from "./client";
import type { Gift, GiftEffectEvent, GiftEffectReceiver, GiftTransaction } from "./types";

/** The part of an effect layer the tray needs. */
export interface EffectPlayer {
  play(event: GiftEffectEvent): number;
  cancel(id: number): void;
}

export interface GiftTrayControllerOptions {
  client: GiftingClient;
  /** Who gets the gifts: the owner of the post or profile on screen. */
  receiver: string;
  /** Returns the effect layer that shows each gift, if there is one right now. */
  effects?: () => EffectPlayer | null | undefined;
  /** `"tap"` (default): play at the tap, take back on failure. `"success"`: play after the server. */
  playOn?: "tap" | "success";
  /** Your own context id, for example the post id. Saved with each gift. */
  reference?: string;
  /** Room on screen (SPEC 17.1): every send names it, so the room's viewers see the gift. */
  roomId?: string;
  /**
   * In a battle, the side a receiver is on (`room.receiverFor`, SPEC 18.4): the user's own gift
   * then says who got it, like the room's gifts of the others. Undefined outside a battle.
   */
  receiverOf?: (receiver: string) => GiftEffectReceiver | undefined;
  onSent?: (transaction: GiftTransaction) => void;
  onError?: (error: GiftingError) => void;
  /** Starts downloading a picture. Called for every icon and big picture once the catalog loads. */
  prefetch?: (url: string) => void;
}

export interface GiftTrayState {
  gifts: Gift[];
  balance: number;
  /** The signed-in user, as named by the token. */
  user: string | null;
  loading: boolean;
  /** The last problem: loading failed, or the last send failed. Cleared by the next success. */
  error: GiftingError | null;
  /** The server said the token is a test token (`me.livemode === false`): show "Test mode". */
  testMode: boolean;
}

/** Any failure as a `GiftingError`. Anything else becomes status 0, `unknown_error`. */
export function asGiftingError(err: unknown): GiftingError {
  return err instanceof GiftingError
    ? err
    : new GiftingError(
        0,
        "unknown_error",
        err instanceof Error ? err.message : "Something went wrong.",
      );
}

export class GiftTrayController {
  private options: GiftTrayControllerOptions;
  private state: GiftTrayState = {
    gifts: [],
    balance: 0,
    user: null,
    loading: true,
    error: null,
    testMode: false,
  };
  private readonly listeners = new Set<() => void>();
  /** Sends that have not finished yet. */
  private pending = 0;
  private alive = true;

  constructor(options: GiftTrayControllerOptions) {
    this.options = options;
  }

  /** Callbacks and settings are read when used, so they can change between calls. */
  setOptions(options: GiftTrayControllerOptions): void {
    this.options = options;
  }

  getState = (): GiftTrayState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /** The screen is (back) on. */
  attach(): void {
    this.alive = true;
  }

  /** The screen is gone: answers that arrive later change nothing. */
  dispose(): void {
    this.alive = false;
  }

  private set(patch: Partial<GiftTrayState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of this.listeners) l();
  }

  /** Reload the catalog and the balance, for example after the person buys coins. */
  refresh = async (): Promise<void> => {
    const { client } = this.options;
    try {
      const [list, me] = await Promise.all([client.getGifts(), client.getMe()]);
      if (!this.alive) return;
      // Download the small icons now, while nobody is waiting. A gift's big picture
      // (`animation_url`) is fetched lazily: the tray warms the selected gift's and the effect
      // layer loads the others when they play (SPEC 8, audit R-08).
      for (const g of list) {
        if (g.icon_url) this.options.prefetch?.(g.icon_url);
      }
      this.set({
        gifts: [...list].sort((a, b) => a.sort_order - b.sort_order),
        balance: me.balance,
        user: me.user,
        error: null,
        testMode: me.livemode === false,
      });
    } catch (err) {
      if (this.alive) this.set({ error: asGiftingError(err) });
    } finally {
      if (this.alive) this.set({ loading: false });
    }
  };

  /** After a burst of taps the server's number is the truth. */
  private async reconcile(client: GiftingClient): Promise<void> {
    try {
      const me = await client.getMe();
      if (this.alive && this.pending === 0) this.set({ balance: me.balance });
    } catch {
      // The optimistic number stays; the next send or refresh corrects it.
    }
  }

  send = async (gift: Gift): Promise<void> => {
    const { client, receiver, reference, effects } = this.options;
    const user = this.state.user;
    this.pending++;
    // Take the coins at once so the number moves with every tap.
    this.set({ balance: this.state.balance - gift.price });
    const show = (sender: string, quantity: number) => {
      let battleReceiver: GiftEffectReceiver | undefined;
      try {
        battleReceiver = this.options.receiverOf?.(receiver);
      } catch {
        battleReceiver = undefined; // app code: never let it break a send
      }
      return effects?.()?.play({
        gift: {
          id: gift.id,
          name: gift.name,
          price: gift.price,
          image: gift.animation_url ?? gift.icon_url,
          icon: gift.icon_url,
        },
        sender,
        quantity,
        ...(battleReceiver ? { receiver: battleReceiver } : {}),
      });
    };
    const early = (this.options.playOn ?? "tap") === "tap";
    const shownId = early ? show(user ?? "You", 1) : undefined;
    try {
      const roomId = this.options.roomId;
      const tx = await client.sendGift(
        roomId
          ? { receiver, giftId: gift.id, reference, roomId }
          : { receiver, giftId: gift.id, reference },
      );
      if (!this.alive) return;
      this.set({ error: null });
      // App code from here on: a throwing callback must never look like a failed send (the coins
      // are spent), so it must not reach the catch below that refunds the optimistic balance.
      if (!early) safe(() => show(user ?? tx.sender, tx.quantity));
      safe(() => this.options.onSent?.(tx));
    } catch (err) {
      const e = asGiftingError(err);
      // The gift was shown before the server answered: take it back.
      if (shownId !== undefined) effects?.()?.cancel(shownId);
      if (this.alive) this.set({ balance: this.state.balance + gift.price, error: e });
      safe(() => this.options.onError?.(e));
    } finally {
      this.pending--;
      if (this.pending === 0) void this.reconcile(client);
    }
  };
}

/** Runs an app callback; whatever it throws is ignored (SPEC 8: callbacks never break the tray). */
function safe(fn: () => void): void {
  try {
    fn();
  } catch {
    // The app's problem, not the send's.
  }
}

export type SendButtonLabel = "send" | "getCoins" | "notEnough";

export interface SendButtonState {
  /** The gift the tray shows as selected, or null for an empty tray. */
  selectedId: string | null;
  /** The selected gift costs more than the balance. */
  broke: boolean;
  label: SendButtonLabel;
  pressable: boolean;
  /** What a press does. */
  action: "send" | "topUp" | "none";
}

/**
 * The tray's Send button. The selected gift is the one with `selectedId`, else the first one.
 * Too expensive: "Get coins" (opens the store) when `canTopUp`, else "Not enough coins" (off).
 */
export function sendButtonState(input: {
  gifts: Pick<Gift, "id" | "price">[];
  selectedId?: string | null;
  balance: number;
  disabled?: boolean;
  canTopUp?: boolean;
}): SendButtonState {
  const { gifts, balance, disabled = false, canTopUp = false } = input;
  const selected = gifts.find((g) => g.id === input.selectedId) ?? gifts[0];
  const broke = selected !== undefined && selected.price > balance;
  const canSend = selected !== undefined && !disabled && !broke;
  const label: SendButtonLabel = broke ? (canTopUp ? "getCoins" : "notEnough") : "send";
  const pressable = canSend || (broke && canTopUp && !disabled);
  return {
    selectedId: selected?.id ?? null,
    broke,
    label,
    pressable,
    action: !pressable ? "none" : broke ? "topUp" : "send",
  };
}
