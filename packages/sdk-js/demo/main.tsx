import { createRoot } from "react-dom/client";
import { useMemo, useRef, useState } from "react";
import { Image, Modal, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import {
  type AwayGroup,
  type AwaySummary,
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  GiftingError,
  type Leaderboard,
  type LeaderboardBoard,
  type LeaderboardQuery,
  type ReceivedGift,
  newIdempotencyKey,
} from "../src/core";
import {
  GiftAwaySummary,
  type GiftAwaySummaryHandle,
  GiftEffectLayer,
  type GiftEffectLayerHandle,
  GiftLeaderboard,
  GiftTray,
  GiftWall,
  useGiftTray,
  wallLoaderFor,
} from "../src/react-native";

interface LibraryFile {
  gifts: { id: string; name: string; suggested_price: number; sort: number }[];
}

const PICK = [
  "pink-tulip",
  "heart-latte",
  "bear-boba",
  "cool-star",
  "magic-hat",
  "rainbow-gem",
  "golden-griffin",
  "sun-dragon",
];

let catalog: Promise<Gift[]> | null = null;
/** The gifts as the API would return them (pictures served by the demo server). */
function loadGifts(): Promise<Gift[]> {
  catalog ??= (async () => {
    const lib = (await (await fetch("/library.json")).json()) as LibraryFile;
    return PICK.flatMap((id, i): Gift[] => {
      const g = lib.gifts.find((x) => x.id === id);
      return g
        ? [
            {
              id,
              name: g.name,
              description: null,
              price: g.suggested_price,
              icon_url: `/gifts/${id}/256.webp`,
              animation_url: `/gifts/${id}/512.webp`,
              sort_order: i,
            },
          ]
        : [];
    });
  })();
  return catalog;
}
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- demo data (not part of the SDK)

/** What the demo's pretend server answers. Switchable from the "Demo only" bar. */
type Mode = "normal" | "slow" | "empty" | "error";

/** Display names for the demo users: your app's `resolveUsers` does this lookup. */
const NAMES: Record<string, string> = {
  ava: "Ava",
  usr_mateo: "Mateo",
  usr_emma: "Emma",
  usr_caleb: "Can",
  usr_zoe: "Zoe",
  usr_elise: "Elise",
  usr_dana: "Dana",
  usr_sofia: "Sofia",
  usr_ben: "Ben",
  usr_ozge: "Özge",
  usr_kai: "Kai",
  usr_ada: "Ada",
  usr_ethan: "Ethan",
  usr_ipek: "İpek",
  usr_baris: "Barış",
  usr_yagmur: "Yağmur",
};
const resolveUsers = async (ids: string[]) => {
  await wait(250);
  return Object.fromEntries(ids.flatMap((id) => (NAMES[id] ? [[id, { name: NAMES[id]! }]] : [])));
};

/** Weekly units of the top 15: two people tie for first, two tie for fifth. */
const WEEK_UNITS: [string, number][] = [
  ["usr_mateo", 54_000],
  ["usr_emma", 54_000],
  ["usr_caleb", 41_200],
  ["usr_zoe", 38_800],
  ["usr_elise", 22_500],
  ["usr_dana", 22_500],
  ["usr_sofia", 18_000],
  ["usr_ben", 9_900],
  ["usr_ozge", 7_600],
  ["usr_kai", 5_400],
  ["usr_ada", 3_300],
  ["usr_ethan", 2_100],
  ["usr_ipek", 950],
  ["usr_baris", 720],
  ["usr_yagmur", 300],
];
const PERIOD_SCALE = { day: 0.12, week: 1, month: 3.6, all: 21 } as const;
/** The viewer is never in the rows: rank 87 today, 417 this week, beyond 1,000 later. */
const MY_RANK = { day: 87, week: 417, month: null, all: null } as const;

function buildBoard(board: LeaderboardBoard, q: LeaderboardQuery): Leaderboard {
  const period = q.period ?? "week";
  const metric = q.metric ?? "units";
  const limit = q.limit ?? 10;
  const rows = WEEK_UNITS.map(([user, base]) => {
    // Equal inputs give equal outputs, so the ties stay ties in every period.
    const units = Math.floor((base * PERIOD_SCALE[period] * (1 + (base % 7) / 50)) / 5) * 5;
    const gifts = Math.max(1, Math.round(units / (110 + (base % 13) * 14)));
    return { user, units, gifts };
  }).sort((a, b) => b[metric] - a[metric]);
  const ranked = rows.map((r, i) => ({
    ...r,
    rank: i > 0 && rows[i - 1]![metric] === r[metric] ? 0 : i + 1,
  }));
  for (let i = 0; i < ranked.length; i++)
    if (ranked[i]!.rank === 0) ranked[i]!.rank = ranked[i - 1]!.rank;
  return {
    board,
    period,
    metric,
    label: period,
    starts_at: null,
    ends_at: null,
    as_of: new Date().toISOString(),
    data: ranked.slice(0, limit),
    has_more: ranked.length > limit,
    me: { user: "ava", rank: MY_RANK[period], gifts: 3, units: 120, hidden: false },
  };
}

const rg = (gifts: Gift[], id: string, count: number): ReceivedGift => {
  const g = gifts.find((x) => x.id === id)!;
  return { gift: { id, name: g.name, icon_url: g.icon_url }, count };
};

/** What a few walls start with, in catalog order. */
function initialWalls(gifts: Gift[]): Map<string, ReceivedGift[]> {
  return new Map([
    [
      "mateo|post_42",
      [
        rg(gifts, "pink-tulip", 120),
        rg(gifts, "heart-latte", 31),
        rg(gifts, "bear-boba", 12),
        rg(gifts, "cool-star", 7),
        rg(gifts, "magic-hat", 3),
        rg(gifts, "rainbow-gem", 2),
        rg(gifts, "golden-griffin", 1),
        rg(gifts, "sun-dragon", 1),
      ],
    ],
    ["mateo|post_43", [rg(gifts, "pink-tulip", 4), rg(gifts, "cool-star", 1)]],
    ["mateo|post_44", []],
    [
      "mateo|",
      [
        rg(gifts, "pink-tulip", 2_400),
        rg(gifts, "heart-latte", 1_999),
        rg(gifts, "bear-boba", 640),
        rg(gifts, "cool-star", 38),
        rg(gifts, "magic-hat", 12),
        rg(gifts, "sun-dragon", 2),
      ],
    ],
  ]);
}

function buildAway(gifts: Gift[]): AwaySummary {
  const g = (id: string) => gifts.find((x) => x.id === id)!;
  const group = (
    id: string,
    count: number,
    sender_count: number,
    senders: AwayGroup["senders"],
  ): AwayGroup => ({
    gift: {
      id,
      name: g(id).name,
      price: g(id).price,
      icon_url: g(id).icon_url,
      animation_url: g(id).animation_url,
    },
    count,
    units: g(id).price * count,
    sender_count,
    senders,
  });
  return {
    user: "ava",
    since: "2026-10-08T09:12:44.120Z",
    until: new Date().toISOString(),
    cursor: "aw1.demo",
    truncated: false,
    total_gifts: 97,
    total_units: 55_540,
    sender_count: 12,
    groups: [
      group("sun-dragon", 1, 1, [{ user: "usr_caleb", count: 1 }]),
      group("magic-hat", 20, 6, [
        { user: "usr_mateo", count: 9 },
        { user: null, count: 4 },
        { user: "usr_emma", count: 3 },
      ]),
      group("rainbow-gem", 6, 3, [
        { user: "usr_emma", count: 3 },
        { user: "usr_sofia", count: 2 },
        { user: "usr_kai", count: 1 },
      ]),
      group("cool-star", 9, 2, [
        { user: "usr_zoe", count: 6 },
        { user: "usr_elise", count: 3 },
      ]),
      group("bear-boba", 12, 4, [
        { user: "usr_mateo", count: 7 },
        { user: "usr_ada", count: 3 },
        { user: "usr_ozge", count: 2 },
      ]),
    ],
    top_senders: [
      { user: "usr_caleb", count: 15, units: 40_450 },
      { user: "usr_mateo", count: 22, units: 8_200 },
      { user: null, count: 4, units: 1_400 },
      { user: "usr_emma", count: 9, units: 4_100 },
    ],
  };
}

/** An in-memory stand-in for the API, so the demo needs no server. */
function demoClient() {
  let balance = 60_000;
  let mode: Mode = "normal";
  let awayMode: "gifts" | "none" | "error" = "gifts";
  let awayAcked = false;
  let walls: Map<string, ReceivedGift[]> | null = null;
  const latency = () => wait(mode === "slow" ? 2_500 : 250);
  const client: GiftingClient & {
    credit(coins: number): void;
    setMode(m: Mode): void;
    setAway(m: "gifts" | "none" | "error"): void;
    resetAway(): void;
  } = {
    // What your server does after a purchase: POST /v1/users/{id}/credit.
    credit: (coins) => void (balance += coins),
    setMode: (m) => void (mode = m),
    setAway: (m) => void (awayMode = m),
    resetAway: () => void (awayAcked = false),
    getGifts: loadGifts,
    async getMe() {
      return { user: "ava", balance, livemode: false };
    },
    async getReceivedGifts() {
      return [];
    },
    async queryGiftWalls(items) {
      const gifts = await loadGifts();
      walls ??= initialWalls(gifts);
      await wait(250);
      if (mode === "error") throw new GiftingError(503, "unavailable", "Demo: walls are down.");
      return items.map((i) => ({
        receiver: i.receiver,
        reference: i.reference ?? null,
        gifts: mode === "empty" ? [] : (walls!.get(`${i.receiver}|${i.reference ?? ""}`) ?? []),
      }));
    },
    async getInbox() {
      const now = new Date().toISOString();
      return { user: "ava", since: now, until: now, data: [], has_more: false, next_cursor: null };
    },
    async getAway() {
      const gifts = await loadGifts();
      await wait(400);
      if (awayMode === "error") throw new GiftingError(500, "server_error", "Demo: away failed.");
      if (awayMode === "none" || awayAcked) {
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
      return buildAway(gifts);
    },
    async ackAway() {
      awayAcked = true;
    },
    async getLeaderboard(board, query = {}) {
      await latency();
      if (mode === "error") throw new GiftingError(503, "leaderboard_building", "Demo: building.");
      const b = buildBoard(board, query);
      return mode === "empty" ? { ...b, data: [], has_more: false, me: null } : b;
    },
    async sendGift(input): Promise<GiftTransaction> {
      const gifts = await loadGifts();
      const g = gifts.find((x) => x.id === input.giftId)!;
      const total = g.price * (input.quantity ?? 1);
      if (balance < total) {
        throw new GiftingError(422, "insufficient_balance", "Insufficient balance.");
      }
      balance -= total;
      walls ??= initialWalls(gifts);
      const key = `${input.receiver}|${input.reference ?? ""}`;
      const list = [...(walls.get(key) ?? [])];
      const at = list.findIndex((x) => x.gift.id === g.id);
      if (at >= 0) list[at] = { ...list[at]!, count: list[at]!.count + (input.quantity ?? 1) };
      else list.push(rg(gifts, g.id, input.quantity ?? 1));
      walls.set(key, list);
      return {
        id: `gtx_${newIdempotencyKey()}`,
        sender: "ava",
        receiver: input.receiver,
        gift: { id: g.id, name: g.name, icon_url: null },
        quantity: input.quantity ?? 1,
        unit_price: g.price,
        total,
        message: null,
        reference: input.reference ?? null,
        status: "completed",
        created_at: new Date().toISOString(),
        sender_balance_after: balance,
      };
    },
  };
  return client;
}

const client = demoClient();

const PACKS = [
  { coins: 1_000, price: "$0.99" },
  { coins: 5_000, price: "$4.49" },
  { coins: 20_000, price: "$15.99" },
];

/** A pretend coin store. A real app opens its own store in onTopUp; this is not part of the SDK. */
function CoinStore({
  open,
  onClose,
  onBuy,
}: {
  open: boolean;
  onClose(): void;
  onBuy(coins: number): void;
}) {
  return (
    <Modal visible={open} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable
        style={styles.storeBackdrop}
        onPress={onClose}
        accessibilityLabel="Close the store"
      >
        <Pressable style={styles.storeCard} onPress={() => {}} accessibilityRole="none">
          <Text style={styles.storeTitle}>Get coins</Text>
          <Text style={styles.storeNote}>Demo store: nothing is charged.</Text>
          {PACKS.map((p) => (
            <Pressable
              key={p.coins}
              style={styles.storePack}
              accessibilityRole="button"
              onPress={() => onBuy(p.coins)}
            >
              <Text style={styles.storePackText}>+{p.coins.toLocaleString("en-US")} coins</Text>
              <Text style={[styles.storePackText, { color: "#ffd27a" }]}>{p.price}</Text>
            </Pressable>
          ))}
          <Pressable onPress={onClose} accessibilityRole="button" style={{ padding: 10 }}>
            <Text style={styles.storeNote}>Not now</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

// ---------------------------------------------------------------- demo-only controls

/** A row of choices. Everything built from this is a demo control, never part of the SDK. */
function Choice<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: readonly [T, string][];
  onChange(v: T): void;
}) {
  return (
    <View style={styles.choiceRow}>
      <Text style={styles.demoTag}>{label}</Text>
      {options.map(([v, text]) => (
        <Pressable
          key={v}
          onPress={() => onChange(v)}
          accessibilityRole="button"
          aria-pressed={v === value}
          style={[styles.choice, v === value && styles.choiceOn]}
        >
          <Text style={[styles.choiceText, v === value && styles.choiceTextOn]}>{text}</Text>
        </Pressable>
      ))}
    </View>
  );
}

type Tab = "feed" | "away" | "board";

function FeedScreen() {
  const effects = useRef<GiftEffectLayerHandle>(null);
  const [wallKey, setWallKey] = useState(0);
  const tray = useGiftTray({
    client,
    receiver: "mateo",
    effects,
    reference: "post_42",
    onSent: () => setWallKey((k) => k + 1),
  });
  const [inset, setInset] = useState(290);
  const [store, setStore] = useState(false);
  const [mode, setMode] = useState<Mode>("normal");
  const [shown, setShown] = useState(0);
  const [tapped, setTapped] = useState("");
  return (
    <>
      <View style={styles.demoBar}>
        <Choice
          label="Demo only"
          value={mode}
          options={[
            ["normal", "Normal"],
            ["empty", "Empty"],
            ["error", "Fails"],
          ]}
          onChange={(m) => {
            client.setMode(m);
            setMode(m);
            wallLoaderFor(client).clear();
            setShown((n) => n + 1);
          }}
        />
        {tapped !== "" && (
          <Text style={styles.demoTag}>Chip tapped: {tapped} (your app opens the tray)</Text>
        )}
      </View>
      <View style={styles.post}>
        <Text style={styles.name}>mateo</Text>
        <Text style={styles.text}>
          New illustration is done. Three weeks of work, hope you like it!
        </Text>
        <View style={styles.media}>
          <Image
            source={{ uri: "/gifts/cloud-temple/512.webp" }}
            style={{ width: 110, height: 110 }}
            resizeMode="contain"
          />
        </View>
        {/* The component: a post's wall, tap a chip to open your own gift tray. */}
        <GiftWall
          key={shown}
          client={client}
          user="mateo"
          reference="post_42"
          refreshKey={wallKey}
          onPressChip={(g) => setTapped(g.name)}
        />
        <View style={styles.rowSep} />
        <Text style={styles.text}>Studio profile (small, not tappable, shortened counts)</Text>
        <GiftWall key={`p${shown}`} client={client} user="mateo" size="sm" max={4} />
        <View style={styles.rowSep} />
        <View style={{ gap: 6 }}>
          <Text style={styles.name}>mateo · earlier posts</Text>
          <GiftWall key={`b${shown}`} client={client} user="mateo" reference="post_43" />
          <GiftWall key={`c${shown}`} client={client} user="mateo" reference="post_44" />
        </View>
      </View>
      {tray.error && (
        <Text style={styles.error}>
          {tray.error.insufficientBalance ? "Not enough coins" : tray.error.message}
        </Text>
      )}
      <View style={{ flex: 1 }} />
      <GiftTray
        tray={tray}
        onTopUp={() => setStore(true)}
        onInsetChange={setInset}
        defaultSelectedId="pink-tulip"
      />
      <GiftEffectLayer ref={effects} noticeBottom={inset + 16} maxConcurrent={{ medium: 4 }} />
      <CoinStore
        open={store}
        onClose={() => setStore(false)}
        onBuy={(coins) => {
          setStore(false);
          client.credit(coins);
          void tray.refresh();
        }}
      />
    </>
  );
}

function AwayScreen() {
  const effects = useRef<GiftEffectLayerHandle>(null);
  const handle = useRef<GiftAwaySummaryHandle>(null);
  const [run, setRun] = useState(0);
  const [mode, setMode] = useState<"gifts" | "none" | "error">("gifts");
  const [quality, setQuality] = useState<"high" | "low">("high");
  const [log, setLog] = useState("");
  return (
    <>
      <View style={styles.post}>
        <Text style={styles.name}>Home</Text>
        <Text style={styles.text}>
          Your app's own screen. The card shows over it when the app opens and gifts arrived.
        </Text>
        <View style={[styles.media, { height: 120 }]} />
        <View style={[styles.media, { height: 120, backgroundColor: "#2a2250" }]} />
      </View>
      <View style={{ flex: 1 }} />
      <View style={styles.demoBar}>
        <Choice
          label="Demo only"
          value={mode}
          options={[
            ["gifts", "New gifts"],
            ["none", "Nothing new"],
            ["error", "Fails"],
          ]}
          onChange={(m) => {
            client.setAway(m);
            setMode(m);
          }}
        />
        <Choice<"high" | "low">
          label="Demo only"
          value={quality}
          options={[
            ["high", "High"],
            ["low", "Low quality"],
          ]}
          onChange={setQuality}
        />
        <Pressable
          style={styles.demoButton}
          accessibilityRole="button"
          onPress={() => {
            client.resetAway();
            setLog("");
            setRun((n) => n + 1);
          }}
        >
          <Text style={styles.choiceTextOn}>Demo only: open the app again</Text>
        </Pressable>
        {log !== "" && <Text style={styles.demoTag}>{log}</Text>}
      </View>
      {/* The component: checks when mounted, shows the card, replays through the effect layer. */}
      <GiftAwaySummary
        key={run}
        ref={handle}
        client={client}
        effects={effects}
        quality={quality}
        resolveUsers={resolveUsers}
        onShow={(s) => setLog(`onShow: ${s.total_gifts} gifts`)}
        onDone={() => setLog((l) => `${l}, onDone`)}
        onError={(e) => setLog(`onError: ${e.message}`)}
      />
      <GiftEffectLayer
        ref={effects}
        quality={quality}
        noticeBottom={120}
        maxConcurrent={{ medium: 4 }}
      />
    </>
  );
}

function BoardScreen() {
  const [mode, setMode] = useState<Mode>("normal");
  const [board, setBoard] = useState<LeaderboardBoard>("senders");
  const [run, setRun] = useState(0);
  const [tapped, setTapped] = useState("");
  return (
    <>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.boardWrap}>
        <Text style={[styles.name, { paddingHorizontal: 4 }]}>
          Top {board === "senders" ? "senders" : "receivers"}
        </Text>
        {/* The component. */}
        <GiftLeaderboard
          key={`${board}-${run}`}
          client={client}
          board={board}
          metricToggle
          limit={15}
          resolveUsers={resolveUsers}
          onPressUser={(id) => setTapped(NAMES[id] ?? id)}
        />
      </ScrollView>
      <View style={styles.demoBar}>
        <Choice
          label="Demo only"
          value={mode}
          options={[
            ["normal", "Normal"],
            ["slow", "Slow"],
            ["empty", "Empty"],
            ["error", "Fails"],
          ]}
          onChange={(m) => {
            client.setMode(m);
            setMode(m);
            setRun((n) => n + 1);
          }}
        />
        <Choice<LeaderboardBoard>
          label="Demo only"
          value={board}
          options={[
            ["senders", "Senders"],
            ["receivers", "Receivers"],
          ]}
          onChange={setBoard}
        />
        {tapped !== "" && <Text style={styles.demoTag}>Row tapped: {tapped}</Text>}
      </View>
    </>
  );
}

function Screen() {
  const [tab, setTab] = useState<Tab>("feed");
  const tabs = useMemo<[Tab, string][]>(
    () => [
      ["feed", "Gift wall"],
      ["away", "While away"],
      ["board", "Leaderboard"],
    ],
    [],
  );
  return (
    <View style={styles.phone}>
      <View style={styles.tabs}>
        <Text style={styles.demoTag}>Demo only</Text>
        {tabs.map(([t, label]) => (
          <Pressable
            key={t}
            onPress={() => setTab(t)}
            accessibilityRole="button"
            aria-pressed={tab === t}
            style={[styles.choice, tab === t && styles.choiceOn]}
          >
            <Text style={[styles.choiceText, tab === t && styles.choiceTextOn]}>{label}</Text>
          </Pressable>
        ))}
      </View>
      {tab === "feed" && <FeedScreen />}
      {tab === "away" && <AwayScreen />}
      {tab === "board" && <BoardScreen />}
    </View>
  );
}

const styles = StyleSheet.create({
  phone: {
    width: 390,
    height: 780,
    backgroundColor: "#0e0e16",
    borderRadius: 36,
    overflow: "hidden",
  },
  tabs: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingTop: 40,
    paddingHorizontal: 12,
    paddingBottom: 6,
  },
  post: { padding: 18, paddingTop: 10, gap: 10 },
  name: { color: "#f4f2ff", fontWeight: "700", fontSize: 16 },
  text: { color: "#f4f2ff", fontSize: 14 },
  media: {
    height: 130,
    borderRadius: 16,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#7c5cd6",
  },
  rowSep: { height: StyleSheet.hairlineWidth, backgroundColor: "#2d2d44" },
  boardWrap: { paddingHorizontal: 10, paddingTop: 6, gap: 8 },
  error: { color: "#ff8fa3", textAlign: "center", paddingBottom: 6 },
  demoBar: { paddingHorizontal: 12, paddingBottom: 8, gap: 6 },
  demoTag: { color: "#7d7ba0", fontSize: 10.5, fontWeight: "700", textTransform: "uppercase" },
  choiceRow: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  choice: {
    paddingVertical: 4,
    paddingHorizontal: 10,
    borderRadius: 999,
    backgroundColor: "#1e1e2e",
  },
  choiceOn: { backgroundColor: "#4a3fb0" },
  choiceText: { color: "#a3a1c2", fontSize: 11.5, fontWeight: "700" },
  choiceTextOn: { color: "#ffffff", fontSize: 11.5, fontWeight: "700" },
  demoButton: {
    alignSelf: "flex-start",
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 999,
    backgroundColor: "#4a3fb0",
  },
  storeBackdrop: {
    flex: 1,
    justifyContent: "flex-end",
    alignItems: "center",
    backgroundColor: "rgba(0,0,0,0.55)",
  },
  storeCard: {
    width: "100%",
    maxWidth: 390,
    gap: 10,
    padding: 16,
    paddingBottom: 22,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    backgroundColor: "#1e1e2e",
  },
  storeTitle: { color: "#f4f2ff", fontSize: 16, fontWeight: "700" },
  storeNote: { color: "#a3a1c2", fontSize: 12, textAlign: "center" },
  storePack: {
    flexDirection: "row",
    justifyContent: "space-between",
    padding: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "#2d2d44",
    backgroundColor: "#14141f",
  },
  storePackText: { color: "#f4f2ff", fontSize: 15, fontWeight: "700" },
});

createRoot(document.getElementById("root")!).render(<Screen />);
