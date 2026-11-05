import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState } from "react";
import { AccessibilityInfo, StyleSheet, View, type StyleProp, type ViewStyle } from "react-native";
import {
  EffectScheduler,
  type EffectQuality,
  type EffectTier,
  type GiftEffectEvent,
  type ScheduledEffect,
  type TierThresholds,
} from "../core";
import { EffectItem } from "./EffectItem";
import { MAX_NOTICE_LINES, type NoticeLineState, NoticeStack } from "./Notice";
import { type RecipesStorage, remoteRecipesLoader } from "./recipes-loader";
import { type GiftTheme, resolveTheme } from "./theme";

export interface GiftEffectLayerHandle {
  /**
   * Show a gift. Large gifts wait their turn; small and medium ones play at once.
   * Returns an id you can pass to `cancel`.
   */
  play(event: GiftEffectEvent): number;
  /** Take back a gift that was shown too early, for example because its send failed. */
  cancel(id: number): void;
  /** Stop everything and forget the queue. */
  clear(): void;
}

export interface GiftEffectLayerProps {
  /** From which price a gift is medium or large. Defaults: 100 and 10,000. */
  thresholds?: Partial<TierThresholds>;
  /** `low` for slow phones: fewer sparks, no coin rain, no rays. */
  quality?: EffectQuality;
  /** Default: follows the phone's "reduce motion" setting. Reduced motion shows only the notice. */
  reducedMotion?: boolean;
  /** Small and medium effects on screen at once, 1 to 12 (defaults 6 and 2). Large ones stay one at a time. */
  maxConcurrent?: { small?: number; medium?: number };
  /** Same gift from the same person within this time counts as a combo. Default 2500. */
  comboWindowMs?: number;
  /** Where gifts start, as fractions of the layer. Default: bottom centre, `{ x: 0.5, y: 0.86 }`. */
  origin?: { x: number; y: number };
  /**
   * Longest wait for a gift's picture before its effect starts anyway, in ms. Default 300.
   * The effect and its notice start together once the picture is ready.
   */
  pictureWaitMs?: number;
  /** Distance of the notice from the bottom edge, in dp. Default 150 (above a gift tray). */
  noticeBottom?: number;
  /**
   * Fetch the effect numbers (durations, sparks, coins, scale, notice time, price thresholds,
   * combo window) from `recipesUrl` (cached, refreshed at most every 6 h; spec section 13).
   * Never blocks an effect. `false`: no network at all. Default `true`.
   */
  remoteRecipes?: boolean;
  /** Pin a document: fetches `recipes.<version>.json` instead of `recipes.json`. */
  recipesVersion?: string;
  /** Default `https://assets.giftingstack.com/recipes.json`. For self-hosting and tests. */
  recipesUrl?: string;
  /**
   * Where to keep the fetched document between app starts: anything with `getItem` and `setItem`
   * on strings, sync or async (for example AsyncStorage). Default: memory only.
   */
  recipesStorage?: RecipesStorage;
  theme?: Partial<GiftTheme>;
  onEffectEnd?: (event: GiftEffectEvent, tier: EffectTier) => void;
  style?: StyleProp<ViewStyle>;
}

function useReducedMotion(override: boolean | undefined): boolean {
  const [system, setSystem] = useState(false);
  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled?.()
      .then((on) => alive && setSystem(on))
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener?.("reduceMotionChanged", setSystem);
    return () => {
      alive = false;
      sub?.remove?.();
    };
  }, []);
  return override ?? system;
}

/**
 * Put one of these over your screen, once, and call `play` on its ref whenever a gift is sent
 * or received. It draws the effect by the gift's price and the "ayla sent X" notice with a combo
 * counter. It never blocks touches.
 */
export const GiftEffectLayer = forwardRef<GiftEffectLayerHandle, GiftEffectLayerProps>(
  function GiftEffectLayer(props, ref) {
    const {
      thresholds,
      quality = "high",
      maxConcurrent,
      comboWindowMs,
      origin = { x: 0.5, y: 0.86 },
      noticeBottom = 150,
      pictureWaitMs = 300,
      onEffectEnd,
      style,
      remoteRecipes,
      recipesVersion,
      recipesUrl,
      recipesStorage,
    } = props;
    const theme = resolveTheme(props.theme);
    const reduced = useReducedMotion(props.reducedMotion);

    const [size, setSize] = useState({ width: 0, height: 0 });
    const [items, setItems] = useState<ScheduledEffect[]>([]);
    const [lines, setLines] = useState<NoticeLineState[]>([]);

    // Each line has its own expiry timer (by line key) and its own removal timer (after the slide out).
    const noticeTimers = useRef(new Map<number, ReturnType<typeof setTimeout>>());
    const removeTimers = useRef(new Map<number, ReturnType<typeof setTimeout>>());
    const linesRef = useRef<NoticeLineState[]>([]);
    const nextKey = useRef(1);
    const onEnd = useRef(onEffectEnd);
    onEnd.current = onEffectEnd;

    // The queue, the caps, the combo and the notice text live in the shared scheduler (core).
    const schedulerRef = useRef<EffectScheduler | null>(null);
    if (!schedulerRef.current) {
      const s = new EffectScheduler({ comboWindowMs });
      const commit = (next: NoticeLineState[]) => {
        linesRef.current = next;
        setLines(next);
      };
      const dropLineTimers = (key: number) => {
        clearTimeout(noticeTimers.current.get(key));
        noticeTimers.current.delete(key);
        clearTimeout(removeTimers.current.get(key));
        removeTimers.current.delete(key);
      };
      const hideLine = (key: number) => {
        const line = linesRef.current.find((l) => l.key === key);
        if (!line || !line.visible) return;
        clearTimeout(noticeTimers.current.get(key));
        noticeTimers.current.delete(key);
        commit(linesRef.current.map((l) => (l.key === key ? { ...l, visible: false } : l)));
        removeTimers.current.set(
          key,
          setTimeout(() => {
            removeTimers.current.delete(key);
            commit(linesRef.current.filter((l) => l.key !== key));
          }, 260),
        );
      };
      s.listener = {
        enter: (item) => setItems((prev) => [...prev, item]),
        exit: (item) => setItems((prev) => prev.filter((i) => i.id !== item.id)),
        end: (item) => onEnd.current?.(item.event, item.recipe.tier),
        notice: (data, durationMs) => {
          let line = linesRef.current.find((l) => l.visible && l.data.id === data.id);
          if (line) {
            const key = line.key as number;
            clearTimeout(noticeTimers.current.get(key));
            commit(linesRef.current.map((l) => (l.key === key ? { ...l, data } : l)));
            noticeTimers.current.set(key, setTimeout(() => hideLine(key), durationMs));
            return;
          }
          let next = linesRef.current;
          // A fourth line pushes the oldest visible one out at once.
          while (next.filter((l) => l.visible).length >= MAX_NOTICE_LINES) {
            const oldest = next.find((l) => l.visible);
            if (!oldest) break;
            dropLineTimers(oldest.key as number);
            next = next.filter((l) => l !== oldest);
          }
          const key = nextKey.current++;
          line = { key, data, visible: true };
          commit([...next, line]);
          noticeTimers.current.set(key, setTimeout(() => hideLine(key), durationMs));
        },
        noticeHide: () => {
          const newest = [...linesRef.current].reverse().find((l) => l.visible);
          if (newest) hideLine(newest.key as number);
        },
        clear: () => {
          for (const t of noticeTimers.current.values()) clearTimeout(t);
          for (const t of removeTimers.current.values()) clearTimeout(t);
          noticeTimers.current.clear();
          removeTimers.current.clear();
          commit([]);
          setItems([]);
        },
      };
      schedulerRef.current = s;
    }
    const scheduler = schedulerRef.current;
    // Remote recipes (null when off). Read at each `play`; never awaited.
    const remote = useMemo(
      () => remoteRecipesLoader({ remoteRecipes, recipesVersion, recipesUrl, recipesStorage }),
      [remoteRecipes, recipesVersion, recipesUrl, recipesStorage],
    );
    useEffect(() => {
      void remote?.refresh();
    }, [remote]);
    const optionsRef = useRef({ thresholds, quality, maxConcurrent, reducedMotion: reduced });
    optionsRef.current = { thresholds, quality, maxConcurrent, reducedMotion: reduced };
    const remoteRef = useRef(remote);
    remoteRef.current = remote;
    const applyOptions = () =>
      scheduler.setOptions({
        ...optionsRef.current,
        recipes: remoteRef.current?.current() ?? undefined,
      });
    applyOptions();

    useImperativeHandle(
      ref,
      () => ({
        play: (event) => {
          applyOptions(); // the newest recipes, for this gift only
          return scheduler.play(event);
        },
        cancel: (id) => scheduler.cancel(id),
        clear: () => scheduler.clear(),
      }),
      [scheduler],
    );
    useEffect(
      () => () => {
        for (const t of noticeTimers.current.values()) clearTimeout(t);
        for (const t of removeTimers.current.values()) clearTimeout(t);
        noticeTimers.current.clear();
        removeTimers.current.clear();
      },
      [],
    );

    const ready = size.width > 0 && size.height > 0;
    return (
      <View
        pointerEvents="none"
        style={[StyleSheet.absoluteFill, style]}
        onLayout={(e) => setSize(e.nativeEvent.layout)}
        testID="gift-effect-layer"
      >
        {ready &&
          items.map((item) => (
            <EffectItem
              key={item.id}
              testID={`gift-effect-${item.recipe.tier}`}
              recipe={item.recipe}
              image={item.event.gift.image}
              size={size}
              origin={{ x: origin.x * size.width, y: origin.y * size.height }}
              theme={theme}
              pictureWaitMs={pictureWaitMs}
              onStart={() => scheduler.started(item.id)}
              onDone={() => scheduler.finished(item.id)}
            />
          ))}
        <NoticeStack lines={lines} bottom={noticeBottom} theme={theme} />
      </View>
    );
  },
);
