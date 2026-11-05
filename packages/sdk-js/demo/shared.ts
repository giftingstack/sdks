/**
 * The single mock-data module of the web demo ("Pixel", web.html): people, posts, the gift catalog
 * from the live library, and a mock client with a leaderboard, an away summary and failures.
 * Not part of the SDK.
 */
import {
  type AwayGroup,
  type AwaySummary,
  type Gift,
  type GiftTransaction,
  type Inbox,
  type InboxItem,
  type GiftWall,
  type GiftingClient,
  GiftingError,
  type Leaderboard,
  type LeaderboardEntry,
  newIdempotencyKey,
} from "../src/core";

const ASSETS = "https://assets.giftingstack.com";
const PICK = [
  "pink-tulip",
  "heart-latte",
  "bear-boba",
  "cool-star",
  "magic-hat",
  "rainbow-gem",
  "treasure-chest",
  "golden-griffin",
  "phoenix",
  "sun-dragon",
  "heart-turkey",
  "star-whale",
];
const START_BALANCE = 60_000;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

interface LibraryFile {
  gifts: { id: string; name: string; suggested_price: number }[];
}

/** Used when the library file cannot be loaded (offline, no asset host): a small catalog. */
const FALLBACK: [string, string, number][] = [
  ["pink-tulip", "Pink Tulip", 10],
  ["heart-latte", "Heart Latte", 20],
  ["bear-boba", "Bear Boba", 45],
  ["cool-star", "Cool Star", 90],
  ["magic-hat", "Magic Hat", 250],
  ["rainbow-gem", "Rainbow Gem", 600],
  ["treasure-chest", "Treasure Chest", 1_500],
  ["golden-griffin", "Golden Griffin", 4_000],
  ["phoenix", "Phoenix", 9_000],
  ["sun-dragon", "Sun Dragon", 20_000],
];

export async function loadGifts(): Promise<Gift[]> {
  let lib: LibraryFile;
  try {
    const res = await fetch("/library.json");
    if (!res.ok) throw new Error(String(res.status));
    lib = (await res.json()) as LibraryFile;
  } catch {
    lib = {
      gifts: FALLBACK.map(([id, name, suggested_price]) => ({ id, name, suggested_price })),
    };
  }
  // Twelve chosen gifts, then others spread from cheap to grand (about ninety in all), so the
  // expanded sheet has plenty to scroll. The 108 country hearts share one price: keep one of them.
  const others = lib.gifts
    .filter((g) => !PICK.includes(g.id) && (!g.id.startsWith("heart-") || g.id === "heart-turkey"))
    .sort((a, b) => a.suggested_price - b.suggested_price);
  const want = 78;
  const step = others.length / want;
  const more = Array.from(
    { length: Math.min(want, others.length) },
    (_, i) => others[Math.floor(i * step)]!.id,
  );
  // The tray lists them from the cheapest to the grandest.
  const chosen = [...PICK, ...more]
    .map((id) => lib.gifts.find((x) => x.id === id))
    .filter((g): g is NonNullable<typeof g> => !!g)
    .sort((x, y) => x.suggested_price - y.suggested_price || (x.id < y.id ? -1 : 1));
  return chosen.flatMap((g, i): Gift[] => {
    const id = g.id;
    return [
      {
        id,
        name: g.name,
        description: null,
        price: g.suggested_price,
        icon_url: `${ASSETS}/gifts/${id}/256.webp`,
        animation_url: `${ASSETS}/gifts/${id}/512.webp`,
        sort_order: i,
      },
    ];
  });
}

/** What the demo's "Demo data" switch makes the wall, away and leaderboard calls do. */
export type Scenario = "normal" | "empty" | "error" | "slow";
/** Where the signed-in person ("ava") stands on the leaderboard (demo switch). */
export type Viewer = "outside" | "inside" | "overflow";

export interface MockClient extends GiftingClient {
  reset(): void;
  credit(coins: number): void;
  /** Demo only: change what the wall, away and leaderboard calls answer. */
  setScenario(scenario: Scenario): void;
  setViewer(viewer: Viewer): void;
  /** Demo only: gifts arrive again, so the next away check has a summary. */
  rearmAway(): void;
  /** Demo only: how many batch calls the walls made, and with how many walls in all. */
  stats: { wallCalls: number; wallItems: number; onChange?: () => void };
  /** Demo only (the mock failure switch): every call fails like a lost connection. */
  setOffline(offline: boolean): void;
  /** The "Hide me from leaderboards" flag of the signed-in person. */
  setHidden(hidden: boolean): void;
  /** Demo only: a gift that ava received (an incoming gift); the next `getInbox` lists it. */
  addToInbox(sender: string, giftId: string, quantity: number): void;
  /** Gifts that reached a wall from elsewhere (an incoming gift, "wall +5"). */
  addToWall(receiver: string, giftId: string, quantity: number, reference?: string | null): void;
}

export interface Person {
  name: string;
  color: string;
}

/** Display names and colours for the external ids of the mock data (your own user directory). */
export const PEOPLE: Record<string, Person> = {
  ava: { name: "Ava Carter", color: "#e0457b" },
  mateo: { name: "Mateo Silva", color: "#2f9e8f" },
  zoe: { name: "Zoe Lambert", color: "#7b61ff" },
  caleb: { name: "Caleb Stone", color: "#e8892b" },
  dana: { name: "Dana", color: "#2a8fd6" },
  ethan: { name: "Ethan Park", color: "#c2453d" },
  emma: { name: "Emma", color: "#b04fd0" },
  sofia: { name: "Sofia Rossi", color: "#1f9d7a" },
  ben: { name: "Ben", color: "#6b7a8f" },
  aisha: { name: "Aisha Khan", color: "#d6559a" },
  kai: { name: "Kai", color: "#4c6ef5" },
  daphne: { name: "Daphne Lee", color: "#3aa356" },
  oliver: { name: "Oliver", color: "#c9822b" },
  ella: { name: "Ella Fox", color: "#8e5bd9" },
  mia: { name: "Mia", color: "#d9534f" },
  theo: { name: "Theo Martin", color: "#3b82a0" },
};

export const displayName = (id: string): string => PEOPLE[id]?.name ?? id;
export const firstName = (id: string): string => displayName(id).split(" ")[0]!;
export const userColor = (id: string): string => PEOPLE[id]?.color ?? "#6b7a8f";

/** The people who send gifts to the signed-in demo user (everyone but ava). */
export const SENDERS = Object.keys(PEOPLE).filter((id) => id !== "ava");

export interface Post {
  id: string;
  author: string;
  text: string;
  /** Which drawing `art.ts` makes for it. */
  art: "sunset" | "city" | "ocean" | "aurora" | "mountains" | "studio" | "neon";
  ago: string;
  likes: number;
}

/** The posts of the feed. The post id is the `reference` of the gifts sent to it. */
export const POSTS: Post[] = [
  {
    id: "post_42",
    author: "mateo",
    text: "Golden hour on the pier. It never gets old.",
    art: "sunset",
    ago: "2h",
    likes: 482,
  },
  {
    id: "post_43",
    author: "zoe",
    text: "New skyline set, three weeks of work. Which window is your favourite?",
    art: "city",
    ago: "5h",
    likes: 1_204,
  },
  {
    id: "post_44",
    author: "caleb",
    text: "The tide was perfect this morning.",
    art: "ocean",
    ago: "9h",
    likes: 236,
  },
  {
    id: "post_45",
    author: "dana",
    text: "Northern lights from the cabin porch. Hot chocolate helped.",
    art: "aurora",
    ago: "1d",
    likes: 3_071,
  },
  {
    id: "post_46",
    author: "sofia",
    text: "First light over the ridge. Worth the 5 a.m. alarm.",
    art: "mountains",
    ago: "1d",
    likes: 912,
  },
  {
    id: "post_47",
    author: "kai",
    text: "Studio corner, finally tidy. The canvas on the right is next.",
    art: "studio",
    ago: "2d",
    likes: 654,
  },
  {
    id: "post_48",
    author: "ella",
    text: "Late drive, loud synths, nothing else.",
    art: "neon",
    ago: "3d",
    likes: 1_588,
  },
];

/**
 * Gifts the demo user (ava) received in the last 24 hours, before the session started: who sent
 * which gift and how many minutes ago. The mock `getInbox` answers from these and from the gifts
 * that arrive while the demo runs. One of them was reversed (the inbox never shows it).
 */
export const SEED_RECEIVED: {
  from: string;
  gift: string;
  quantity: number;
  minutesAgo: number;
  reversed?: boolean;
}[] = [
  { from: "mateo", gift: "pink-tulip", quantity: 3, minutesAgo: 35 },
  { from: "zoe", gift: "heart-latte", quantity: 1, minutesAgo: 70 },
  { from: "ethan", gift: "bear-boba", quantity: 2, minutesAgo: 140, reversed: true },
  { from: "dana", gift: "cool-star", quantity: 1, minutesAgo: 190 },
  { from: "sofia", gift: "magic-hat", quantity: 1, minutesAgo: 300 },
  { from: "caleb", gift: "pink-tulip", quantity: 5, minutesAgo: 430 },
  { from: "daphne", gift: "rainbow-gem", quantity: 1, minutesAgo: 600 },
  { from: "emma", gift: "heart-latte", quantity: 2, minutesAgo: 780 },
  { from: "ben", gift: "treasure-chest", quantity: 1, minutesAgo: 1_000 },
  { from: "aisha", gift: "cool-star", quantity: 3, minutesAgo: 1_200 },
  { from: "kai", gift: "bear-boba", quantity: 1, minutesAgo: 1_340 },
];

const initialOf = (name: string): string => [...name][0]?.toUpperCase() ?? "?";

/** A round initial avatar as a data URL: the demo needs no image host for its pretend avatars. */
export const avatarUrl = (color: string, name: string): string =>
  "data:image/svg+xml," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" fill="${color}"/><text x="32" y="43" text-anchor="middle" font-family="system-ui,sans-serif" font-size="30" font-weight="700" fill="#fff">${initialOf(name)}</text></svg>`,
  );

/** The `resolveUsers` of the demo: what your app would answer from its own user table. */
export async function resolveDemoUsers(
  ids: string[],
): Promise<Record<string, { name: string; avatarUrl?: string }>> {
  await wait(200);
  return Object.fromEntries(
    ids.flatMap((id) => {
      const p = PEOPLE[id];
      return p
        ? [
            [
              id,
              {
                name: p.name,
                avatarUrl: avatarUrl(p.color, p.name),
              },
            ],
          ]
        : [];
    }),
  );
}

/** Ten gifts a post might have received (counts from big to small, in catalog order). */
const WALL_COUNTS = [48, 31, 17, 12, 9, 6, 4, 3, 2, 1];

/** Leaderboard: external id, `week` coins, and a tie group (equal groups score the same). */
const BOARD_BASE: [string, number, number][] = [
  ["zoe", 54_000, 1],
  ["mateo", 41_000, 2],
  ["caleb", 41_000, 2],
  ["dana", 33_500, 3],
  ["ethan", 28_200, 4],
  ["emma", 19_900, 5],
  ["sofia", 19_900, 5],
  ["ben", 12_300, 6],
  ["aisha", 9_800, 7],
  ["kai", 7_200, 8],
  ["daphne", 5_100, 9],
  ["oliver", 3_900, 10],
  ["ella", 2_450, 11],
  ["mia", 1_800, 12],
  ["theo", 640, 13],
];
const PERIOD_FACTOR = { day: 0.12, week: 1, month: 3.4, all: 21 } as const;
const PERIOD_LABEL = { day: "2026-10-11", week: "2026-W41", month: "2026-10", all: "all" } as const;

const hash = (s: string): number => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);

/** A stand-in for GiftingStack: same shapes and errors, a quarter second of fake network delay. */
export function createMockClient(gifts: Gift[]): MockClient {
  let balance = START_BALANCE;
  let scenario: Scenario = "normal";
  let viewer: Viewer = "outside";
  let awayAcked = false;
  let offline = false;
  let hidden = false;
  const sent = new Map<string, GiftTransaction>();
  /** Gifts sent in this session, per `receiver|reference`, so a wall grows after a send. */
  const extra = new Map<string, Map<string, number>>();
  const stats: MockClient["stats"] = { wallCalls: 0, wallItems: 0 };
  const byId = (id: string): Gift | undefined => gifts.find((g) => g.id === id);

  /** Gifts ava received, newest first: the seeded ones (last 24 h) and those that arrive live. */
  interface Received {
    id: string;
    at: number;
    sender: string;
    gift: Gift;
    quantity: number;
    status: InboxItem["status"];
  }
  let receivedSeq = 0;
  const seedReceived = (): Received[] => {
    const now = Date.now();
    return SEED_RECEIVED.map((r, i) => ({
      id: `gtx_seed_${i + 1}`,
      at: now - r.minutesAgo * 60_000,
      sender: r.from,
      gift: byId(r.gift) ?? gifts[i % gifts.length]!,
      quantity: r.quantity,
      status: r.reversed ? ("reversed" as const) : ("completed" as const),
    }));
  };
  let received: Received[] = seedReceived();

  /** The delay of every read of the new components, and the failure of the "error" scenario. */
  const down = (): void => {
    if (offline) throw new GiftingError(0, "network_error", "You are offline.");
  };
  const guard = async (): Promise<void> => {
    await wait(scenario === "slow" ? 3_000 : 250);
    down();
    if (scenario === "error") throw new GiftingError(500, "server_error", "Mock failure.");
  };

  const wallOf = (receiver: string, reference: string | null): GiftWall["gifts"] => {
    if (scenario === "empty") return [];
    const seed = hash(`${receiver}|${reference ?? ""}`);
    const own = extra.get(`${receiver}|${reference ?? ""}`);
    // A post gets ten kinds of gift; a plain profile twelve, with bigger numbers.
    const kinds = reference ? 10 : 12;
    const out = gifts.slice(0, kinds).map((g, i) => {
      const base = Math.max(
        0,
        Math.round((WALL_COUNTS[i % 10]! * (1 + ((seed >>> i) % 5))) / (reference ? 1 : 0.4)),
      );
      return {
        gift: { id: g.id, name: g.name, icon_url: g.icon_url },
        count: base + (own?.get(g.id) ?? 0),
      };
    });
    // The demo post is full; others are quieter: few gifts, or none.
    if (!reference || reference === "post_42") return out;
    const known = POSTS.some((p) => p.id === reference);
    if (!known && seed % 7 === 0) return [];
    return seed % 3 === 0 ? out.slice(0, 5) : out;
  };

  /** The away summary: several groups and senders, one of them deleted. */
  const awaySummary = (): AwaySummary => {
    const now = new Date();
    const since = new Date(now.getTime() - 2 * 86_400_000 - 3 * 3_600_000);
    const plan: [string, number, [string | null, number][]][] = [
      ["sun-dragon", 1, [["zoe", 1]]],
      [
        "treasure-chest",
        3,
        [
          ["mateo", 2],
          ["caleb", 1],
        ],
      ],
      [
        "magic-hat",
        20,
        [
          ["mateo", 9],
          [null, 4],
          ["emma", 3],
        ],
      ],
      [
        "heart-latte",
        50,
        [
          ["dana", 30],
          ["ethan", 15],
          ["caleb", 5],
        ],
      ],
      ["cool-star", 3, [["emma", 3]]],
    ];
    const groups: AwayGroup[] = [];
    const people = new Map<string | null, { count: number; units: number }>();
    for (const [id, count, senders] of plan) {
      const g = byId(id);
      if (!g) continue;
      groups.push({
        gift: {
          id,
          name: g.name,
          price: g.price,
          icon_url: g.icon_url,
          animation_url: g.animation_url,
        },
        count,
        units: g.price * count,
        sender_count: senders.length === 3 && id === "magic-hat" ? 6 : senders.length,
        senders: senders.map(([user, n]) => ({ user, count: n })),
      });
      for (const [user, n] of senders) {
        const p = people.get(user) ?? { count: 0, units: 0 };
        people.set(user, { count: p.count + n, units: p.units + n * g.price });
      }
    }
    groups.sort((a, b) => b.units - a.units || (a.gift.id < b.gift.id ? -1 : 1));
    const top = [...people.entries()]
      .map(([user, v]) => ({ user, ...v }))
      .sort((a, b) => b.count - a.count || b.units - a.units)
      .slice(0, 5);
    return {
      user: "ava",
      since: since.toISOString(),
      until: now.toISOString(),
      cursor: `aw1.${btoa(`${now.getTime()}.1`)}`,
      truncated: false,
      total_gifts: groups.reduce((n, g) => n + g.count, 0),
      total_units: groups.reduce((n, g) => n + g.units, 0),
      sender_count: 7,
      groups,
      top_senders: top,
    };
  };

  const leaderboard = (
    board: "senders" | "receivers",
    q: {
      period?: keyof typeof PERIOD_FACTOR;
      metric?: "units" | "gifts";
      limit?: number;
      includeMe?: boolean;
    },
  ): Leaderboard => {
    const period = q.period ?? "week";
    const metric = q.metric ?? "units";
    const limit = Math.min(100, Math.max(1, q.limit ?? 10));
    const factor = PERIOD_FACTOR[period] * (board === "receivers" ? 0.8 : 1);
    type Row = { user: string; units: number; gifts: number };
    const rows: Row[] = BOARD_BASE.map(([user, units, group]) => {
      // The same tie group keeps the same score; each period/board nudges the groups a little.
      const jitter =
        1 +
        (((hash(`${group}|${period}|${board}`) % 31) - 15) / 100) *
          (period === "week" && board === "senders" ? 0 : 1);
      const u = Math.max(1, Math.round(units * factor * jitter));
      const avg = 40 + ((group * 37) % 160);
      return {
        user,
        units: u,
        gifts: Math.max(1, Math.round(u / avg)) + (hash(user) % 3 === 0 ? 0 : group % 2),
      };
    });
    if (viewer === "inside")
      rows.push({
        user: "ava",
        units: Math.round(21_000 * factor),
        gifts: Math.round(95 * factor) + 1,
      });
    const score = (r: Row): number => (metric === "gifts" ? r.gifts : r.units);
    rows.sort(
      (a, b) =>
        score(b) - score(a) ||
        BOARD_BASE.findIndex(([u]) => u === a.user) - BOARD_BASE.findIndex(([u]) => u === b.user),
    );
    const ranked: LeaderboardEntry[] = rows.map((r, i) => ({
      rank: i > 0 && score(rows[i - 1]!) === score(r) ? 0 : i + 1,
      user: r.user,
      gifts: r.gifts,
      units: r.units,
    }));
    // Competition ranking: equal scores share the rank of the first of them.
    for (let i = 0; i < ranked.length; i++)
      if (ranked[i]!.rank === 0) ranked[i]!.rank = ranked[i - 1]!.rank;
    const empty = scenario === "empty";
    const me = ranked.find((r) => r.user === "ava");
    const meBlock =
      q.includeMe === false || empty
        ? null
        : me
          ? { user: "ava", rank: me.rank, gifts: me.gifts, units: me.units, hidden }
          : {
              user: "ava",
              rank: viewer === "overflow" ? null : 417,
              gifts: 3,
              units: 120,
              hidden,
            };
    return {
      board,
      period,
      metric,
      label: PERIOD_LABEL[period],
      starts_at: null,
      ends_at: null,
      as_of: new Date().toISOString(),
      data: empty ? [] : ranked.slice(0, limit),
      has_more: !empty && ranked.length > limit,
      me: meBlock,
    };
  };

  return {
    reset() {
      balance = START_BALANCE;
      awayAcked = false;
      hidden = false;
      extra.clear();
      sent.clear();
      received = seedReceived();
    },
    addToInbox(sender, giftId, quantity) {
      const gift = byId(giftId) ?? gifts[0]!;
      received.unshift({
        id: `gtx_live_${++receivedSeq}`,
        at: Date.now(),
        sender,
        gift,
        quantity,
        status: "completed",
      });
    },
    setOffline: (o) => void (offline = o),
    setHidden: (h) => void (hidden = h),
    addToWall(receiver, giftId, quantity, reference = null) {
      const key = `${receiver}|${reference ?? ""}`;
      const mine = extra.get(key) ?? new Map<string, number>();
      mine.set(giftId, (mine.get(giftId) ?? 0) + quantity);
      extra.set(key, mine);
    },
    // What your server does after a purchase: POST /v1/users/{id}/credit.
    credit: (coins) => void (balance += coins),
    setScenario: (s) => void (scenario = s),
    setViewer: (v) => void (viewer = v),
    rearmAway: () => void (awayAcked = false),
    stats,
    async getGifts() {
      await wait(250);
      down();
      return gifts;
    },
    async getMe() {
      await wait(120);
      down();
      return { user: "ava", balance, livemode: false };
    },
    async getReceivedGifts(user, reference) {
      await guard();
      return wallOf(user, reference ?? null);
    },
    async queryGiftWalls(items) {
      stats.wallCalls++;
      stats.wallItems += items.length;
      stats.onChange?.();
      await guard();
      return items.map((i) => ({
        receiver: i.receiver,
        reference: i.reference ?? null,
        gifts: wallOf(i.receiver, i.reference ?? null),
      }));
    },
    async getAway() {
      await guard();
      if (scenario === "empty" || awayAcked) {
        const now = new Date().toISOString();
        return {
          user: "ava",
          since: now,
          until: now,
          cursor: null,
          truncated: false,
          total_gifts: 0,
          total_units: 0,
          sender_count: 0,
          groups: [],
          top_senders: [],
        };
      }
      return awaySummary();
    },
    async ackAway() {
      await wait(120);
      down();
      awayAcked = true;
    },
    async getInbox(query = {}) {
      await guard();
      const now = Date.now();
      const recent =
        scenario === "empty" ? [] : received.filter((r) => now - r.at < 24 * 3_600_000);
      const start = Math.max(0, Number(/^ib1.(d+)$/.exec(query.cursor ?? "")?.[1] ?? 0));
      const limit = Math.min(100, Math.max(1, query.limit ?? 20));
      const page = recent.slice(start, start + limit);
      const more = start + limit < recent.length;
      const body: Inbox = {
        user: "ava",
        since: new Date(now - 24 * 3_600_000).toISOString(),
        until: new Date(now).toISOString(),
        data: page.map((r) => ({
          id: r.id,
          created_at: new Date(r.at).toISOString(),
          sender: r.sender,
          gift: {
            id: r.gift.id,
            name: r.gift.name,
            price: r.gift.price,
            icon_url: r.gift.icon_url,
            animation_url: r.gift.animation_url,
          },
          quantity: r.quantity,
          units: r.gift.price * r.quantity,
          status: r.status,
        })),
        has_more: more,
        next_cursor: more ? `ib1.${start + limit}` : null,
      };
      return body;
    },
    async getLeaderboard(board, query = {}) {
      await guard();
      return leaderboard(board, query);
    },
    async sendGift(input) {
      await wait(250);
      down();
      const key = input.idempotencyKey ?? newIdempotencyKey();
      const again = sent.get(key);
      if (again) return again;
      const gift = gifts.find((g) => g.id === input.giftId);
      if (!gift) throw new GiftingError(404, "not_found", "Gift not found.");
      const total = gift.price * (input.quantity ?? 1);
      if (balance < total)
        throw new GiftingError(422, "insufficient_balance", "Insufficient balance.");
      balance -= total;
      const tx: GiftTransaction = {
        id: `gtx_${key}`,
        sender: "ava",
        receiver: input.receiver,
        gift: { id: gift.id, name: gift.name, icon_url: gift.icon_url },
        quantity: input.quantity ?? 1,
        unit_price: gift.price,
        total,
        message: input.message ?? null,
        reference: input.reference ?? null,
        status: "completed",
        created_at: new Date().toISOString(),
        sender_balance_after: balance,
      };
      sent.set(key, tx);
      const wallKey = `${input.receiver}|${input.reference ?? ""}`;
      const mine = extra.get(wallKey) ?? new Map<string, number>();
      mine.set(gift.id, (mine.get(gift.id) ?? 0) + (input.quantity ?? 1));
      extra.set(wallKey, mine);
      return tx;
    },
  };
}

export const el = <K extends keyof HTMLElementTagNameMap>(
  tag: K,
  text = "",
): HTMLElementTagNameMap[K] => {
  const e = document.createElement(tag);
  e.textContent = text;
  return e;
};
