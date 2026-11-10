/** A gift as the app sees it (`GET /v1/client/gifts`). */
export interface Gift {
  id: string;
  name: string;
  description: string | null;
  price: number;
  icon_url: string | null;
  animation_url: string | null;
  sort_order: number;
}

export interface Me {
  user: string;
  balance: number;
  /**
   * `false`: the token was made with a test key. The test environment allows 50 users and 5,000
   * operations a month, and the tray shows "Test mode". Absent from older servers.
   */
  livemode?: boolean;
}

export interface ReceivedGift {
  gift: { id: string; name: string; icon_url: string | null };
  count: number;
}

/** What `POST /v1/client/gift-transactions` returns. */
export interface GiftTransaction {
  id: string;
  sender: string;
  receiver: string;
  gift: { id: string; name: string; icon_url: string | null };
  quantity: number;
  unit_price: number;
  total: number;
  message: string | null;
  reference: string | null;
  status: "completed" | "reversed";
  created_at: string;
  sender_balance_after: number;
}

export interface SendGiftInput {
  receiver: string;
  giftId: string;
  /** 1 to 1000. Default 1. */
  quantity?: number;
  /** Up to 280 characters. */
  message?: string;
  /** Your own context id, for example the post the gift is on. */
  reference?: string;
  /** A room id (SPEC 17.1): everyone in that room sees the gift's effect. */
  roomId?: string;
  /**
   * Identifies this send. Retrying with the same key never charges twice. The client makes
   * one per call; pass your own only if you retry across app restarts.
   */
  idempotencyKey?: string;
}

/** What an effect player needs to show a gift. */
export interface GiftEffectEvent {
  gift: Pick<Gift, "id" | "name" | "price"> & {
    /** Large picture shown with the effect (512 px). Falls back to the icon. */
    image: string | null;
    /**
     * Small picture for the "sent" notice (the 256 px icon). Give the one your tray already shows:
     * it is loaded by then, so the notice appears complete. Falls back to `image`.
     */
    icon?: string | null;
  };
  /** Who sent it, shown in the notice. */
  sender?: string;
  /** How many were sent in this one send. Default 1. */
  quantity?: number;
  /**
   * Who got the gift, for a battle (SPEC 7.4): the notice then reads "sent Rose to Mia" and its
   * pill gets a border in the side's colour. Leave it out outside battles.
   */
  receiver?: GiftEffectReceiver;
}

/** The receiving side of a battle gift (SPEC 7.4, 18.4). */
export interface GiftEffectReceiver {
  /** Shown in the notice. */
  name: string;
  /** 0 = first side, 1 = second side (the battle bar's order). Picks the default colour. */
  side?: number;
  /** A CSS/hex colour for the border; null or absent: the side's default (accent, coin). */
  color?: string | null;
}

// ---------------------------------------------------------------- gift walls (SPEC section 14)

/** One wall of the batch call: a receiver's profile wall, or one post's wall with `reference`. */
export interface GiftWallQueryItem {
  receiver: string;
  /** Your own context id the gifts were sent with (for example a post id). Absent: profile wall. */
  reference?: string | null;
}

/** One answer of `POST /v1/client/gift-walls/query`, in the order of the request. */
export interface GiftWall {
  receiver: string;
  reference: string | null;
  /** Counters per gift, in catalog order. Empty for unknown users. */
  gifts: ReceivedGift[];
}

// ---------------------------------------------------------------- away summary (SPEC section 15)

export interface AwayQuery {
  /** An opaque `cursor` from an earlier summary. Overrides the stored cursor for this read. */
  since?: string;
  /** Most gift groups to return, 1 to 10. Server default 5. */
  maxGroups?: number;
}

export interface AwaySender {
  /** External id; `null` = deleted senders (all merged into one entry). */
  user: string | null;
  count: number;
}

export interface AwayGroup {
  gift: {
    id: string;
    name: string;
    /** Today's catalog price: the effect tier matches the tray's. */
    price: number;
    icon_url: string | null;
    animation_url: string | null;
  };
  /** Number of gifts (sum of quantities). */
  count: number;
  /** Value in your own coin units. A display counter, never a balance. */
  units: number;
  /** Distinct people who sent this gift. */
  sender_count: number;
  /** At most 3, by count. */
  senders: AwaySender[];
}

/** What `GET /v1/client/me/away` returns: gifts received since the person last looked. */
export interface AwaySummary {
  user: string;
  since: string;
  until: string;
  /** Send this to `ackAway` once the summary was shown. Unchanged when nothing is new. */
  cursor: string | null;
  /** More than 2,000 gifts arrived: the totals are lower bounds ("2,000+"). */
  truncated: boolean;
  total_gifts: number;
  total_units: number;
  sender_count: number;
  /** Biggest first (by units), at most `maxGroups`. */
  groups: AwayGroup[];
  /** At most 5, by count. */
  top_senders: (AwaySender & { units: number })[];
}

// ---------------------------------------------------------------- gift inbox (SPEC section 19)

export interface InboxQuery {
  /** `next_cursor` of the previous page: the next (older) page. */
  cursor?: string;
  /** Rows per page, 1 to 100. Server default 20. */
  limit?: number;
}

export interface InboxItem {
  id: string;
  /** ISO time the gift was sent. */
  created_at: string;
  /** External id of the sender; `null` = a deleted sender. */
  sender: string | null;
  gift: {
    id: string;
    name: string;
    price: number;
    icon_url: string | null;
    animation_url: string | null;
  };
  quantity: number;
  /** Value in your own coin units. A display counter, never a balance. */
  units: number;
  status: "completed" | "reversed";
}

/** What `GET /v1/client/me/inbox` returns: the gifts received over the last 24 hours, newest first. */
export interface Inbox {
  user: string;
  since: string;
  until: string;
  data: InboxItem[];
  has_more: boolean;
  /** Pass to `getInbox({ cursor })` for the next (older) page. */
  next_cursor: string | null;
}

// ---------------------------------------------------------------- leaderboards (SPEC section 16)

export type LeaderboardBoard = "senders" | "receivers";
export type LeaderboardPeriod = "day" | "week" | "month" | "all";
export type LeaderboardMetric = "units" | "gifts";

export interface LeaderboardQuery {
  /** Default `week` (server). */
  period?: LeaderboardPeriod;
  /** Default `units` (server). */
  metric?: LeaderboardMetric;
  /** `YYYY-MM-DD`, any day inside the wanted period (UTC). Default today. Ignored for `all`. */
  at?: string;
  /** 1 to 100. Default 10 (server). */
  limit?: number;
  /** `false` leaves out the `me` block. Default true. */
  includeMe?: boolean;
}

export interface LeaderboardEntry {
  /** Competition rank on the metric: equal scores share a rank (1, 2, 2, 4). */
  rank: number;
  user: string;
  gifts: number;
  units: number;
}

export interface LeaderboardMe {
  user: string;
  /** Exact within the top 1,000, else `null` ("1,000+"). Also `null` without a score or when hidden. */
  rank: number | null;
  gifts: number;
  units: number;
  hidden: boolean;
}

/** What `GET /v1/client/leaderboards/{board}` returns. */
export interface Leaderboard {
  board: LeaderboardBoard;
  period: LeaderboardPeriod;
  metric: LeaderboardMetric;
  /** `2026-10-11`, `2026-W41`, `2026-10` or `all`. */
  label: string;
  starts_at: string | null;
  ends_at: string | null;
  as_of: string;
  data: LeaderboardEntry[];
  has_more: boolean;
  me: LeaderboardMe | null;
}
