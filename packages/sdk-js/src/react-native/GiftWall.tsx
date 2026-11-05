import { type ReactNode, useEffect, useRef } from "react";
import {
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
  type ReceivedGift,
  type WallChip,
  type WallOrder,
  DEFAULT_WALL_MAX,
  formatCount,
  groupThousands,
  wallChips,
} from "../core";
import { type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { useReducedMotion } from "./reduced-motion";
import { type GiftTheme, resolveTheme } from "./theme";
import { GiftIcon } from "./ui-parts";
import { useGiftWall } from "./useGiftWall";

/** What `renderChip` receives for one gift chip. */
export interface WallChipInfo {
  gift: ReceivedGift["gift"];
  /** The exact count. */
  count: number;
  /** The count as the default chip shows it (`1.2K`). */
  countText: string;
  /** The resolved theme, so your chip can match the rest. */
  theme: GiftTheme;
}

export interface GiftWallProps {
  client: GiftingClient;
  /** The receiver's external id. */
  user: string;
  /** Your content id, for example the post. Absent: the profile wall. */
  reference?: string;
  /** Chips shown, the "+37" overflow chip included. Default 6. */
  max?: number;
  /** `"count"` (default): most received first. `"catalog"`: the catalog's order. */
  order?: WallOrder;
  /** `sm`: icon 16, text 11. `md` (default): icon 20, text 12.5. */
  size?: "sm" | "md";
  /** Counters you already have: no request is made. */
  data?: readonly ReceivedGift[];
  /** Change it to fetch again, for example after the person sent a gift. */
  refreshKey?: unknown;
  /**
   * Draw the inside of each gift chip yourself (RN / web only, pending native port). The wall keeps
   * loading, ordering, capping, the chip container (pill, press and accessibility label) and the
   * fade. Return a node; `null`, `undefined` or `false` draws the default icon and count. The
   * "+37" overflow chip is not passed here.
   */
  renderChip?: (chip: WallChipInfo) => ReactNode;
  /** Makes the chips buttons. Open your gift tray here. */
  onPressChip?: (gift: ReceivedGift["gift"]) => void;
  /** Failures only arrive here: a wall never shows an error. */
  onError?: (error: GiftingError) => void;
  /** Default: follows the phone's "reduce motion" setting. */
  reducedMotion?: boolean;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  style?: StyleProp<ViewStyle>;
}

const SIZES = {
  sm: { icon: 16, text: 11, height: 20 },
  md: { icon: 20, text: 12.5, height: 24 },
};
const MIN_TARGET = 44;

/**
 * The gifts a post or a profile received, as a row of small chips: icon and count. Read-only
 * unless you pass `onPressChip`. Nothing to show (no gifts, or the request failed) draws nothing.
 * Walls on one screen share their requests.
 */
export function GiftWall(props: GiftWallProps) {
  const {
    client,
    user,
    reference,
    max = DEFAULT_WALL_MAX,
    order = "count",
    size = "md",
    data,
    refreshKey,
    onPressChip,
    renderChip,
    onError,
    style,
  } = props;
  const theme = resolveTheme(props.theme);
  const labels = resolveLabels(props.labels);
  const reduced = useReducedMotion(props.reducedMotion);
  const wall = useGiftWall({ client, user, reference, data, refreshKey, onError });
  const dim = SIZES[size];

  const fade = useRef(new Animated.Value(1)).current;
  const fadeFor = useRef<readonly ReceivedGift[] | null>(null);
  useEffect(() => {
    if (wall.status !== "ready" || !wall.arrived || fadeFor.current === wall.gifts) return;
    fadeFor.current = wall.gifts;
    if (reduced) return;
    fade.setValue(0);
    Animated.timing(fade, { toValue: 1, duration: 120, useNativeDriver: false }).start();
  }, [wall.status, wall.arrived, wall.gifts, reduced, fade]);

  if (wall.status === "error") return null;
  const row = [styles.row, style];

  if (wall.status === "loading") {
    return (
      <View
        style={row}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
        testID="gift-wall-skeleton"
      >
        {[0, 1, 2].map((i) => (
          <View
            key={i}
            style={[
              styles.chip,
              {
                height: dim.height,
                width: 40 + i * 8,
                backgroundColor: theme.border,
              },
            ]}
            testID="gift-wall-skeleton-chip"
          />
        ))}
      </View>
    );
  }

  const chips = wallChips(wall.gifts, { max, order });
  if (chips.length === 0) {
    return labels.emptyText ? (
      <Text style={[styles.empty, { color: theme.muted, fontSize: dim.text }, style]}>
        {labels.emptyText}
      </Text>
    ) : null;
  }

  const name = (c: Extract<WallChip, { type: "gift" }>) =>
    c.count > 1 ? `${c.gift.name}${labels.plural}` : c.gift.name;
  const list = chips
    .filter((c): c is Extract<WallChip, { type: "gift" }> => c.type === "gift")
    .map((c) => `${groupThousands(c.count)} ${name(c)}`);
  const overflow = chips.find((c) => c.type === "overflow");
  if (overflow) list.push(fill(labels.wallMore, { n: groupThousands(overflow.count) }));
  const summary = fill(labels.wallSummary, { list: list.join(", ") });
  const tappable = !!onPressChip;
  const hit = Math.max(0, (MIN_TARGET - dim.height) / 2);

  const content = (c: WallChip, i: number) => {
    const isGift = c.type === "gift";
    const text = isGift ? formatCount(c.count, labels) : `+${formatCount(c.count, labels)}`;
    const custom =
      isGift && renderChip
        ? renderChip({ gift: c.gift, count: c.count, countText: text, theme })
        : null;
    const body =
      custom !== null && custom !== undefined && custom !== false ? (
        custom
      ) : (
        <>
          {isGift && <GiftIcon url={c.gift.icon_url} size={dim.icon} theme={theme} />}
          <Text
            style={[styles.count, { color: isGift ? theme.text : theme.muted, fontSize: dim.text }]}
          >
            {text}
          </Text>
        </>
      );
    const chipStyle = [
      styles.chip,
      {
        height: dim.height,
        backgroundColor: theme.surface,
        borderColor: theme.border,
        paddingLeft: isGift ? 4 : 8,
      },
    ];
    if (tappable && isGift) {
      return (
        <Pressable
          key={`g-${c.gift.id}`}
          onPress={() => onPressChip(c.gift)}
          hitSlop={{ top: hit, bottom: hit, left: 3, right: 3 }}
          accessibilityRole="button"
          accessibilityLabel={fill(labels.wallChip, {
            name: c.gift.name,
            count: groupThousands(c.count),
          })}
          style={chipStyle}
          testID={`gift-wall-chip-${c.gift.id}`}
        >
          {body}
        </Pressable>
      );
    }
    return (
      <View
        key={isGift ? `g-${c.gift.id}` : `o-${i}`}
        style={chipStyle}
        testID={isGift ? `gift-wall-chip-${c.gift.id}` : "gift-wall-overflow"}
        accessible={tappable ? true : undefined}
        accessibilityLabel={
          tappable && !isGift ? fill(labels.wallMore, { n: groupThousands(c.count) }) : undefined
        }
      >
        {body}
      </View>
    );
  };

  return (
    <Animated.View
      // One element for a screen reader, or a list of buttons when the chips can be tapped.
      accessible={!tappable}
      accessibilityRole={tappable ? "list" : undefined}
      accessibilityLabel={tappable ? undefined : summary}
      style={[row, { opacity: fade }]}
      testID="gift-wall"
    >
      {chips.map(content)}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", flexWrap: "wrap", gap: 6, alignItems: "center" },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingRight: 8,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
  },
  count: { fontWeight: "700", fontVariant: ["tabular-nums"] },
  empty: { fontWeight: "600" },
});
