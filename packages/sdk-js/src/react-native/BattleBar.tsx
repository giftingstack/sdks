import { useEffect, useRef, useState } from "react";
import {
  Animated,
  Easing,
  Image,
  type StyleProp,
  StyleSheet,
  Text,
  View,
  type ViewStyle,
  Platform,
} from "react-native";
import {
  type BattleBarLabelsInput,
  type BattleBarSide,
  type BattleView,
  type SideColor,
  battleBarModel,
  battleGains,
  battleSidePalette,
  formatBattleScore,
  pictureFailed,
  pictureSrc,
  resolveBattleBarLabels,
} from "../core";
import { initialOf } from "./ui-parts";
import { useReducedMotion } from "./reduced-motion";
import { type GiftTheme, resolveTheme } from "./theme";

export interface BattleBarUser {
  name: string;
  avatarUrl?: string | null;
}

export interface BattleBarProps {
  /** From `useBattleScore(room.controller)`. Null (no round, or fewer than two sides): nothing is drawn. */
  view: BattleView | null;
  /** Names and pictures of the receivers by id. Fallback: the id. */
  users?: Record<string, BattleBarUser | undefined>;
  /**
   * Override the side colours, one per side in order (default: the theme's accent, its coin colour,
   * then teal and pink, then the same again). A shorter list keeps the default for the sides it
   * does not name. Give the room the same list (`useGiftRoom({ sideColors })`).
   */
  sideColors?: readonly string[];
  /** Default: follows the phone's "reduce motion" setting. No sliding, counting or pulse. */
  reducedMotion?: boolean;
  theme?: Partial<GiftTheme>;
  labels?: BattleBarLabelsInput;
  style?: StyleProp<ViewStyle>;
}

const native = Platform.OS !== "web";
const AVATAR = 40;
const GOLD = "#ffc83d";

/** A score that counts up to its value (straight to it when `still`). */
function useCount(to: number, still: boolean): number {
  const [shown, setShown] = useState(to);
  const from = useRef(to);
  useEffect(() => {
    if (still || from.current === to) {
      from.current = to;
      setShown(to);
      return;
    }
    const start = Date.now();
    const base = from.current;
    let frame = 0;
    const step = () => {
      const k = Math.min(1, (Date.now() - start) / 650);
      const v = k < 1 ? Math.round(base + (to - base) * (1 - (1 - k) ** 3)) : to;
      from.current = v;
      setShown(v);
      if (k < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [to, still]);
  return shown;
}

function SideView(props: {
  side: BattleBarSide;
  index: number;
  /** Three or more sides: a centred cell (avatar over name over score), smaller with 5 or more. */
  cell?: "few" | "many";
  color: SideColor;
  user?: BattleBarUser;
  gained: boolean;
  still: boolean;
  theme: GiftTheme;
  labels: BattleBarLabelsInput;
}) {
  const { side, color, theme, still, index } = props;
  const count = useCount(side.units, still);
  const scale = useRef(new Animated.Value(1)).current;
  useEffect(() => {
    if (!props.gained || still) return;
    Animated.sequence([
      Animated.timing(scale, { toValue: 1.07, duration: 200, useNativeDriver: native }),
      Animated.timing(scale, { toValue: 1, duration: 300, useNativeDriver: native }),
    ]).start();
  }, [side.units]);
  const cell = props.cell;
  const right = !cell && index === 1;
  const ring = side.won ? GOLD : color.color;
  const url = pictureSrc(props.user?.avatarUrl);
  const size = cell ? (cell === "many" ? 30 : 36) : AVATAR;
  const avatarStyle = { width: size, height: size, borderRadius: size / 2 };
  return (
    <Animated.View
      style={[
        styles.side,
        right && styles.sideRight,
        cell && styles.sideCell,
        { transform: [{ scale }], opacity: side.lost ? 0.5 : 1 },
      ]}
    >
      <View style={[styles.ring, { borderColor: ring, borderRadius: (size + 8) / 2 }]}>
        {url ? (
          <Image
            source={{ uri: url }}
            onError={() => pictureFailed(url)}
            fadeDuration={0}
            accessible={false}
            style={[styles.avatar, avatarStyle, { backgroundColor: theme.border }]}
            testID="battle-avatar-image"
          />
        ) : (
          <View
            style={[styles.avatar, avatarStyle, { backgroundColor: color.color }]}
            testID="battle-avatar"
          >
            <Text
              style={[styles.avatarText, { color: color.text }, cell && { fontSize: size * 0.45 }]}
            >
              {initialOf(side.name)}
            </Text>
          </View>
        )}
        {side.won ? (
          <Text
            style={[
              styles.crown,
              cell ? { alignSelf: "center" } : right ? { right: 2 } : { left: 2 },
            ]}
          >
            {"♛"}
          </Text>
        ) : null}
      </View>
      <View style={[styles.who, right && { alignItems: "flex-end" }, cell && styles.whoCell]}>
        <Text
          numberOfLines={1}
          style={[styles.name, { color: theme.text }, cell && styles.nameCell]}
        >
          {side.name}
        </Text>
        <Text
          numberOfLines={1}
          style={[
            styles.score,
            { color: theme.text },
            cell && (cell === "many" ? styles.scoreMany : styles.scoreCell),
          ]}
          testID={`battle-score-${index}`}
        >
          {formatBattleScore(count, props.labels)}
        </Text>
      </View>
    </Animated.View>
  );
}

/** One segment of the bar of three or more sides: its width slides to a new share (800 ms). */
function Segment(props: { pct: number; color: string; first: boolean; still: boolean }) {
  const w = useRef(new Animated.Value(props.pct)).current;
  useEffect(() => {
    if (props.still) {
      w.setValue(props.pct);
      return;
    }
    Animated.timing(w, {
      toValue: props.pct,
      duration: 800,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [props.pct, props.still, w]);
  const width = w.interpolate({ inputRange: [0, 100], outputRange: ["0%", "100%"] });
  return (
    <Animated.View
      style={[
        styles.segment,
        { width, backgroundColor: props.color },
        !props.first && { borderLeftWidth: 2, borderLeftColor: "#ffffff" },
      ]}
    />
  );
}

/**
 * The battle bar of a round (SPEC 18.6, 18.7): the receivers with their scores, a countdown, and
 * a split bar whose boundary slides as gifts arrive. Two sides are the classic versus; three or
 * more (up to 8) are a free-for-all: the clock, a row of cells, a bar of proportional segments.
 * Draws `battleView` data only; your server starts and ends rounds. Pass
 * `useBattleScore(room.controller)` as `view`.
 */
export function BattleBar(props: BattleBarProps) {
  const theme = resolveTheme(props.theme);
  const labels = resolveBattleBarLabels(props.labels);
  const still = useReducedMotion(props.reducedMotion);
  const users = props.users;
  const model = battleBarModel(props.view, {
    nameOf: (id) => users?.[id]?.name ?? id,
    labels,
  });

  const split = useRef(new Animated.Value(model?.pct ?? 50)).current;
  const pct = model?.pct;
  useEffect(() => {
    if (pct === undefined) return;
    if (still) {
      split.setValue(pct);
      return;
    }
    Animated.timing(split, {
      toValue: pct,
      duration: 800,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [pct, still, split]);

  // Which sides gained since the last frame of this round.
  const previous = useRef<{ round: string; units: number[] } | null>(null);
  const units = props.view?.sides.map((s) => s.units) ?? [];
  const round = props.view?.round;
  const same = previous.current && previous.current.round === round ? previous.current.units : null;
  const gains = battleGains(same, units);
  useEffect(() => {
    previous.current = round === undefined ? null : { round, units };
  }, [round, units.join(",")]);

  if (!model) return null;
  const palette = battleSidePalette(props.theme, model.sides.length, props.sideColors);
  const [colA, colB] = [palette[0]!, palette[1]!];
  const multi = model.sides.length > 2;
  const width = split.interpolate({ inputRange: [0, 100], outputRange: ["0%", "100%"] });
  const clockStyle = model.final
    ? { backgroundColor: theme.accent, borderColor: "transparent" }
    : {
        backgroundColor: theme.background,
        borderColor: model.urgent ? theme.danger : theme.border,
      };
  const clockColor = model.final ? theme.accentText : model.urgent ? theme.danger : theme.text;
  return (
    <View
      style={[styles.root, props.style]}
      accessible
      accessibilityLabel={[model.spoken, model.banner].filter(Boolean).join(". ")}
      accessibilityLiveRegion="polite"
      testID="battle-bar"
    >
      {multi ? (
        <>
          <View
            style={styles.mid}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            <Text style={[styles.tag, { color: theme.muted }]}>{labels.vs}</Text>
            <View style={[styles.clock, clockStyle]}>
              <Text style={[styles.clockText, { color: clockColor }]} testID="battle-clock">
                {model.clock}
              </Text>
            </View>
          </View>
          <View
            style={styles.cells}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            {model.sides.map((s, i) => (
              <SideView
                key={s.id}
                side={s}
                index={i}
                cell={model.sides.length > 4 ? "many" : "few"}
                color={palette[i]!}
                user={users?.[s.id]}
                gained={gains[i] ?? false}
                still={still}
                theme={theme}
                labels={labels}
              />
            ))}
          </View>
          <View
            style={[styles.bar, styles.barMulti, { borderColor: theme.border }]}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            {model.pcts.map((p, i) => (
              <Segment
                key={model.sides[i]!.id}
                pct={p}
                color={palette[i]!.color}
                first={i === 0}
                still={still}
              />
            ))}
          </View>
        </>
      ) : (
        <>
          <View
            style={styles.top}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            <SideView
              side={model.sides[0]!}
              index={0}
              color={colA}
              user={users?.[model.sides[0]!.id]}
              gained={gains[0] ?? false}
              still={still}
              theme={theme}
              labels={labels}
            />
            <View style={styles.mid}>
              <Text style={[styles.tag, { color: theme.muted }]}>{labels.vs}</Text>
              <View style={[styles.clock, clockStyle]}>
                <Text style={[styles.clockText, { color: clockColor }]} testID="battle-clock">
                  {model.clock}
                </Text>
              </View>
            </View>
            <SideView
              side={model.sides[1]!}
              index={1}
              color={colB}
              user={users?.[model.sides[1]!.id]}
              gained={gains[1] ?? false}
              still={still}
              theme={theme}
              labels={labels}
            />
          </View>
          <View
            style={[styles.bar, { backgroundColor: colB.color, borderColor: theme.border }]}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            <Animated.View style={[styles.fillA, { width, backgroundColor: colA.color }]} />
            <Animated.View
              style={[
                styles.spark,
                { left: width, opacity: model.final ? 0.5 : 1, shadowColor: theme.accent },
              ]}
            />
          </View>
        </>
      )}
      {model.banner ? (
        <Text style={[styles.banner, { color: theme.text }]} testID="battle-banner">
          {model.banner}
        </Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { gap: 10 },
  top: { flexDirection: "row", alignItems: "center", gap: 8 },
  side: { flex: 1, flexDirection: "row", alignItems: "center", gap: 8, minWidth: 0 },
  sideRight: { flexDirection: "row-reverse" },
  ring: { padding: 2, borderWidth: 2, borderRadius: (AVATAR + 8) / 2 },
  avatar: {
    width: AVATAR,
    height: AVATAR,
    borderRadius: AVATAR / 2,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarText: { fontSize: 18, fontWeight: "800" },
  crown: { position: "absolute", top: -14, fontSize: 18, color: GOLD },
  who: { flexShrink: 1, minWidth: 0 },
  name: { fontSize: 13, fontWeight: "700" },
  score: { fontSize: 20, fontWeight: "800", fontVariant: ["tabular-nums"] },
  cells: { flexDirection: "row", alignItems: "flex-start", gap: 6 },
  sideCell: { flexDirection: "column", alignItems: "center", gap: 4, flex: 1 },
  whoCell: { alignItems: "center", alignSelf: "stretch" },
  nameCell: { fontSize: 12 },
  scoreCell: { fontSize: 17 },
  scoreMany: { fontSize: 14 },
  barMulti: { flexDirection: "row", overflow: "hidden" },
  segment: { height: "100%" },
  mid: { alignItems: "center", gap: 3 },
  tag: { fontSize: 10, fontWeight: "900", letterSpacing: 1.8 },
  clock: {
    minWidth: 52,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderWidth: 1,
    borderRadius: 999,
    alignItems: "center",
  },
  clockText: { fontSize: 13, fontWeight: "800", fontVariant: ["tabular-nums"] },
  bar: {
    height: 16,
    borderRadius: 8,
    borderWidth: 1,
    overflow: "visible",
    justifyContent: "center",
  },
  fillA: {
    position: "absolute",
    left: 0,
    top: 0,
    bottom: 0,
    borderTopLeftRadius: 7,
    borderBottomLeftRadius: 7,
  },
  spark: {
    position: "absolute",
    top: -5,
    width: 4,
    height: 26,
    marginLeft: -2,
    borderRadius: 2,
    backgroundColor: "#ffffff",
    shadowOpacity: 0.9,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 0 },
    elevation: 4,
  },
  banner: { fontSize: 13, fontWeight: "800", textAlign: "center" },
});
