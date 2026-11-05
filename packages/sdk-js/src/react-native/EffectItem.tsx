import { useEffect, useMemo, useRef, useState } from "react";
import { Animated, Easing, Image, Platform, StyleSheet, View } from "react-native";
import { type EffectRecipe, pictureFailed, pictureSrc } from "../core";
import type { GiftTheme } from "./theme";

/** Picture size at scale 1, in dp. The recipe's `peakScale` is relative to this. */
const BASE = 100;
/** The picture is drawn at this size, so a warm-up picture must use it to share the decoded copy. */
export const EFFECT_PICTURE_SIZE = BASE;
const native = Platform.OS !== "web";

export interface EffectItemProps {
  recipe: EffectRecipe;
  image: string | null;
  size: { width: number; height: number };
  /** Where the gift starts, in layer coordinates. */
  origin: { x: number; y: number };
  theme: GiftTheme;
  /**
   * Longest wait for the picture before starting anyway, in ms. Starting only once the picture
   * is ready keeps the dimming, the notice and the gift itself in step.
   */
  pictureWaitMs: number;
  /** The effect really starts now (the picture is ready or the wait ran out). */
  onStart: () => void;
  onDone: () => void;
  testID?: string;
}

interface Spark {
  dx: number;
  dy: number;
  size: number;
  color: string;
}
interface Coin {
  x: number;
  size: number;
  /** Fraction of the rain duration the coin waits, and the fraction it takes to fall. */
  start: number;
  fall: number;
}

/** A thin triangle from the centre to the edge: one light ray. */
function Ray({
  R,
  angle,
  halfWidth,
  color,
  opacity,
}: {
  R: number;
  angle: number;
  halfWidth: number;
  color: string;
  opacity: number;
}) {
  return (
    <View
      style={{ position: "absolute", width: R, height: R, transform: [{ rotate: `${angle}deg` }] }}
    >
      <View
        style={{
          marginLeft: R / 2 - halfWidth,
          width: 0,
          height: 0,
          borderLeftWidth: halfWidth,
          borderRightWidth: halfWidth,
          borderTopWidth: R / 2,
          borderLeftColor: "transparent",
          borderRightColor: "transparent",
          borderTopColor: color,
          opacity,
        }}
      />
    </View>
  );
}

/**
 * Plays one gift from start to finish and calls `onDone`. Waits for its picture first (up to
 * `pictureWaitMs`), so nothing appears half-done. Driven only by transform and opacity, which
 * the native animation driver runs off the JavaScript thread.
 */
export function EffectItem({
  recipe,
  image: rawImage,
  size,
  origin,
  theme,
  pictureWaitMs,
  onStart,
  onDone,
  testID,
}: EffectItemProps) {
  const { width: W, height: H } = size;
  const fly = useRef(new Animated.Value(0)).current;
  const leave = useRef(new Animated.Value(0)).current;
  const burst = useRef(new Animated.Value(0)).current;
  const rain = useRef(new Animated.Value(0)).current;
  const spin = useRef(new Animated.Value(0)).current;
  const dim = useRef(new Animated.Value(0)).current;
  const callbacks = useRef({ onStart, onDone });
  callbacks.current = { onStart, onDone };
  // A URL the SDK refuses, or one that failed a moment ago, is the same as no picture (SPEC 7.6).
  // Fixed for the life of the effect, like the layout below.
  const image = useMemo(() => pictureSrc(rawImage), []);
  const [ready, setReady] = useState(!image || pictureWaitMs <= 0);

  // The picture may never report back (offline, bad URL): start anyway after the wait.
  useEffect(() => {
    if (ready) return;
    const t = setTimeout(() => setReady(true), pictureWaitMs);
    return () => clearTimeout(t);
  }, [ready, pictureWaitMs]);

  const stage = useMemo(
    () =>
      recipe.stage === "center"
        ? { x: W / 2, y: H * 0.38 }
        : { x: origin.x + (Math.random() - 0.5) * 0.2 * W, y: origin.y - 0.32 * H },
    // Fixed for the life of the effect, even if the layer is resized.
    [],
  );

  // Random layout that must not change while the effect runs.
  const sparks = useMemo<Spark[]>(
    () =>
      Array.from({ length: recipe.sparks }, (_, i) => {
        const angle = (i / Math.max(1, recipe.sparks)) * Math.PI * 2 + Math.random() * 0.6;
        const dist = recipe.sparkSpread * (0.4 + Math.random() * 0.8);
        return {
          dx: Math.cos(angle) * dist,
          dy: Math.sin(angle) * dist,
          size: 5 + Math.random() * 6,
          color: i % 3 === 0 ? theme.accent : theme.glow,
        };
      }),
    [recipe.sparks, recipe.sparkSpread, theme.accent, theme.glow],
  );
  const coins = useMemo<Coin[]>(
    () =>
      Array.from({ length: recipe.coins }, () => ({
        x: Math.random() * W,
        size: 10 + Math.random() * 8,
        start: Math.random() * 0.35,
        fall: 0.45 + Math.random() * 0.2,
      })),
    [recipe.coins, W],
  );

  useEffect(() => {
    if (!ready) return;
    callbacks.current.onStart();
    const tail = recipe.holdMs + recipe.flyOutMs;
    const timing = (v: Animated.Value, toValue: number, duration: number, easing = Easing.linear) =>
      Animated.timing(v, { toValue, duration, easing, useNativeDriver: native });

    const main = Animated.sequence([
      Animated.parallel([
        timing(fly, 1, recipe.flyInMs, Easing.out(Easing.back(1.3))),
        ...(recipe.dim ? [timing(dim, 1, 300)] : []),
      ]),
      Animated.parallel([
        timing(burst, 1, 900, Easing.out(Easing.cubic)),
        ...(recipe.coins > 0 ? [timing(rain, 1, tail + 800)] : []),
        Animated.sequence([
          Animated.delay(recipe.holdMs),
          Animated.parallel([
            timing(leave, 1, recipe.flyOutMs, Easing.in(Easing.quad)),
            ...(recipe.dim ? [timing(dim, 0, recipe.flyOutMs)] : []),
          ]),
        ]),
      ]),
    ]);
    // The rays run beside the gift from its first frame to its last, never holding it up.
    const run = recipe.rays
      ? Animated.parallel([main, timing(spin, 1, recipe.flyInMs + tail)])
      : main;
    run.start(({ finished }) => {
      if (finished) callbacks.current.onDone();
    });
    return () => run.stop();
    // The recipe is fixed for the life of one effect.
  }, [ready]);

  const half = BASE / 2;
  const x = fly.interpolate({ inputRange: [0, 1], outputRange: [origin.x - half, stage.x - half] });
  const y = fly.interpolate({ inputRange: [0, 1], outputRange: [origin.y - half, stage.y - half] });
  const lift = leave.interpolate({ inputRange: [0, 1], outputRange: [0, -0.07 * H] });
  const growth = fly.interpolate({ inputRange: [0, 1], outputRange: [0.3, recipe.peakScale] });
  const shrink = leave.interpolate({ inputRange: [0, 1], outputRange: [1, 0.55] });
  const appear = fly.interpolate({ inputRange: [0, 0.06, 1], outputRange: [0, 1, 1] });
  const vanish = leave.interpolate({ inputRange: [0, 1], outputRange: [1, 0] });

  const R = Math.min(W, H) * 1.6;
  const raysFade = spin.interpolate({ inputRange: [0, 0.1, 0.85, 1], outputRange: [0, 1, 1, 0] });
  const wideTurn = spin.interpolate({ inputRange: [0, 1], outputRange: ["0deg", "60deg"] });
  const thinTurn = spin.interpolate({ inputRange: [0, 1], outputRange: ["15deg", "-35deg"] });
  const haloGrow = fly.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] });

  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none" testID={testID}>
      {recipe.dim && (
        <Animated.View
          style={[
            StyleSheet.absoluteFill,
            {
              backgroundColor: "#000",
              opacity: dim.interpolate({ inputRange: [0, 1], outputRange: [0, 0.62] }),
            },
          ]}
        />
      )}

      {recipe.rays && (
        <>
          {/* Two sets of rays turning in opposite directions, like a stage light. */}
          {[
            { turn: wideTurn, count: 12, halfWidth: R * 0.075, opacity: 0.34 },
            { turn: thinTurn, count: 12, halfWidth: R * 0.028, opacity: 0.42 },
          ].map((set, s) => (
            <Animated.View
              key={s}
              style={{
                position: "absolute",
                left: stage.x - R / 2,
                top: stage.y - R / 2,
                width: R,
                height: R,
                opacity: raysFade,
                transform: [{ rotate: set.turn }],
              }}
            >
              {Array.from({ length: set.count }, (_, i) => (
                <Ray
                  key={i}
                  R={R}
                  angle={(i * 360) / set.count}
                  halfWidth={set.halfWidth}
                  color={theme.glow}
                  opacity={set.opacity}
                />
              ))}
            </Animated.View>
          ))}
          {/* A soft round glow: circles that are brighter towards the middle. */}
          {[1, 0.78, 0.58, 0.4, 0.24].map((k, i) => (
            <Animated.View
              key={`halo${i}`}
              style={{
                position: "absolute",
                left: stage.x - (BASE * 3.4 * k) / 2,
                top: stage.y - (BASE * 3.4 * k) / 2,
                width: BASE * 3.4 * k,
                height: BASE * 3.4 * k,
                borderRadius: BASE * 2 * k,
                backgroundColor: theme.glow,
                opacity: Animated.multiply(raysFade, 0.16),
                transform: [{ scale: haloGrow }],
              }}
            />
          ))}
        </>
      )}

      {sparks.map((s, i) => (
        <Animated.View
          key={i}
          style={{
            position: "absolute",
            left: stage.x - s.size / 2,
            top: stage.y - s.size / 2,
            width: s.size,
            height: s.size,
            borderRadius: s.size / 2,
            backgroundColor: s.color,
            opacity: burst.interpolate({ inputRange: [0, 0.12, 1], outputRange: [0, 1, 0] }),
            transform: [
              { translateX: burst.interpolate({ inputRange: [0, 1], outputRange: [0, s.dx] }) },
              { translateY: burst.interpolate({ inputRange: [0, 1], outputRange: [0, s.dy] }) },
              { scale: burst.interpolate({ inputRange: [0, 1], outputRange: [1, 0.2] }) },
            ],
          }}
        />
      ))}

      {coins.map((c, i) => (
        <Animated.View
          key={i}
          style={{
            position: "absolute",
            left: c.x,
            top: -24,
            width: c.size,
            height: c.size,
            borderRadius: c.size / 2,
            backgroundColor: theme.coin,
            opacity: rain.interpolate({
              inputRange: [0, c.start, c.start + 0.02, 1],
              outputRange: [0, 0, 1, 1],
            }),
            transform: [
              {
                translateY: rain.interpolate({
                  inputRange: [c.start, Math.min(1, c.start + c.fall)],
                  outputRange: [0, H + 48],
                  extrapolate: "clamp",
                }),
              },
            ],
          }}
        />
      ))}

      <Animated.View
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: BASE,
          height: BASE,
          opacity: Animated.multiply(appear, vanish),
          transform: [
            { translateX: x },
            { translateY: Animated.add(y, lift) },
            { scale: Animated.multiply(growth, shrink) },
          ],
        }}
      >
        {image ? (
          <Image
            source={{ uri: image }}
            // Android fades a picture in over 300 ms after it loads, even from the cache.
            fadeDuration={0}
            onLoad={() => setReady(true)}
            onError={() => {
              pictureFailed(image);
              setReady(true);
            }}
            style={{ width: BASE, height: BASE }}
            resizeMode="contain"
          />
        ) : (
          <View
            style={{ width: BASE, height: BASE, borderRadius: half, backgroundColor: theme.coin }}
          />
        )}
      </Animated.View>
    </View>
  );
}
