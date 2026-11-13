import { type ReactNode, useState } from "react";
import { Pressable, type StyleProp, View, type ViewStyle } from "react-native";
import { type GiftTheme, resolveTheme } from "./theme";
import type { UseGiftTray } from "./useGiftTray";

/** The three fixed sizes of spec 20.4. */
export type GiftButtonSize = "small" | "medium" | "large";

/** The circle diameter in dp of each size name. */
export const GIFT_BUTTON_SIZES: Record<GiftButtonSize, number> = {
  small: 32,
  medium: 36,
  large: 44,
};

/** The circle diameter for a size name; anything unknown is `medium` (36). */
export function giftButtonDiameter(size: unknown): number {
  return typeof size === "string" && Object.hasOwn(GIFT_BUTTON_SIZES, size)
    ? GIFT_BUTTON_SIZES[size as GiftButtonSize]
    : GIFT_BUTTON_SIZES.medium;
}

export interface GiftButtonProps {
  /** The result of `useGiftTray()`: a press is `tray.toggle()`, the button is active while it is open. */
  tray?: Pick<UseGiftTray, "toggle" | "isOpen">;
  /** Called on every press (after the toggle). Without `tray` it is the only action. */
  onPress?: () => void;
  /** Screen reader label. Default "Send a gift". */
  label?: string;
  /** `false` (default): no background, the glyph in `accent`, like an emoji button. `true`: an `accent` circle. */
  filled?: boolean;
  /** One of three fixed sizes (circle 32 / 36 / 44). Default `"medium"`; an unknown value is `"medium"`. */
  size?: GiftButtonSize;
  /**
   * Replaces the gift glyph (spec 20.4). A node, or a function that gets the glyph colour
   * (`accent` plain/active, `accentText` filled). It keeps the size it asks for, is centred in a
   * fixed glyph box of `22 * circle / 36` and scaled down (never up) when it is bigger than the box,
   * with `overflow: "hidden"`, so it can never change the button's size.
   */
  icon?: ReactNode | ((color: string) => ReactNode);
  disabled?: boolean;
  /** The tray's theme tokens (`accent`, `accentText`, `selected`). */
  theme?: Partial<GiftTheme>;
  style?: StyleProp<ViewStyle>;
  testID?: string;
}

/**
 * A small round gift button for your own message bar, next to your `TextInput` or emoji button
 * (spec 20.4). With `useGiftTray({ input: textInputRef })` a press closes the keyboard and opens
 * the tray in its place; another press brings the keyboard back.
 */
export function GiftButton(props: GiftButtonProps) {
  const {
    tray,
    onPress,
    label = "Send a gift",
    filled = false,
    size: sizeName,
    icon,
    disabled = false,
    style,
    testID = "gift-button",
  } = props;
  const size = giftButtonDiameter(sizeName);
  const glyph = (size * 22) / 36;
  const theme = resolveTheme(props.theme);
  const active = !!tray?.isOpen;
  const background = active ? theme.selected : filled ? theme.accent : "transparent";
  const color = active ? theme.accent : filled ? theme.accentText : theme.accent;
  // At least 44 x 44 to touch, whatever the circle's size.
  const slop = Math.max(0, (44 - size) / 2);
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled, ...(tray ? { expanded: active } : null) }}
      aria-expanded={tray ? active : undefined}
      disabled={disabled}
      hitSlop={slop}
      onPress={() => {
        tray?.toggle();
        onPress?.();
      }}
      testID={testID}
      style={[
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: background,
          opacity: disabled ? 0.5 : 1,
        },
        style,
      ]}
    >
      {icon === undefined || icon === null ? (
        <GiftGlyph size={glyph} color={color} />
      ) : (
        <FittedIcon box={glyph}>{typeof icon === "function" ? icon(color) : icon}</FittedIcon>
      )}
    </Pressable>
  );
}

/** The scale that fits a w x h icon into a box x box glyph box: down only, never up, aspect ratio kept. */
export function giftIconFitScale(w: number, h: number, box: number): number {
  if (!(w > 0) || !(h > 0)) return 1;
  return Math.min(1, box / w, box / h);
}

/** Draws `children` at the size they ask for, centred in a `box` x `box` area, scaled down to fit, clipped. */
function FittedIcon({ box, children }: { box: number; children: ReactNode }) {
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const k = natural ? giftIconFitScale(natural.w, natural.h, box) : 1;
  return (
    <View
      pointerEvents="none"
      testID="gift-button-icon"
      style={{
        width: box,
        height: box,
        overflow: "hidden",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <View
        testID="gift-button-icon-content"
        onLayout={(e) => {
          const { width, height } = e.nativeEvent.layout;
          setNatural((prev) =>
            prev && prev.w === width && prev.h === height ? prev : { w: width, h: height },
          );
        }}
        style={{ position: "absolute", transform: [{ scale: k }] }}
      >
        {children}
      </View>
    </View>
  );
}

/**
 * The gift glyph of spec 20.4 (24 x 24 box, strokes 1.8) drawn with Views, so the SDK needs no SVG
 * library: the box, the lid, the ribbon and two bows. A View's border lies inside its box while
 * an SVG stroke is centred on the path, so each rectangle grows by half a stroke on every side.
 */
export function GiftGlyph({ size, color }: { size: number; color: string }) {
  const u = size / 24;
  const w = 1.8 * u;
  const rect = (x1: number, y1: number, x2: number, y2: number, radius = 0): ViewStyle => ({
    position: "absolute",
    left: (x1 - 0.9) * u,
    top: (y1 - 0.9) * u,
    width: (x2 - x1 + 1.8) * u,
    height: (y2 - y1 + 1.8) * u,
    borderWidth: w,
    borderColor: color,
    borderRadius: radius * u,
  });
  const bow = (left: number, turn: string): ViewStyle => ({
    position: "absolute",
    left: left * u,
    top: 2.9 * u,
    width: 5 * u,
    height: 3.6 * u,
    borderWidth: w,
    borderColor: color,
    borderRadius: 2 * u,
    transform: [{ rotate: turn }],
  });
  return (
    <View style={{ width: size, height: size }} pointerEvents="none" testID="gift-button-glyph">
      <View style={rect(4, 11, 20, 21, 1)} />
      <View style={rect(3, 7, 21, 11, 1)} />
      <View
        style={{
          position: "absolute",
          left: 12 * u - w / 2,
          top: 7 * u,
          width: w,
          height: 14 * u,
          backgroundColor: color,
        }}
      />
      <View style={bow(7.4, "28deg")} />
      <View style={bow(11.6, "-28deg")} />
    </View>
  );
}
