import type { LeaderboardPeriod } from "../core";

/**
 * Every visible and spoken word of the gift wall, the "while you were away" card and the
 * leaderboard. Pass any of them as `labels` (translations); the rest keep the English default.
 * `{x}` marks a place a value goes. The same keys and defaults as the React Native components.
 */
export interface GiftLabels {
  /** Count suffixes of `formatCount`. Defaults `"K"` and `"M"`. */
  thousand: string;
  million: string;
  /** A deleted sender. */
  someone: string;

  /** Wall: the row as one element. `{list}` = `"12 Roses, 3 Hearts"`, then `wallMore`. */
  wallSummary: string;
  /** Wall: the end of `{list}` when more gifts exist. */
  wallMore: string;
  /** Wall: a tappable chip, for example `"Rose, 12"`. */
  wallChip: string;
  /** Wall: added to a gift name when its count is above 1 (`"12 Roses"`). */
  plural: string;
  /** Wall: text under the chips when nothing was received. Default none (the wall is empty). */
  emptyText: string;

  /** Away card. */
  awayTitle: string;
  /** `{gifts}` and `{people}` are `giftOne`/`giftOther` and `personOne`/`personOther`. */
  awaySummary: string;
  awayAnnounce: string;
  giftOne: string;
  giftOther: string;
  personOne: string;
  personOther: string;
  dismiss: string;

  /** Leaderboard. */
  tabs: Record<LeaderboardPeriod, string>;
  empty: Record<LeaderboardPeriod, string>;
  /** Metric switch. `metricUnits` defaults to the capitalised `coinName`. */
  metricUnits: string;
  metricGifts: string;
  metricSwitch: string;
  giftsWord: string;
  error: string;
  tryAgain: string;
  /** `{rank}` is `"#417"` or `rankOverflow`. */
  pinned: string;
  pinnedSpoken: string;
  rowSpoken: string;
  rankOverflow: string;
  loading: string;
  updating: string;

  /** Gift inbox. `{name}` and `{gift}`; `{n}` is the quantity (shown when above 1). */
  inboxSent: string;
  inboxSentMany: string;
  /** The row as one element: `{sentence}` and `{time}` (`"now"`, `"5m"`, `"3h"`, `"1d"`). */
  inboxSpoken: string;
  inboxEmpty: string;
  inboxError: string;
  showMore: string;
}

export const defaultLabels: GiftLabels = {
  thousand: "K",
  million: "M",
  someone: "Someone",

  wallSummary: "Gifts: {list}",
  wallMore: "and {n} more",
  wallChip: "{name}, {count}",
  plural: "s",
  emptyText: "",

  awayTitle: "While you were away",
  awaySummary: "{gifts} from {people}",
  awayAnnounce: "You received {summary} while you were away",
  giftOne: "{n} gift",
  giftOther: "{n} gifts",
  personOne: "{n} person",
  personOther: "{n} people",
  dismiss: "Dismiss",

  tabs: { day: "Today", week: "This week", month: "This month", all: "All time" },
  empty: {
    day: "No gifts yet today",
    week: "No gifts yet this week",
    month: "No gifts yet this month",
    all: "No gifts yet",
  },
  metricUnits: "",
  metricGifts: "Gifts",
  metricSwitch: "Ranked by",
  giftsWord: "gifts",
  error: "Could not load the leaderboard.",
  tryAgain: "Try again",
  pinned: "You: {rank}",
  pinnedSpoken: "Your rank: {rank}, {score}",
  rowSpoken: "Rank {rank}, {name}, {score}",
  rankOverflow: "1,000+",
  loading: "Loading",
  updating: "Updating",

  inboxSent: "{name} sent you {gift}",
  inboxSentMany: "{name} sent you {gift} x{n}",
  inboxSpoken: "{sentence}, {time}",
  inboxEmpty: "No gifts in the last 24 hours",
  inboxError: "Could not load gifts",
  showMore: "Show more",
};

export type GiftLabelsInput = Partial<Omit<GiftLabels, "tabs" | "empty">> & {
  tabs?: Partial<GiftLabels["tabs"]>;
  empty?: Partial<GiftLabels["empty"]>;
};

export function resolveLabels(labels?: GiftLabelsInput): GiftLabels {
  return {
    ...defaultLabels,
    ...labels,
    tabs: { ...defaultLabels.tabs, ...labels?.tabs },
    empty: { ...defaultLabels.empty, ...labels?.empty },
  };
}

/** `fill("Rank {rank}", { rank: 1 })`. */
export function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (m, k: string) => (k in values ? String(values[k]) : m));
}
