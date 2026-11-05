import {
  type ComponentRef,
  type ReactNode,
  type RefObject,
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from "react";
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  findNodeHandle,
  type StyleProp,
  type ViewStyle,
} from "react-native";
import {
  type AwayAckOn,
  type AwaySummary,
  type EffectQuality,
  type GiftingClient,
  type GiftingError,
  type TierThresholds,
  formatCount,
  groupThousands,
} from "../core";
import type { GiftEffectLayerHandle } from "./GiftEffectLayer";
import { type GiftLabels, type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { useReducedMotion } from "./reduced-motion";
import { type GiftTheme, resolveTheme } from "./theme";
import { Avatar, GiftIcon } from "./ui-parts";
import { useGiftAway } from "./useGiftAway";

export type AwayUser = { name: string; avatarUrl?: string | null };

/** What `renderSummary` receives: the data the card would show, already computed, and callbacks. */
export interface AwaySummaryInfo {
  summary: AwaySummary;
  /** The card title, from the labels. */
  title: string;
  /** `"37 gifts from 12 people"`, as the default card shows it. */
  headline: string;
  /** Top senders (the default card shows three), names from `resolveUsers` or the id. */
  senders: { user: string | null; name: string; avatarUrl: string | null; count: number }[];
  /** Close the card. Your own buttons call this: a tap on custom content does not dismiss. */
  dismiss: () => void;
  /** `ackOn="manual"`: mark the summary as seen. */
  ack: () => Promise<void>;
  /** The resolved theme, so your card can match the rest. */
  theme: GiftTheme;
}

export interface GiftAwaySummaryProps {
  client: GiftingClient;
  /** The effect layer (the same ref you give `GiftEffectLayer`). Absent: card only. */
  effects?: RefObject<GiftEffectLayerHandle | null>;
  /**
   * External ids are often not display names: map them here. Waits up to 1.5 s before the card
   * shows; ids it does not answer keep the id itself.
   */
  resolveUsers?: (ids: string[]) => Promise<Record<string, AwayUser>>;
  /** `true` (default): check on mount and when the app returns to the foreground (once a minute). */
  autoCheck?: boolean;
  /** When the cursor moves on: `"shown"` (default), `"finished"`, or `"manual"` (`ack()` on the ref). */
  ackOn?: AwayAckOn;
  /** Show the card only with at least this many gifts (default 1); fewer: nothing shows, still acknowledged. */
  minGifts?: number;
  /** Gift groups replayed at most. Default 5. */
  maxEffects?: number;
  /** The replay ends within this many ms. Default 8000. */
  budgetMs?: number;
  thresholds?: Partial<TierThresholds>;
  quality?: EffectQuality;
  /**
   * Draw the body of the card yourself (RN / web only, pending native port). The component keeps
   * the check, names, the card container (surface, border, slide-in), `focusOnShow`, the screen
   * reader announcement, the replay and the acknowledgement. Return a node; `null`, `undefined`
   * or `false` draws the default body. With your body (and no default close button) a tap does
   * not dismiss: call `dismiss()`.
   */
  renderSummary?: (summary: AwaySummaryInfo) => ReactNode;
  /** Move the screen reader's focus to the card when it appears. Default false. */
  focusOnShow?: boolean;
  onShow?: (summary: AwaySummary) => void;
  onDone?: () => void;
  /** Failures never show: they arrive here and the next check tries again. */
  onError?: (error: GiftingError) => void;
  /** Default: follows the phone's "reduce motion" setting (no replay, no slide-in). */
  reducedMotion?: boolean;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  style?: StyleProp<ViewStyle>;
}

export interface GiftAwaySummaryHandle {
  /** Ask the server now. */
  check(): Promise<void>;
  /** For `ackOn="manual"`: mark the card as seen. */
  ack(): Promise<void>;
  dismiss(): void;
}

/** The longest the card waits for `resolveUsers`. */
export const AWAY_RESOLVE_WAIT_MS = 1_500;
const native = Platform.OS !== "web";

const userIds = (s: AwaySummary): string[] => {
  const ids = new Set<string>();
  for (const t of s.top_senders) if (t.user !== null) ids.add(t.user);
  for (const g of s.groups) for (const x of g.senders) if (x.user !== null) ids.add(x.user);
  return [...ids];
};

export function awayTexts(summary: AwaySummary, labels: GiftLabels) {
  const gifts = summary.truncated ? "2,000+" : groupThousands(summary.total_gifts);
  const giftsText = fill(summary.total_gifts === 1 ? labels.giftOne : labels.giftOther, {
    n: gifts,
  });
  const people = groupThousands(summary.sender_count);
  const peopleText = fill(summary.sender_count === 1 ? labels.personOne : labels.personOther, {
    n: people,
  });
  const line = fill(labels.awaySummary, { gifts: giftsText, people: peopleText });
  return { line, announce: fill(labels.awayAnnounce, { summary: line }) };
}

/**
 * "While you were away: 37 gifts from 12 people". Checks once when the app opens (and when it
 * comes back to the foreground), shows a card with the top senders and the gifts, replays the
 * biggest gift groups through your `GiftEffectLayer`, then goes away by itself or on a tap.
 * Nothing new, or any failure: draws nothing. Render it above your screen and below (or beside)
 * the effect layer.
 */
export const GiftAwaySummary = forwardRef<GiftAwaySummaryHandle, GiftAwaySummaryProps>(
  function GiftAwaySummary(props, ref) {
    const { client, effects, resolveUsers, focusOnShow = false, style } = props;
    const theme = resolveTheme(props.theme);
    const labels = resolveLabels(props.labels);
    const reduced = useReducedMotion(props.reducedMotion);
    const reducedRef = useRef(reduced);
    reducedRef.current = reduced;

    const [users, setUsers] = useState<Record<string, AwayUser>>({});
    const usersRef = useRef(users);
    usersRef.current = users;
    const away = useGiftAway({
      client,
      effects,
      autoCheck: props.autoCheck,
      ackOn: props.ackOn,
      minGifts: props.minGifts,
      maxEffects: props.maxEffects,
      budgetMs: props.budgetMs,
      thresholds: props.thresholds,
      quality: props.quality,
      reducedMotion: () => reducedRef.current,
      resolveName: (u) => usersRef.current[u]?.name ?? u,
      someone: labels.someone,
      onShow: props.onShow,
      onDone: props.onDone,
      onError: props.onError,
    });
    const { state, controller } = away;
    useImperativeHandle(
      ref,
      () => ({ check: controller.check, ack: controller.ack, dismiss: controller.dismiss }),
      [controller],
    );

    // The card shows once the names are in (or 1.5 s passed), so it never redraws its senders.
    const summary = state.summary;
    const [shownFor, setShownFor] = useState<AwaySummary | null>(null);
    const resolveRef = useRef(resolveUsers);
    resolveRef.current = resolveUsers;
    useEffect(() => {
      if (!summary) return;
      const ids = userIds(summary);
      const resolve = resolveRef.current;
      if (!resolve || ids.length === 0) {
        setShownFor(summary);
        return;
      }
      let alive = true;
      const timer = setTimeout(() => alive && setShownFor(summary), AWAY_RESOLVE_WAIT_MS);
      resolve(ids).then(
        (found) => {
          if (!alive) return;
          clearTimeout(timer);
          setUsers((prev) => ({ ...prev, ...found }));
          setShownFor(summary);
        },
        () => {
          if (!alive) return;
          clearTimeout(timer);
          setShownFor(summary);
        },
      );
      return () => {
        alive = false;
        clearTimeout(timer);
      };
    }, [summary]);

    const visible =
      !!summary && shownFor === summary && (state.status === "ready" || state.status === "playing");
    // The card is on screen: start the replay and the countdown (once per summary).
    useEffect(() => {
      if (visible && state.status === "ready") controller.start();
    }, [visible, state.status, controller]);

    const slide = useRef(new Animated.Value(reduced ? 1 : 0)).current;
    useEffect(() => {
      if (!visible) return;
      if (reduced) {
        slide.setValue(1);
        return;
      }
      slide.setValue(0);
      Animated.timing(slide, {
        toValue: 1,
        duration: 240,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: native,
      }).start();
    }, [visible, reduced, slide]);

    const card = useRef<ComponentRef<typeof View>>(null);
    useEffect(() => {
      if (!visible || !focusOnShow) return;
      try {
        const handle = findNodeHandle(card.current);
        if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
        else (card.current as unknown as { focus?: () => void } | null)?.focus?.();
      } catch {
        // No accessibility service: nothing to focus.
      }
    }, [visible, focusOnShow]);

    // Your own body replaces the labelled head, so the arrival is announced here instead.
    const customBody = !!props.renderSummary;
    useEffect(() => {
      if (!visible || !summary || !customBody) return;
      try {
        AccessibilityInfo.announceForAccessibility(awayTexts(summary, labels).announce);
      } catch {
        // No accessibility service: nothing to announce.
      }
      // The labels are read once per summary.
    }, [visible, summary, customBody]);

    if (!visible || !summary) return null;
    const nameOf = (u: string | null) => (u === null ? labels.someone : (users[u]?.name ?? u));
    const { line, announce } = awayTexts(summary, labels);
    const senders = summary.top_senders.slice(0, 3);
    const custom = props.renderSummary?.({
      summary,
      title: labels.awayTitle,
      headline: line,
      senders: summary.top_senders.map((s) => ({
        user: s.user,
        name: nameOf(s.user),
        avatarUrl: (s.user === null ? null : users[s.user]?.avatarUrl) ?? null,
        count: s.count,
      })),
      dismiss: controller.dismiss,
      ack: controller.ack,
      theme,
    });
    const hasCustom = custom !== null && custom !== undefined && custom !== false;

    return (
      <View ref={card} pointerEvents="box-none" style={[styles.backdrop, style]} testID="gift-away">
        <Animated.View
          style={[
            styles.card,
            {
              backgroundColor: theme.surface,
              borderColor: theme.border,
              opacity: slide,
              transform: [
                { translateY: slide.interpolate({ inputRange: [0, 1], outputRange: [18, 0] }) },
              ],
            },
          ]}
          testID="gift-away-card"
        >
          {hasCustom ? (
            <View testID="gift-away-custom">{custom}</View>
          ) : (
            <>
              <Pressable
                accessible={false}
                onPress={controller.dismiss}
                style={styles.body}
                testID="gift-away-body"
              >
                <View
                  accessible
                  accessibilityRole="alert"
                  accessibilityLiveRegion="polite"
                  accessibilityLabel={announce}
                  style={styles.head}
                >
                  <Text style={[styles.title, { color: theme.text }]}>{labels.awayTitle}</Text>
                  <Text style={[styles.line, { color: theme.muted }]}>{line}</Text>
                </View>

                {senders.length > 0 && (
                  <View style={styles.senders}>
                    {senders.map((s, i) => {
                      const name = nameOf(s.user);
                      const avatar = s.user === null ? undefined : users[s.user]?.avatarUrl;
                      return (
                        <View
                          key={`${s.user ?? "deleted"}-${i}`}
                          accessible
                          accessibilityLabel={`${name}, ${fill(
                            s.count === 1 ? labels.giftOne : labels.giftOther,
                            { n: groupThousands(s.count) },
                          )}`}
                          style={styles.sender}
                          testID="gift-away-sender"
                        >
                          <Avatar name={name} url={avatar} size={36} theme={theme} />
                          <Text
                            numberOfLines={1}
                            style={[styles.senderName, { color: theme.text }]}
                          >
                            {name}
                          </Text>
                          <Text style={[styles.senderCount, { color: theme.muted }]}>
                            {formatCount(s.count, labels)}
                          </Text>
                        </View>
                      );
                    })}
                  </View>
                )}

                <View style={styles.gifts}>
                  {summary.groups.map((g) => (
                    <View
                      key={g.gift.id}
                      accessible
                      accessibilityLabel={`${g.gift.name}, ${groupThousands(g.count)}`}
                      style={[styles.gift, { backgroundColor: theme.background }]}
                      testID="gift-away-group"
                    >
                      <GiftIcon url={g.gift.icon_url} size={28} theme={theme} />
                      <Text style={[styles.giftCount, { color: theme.text }]}>
                        {formatCount(g.count, labels)}
                      </Text>
                    </View>
                  ))}
                </View>
              </Pressable>
              <Pressable
                onPress={controller.dismiss}
                accessibilityRole="button"
                accessibilityLabel={labels.dismiss}
                hitSlop={4}
                style={styles.close}
                testID="gift-away-dismiss"
              >
                <Text style={[styles.closeText, { color: theme.muted }]}>{"×"}</Text>
              </Pressable>
            </>
          )}
        </Animated.View>
      </View>
    );
  },
);

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFill,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  card: {
    width: "100%",
    maxWidth: 360,
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    shadowColor: "#000",
    shadowOpacity: 0.35,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 12 },
    elevation: 12,
  },
  body: { padding: 18, paddingRight: 52, gap: 14 },
  head: { gap: 3 },
  title: { fontSize: 17, fontWeight: "800" },
  line: { fontSize: 13.5, fontWeight: "600" },
  senders: { flexDirection: "row", gap: 14 },
  sender: { alignItems: "center", gap: 3, flexShrink: 1, minWidth: 56, maxWidth: 88 },
  senderName: { fontSize: 12, fontWeight: "700" },
  senderCount: { fontSize: 11.5, fontWeight: "600", fontVariant: ["tabular-nums"] },
  gifts: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  gift: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingVertical: 4,
    paddingLeft: 6,
    paddingRight: 10,
    borderRadius: 999,
  },
  giftCount: { fontSize: 13, fontWeight: "700", fontVariant: ["tabular-nums"] },
  close: {
    position: "absolute",
    top: 0,
    right: 0,
    width: 44,
    height: 44,
    alignItems: "center",
    justifyContent: "center",
  },
  closeText: { fontSize: 26, lineHeight: 28 },
});
