import { useEffect, useRef } from "react";
import { Animated, Easing, Image, Platform, StyleSheet, Text, View } from "react-native";
import { pictureFailed, pictureSrc } from "../core";
import type { GiftTheme } from "./theme";

const native = Platform.OS !== "web";

/** The first letter of a name, as the sender avatars show it. */
export function initialOf(name: string): string {
  return ([...name.trim()][0] ?? "?").toUpperCase();
}

/** A round avatar: the picture when there is one, else the initial on the accent colour. */
export function Avatar({
  name,
  url,
  size,
  theme,
}: {
  name: string;
  url?: string | null;
  size: number;
  theme: GiftTheme;
}) {
  const round = { width: size, height: size, borderRadius: size / 2 };
  const src = pictureSrc(url);
  if (src) {
    return (
      <Image
        source={{ uri: src }}
        onError={() => pictureFailed(src)}
        fadeDuration={0}
        accessible={false}
        style={[round, { backgroundColor: theme.border }]}
        testID="gift-avatar-image"
      />
    );
  }
  return (
    <View
      accessible={false}
      style={[styles.avatar, round, { backgroundColor: theme.accent }]}
      testID="gift-avatar"
    >
      <Text style={[styles.avatarText, { color: theme.accentText, fontSize: size * 0.42 }]}>
        {initialOf(name)}
      </Text>
    </View>
  );
}

/** A small coin disc, like the tray's. */
export function CoinDot({ color, size }: { color: string; size: number }) {
  return (
    <View
      accessible={false}
      style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color }}
    />
  );
}

/** A gift picture that never breaks the layout: a neutral disc while it is missing. */
export function GiftIcon({
  url,
  size,
  theme,
}: {
  url: string | null | undefined;
  size: number;
  theme: GiftTheme;
}) {
  const src = pictureSrc(url);
  if (src) {
    return (
      <Image
        source={{ uri: src }}
        onError={() => pictureFailed(src)}
        fadeDuration={0}
        resizeMode="contain"
        accessible={false}
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <View
      accessible={false}
      style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: theme.border }}
    />
  );
}

/**
 * A placeholder block. A gentle pulse, or fully static under reduced motion (`still`): no shimmer
 * for people who asked for none.
 */
export function useSkeletonOpacity(still: boolean): Animated.Value {
  const value = useRef(new Animated.Value(1)).current;
  useEffect(() => {
    if (still) {
      value.setValue(1);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(value, {
          toValue: 0.55,
          duration: 700,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: native,
        }),
        Animated.timing(value, {
          toValue: 1,
          duration: 700,
          easing: Easing.inOut(Easing.quad),
          useNativeDriver: native,
        }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [still, value]);
  return value;
}

const styles = StyleSheet.create({
  avatar: { alignItems: "center", justifyContent: "center" },
  avatarText: { fontWeight: "700" },
});
