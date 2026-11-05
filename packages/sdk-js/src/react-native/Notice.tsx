import { useEffect, useRef } from "react";
import { Animated, Easing, Image, Platform, StyleSheet, Text, View } from "react-native";
import { type NoticeData, pictureFailed, pictureSrc } from "../core";
import type { GiftTheme } from "./theme";

export type { NoticeData };

const native = Platform.OS !== "web";

/** Up to this many lines at once, newest at the bottom (same on every SDK). */
export const MAX_NOTICE_LINES = 3;

export interface NoticeLineState {
  /** Unique per line (an id shown again after its line left is a new line). Defaults to data.id. */
  key?: number;
  data: NoticeData;
  visible: boolean;
}

/** The lines in a column anchored at `bottom`; the last one is the newest, at the bottom. */
export function NoticeStack({
  lines,
  bottom,
  theme,
}: {
  lines: NoticeLineState[];
  bottom: number;
  theme: GiftTheme;
}) {
  if (lines.length === 0) return null;
  return (
    <View pointerEvents="none" style={[styles.stack, { bottom }]}>
      {lines.map((l) => (
        <Notice key={l.key ?? l.data.id} data={l.data} visible={l.visible} theme={theme} />
      ))}
    </View>
  );
}

/**
 * One line, "ayla sent Bear boba x3". Slides in from the left, stays, and slides out. The combo
 * number pops each time it grows.
 */
export function Notice({
  data,
  visible,
  theme,
}: {
  data: NoticeData | null;
  visible: boolean;
  theme: GiftTheme;
}) {
  const slide = useRef(new Animated.Value(0)).current;
  const pop = useRef(new Animated.Value(1)).current;
  const lastId = useRef<number | null>(null);
  const lastCount = useRef(0);

  useEffect(() => {
    Animated.timing(slide, {
      toValue: visible ? 1 : 0,
      duration: visible ? 380 : 260,
      easing: visible ? Easing.out(Easing.back(1.2)) : Easing.in(Easing.quad),
      useNativeDriver: native,
    }).start();
  }, [visible, data?.id, slide]);

  useEffect(() => {
    if (!data) return;
    if (data.id === lastId.current && data.count > lastCount.current && data.count > 1) {
      pop.setValue(1.9);
      Animated.spring(pop, {
        toValue: 1,
        friction: 4,
        tension: 160,
        useNativeDriver: native,
      }).start();
    }
    lastId.current = data.id;
    lastCount.current = data.count;
  }, [data, pop]);

  if (!data) return null;
  const { big } = data;
  return (
    <Animated.View
      pointerEvents="none"
      accessibilityRole="alert"
      accessibilityLiveRegion="polite"
      testID="gift-notice"
      style={[
        styles.row,
        {
          backgroundColor: big ? theme.noticeBigBackground : theme.noticeBackground,
          paddingVertical: big ? 7 : 5,
          opacity: slide,
          transform: [
            { translateX: slide.interpolate({ inputRange: [0, 1], outputRange: [-260, 0] }) },
          ],
        },
      ]}
    >
      <View style={[styles.avatar, big && styles.avatarBig, { backgroundColor: theme.accent }]}>
        <Text style={[styles.avatarText, { color: theme.accentText }]}>
          {data.senderName.slice(0, 1).toUpperCase()}
        </Text>
      </View>
      <View>
        <Text style={[styles.name, { color: big ? theme.noticeBigText : theme.noticeText }]}>
          {data.senderName}
        </Text>
        <Text style={[styles.what, { color: big ? theme.noticeBigText : theme.noticeText }]}>
          sent {data.giftName}
        </Text>
      </View>
      {pictureSrc(data.image) && (
        <Image
          // A fresh Image per picture: one reused Image shows the previous gift until the new one has loaded.
          key={data.image}
          source={{ uri: pictureSrc(data.image) as string }}
          onError={() => pictureFailed(data.image)}
          fadeDuration={0}
          style={{ width: big ? 46 : 36, height: big ? 46 : 36 }}
          resizeMode="contain"
        />
      )}
      {data.count > 1 && (
        <Animated.Text
          testID="gift-combo"
          style={[
            styles.combo,
            { color: big ? theme.noticeBigText : theme.comboText, transform: [{ scale: pop }] },
          ]}
        >
          x{data.count}
        </Animated.Text>
      )}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  stack: {
    position: "absolute",
    left: 12,
    flexDirection: "column",
    alignItems: "flex-start",
    gap: 6,
    maxWidth: "92%",
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingLeft: 5,
    paddingRight: 16,
    borderRadius: 999,
    maxWidth: "92%",
  },
  avatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarBig: { width: 34, height: 34, borderRadius: 17 },
  avatarText: { fontWeight: "700", fontSize: 12 },
  name: { fontWeight: "700", fontSize: 12.5, lineHeight: 15 },
  what: { fontSize: 12.5, lineHeight: 15, opacity: 0.92 },
  combo: {
    fontSize: 28,
    fontWeight: "800",
    fontStyle: "italic",
    minWidth: 40,
    textAlign: "center",
  },
});
