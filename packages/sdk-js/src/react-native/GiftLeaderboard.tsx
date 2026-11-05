import {
  type ReactNode,
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from "react";
import {
  ActivityIndicator,
  Animated,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type ViewStyle,
} from "react-native";
import {
  type GiftingClient,
  type GiftingError,
  type Leaderboard,
  type LeaderboardBoard,
  type LeaderboardEntry,
  type LeaderboardMe,
  type LeaderboardMetric,
  type LeaderboardPeriod,
  RANK_COLORS,
  formatCount,
  groupThousands,
  leaderboardRankLabel,
} from "../core";
import { type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { useReducedMotion } from "./reduced-motion";
import { type GiftTheme, resolveTheme } from "./theme";
import { Avatar, CoinDot, useSkeletonOpacity } from "./ui-parts";
import { useGiftLeaderboard } from "./useGiftLeaderboard";

export interface LeaderboardUser {
  name: string;
  avatarUrl?: string | null;
}

/** What `renderRow` receives for one ranked row. */
export interface LeaderboardRowInfo {
  entry: LeaderboardEntry;
  rank: number;
  /** The display name (from `resolveUsers`), else the id. */
  name: string;
  avatarUrl: string | null;
  metric: LeaderboardMetric;
  /** The score for the shown metric: coins (`"units"`) or gifts. */
  score: number;
  /** The score as the default row shows it (`54K`). */
  scoreText: string;
  /** Whether this is the highlighted (signed-in) person. */
  isMe: boolean;
  /** The resolved theme, so your row can match the rest. */
  theme: GiftTheme;
}

export interface GiftLeaderboardProps {
  client: GiftingClient;
  /** `"senders"` (default) or `"receivers"`. */
  board?: LeaderboardBoard;
  /** Tabs, in this order. One item: no tabs. Default day, week, month, all. */
  periods?: readonly LeaderboardPeriod[];
  /** Default `"week"`. */
  initialPeriod?: LeaderboardPeriod;
  /** `"units"` (default for senders) or `"gifts"` (default for receivers). */
  metric?: LeaderboardMetric;
  /** Show a switch between coins and gifts. Default false. */
  metricToggle?: boolean;
  /** Rows, 1 to 100. Default 10. */
  limit?: number;
  /** External ids are often not display names: map them here. Unknown ids keep the id. */
  resolveUsers?: (ids: string[]) => Promise<Record<string, LeaderboardUser>>;
  /** Whose row is highlighted. Default: the signed-in user. */
  highlightUser?: string;
  /** 0 (default): no polling. Otherwise at least 5,000 ms. */
  refreshIntervalMs?: number;
  /**
   * Draw the inside of each ranked row yourself (RN / web only, pending native port). The board
   * keeps loading, ordering, names, the row container (highlight, press, accessibility label) and
   * the pinned row. Return a node; `null`, `undefined` or `false` draws the default rank,
   * avatar, name and score. The pinned "You: #417" row stays the default.
   */
  renderRow?: (row: LeaderboardRowInfo) => ReactNode;
  /** Makes the rows buttons. Open a profile here. */
  onPressUser?: (id: string) => void;
  onError?: (error: GiftingError) => void;
  /** Default: follows the phone's "reduce motion" setting (no pulse, no spinner). */
  reducedMotion?: boolean;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  /** Name of your currency, used in labels and for screen readers. Default "coins". */
  coinName?: string;
  style?: StyleProp<ViewStyle>;
}

export interface GiftLeaderboardHandle {
  /** Fetch the shown tab again (pull to refresh). */
  refresh(): void;
}

const ROW_HEIGHT = 52;
const capitalise = (s: string) => (s ? s[0]!.toUpperCase() + s.slice(1) : s);

/**
 * Top senders or top receivers: tabs for today, this week, this month and all time, an optional
 * coins / gifts switch, up to 100 rows with medals for the first three, and the viewer's own
 * position pinned underneath when they are not in the rows.
 */
export const GiftLeaderboard = forwardRef<GiftLeaderboardHandle, GiftLeaderboardProps>(
  function GiftLeaderboard(props, ref) {
    const {
      client,
      board = "senders",
      resolveUsers,
      onPressUser,
      renderRow,
      metricToggle = false,
      coinName = "coins",
      style,
    } = props;
    const limit = props.limit ?? 10;
    const theme = resolveTheme(props.theme);
    const labels = resolveLabels(props.labels);
    const reduced = useReducedMotion(props.reducedMotion);
    const lb = useGiftLeaderboard({
      client,
      board,
      periods: props.periods,
      initialPeriod: props.initialPeriod,
      metric: props.metric,
      limit,
      refreshIntervalMs: props.refreshIntervalMs,
      onError: props.onError,
    });
    const { state } = lb;
    useImperativeHandle(ref, () => ({ refresh: lb.refresh }), [lb.refresh]);

    // Names for the rows on screen.
    const [users, setUsers] = useState<Record<string, LeaderboardUser>>({});
    const asked = useRef(new Set<string>());
    const resolveRef = useRef(resolveUsers);
    resolveRef.current = resolveUsers;
    const ids = [
      ...new Set([
        ...(state.data?.data.map((r) => r.user) ?? []),
        ...(state.pinned ? [state.pinned.user] : []),
      ]),
    ];
    const idsKey = ids.join("\u0000");
    useEffect(() => {
      const resolve = resolveRef.current;
      const fresh = ids.filter((id) => !asked.current.has(id));
      if (!resolve || fresh.length === 0) return;
      fresh.forEach((id) => asked.current.add(id));
      let alive = true;
      resolve(fresh).then(
        (found) => alive && setUsers((prev) => ({ ...prev, ...found })),
        () => fresh.forEach((id) => asked.current.delete(id)),
      );
      return () => {
        alive = false;
      };
      // `ids` is derived from `idsKey`.
    }, [idsKey]);

    const pulse = useSkeletonOpacity(reduced);
    const me = state.data?.me?.user;
    const highlight = props.highlightUser ?? me;
    const metric = state.metric;
    const unitsName = labels.metricUnits || capitalise(coinName);
    const nameOf = (id: string) => users[id]?.name ?? id;
    const score = (e: { gifts: number; units: number }, spoken: boolean) =>
      metric === "units"
        ? spoken
          ? `${groupThousands(e.units)} ${coinName}`
          : formatCount(e.units, labels)
        : spoken
          ? `${groupThousands(e.gifts)} ${labels.giftsWord}`
          : groupThousands(e.gifts);

    const renderScore = (e: { gifts: number; units: number }) => (
      <View style={styles.score}>
        <Text style={[styles.scoreText, { color: theme.text }]}>{score(e, false)}</Text>
        {metric === "units" ? (
          <CoinDot color={theme.coin} size={11} />
        ) : (
          <Text style={[styles.scoreUnit, { color: theme.muted }]}>{labels.giftsWord}</Text>
        )}
      </View>
    );

    const row = (e: LeaderboardEntry) => {
      const medal = e.rank >= 1 && e.rank <= 3 ? RANK_COLORS[`rank${e.rank as 1 | 2 | 3}`] : null;
      const name = nameOf(e.user);
      const mine = e.user === highlight;
      const custom = renderRow
        ? renderRow({
            entry: e,
            rank: e.rank,
            name,
            avatarUrl: users[e.user]?.avatarUrl ?? null,
            metric,
            score: metric === "units" ? e.units : e.gifts,
            scoreText: score(e, false),
            isMe: mine,
            theme,
          })
        : null;
      const inner =
        custom !== null && custom !== undefined && custom !== false ? (
          custom
        ) : (
          <>
            <View
              style={[styles.rank, medal ? { backgroundColor: medal } : null]}
              testID={medal ? `gift-lb-medal-${e.rank}` : undefined}
            >
              <Text style={[styles.rankText, { color: medal ? theme.noticeBigText : theme.muted }]}>
                {groupThousands(e.rank)}
              </Text>
            </View>
            <Avatar name={name} url={users[e.user]?.avatarUrl} size={32} theme={theme} />
            <Text numberOfLines={1} style={[styles.name, { color: theme.text }]}>
              {name}
            </Text>
            {renderScore(e)}
          </>
        );
      const label = fill(labels.rowSpoken, {
        rank: e.rank,
        name,
        score: score(e, true),
      });
      const common = {
        accessibilityLabel: label,
        style: [styles.row, mine && { backgroundColor: theme.selected }],
        testID: `gift-lb-row-${e.user}`,
      };
      return onPressUser ? (
        <Pressable
          key={`${e.rank}-${e.user}`}
          {...common}
          accessibilityRole="button"
          onPress={() => onPressUser(e.user)}
        >
          {inner}
        </Pressable>
      ) : (
        <View key={`${e.rank}-${e.user}`} {...common} accessible role="listitem">
          {inner}
        </View>
      );
    };

    const pinnedRow = (m: LeaderboardMe) => {
      const rankText = leaderboardRankLabel(m.rank, { overflow: labels.rankOverflow });
      const name = nameOf(m.user);
      const inner = (
        <>
          <Avatar name={name} url={users[m.user]?.avatarUrl} size={32} theme={theme} />
          <Text numberOfLines={1} style={[styles.name, { color: theme.text }]}>
            {fill(labels.pinned, { rank: rankText })}
          </Text>
          {renderScore(m)}
        </>
      );
      const common = {
        accessibilityLabel: fill(labels.pinnedSpoken, {
          rank: m.rank === null ? labels.rankOverflow : groupThousands(m.rank),
          score: score(m, true),
        }),
        style: [
          styles.row,
          styles.pinned,
          { backgroundColor: theme.selected, borderColor: theme.border },
        ],
        testID: "gift-lb-pinned",
      };
      return onPressUser ? (
        <Pressable {...common} accessibilityRole="button" onPress={() => onPressUser(m.user)}>
          {inner}
        </Pressable>
      ) : (
        <View {...common} accessible>
          {inner}
        </View>
      );
    };

    const tab = (selected: boolean, label: string, onPress: () => void, role: "tab" | "radio") => (
      <Pressable
        key={label}
        onPress={onPress}
        accessibilityRole={role}
        {...(role === "tab" ? { "aria-selected": selected } : { "aria-checked": selected })}
        accessibilityLabel={label}
        hitSlop={{ top: 6, bottom: 6, left: 2, right: 2 }}
        style={[styles.tab, { backgroundColor: selected ? theme.accent : "transparent" }]}
        testID={`gift-lb-${role}-${label}`}
      >
        <Text style={[styles.tabText, { color: selected ? theme.accentText : theme.muted }]}>
          {label}
        </Text>
      </Pressable>
    );

    const data: Leaderboard | null = state.data;
    let body;
    if (state.status === "loading") {
      body = (
        <View accessibilityLabel={labels.loading} aria-busy accessible>
          {Array.from({ length: limit }, (_, i) => (
            <View key={i} style={styles.row} testID="gift-lb-skeleton-row">
              <Animated.View
                style={[styles.rank, { backgroundColor: theme.border, opacity: pulse }]}
              />
              <Animated.View
                style={[styles.skelAvatar, { backgroundColor: theme.border, opacity: pulse }]}
              />
              <Animated.View
                style={[
                  styles.skelName,
                  { backgroundColor: theme.border, opacity: pulse, width: 90 + ((i * 37) % 60) },
                ]}
              />
            </View>
          ))}
        </View>
      );
    } else if (state.status === "error") {
      body = (
        <View style={styles.message} testID="gift-lb-error">
          <Text style={[styles.messageText, { color: theme.danger }]} accessibilityRole="alert">
            {labels.error}
          </Text>
          <Pressable
            onPress={lb.refresh}
            accessibilityRole="button"
            style={[styles.retry, { backgroundColor: theme.accent }]}
            testID="gift-lb-retry"
          >
            <Text style={[styles.retryText, { color: theme.accentText }]}>{labels.tryAgain}</Text>
          </Pressable>
        </View>
      );
    } else if (state.status === "empty" || !data) {
      body = (
        <View style={styles.message} testID="gift-lb-empty">
          <Text style={[styles.messageText, { color: theme.muted }]}>
            {labels.empty[state.period]}
          </Text>
        </View>
      );
    } else {
      body = (
        <View accessibilityRole="list" testID="gift-lb-list">
          {data.data.map(row)}
        </View>
      );
    }

    return (
      <View
        style={[styles.root, { backgroundColor: theme.surface, borderColor: theme.border }, style]}
      >
        <View style={styles.header}>
          {state.periods.length > 1 && (
            <View accessibilityRole="tablist" style={styles.tabs} testID="gift-lb-tabs">
              {state.periods.map((p) =>
                tab(state.period === p, labels.tabs[p], () => lb.setPeriod(p), "tab"),
              )}
            </View>
          )}
          <View style={styles.spacer} />
          {state.refreshing && !reduced && (
            <ActivityIndicator
              size="small"
              color={theme.muted}
              accessibilityLabel={labels.updating}
              testID="gift-lb-spinner"
            />
          )}
        </View>
        {metricToggle && (
          <View
            accessibilityRole="radiogroup"
            accessibilityLabel={labels.metricSwitch}
            style={styles.tabs}
            testID="gift-lb-metric"
          >
            {tab(metric === "units", unitsName, () => lb.setMetric("units"), "radio")}
            {tab(metric === "gifts", labels.metricGifts, () => lb.setMetric("gifts"), "radio")}
          </View>
        )}
        {body}
        {state.pinned && state.status !== "loading" && pinnedRow(state.pinned)}
      </View>
    );
  },
);

const styles = StyleSheet.create({
  root: { borderRadius: 20, borderWidth: StyleSheet.hairlineWidth, padding: 8, gap: 8 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    minHeight: 32,
    paddingHorizontal: 4,
  },
  tabs: { flexDirection: "row", gap: 4, paddingHorizontal: 4 },
  spacer: { flex: 1 },
  tab: { minHeight: 32, paddingHorizontal: 12, borderRadius: 999, justifyContent: "center" },
  tabText: { fontSize: 13, fontWeight: "700" },
  row: {
    height: ROW_HEIGHT,
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingHorizontal: 8,
    borderRadius: 14,
  },
  pinned: { borderTopWidth: StyleSheet.hairlineWidth },
  rank: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: "center",
    justifyContent: "center",
  },
  rankText: { fontSize: 13, fontWeight: "800", fontVariant: ["tabular-nums"] },
  name: { flex: 1, fontSize: 14, fontWeight: "700" },
  score: { flexDirection: "row", alignItems: "center", gap: 5 },
  scoreText: { fontSize: 13.5, fontWeight: "800", fontVariant: ["tabular-nums"] },
  scoreUnit: { fontSize: 11.5, fontWeight: "600" },
  skelAvatar: { width: 32, height: 32, borderRadius: 16 },
  skelName: { height: 12, borderRadius: 6 },
  message: { alignItems: "center", gap: 12, paddingVertical: 28, paddingHorizontal: 16 },
  messageText: { fontSize: 14, fontWeight: "600", textAlign: "center" },
  retry: { minHeight: 44, paddingHorizontal: 20, borderRadius: 999, justifyContent: "center" },
  retryText: { fontSize: 14, fontWeight: "700" },
});
