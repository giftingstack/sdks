/**
 * What the battle bar (SPEC 18.6) shows, as plain data: the split, the clock, the winner, the
 * words and the two side colours. Pure, no UI: the web and React Native bars draw it, other
 * platforms port this file. The scores themselves come from `battleView`.
 */
import { type BattleView, type RoomScoreEntry } from "./rooms";
import { type GiftTheme, contrastRatio, parseHex, resolveTheme } from "./theme";
import { formatCount } from "./wall";
import { groupThousands } from "./leaderboard";

/** Every word of the bar. `{name}`, `{a}`, `{b}` mark a place a value goes. */
export interface BattleBarLabels {
  /** The small "VS" over the clock. */
  vs: string;
  /** The clock when the round has ended. */
  final: string;
  /** Below the bar when a side won. */
  wins: string;
  /** Below the bar when the round ended level. */
  draw: string;
  /** The spoken summary: `"{a}, {b}"`, each side `"{name} {score}"`. */
  spoken: string;
  side: string;
  /** Count suffixes, as in `formatCount`. */
  thousand: string;
  million: string;
}

export const defaultBattleBarLabels: BattleBarLabels = {
  vs: "VS",
  final: "Final",
  wins: "{name} wins the round",
  draw: "Draw: nobody wins this round",
  spoken: "{a}, {b}",
  side: "{name} {score}",
  thousand: "K",
  million: "M",
};

export type BattleBarLabelsInput = Partial<BattleBarLabels>;

export const resolveBattleBarLabels = (labels?: BattleBarLabelsInput): BattleBarLabels => ({
  ...defaultBattleBarLabels,
  ...labels,
});

const fillText = (template: string, values: Record<string, string>): string =>
  template.replace(/\{(\w+)\}/g, (m, k: string) => values[k] ?? m);

/** Seconds left on the clock at which it turns urgent. */
export const BATTLE_URGENT_SECONDS = 10;
/** The boundary never leaves this band, so both sides stay visible (percent of the bar). */
export const BATTLE_MIN_SHARE_PCT = 6;

/** A score for the bar: 9,999 in full, then `10K`, `1.2M`. */
export function formatBattleScore(n: number, labels: BattleBarLabelsInput = {}): string {
  const l = resolveBattleBarLabels(labels);
  return n >= 10_000
    ? formatCount(n, { thousand: l.thousand, million: l.million })
    : groupThousands(Math.max(0, Math.trunc(n)));
}

/** `m:ss`, rounded up like a countdown. */
export function formatBattleClock(remainingMs: number): string {
  const secs = Math.max(0, Math.ceil(remainingMs / 1000));
  return `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`;
}

export interface BattleBarSide {
  id: string;
  name: string;
  /** Full score and its short form. */
  units: number;
  score: string;
  /** Spoken: `"Mia 1,800"`. */
  spoken: string;
  /** This side leads while the round is open, or won it. */
  leads: boolean;
  won: boolean;
  lost: boolean;
}

export interface BattleBarModel {
  /** Every side of the round, in the server's order: two or more (up to the API's 8). */
  sides: BattleBarSide[];
  /** The first side's part of the bar, percent, kept inside the visible band (= `pcts[0]`). */
  pct: number;
  /**
   * Every side's part of the bar, percent, in order, summing to 100; none under
   * `BATTLE_MIN_SHARE_PCT` (a side under it is held at it, the rest share what is left).
   */
  pcts: number[];
  clock: string;
  /** Under `BATTLE_URGENT_SECONDS` and still open. */
  urgent: boolean;
  /** The round has ended. */
  final: boolean;
  winner: string | null;
  /** The line under the bar once the round ended; empty before. */
  banner: string;
  /** One sentence for a screen reader: both sides and their scores. */
  spoken: string;
}

/**
 * Every side's part of a bar, percent (SPEC 18.7): `share x 100`, but no side under
 * `BATTLE_MIN_SHARE_PCT`: such a side is held at the minimum and the rest share what is left in
 * proportion to their shares, repeated until every part is visible. Sums to 100. For two sides
 * this is the clamp of the first part to 6..94.
 */
export function battleSegmentPcts(shares: readonly number[]): number[] {
  const n = shares.length;
  const pinned = new Array<boolean>(n).fill(false);
  const out = new Array<number>(n).fill(0);
  for (;;) {
    const free = shares.map((_, i) => i).filter((i) => !pinned[i]);
    const left = 100 - BATTLE_MIN_SHARE_PCT * (n - free.length);
    const sum = free.reduce((s, i) => s + shares[i]!, 0);
    let again = false;
    for (const i of free) {
      out[i] = sum > 0 ? (shares[i]! / sum) * left : left / free.length;
      if (out[i]! < BATTLE_MIN_SHARE_PCT) {
        pinned[i] = true;
        again = true;
      }
    }
    if (!again) break;
    for (let i = 0; i < n; i++) if (pinned[i]) out[i] = BATTLE_MIN_SHARE_PCT;
  }
  for (let i = 0; i < n; i++) if (pinned[i]) out[i] = BATTLE_MIN_SHARE_PCT;
  return out;
}

/**
 * The bar for one `BattleView`, or null when it has fewer than two sides (a round with one
 * receiver has nothing to compare). Every side is a cell of the bar (a free-for-all of up to 8);
 * two sides look exactly as the versus always did.
 */
export function battleBarModel(
  view: BattleView | null,
  options: { nameOf?: (id: string) => string; labels?: BattleBarLabelsInput } = {},
): BattleBarModel | null {
  if (!view || view.sides.length < 2) return null;
  const l = resolveBattleBarLabels(options.labels);
  const nameOf = options.nameOf ?? ((id: string) => id);
  const final = !view.open;
  const side = (s: RoomScoreEntry): BattleBarSide => {
    const name = nameOf(s.id);
    const score = formatBattleScore(s.units, l);
    return {
      id: s.id,
      name,
      units: s.units,
      score,
      spoken: fillText(l.side, { name, score: groupThousands(Math.trunc(s.units)) }),
      leads: view.leader === s.id,
      won: final && view.leader === s.id,
      lost: final && view.leader !== null && view.leader !== s.id,
    };
  };
  const sides = view.sides.map(side);
  const secs = Math.ceil(view.remainingMs / 1000);
  const winner = final ? view.leader : null;
  const pct = Math.min(
    100 - BATTLE_MIN_SHARE_PCT,
    Math.max(BATTLE_MIN_SHARE_PCT, view.sides[0]!.share * 100),
  );
  const pcts =
    sides.length === 2 ? [pct, 100 - pct] : battleSegmentPcts(view.sides.map((s) => s.share));
  return {
    sides,
    pct: sides.length === 2 ? pct : pcts[0]!,
    pcts,
    clock: final ? l.final : formatBattleClock(view.remainingMs),
    urgent: !final && secs <= BATTLE_URGENT_SECONDS,
    final,
    winner,
    banner: !final
      ? ""
      : winner
        ? fillText(l.wins, { name: sides.find((s) => s.id === winner)?.name ?? winner })
        : l.draw,
    // Two sides: the `spoken` label (`"{a}, {b}"`); more: every side's spoken text, joined by ", ".
    spoken:
      sides.length === 2
        ? fillText(l.spoken, { a: sides[0]!.spoken, b: sides[1]!.spoken })
        : sides.map((s) => s.spoken).join(", "),
  };
}

/** A colour and the text colour that reads on it (black or white, whichever has more contrast). */
export interface SideColor {
  color: string;
  text: string;
}

const readableOn = (hex: string): string =>
  !parseHex(hex) || contrastRatio("#ffffff", hex) >= contrastRatio("#000000", hex)
    ? "#ffffff"
    : "#000000";

/**
 * The third and fourth side colour of the default palette (teal, pink); the fifth side starts
 * over with the theme's accent. Their text colour is picked by contrast, like an override's.
 */
export const BATTLE_EXTRA_COLORS = ["#2ec4b6", "#ff5d8f"] as const;

/**
 * The colour of every side of a bar or notice (SPEC 18.7, 7.4): side `i` takes `override[i]` when
 * the app gave one (text picked by contrast), else the default palette: the theme's accent, its
 * coin colour (each with the theme's own text colour on it, already 4.5:1 in both presets), then
 * `BATTLE_EXTRA_COLORS`, then the same four again.
 */
export function battleSidePalette(
  theme: Partial<GiftTheme> | undefined,
  count: number,
  override?: readonly string[],
): SideColor[] {
  const t = resolveTheme(theme);
  const defaults: SideColor[] = [
    { color: t.accent, text: t.accentText },
    { color: t.coin, text: t.coinText },
    ...BATTLE_EXTRA_COLORS.map((color) => ({ color, text: readableOn(color) })),
  ];
  return Array.from({ length: count }, (_, i) => {
    const own = override?.[i];
    return own ? { color: own, text: readableOn(own) } : defaults[i % defaults.length]!;
  });
}

/**
 * The two side colours: the theme's accent against its coin colour (each with the theme's own
 * text colour on it, already 4.5:1 in both presets), or `override` (text picked by contrast).
 * `battleSidePalette` for any number of sides.
 */
export function battleSideColors(
  theme?: Partial<GiftTheme>,
  override?: readonly string[],
): [SideColor, SideColor] {
  const [a, b] = battleSidePalette(theme, 2, override);
  return [a!, b!];
}

/** Which sides gained score since `before` (to pulse them). `before` null: nobody pulses. */
export function battleGains(before: number[] | null, after: number[]): boolean[] {
  return after.map((u, i) => before !== null && u > (before[i] ?? u));
}
