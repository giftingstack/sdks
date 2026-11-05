/**
 * A pretend rooms server for the demo: a `WebSocket` look-alike that speaks the real wire protocol
 * (SPEC 17: `hello` -> `welcome`, then `gift` and `viewers` frames), so the demo runs the SDK's
 * real `joinRoom` code without a rooms Worker. Other people send gifts to the room every few
 * seconds, now and then five in a row (a combo). With `battle`, the room also runs back-to-back
 * battle rounds between the receivers and sends `scores` frames like the real room (SPEC 17.8:
 * at most one per 250 ms, nothing when a round ends, a new round after a short break).
 * Not part of the SDK.
 */
import type { Gift, RoomBattle } from "../src/core";

export interface FakeRoomBattleOptions {
  /** The round's receivers, in bar order (left first). Others' gifts go to one of them. */
  receivers: string[];
  /** Default 90 s. */
  roundMs?: number;
  /** Pause between rounds; default 8 s. */
  breakMs?: number;
}

export interface FakeRoomOptions {
  gifts: Gift[];
  /** External ids that send the gifts. */
  senders: string[];
  /** Display name of a sender (the real server gets it from the sender's token). */
  nameOf: (id: string) => string;
  random?: () => number;
  /** Default 8000-16000 ms between gifts. */
  minDelayMs?: number;
  maxDelayMs?: number;
  battle?: FakeRoomBattleOptions;
}

type Socket = {
  onopen: ((ev: unknown) => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onclose: ((ev: { code: number; reason: string }) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  send(data: string): void;
  close(code?: number, reason?: string): void;
};

/** A `WebSocket` constructor for `joinRoom({ WebSocket })`, plus `publish` for the app's own sends. */
export type FakeRoomSocket = (new (url: string, protocols: string[]) => Socket) & {
  /**
   * What the real API does after a send with `room_id`: the gift reaches everyone in the room
   * (and counts for the round). The SDK leaves the sender's own gifts out of its events.
   */
  publish(sender: string, gift: Gift, quantity: number, receiver: string): void;
};

const SCORES_INTERVAL_MS = 250;

/** A `WebSocket` constructor for `joinRoom({ WebSocket })`, bound to these options. */
export function fakeRoomSocket(options: FakeRoomOptions): FakeRoomSocket {
  const rand = options.random ?? Math.random;
  const minDelay = options.minDelayMs ?? 8_000;
  const maxDelay = options.maxDelayMs ?? 16_000;
  let nextId = Date.now() * 1000;
  let nextTx = 1;
  let viewers = 38 + Math.floor(rand() * 20);
  const sockets = new Set<FakeRoomWebSocket>();

  // ---- battle: one round at a time, shared by every socket of this room
  const roundMs = options.battle?.roundMs ?? 90_000;
  const breakMs = options.battle?.breakMs ?? 8_000;
  let battle: RoomBattle | null = null;
  let roundNo = 0;
  let roundTimer: ReturnType<typeof setTimeout> | undefined;
  let scoresTimer: ReturnType<typeof setTimeout> | undefined;
  let lastScoresAt = 0;
  const copy = (b: RoomBattle | null): RoomBattle | null =>
    b && { ...b, scores: b.scores.map((s) => ({ ...s })) };
  const broadcast = (message: unknown): void => {
    for (const s of sockets) s.push(message);
  };
  const sendScores = (): void => {
    scoresTimer = undefined;
    lastScoresAt = Date.now();
    broadcast({ t: "scores", battle: copy(battle) });
  };
  /** Like the real room: a full snapshot, at most one per 250 ms, never one per gift. */
  const queueScores = (): void => {
    if (scoresTimer !== undefined) return;
    const wait = Math.max(0, lastScoresAt + SCORES_INTERVAL_MS - Date.now());
    scoresTimer = setTimeout(sendScores, wait);
  };
  const startRound = (): void => {
    const receivers = options.battle?.receivers ?? [];
    const now = Date.now();
    battle = {
      round: `demo_r${++roundNo}`,
      started: now,
      ends: now + roundMs,
      scores: receivers.map((id) => ({ id, units: 0, gifts: 0 })),
    };
    queueScores();
    // No frame when the round ends (clients count down to `ends`); the next round starts later.
    roundTimer = setTimeout(startRound, roundMs + breakMs);
  };
  const count = (receiver: string, gift: Gift, quantity: number): void => {
    const now = Date.now();
    if (!battle || now < battle.started || now >= battle.ends) return;
    const entry = battle.scores.find((s) => s.id === receiver);
    if (!entry) return;
    entry.units += gift.price * quantity;
    entry.gifts += quantity;
    queueScores();
  };
  const stopBattle = (): void => {
    clearTimeout(roundTimer);
    clearTimeout(scoresTimer);
    roundTimer = scoresTimer = undefined;
    battle = null;
  };

  const pickReceiver = (): string => {
    const r = options.battle?.receivers ?? [];
    return r.length > 0 ? r[Math.floor(rand() * r.length)]! : "mira";
  };
  /** Mostly everyday gifts (the cheaper 60%): luxury effects cover the stream, so they are rare. */
  const pickGift = (): Gift | undefined => {
    const all = options.gifts;
    if (all.length === 0) return undefined;
    const cheap = [...all].sort((a, b) => a.price - b.price).slice(0, Math.max(1, Math.ceil(all.length * 0.6)));
    const from = rand() < 0.1 ? all : cheap;
    return from[Math.floor(rand() * from.length)];
  };
  const frame = (sender: string, gift: Gift, quantity: number, receiver: string) => ({
    t: "gift",
    id: ++nextId,
    at: Date.now(),
    tx: `gtx_demo${nextTx++}`,
    gift: { id: gift.id, name: gift.name, price: gift.price, icon_url: gift.icon_url },
    quantity,
    sender: { id: sender, name: options.nameOf(sender) },
    receiver: { id: receiver },
  });
  const deliver = (sender: string, gift: Gift, quantity: number, receiver: string): void => {
    broadcast(frame(sender, gift, quantity, receiver));
    count(receiver, gift, quantity);
  };

  class FakeRoomWebSocket implements Socket {
    onopen: Socket["onopen"] = null;
    onmessage: Socket["onmessage"] = null;
    onclose: Socket["onclose"] = null;
    onerror: Socket["onerror"] = null;
    private timers = new Set<ReturnType<typeof setTimeout>>();
    private open = false;
    private closed = false;

    constructor(
      readonly url: string,
      readonly protocols: string[],
    ) {
      this.later(150, () => {
        this.open = true;
        this.onopen?.({});
      });
    }

    send(data: string): void {
      if (!this.open) return;
      let msg: { t?: string };
      try {
        msg = JSON.parse(data) as { t?: string };
      } catch {
        return;
      }
      if (msg.t === "hello") {
        if (options.battle && battle === null) startRound();
        sockets.add(this);
        this.push({
          t: "welcome",
          v: 1,
          viewers,
          gap: false,
          replay: [],
          ttl: 3600,
          now: Date.now(),
          ...(battle ? { battle: copy(battle) } : {}),
        });
        this.schedule();
        this.drift();
      } else if (msg.t === "ping") {
        this.push({ t: "pong" });
      }
    }

    close(code = 1000, reason = ""): void {
      if (this.closed) return;
      this.closed = true;
      for (const t of this.timers) clearTimeout(t);
      this.timers.clear();
      sockets.delete(this);
      if (sockets.size === 0) stopBattle();
      this.onclose?.({ code, reason });
    }

    push(message: unknown): void {
      if (!this.closed) this.onmessage?.({ data: JSON.stringify(message) });
    }

    private later(ms: number, fn: () => void): void {
      const t = setTimeout(() => {
        this.timers.delete(t);
        if (!this.closed) fn();
      }, ms);
      this.timers.add(t);
    }

    /**
     * Someone in the room sends a gift; 1 in 12 times it is a combo of five. Only the first open
     * socket drives this traffic, so a second viewer of the same room sees the same gifts.
     */
    private schedule(): void {
      this.later(minDelay + rand() * (maxDelay - minDelay), () => {
        const sender = options.senders[Math.floor(rand() * options.senders.length)];
        const gift = pickGift();
        if (sender && gift && sockets.values().next().value === this) {
          const receiver = pickReceiver();
          if (rand() < 1 / 12) {
            for (let i = 0; i < 5; i++)
              this.later(i * 250, () => deliver(sender, gift, 1, receiver));
          } else {
            deliver(sender, gift, 1 + Math.floor(rand() * 2), receiver);
          }
        }
        this.schedule();
      });
    }

    /** The viewer count wanders a little, like a real room. */
    private drift(): void {
      this.later(5_000, () => {
        viewers = Math.max(1, viewers + Math.floor(rand() * 7) - 3);
        this.push({ t: "viewers", n: viewers });
        this.drift();
      });
    }
  }

  return Object.assign(FakeRoomWebSocket, {
    publish(sender: string, gift: Gift, quantity: number, receiver: string): void {
      deliver(sender, gift, quantity, receiver);
    },
  });
}

/**
 * A token shaped like the real one (`gs_ct_<claims>.<signature>`) so the SDK can read the user
 * from it (it never checks the signature: only the server does). Not a secret, not valid anywhere.
 */
export function demoRoomToken(user: string): string {
  const claims = JSON.stringify({ v: 1, u: user, n: user });
  const b64 = btoa(claims).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `gs_ct_${b64}.demo`;
}
