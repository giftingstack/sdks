import {
  type Ref,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Image,
  PanResponder,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  type AccessibilityActionEvent,
  type LayoutChangeEvent,
  type PanResponderGestureState,
  type StyleProp,
  type ViewStyle,
} from "react-native";
import {
  type Gift,
  SCRIM_OPACITY,
  type ScrimTap,
  type SheetLayout,
  type SheetSnap,
  TraySheetController,
  pictureFailed,
  pictureSrc,
  scrimFadeMs,
  scrimTapOutcome,
  scrimTakesTouches,
  scrimVisible,
  sendButtonState,
} from "../core";
import { EFFECT_PICTURE_SIZE } from "./EffectItem";
import { prefetch } from "./images";
import { type GiftTheme, resolveTheme } from "./theme";
import type { UseGiftTray } from "./useGiftTray";

/** What `GiftTray` reads from `useGiftTray()` when you pass it as `tray`. */
export type GiftTrayState = Pick<UseGiftTray, "gifts" | "balance" | "send" | "testMode"> &
  Partial<Pick<UseGiftTray, "isOpen" | "close">>;

export interface GiftTrayProps {
  /**
   * The result of `useGiftTray()`. The tray then takes `gifts`, `balance`, `onSend` and the
   * "Test mode" badge from it, so you do not wire them one by one. Any prop below still wins.
   */
  tray?: GiftTrayState;
  /** Default: `tray.gifts`. */
  gifts?: Gift[];
  /** Default: `tray.balance`. */
  balance?: number;
  /** Called when the person taps Send. Tap again for a combo. Default: `tray.send`. */
  onSend?: (gift: Gift) => void | Promise<void>;
  /** Shows "+ Coins" and, when the balance is too low, a "Get coins" button. Open your store here. */
  onTopUp?: () => void;
  title?: string;
  /**
   * The "Test mode" badge next to the title. Default: `tray.testMode` (true when the server says
   * the token was made with a test key; no badge without `tray`). `true` forces it on, `false`
   * forces it off.
   */
  testMode?: boolean;
  /** Default "Test mode". */
  testModeLabel?: string;
  /** Name of your currency, used in labels for screen readers. Default "coins". */
  coinName?: string;
  sendLabel?: string;
  notEnoughLabel?: string;
  getCoinsLabel?: string;
  columns?: number;
  /** Fixed tray only (`sheet={false}`): rows scroll when taller than this. Default 230. */
  gridMaxHeight?: number;
  /**
   * Default `true`: a bottom sheet the person drags between peek, default and expanded. It fills
   * its parent (absolutely positioned, touches pass through above it), so render it as a child of
   * the screen's root view. `false`: the old fixed-height tray in the normal layout flow.
   */
  sheet?: boolean;
  /** Sheet only: the state it opens in. Default `"default"`. */
  initialSnap?: SheetSnap;
  /** Sheet only: snap heights as fractions of the container height (0 = fit the content). */
  snaps?: SheetLayout["snaps"];
  /** Sheet only: the settled state changed (release, tap, accessibility action). */
  onSnapChange?: (snap: SheetSnap) => void;
  /**
   * Sheet only: picking a gift in the grid lowers the sheet to peek (the picked gift and Send),
   * so what is behind it stays in sight, for example a live stream. Tap the handle (or drag it
   * up) for the grid again. Default `false`.
   */
  collapseOnSelect?: boolean;
  /**
   * Sheet only: the tray is shown (default) or hidden. Default: `tray.isOpen` when you pass
   * `tray`, else `true`. While it is `false` the sheet and the scrim are invisible and take no
   * touches; opening shows it again at `initialSnap` (spec 9.4).
   */
  open?: boolean;
  /**
   * Sheet only (spec 9.4): a dim behind the sheet over the whole container. It fades in over
   * 200 ms (at once with reduced motion) once the sheet is placed, is hidden while the sheet is
   * at peek (what is behind it stays in sight) and takes the touches above the sheet while it
   * shows. Default `false`: no dim, touches above the sheet reach the screen behind.
   */
  scrim?: boolean;
  /**
   * What a tap on the scrim does. `"lower"` (default): lowers the sheet to peek (the dim goes
   * away), and from peek dismisses. `"dismiss"`: dismisses from every state. A dismissal calls
   * `tray.close()` (when `open` is not given as a prop) and then `onDismiss`.
   */
  scrimTap?: ScrimTap;
  /** Sheet only: a scrim tap asked to close. With `tray`, the tray is already closed. */
  onDismiss?: () => void;
  /** Sheet only: `ref.current.snapTo("peek")` moves the sheet from your code. */
  ref?: Ref<GiftTrayHandle>;
  /**
   * Sheet only: the sheet's top edge, in dp from the container's bottom, live during a drag and the
   * target when it snaps. Keep the notice above it: `noticeBottom={inset + 16}`.
   */
  onInsetChange?: (inset: number) => void;
  /** Sheet only: the container height, if you know it. Default: measured. */
  containerHeight?: number;
  /** Extra space under the Send button, for example the safe-area bottom inset. Default 0. */
  bottomInset?: number;
  /** Id of the gift selected first. Default: the first gift. */
  defaultSelectedId?: string;
  /** Turn off sending, for example while a request is running. */
  disabled?: boolean;
  theme?: Partial<GiftTheme>;
  style?: StyleProp<ViewStyle>;
}

/** What `ref` gives: move the sheet to a state (animated unless reduced motion). */
export interface GiftTrayHandle {
  snapTo(snap: SheetSnap): void;
}

const NO_GIFTS: Gift[] = [];
const fmt = (n: number) => n.toLocaleString("en-US");
const native = Platform.OS !== "web";
/** Movement before a touch becomes a drag of the sheet. */
const SLOP = 6;

function useSystemReducedMotion(): boolean {
  const [on, setOn] = useState(false);
  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled?.()
      .then((v) => alive && setOn(v))
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener?.("reduceMotionChanged", setOn);
    return () => {
      alive = false;
      sub?.remove?.();
    };
  }, []);
  return on;
}

/** The balance counts up or down to its new value. */
function useCountTo(value: number): number {
  const [shown, setShown] = useState(value);
  const anim = useRef(new Animated.Value(value)).current;
  useEffect(() => {
    const id = anim.addListener(({ value: v }) => setShown(Math.round(v)));
    return () => anim.removeListener(id);
  }, [anim]);
  useEffect(() => {
    Animated.timing(anim, {
      toValue: value,
      duration: 600,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start(({ finished }) => {
      if (!finished) setShown(value);
    });
  }, [value, anim]);
  return shown;
}

function Coin({ color, size }: { color: string; size: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color }} />
  );
}

/** The sheet's controller, measurements and gestures (spec 9.1). Inert for a fixed tray. */
function useSheet(props: GiftTrayProps, rows: number, open: boolean) {
  const { initialSnap, snaps, onSnapChange, onInsetChange, containerHeight } = props;
  const controller = useRef<TraySheetController | null>(null);
  if (!controller.current) controller.current = new TraySheetController({ initialSnap });
  const sheet = controller.current;
  const state = useSyncExternalStore(sheet.subscribe, sheet.getState, sheet.getState);
  const reduced = useSystemReducedMotion();

  // Callbacks change every render; the controller and the gestures read the latest ones.
  const latest = useRef({ onSnapChange, onInsetChange });
  latest.current = { onSnapChange, onInsetChange };
  useEffect(() => {
    sheet.setOnSnapChange((snap) => latest.current.onSnapChange?.(snap));
  }, [sheet]);

  // Content floors: container, the block above the grid, one row, the footer.
  const [measured, setMeasured] = useState({ container: 0, gridTop: 0, row: 0, footer: 0 });
  const measure = (key: keyof typeof measured) => (e: LayoutChangeEvent) => {
    const { height, y } = e.nativeEvent.layout;
    const v = key === "gridTop" ? y : height;
    setMeasured((m) => (m[key] === v ? m : { ...m, [key]: v }));
  };
  const snapsKey = JSON.stringify(snaps ?? null);
  useEffect(() => {
    const peek = measured.gridTop + measured.footer;
    sheet.setLayout({
      containerHeight: containerHeight ?? measured.container,
      snaps,
      peekMinHeight: peek,
      defaultMinHeight: peek + Math.min(2, rows) * measured.row,
      contentHeight: peek + rows * measured.row,
    });
    // `snaps` is compared by value (snapsKey), so a new object with the same numbers changes nothing.
  }, [sheet, measured, rows, containerHeight, snapsKey]);

  // Until the container, the block above the grid, a row and the footer are measured, the snap
  // heights are guesses: the sheet would appear in the wrong place and glide to the right one.
  // So it stays invisible, then jumps (no spring) to where it belongs and shows.
  const measuredAll =
    (containerHeight ?? measured.container) > 0 &&
    measured.footer > 0 &&
    measured.gridTop > 0 &&
    (rows === 0 || measured.row > 0);
  // ...and the controller has taken those floors in (its heights follow the effect above).
  const ready = measuredAll && state.heights.peek >= measured.gridTop + measured.footer;

  // The body moves with translateY only: set during a drag, a spring (or a jump) to a snap.
  const y = useRef(new Animated.Value(state.offset)).current;
  const shown = useRef(state.offset);
  const placed = useRef(false);
  // Visible only from the render AFTER the jump: showing in the same render would paint one frame
  // with the body still at its starting offset.
  const [visible, setVisible] = useState(false);
  // Closing hides the sheet and puts it back at its first state, so opening shows it where it
  // started, placed with a jump (the effect below), not gliding in from where it was left.
  const wasOpen = useRef(open);
  useEffect(() => {
    if (open === wasOpen.current) return;
    wasOpen.current = open;
    if (open) return;
    placed.current = false;
    setVisible(false);
    sheet.snapTo(initialSnap ?? "default");
  }, [open, sheet, initialSnap]);
  useEffect(() => {
    if (!ready || !open) return;
    if (!placed.current) {
      placed.current = true;
      shown.current = state.offset;
      y.stopAnimation();
      y.setValue(state.offset);
      setVisible(true);
      return;
    }
    if (state.offset === shown.current && !state.dragging) return;
    shown.current = state.offset;
    if (state.dragging || reduced) {
      y.stopAnimation();
      y.setValue(state.offset);
    } else {
      Animated.spring(y, {
        toValue: state.offset,
        stiffness: 320,
        damping: 36,
        mass: 1,
        overshootClamping: true,
        useNativeDriver: native,
      }).start();
    }
  }, [ready, open, state.offset, state.dragging, reduced, y]);

  const lastInset = useRef(-1);
  useEffect(() => {
    const inset = open ? state.visibleHeight : 0;
    if (inset === lastInset.current) return;
    lastInset.current = inset;
    latest.current.onInsetChange?.(inset);
  }, [state.visibleHeight, open]);

  // Gestures. A drag that starts on the grid asks the controller who owns it (nested scroll).
  const scrollY = useRef(0);
  const onGrid = useRef(false);
  const pan = useMemo(() => {
    let last = 0;
    // PanResponder starts dy again at 0 on grant; the slop already travelled is added then.
    let travelled = 0;
    const vertical = (g: PanResponderGestureState) => {
      travelled = g.dy;
      return Math.abs(g.dy) > SLOP && Math.abs(g.dy) > Math.abs(g.dx);
    };
    const ours = (g: PanResponderGestureState) =>
      !onGrid.current || sheet.scrollOwner(g.dy, scrollY.current) === "sheet";
    return PanResponder.create({
      // A scrolling grid would keep the pull down at its top: take that one first.
      onMoveShouldSetPanResponderCapture: (_, g) =>
        vertical(g) && onGrid.current && sheet.getState().gridScrollable && ours(g),
      onMoveShouldSetPanResponder: (_, g) => vertical(g) && ours(g),
      onPanResponderGrant: (_, g) => {
        last = g.dy;
        sheet.dragStart();
        sheet.drag(travelled - g.dy);
      },
      onPanResponderMove: (_, g) => {
        sheet.drag(g.dy - last);
        last = g.dy;
      },
      onPanResponderRelease: (_, g) => void sheet.release(g.vy * 1000),
      onPanResponderTerminate: () => sheet.cancel(),
      onPanResponderTerminationRequest: () => false,
    });
  }, [sheet]);

  return { sheet, state, y, measure, pan, scrollY, onGrid, ready: visible, reduced };
}

/** The dim behind the sheet (spec 9.4): black at 0.4, fades over `fadeMs`, takes touches only while shown. */
function Scrim({
  on,
  active,
  fadeMs,
  onPress,
}: {
  on: boolean;
  active: boolean;
  fadeMs: number;
  onPress: () => void;
}) {
  const opacity = useRef(new Animated.Value(on ? SCRIM_OPACITY : 0)).current;
  useEffect(() => {
    Animated.timing(opacity, {
      toValue: on ? SCRIM_OPACITY : 0,
      duration: fadeMs,
      easing: Easing.out(Easing.ease),
      useNativeDriver: native,
    }).start();
  }, [on, fadeMs, opacity]);
  return (
    <Animated.View
      style={[StyleSheet.absoluteFill, { backgroundColor: "#000", opacity }]}
      pointerEvents={active ? "auto" : "none"}
      accessibilityElementsHidden={!active}
      importantForAccessibility={active ? "auto" : "no-hide-descendants"}
      testID="gift-scrim"
    >
      <Pressable
        style={StyleSheet.absoluteFill}
        onPress={onPress}
        accessibilityRole="button"
        accessibilityLabel="Close gift tray"
        testID="gift-scrim-press"
      />
    </Animated.View>
  );
}

/** A tray of gifts with the balance and a Send button. Presentational: you pass data and callbacks. */
export function GiftTray(props: GiftTrayProps) {
  const {
    tray,
    onTopUp,
    title = "Send a gift",
    testModeLabel = "Test mode",
    coinName = "coins",
    sendLabel = "Send",
    notEnoughLabel = "Not enough coins",
    getCoinsLabel = "Get coins",
    columns = 4,
    gridMaxHeight = 230,
    defaultSelectedId,
    disabled = false,
    sheet: isSheet = true,
    bottomInset = 0,
    style,
  } = props;
  const gifts = props.gifts ?? tray?.gifts ?? NO_GIFTS;
  const balance = props.balance ?? tray?.balance ?? 0;
  const onSend = props.onSend ?? tray?.send;
  const testMode = props.testMode ?? tray?.testMode ?? false;
  const theme = resolveTheme(props.theme);
  const [selectedId, setSelectedId] = useState<string | undefined>(
    defaultSelectedId ?? gifts[0]?.id,
  );
  const selected = gifts.find((g) => g.id === selectedId) ?? gifts[0];
  const shownBalance = useCountTo(balance);
  const rows = Math.ceil(gifts.length / Math.max(1, columns));
  const open = props.open ?? tray?.isOpen ?? true;
  const s = useSheet(props, rows, open);
  useImperativeHandle(props.ref, () => ({ snapTo: (snap) => s.sheet.snapTo(snap) }), [s.sheet]);

  // Warm up the pictures: small icons for the whole tray, the big picture for the selected gift.
  useEffect(() => {
    for (const g of gifts) prefetch(g.icon_url);
  }, [gifts]);
  const bigPicture = selected?.animation_url ?? selected?.icon_url;
  useEffect(() => {
    prefetch(bigPicture);
  }, [bigPicture]);

  const button = sendButtonState({ gifts, selectedId, balance, disabled, canTopUp: !!onTopUp });
  const { broke, pressable } = button;
  const label = { send: sendLabel, getCoins: getCoinsLabel, notEnough: notEnoughLabel }[
    button.label
  ];

  function press() {
    if (!selected) return;
    if (button.action === "topUp") onTopUp?.();
    else if (button.action === "send") void onSend?.(selected);
  }

  const warmupSrc = pictureSrc(bigPicture);
  const warmup = warmupSrc ? (
    // Draws the selected gift's big picture where nobody can see it, at the size the effect
    // uses. The phone decodes it now, so the effect does not wait for that when you tap Send.
    <Image
      key={warmupSrc}
      testID="gift-warmup"
      source={{ uri: warmupSrc }}
      onError={() => pictureFailed(warmupSrc)}
      fadeDuration={0}
      resizeMode="contain"
      accessible={false}
      style={{
        position: "absolute",
        left: -EFFECT_PICTURE_SIZE * 2,
        top: 0,
        width: EFFECT_PICTURE_SIZE,
        height: EFFECT_PICTURE_SIZE,
        opacity: 0,
      }}
    />
  ) : null;

  const head = (
    <View style={styles.head}>
      <Text numberOfLines={1} style={[styles.title, { color: theme.text }]}>
        {title}
      </Text>
      {testMode && (
        <View style={styles.testBadge} testID="gift-test-mode">
          <Text style={styles.testBadgeText}>{testModeLabel}</Text>
        </View>
      )}
      <View
        style={[styles.balance, { backgroundColor: theme.background }]}
        accessibilityLabel={`Balance: ${fmt(balance)} ${coinName}`}
        testID="gift-balance"
      >
        <Coin color={theme.coin} size={14} />
        <Text style={[styles.balanceText, { color: theme.text }]}>{fmt(shownBalance)}</Text>
      </View>
      {onTopUp && (
        <Pressable
          onPress={onTopUp}
          accessibilityRole="button"
          accessibilityLabel={`Get more ${coinName}`}
        >
          <Text style={[styles.topup, { color: theme.coin }]}>+ Coins</Text>
        </Pressable>
      )}
    </View>
  );

  const cells = gifts.map((g, i) => {
    const isSelected = g.id === selected?.id;
    return (
      <Pressable
        key={g.id}
        onPress={() => {
          setSelectedId(g.id);
          if (props.collapseOnSelect && isSheet) s.sheet.snapTo("peek");
        }}
        onLayout={i === 0 ? s.measure("row") : undefined}
        accessibilityRole="radio"
        aria-checked={isSelected}
        accessibilityLabel={`${g.name}, ${fmt(g.price)} ${coinName}`}
        style={{ width: `${100 / columns}%`, padding: 4 }}
        testID={`gift-${g.id}`}
      >
        <View
          style={[
            styles.cell,
            {
              backgroundColor: isSelected ? theme.selected : theme.background,
              borderColor: isSelected ? theme.accent : "transparent",
            },
          ]}
        >
          {pictureSrc(g.icon_url) ? (
            <Image
              source={{ uri: pictureSrc(g.icon_url) as string }}
              onError={() => pictureFailed(g.icon_url)}
              fadeDuration={0}
              style={styles.icon}
              resizeMode="contain"
            />
          ) : (
            <View style={[styles.icon, { backgroundColor: theme.border, borderRadius: 12 }]} />
          )}
          <View style={styles.price}>
            <Coin color={theme.coin} size={9} />
            <Text style={[styles.priceText, { color: theme.text }]}>{fmt(g.price)}</Text>
          </View>
        </View>
      </Pressable>
    );
  });

  const sendButton = (
    <Pressable
      onPress={press}
      disabled={!pressable}
      accessibilityRole="button"
      aria-disabled={!pressable}
      accessibilityLabel={selected ? `${label}: ${selected.name}` : label}
      style={[
        styles.send,
        isSheet && styles.sendInFooter,
        { backgroundColor: pressable ? (broke ? theme.coin : theme.accent) : theme.border },
      ]}
      testID="gift-send"
    >
      <Text
        style={[styles.sendText, { color: broke && pressable ? theme.coinText : theme.accentText }]}
      >
        {label}
      </Text>
    </Pressable>
  );

  if (!isSheet) {
    return (
      <View
        style={[
          styles.tray,
          { backgroundColor: theme.surface, borderColor: theme.border },
          bottomInset > 0 && { paddingBottom: 14 + bottomInset },
          style,
        ]}
        testID="gift-tray"
      >
        {warmup}
        {head}
        <ScrollView style={{ maxHeight: gridMaxHeight }} contentContainerStyle={styles.grid}>
          {cells}
        </ScrollView>
        {sendButton}
      </View>
    );
  }

  const { sheet, state } = s;
  const act = (e: AccessibilityActionEvent) => {
    const name = e.nativeEvent.actionName;
    if (name === "increment" || name === "expand") sheet.step(1);
    else if (name === "decrement" || name === "collapse") sheet.step(-1);
    else if (name === "activate") sheet.toggle();
  };
  // Web (react-native-web): arrow keys on the focused handle.
  const keys = {
    onKeyDown: (e: { key: string; preventDefault(): void }) => {
      if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
      e.preventDefault();
      sheet.step(e.key === "ArrowUp" ? 1 : -1);
    },
  };
  const edge = { backgroundColor: theme.surface, borderColor: theme.border };
  const peek = state.snap === "peek" && !state.dragging;
  const shownNow = s.ready && open;
  const scrimOn = scrimVisible({
    scrim: !!props.scrim,
    open,
    snap: state.snap,
    placed: s.ready,
  });
  const scrimActive = scrimTakesTouches({ scrim: !!props.scrim, open, placed: s.ready });
  function tapScrim() {
    const outcome = scrimTapOutcome({
      scrim: !!props.scrim,
      scrimTap: props.scrimTap,
      open,
      snap: state.snap,
    });
    if (outcome === "lower") sheet.snapTo("peek");
    else if (outcome === "dismiss") {
      // The `open` prop, when given, is the host's to change.
      if (props.open === undefined) tray?.close?.();
      props.onDismiss?.();
    }
  }

  return (
    <View
      style={StyleSheet.absoluteFill}
      pointerEvents={open ? "box-none" : "none"}
      onLayout={s.measure("container")}
      accessibilityElementsHidden={!open}
      importantForAccessibility={open ? "auto" : "no-hide-descendants"}
      testID="gift-sheet"
    >
      {props.scrim && (
        <Scrim
          on={scrimOn}
          active={scrimActive}
          fadeMs={scrimFadeMs(s.reduced)}
          onPress={tapScrim}
        />
      )}
      <View
        style={[
          styles.sheetRoot,
          { height: state.heights.expanded, opacity: shownNow ? 1 : 0 },
          style,
        ]}
        pointerEvents={open ? "box-none" : "none"}
      >
        <Animated.View
          style={[styles.sheetBody, edge, { transform: [{ translateY: s.y }] }]}
          onTouchStartCapture={() => (s.onGrid.current = false)}
          testID="gift-tray"
          {...s.pan.panHandlers}
        >
          {warmup}
          <Pressable
            onPress={() => sheet.toggle()}
            accessibilityRole="button"
            accessibilityLabel="Gift tray"
            accessibilityHint="Drag up or down to see more or fewer gifts"
            aria-expanded={state.snap !== "peek"}
            accessibilityValue={{ text: state.snap }}
            accessibilityActions={[
              { name: "activate" },
              { name: "increment" },
              { name: "decrement" },
              { name: "expand", label: "Show more gifts" },
              { name: "collapse", label: "Show fewer gifts" },
            ]}
            onAccessibilityAction={act}
            style={styles.handle}
            testID="gift-handle"
            {...(keys as object)}
          >
            <View style={[styles.handlePill, { backgroundColor: theme.muted }]} />
          </Pressable>
          {head}
          <ScrollView
            style={styles.sheetGrid}
            contentContainerStyle={styles.grid}
            scrollEnabled={state.gridScrollable}
            onScroll={(e) => (s.scrollY.current = e.nativeEvent.contentOffset.y)}
            scrollEventThrottle={16}
            onTouchStart={() => (s.onGrid.current = true)}
            onLayout={s.measure("gridTop")}
            accessibilityElementsHidden={peek}
            importantForAccessibility={peek ? "no-hide-descendants" : "auto"}
            testID="gift-grid"
          >
            {cells}
          </ScrollView>
        </Animated.View>
        <View
          style={[
            styles.footer,
            edge,
            { paddingBottom: 14 + bottomInset, opacity: shownNow ? 1 : 0 },
          ]}
          onLayout={s.measure("footer")}
          testID="gift-footer"
        >
          {selected && (
            <View style={styles.picked} accessible={false} importantForAccessibility="no">
              {pictureSrc(selected.icon_url) ? (
                <Image
                  source={{ uri: pictureSrc(selected.icon_url) as string }}
                  onError={() => pictureFailed(selected.icon_url)}
                  fadeDuration={0}
                  style={styles.pickedIcon}
                  resizeMode="contain"
                />
              ) : (
                <View
                  style={[styles.pickedIcon, { backgroundColor: theme.border, borderRadius: 8 }]}
                />
              )}
              <View style={{ flexShrink: 1 }}>
                <Text numberOfLines={1} style={[styles.pickedName, { color: theme.text }]}>
                  {selected.name}
                </Text>
                <View style={styles.price}>
                  <Coin color={theme.coin} size={9} />
                  <Text style={[styles.priceText, { color: theme.text }]}>
                    {fmt(selected.price)}
                  </Text>
                </View>
              </View>
            </View>
          )}
          {sendButton}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  tray: {
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    gap: 12,
  },
  head: { flexDirection: "row", alignItems: "center", gap: 10 },
  // One line, ends with "…" (SPEC 9): a long or translated title never changes the peek height.
  title: { flex: 1, minWidth: 0, fontSize: 15, fontWeight: "700" },
  testBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
    backgroundColor: "#f5a524",
  },
  testBadgeText: {
    color: "#1a1300",
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 0.4,
    textTransform: "uppercase",
  },
  balance: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingVertical: 4,
    paddingHorizontal: 10,
    borderRadius: 999,
  },
  balanceText: { fontSize: 13, fontWeight: "700", fontVariant: ["tabular-nums"] },
  topup: { fontSize: 13, fontWeight: "700" },
  grid: { flexDirection: "row", flexWrap: "wrap" },
  cell: { alignItems: "center", paddingVertical: 8, borderRadius: 14, borderWidth: 1.5, gap: 2 },
  icon: { width: 48, height: 48 },
  price: { flexDirection: "row", alignItems: "center", gap: 3 },
  priceText: { fontSize: 11.5, fontWeight: "700", fontVariant: ["tabular-nums"] },
  send: { alignItems: "center", justifyContent: "center", paddingVertical: 13, borderRadius: 999 },
  sendText: { fontSize: 15, fontWeight: "700" },
  sendInFooter: { flex: 1 },
  sheetRoot: { position: "absolute", left: 0, right: 0, bottom: 0 },
  sheetBody: {
    flex: 1,
    zIndex: 0,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: 0,
    paddingHorizontal: 14,
    gap: 12,
  },
  handle: {
    alignItems: "center",
    paddingTop: 14,
    paddingBottom: 10,
    marginHorizontal: -14,
    marginTop: -6,
    marginBottom: -6,
  },
  handlePill: { width: 36, height: 5, borderRadius: 3, opacity: 0.7 },
  sheetGrid: { flex: 1 },
  footer: {
    zIndex: 1,
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingHorizontal: 14,
    paddingTop: 10,
    paddingBottom: 14,
    borderLeftWidth: StyleSheet.hairlineWidth,
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  picked: { flexDirection: "row", alignItems: "center", gap: 8, maxWidth: "45%" },
  pickedIcon: { width: 36, height: 36 },
  pickedName: { fontSize: 12.5, fontWeight: "700" },
});
