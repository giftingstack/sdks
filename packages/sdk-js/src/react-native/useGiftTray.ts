import { type RefObject, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Keyboard, type KeyboardEvent, Platform } from "react-native";
import {
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  GiftTrayController,
  type GiftTrayControllerOptions,
  TrayOpenState,
  type GiftingError,
  type InputSwapEvent,
  KEYBOARD_MIN_HEIGHT,
  type TrayReceiver,
  inputSwapStep,
  resolveReceiver,
} from "../core";
import type { GiftEffectLayerHandle } from "./GiftEffectLayer";
import { prefetch } from "./images";

/** What the tray needs of your `TextInput` (its ref has all three). */
export interface FocusableInput {
  focus(): void;
  blur(): void;
  isFocused?(): boolean;
}

export interface UseGiftTrayOptions {
  client: GiftingClient;
  /** Who gets the gifts: the owner of the post or profile on screen. */
  receiver: string;
  /** The effect layer that shows each gift. */
  effects?: RefObject<GiftEffectLayerHandle | null>;
  /**
   * When the effect starts. `"tap"` (default) plays it the moment the person taps, so it feels
   * instant, and takes it back if the send fails. `"success"` waits for the server first, so
   * the effect appears a network round trip later but is never shown for a failed send.
   */
  playOn?: "tap" | "success";
  /** Your own context id, for example the post id. Saved with each gift. */
  reference?: string;
  /** Room on screen (see `useGiftRoom`): every send names it, so the room's viewers see it. */
  roomId?: string;
  /** In a battle: `room.controller.receiverFor`, so your own gift says who got it (SPEC 18.4). */
  receiverOf?: GiftTrayControllerOptions["receiverOf"];
  onSent?: (transaction: GiftTransaction) => void;
  /** Called for every failed send. `error.insufficientBalance` means: open your coin store. */
  onError?: (error: GiftingError) => void;
  /**
   * Whether the tray starts open (default `true`: a tray you render is shown, as before).
   * `false`: hidden until `open()` or `toggle()` (spec 9.4). Read once.
   */
  open?: boolean;
  /** The tray opened or closed (`open()`, `close()`, `toggle()`, a dismissed scrim tap). */
  onOpenChange?: (open: boolean) => void;
  /**
   * Your message bar's own `TextInput` (a ref, spec 20). The tray then takes the keyboard's place:
   * `toggle()` (your `GiftButton`) closes the keyboard and opens the tray, a tap on the field
   * closes the tray, `toggle()` again brings the keyboard back. The tray starts closed (unless
   * `open` is given) and opens about as tall as the keyboard was. Read once.
   */
  input?: RefObject<FocusableInput | null>;
  /**
   * A battle (spec 21): the sides the viewer can send to. Two or more show a "Send to" row in the
   * tray; every send goes to the picked side (default: the side this tray last sent to, else the
   * first). `receiver` stays the fallback.
   */
  receivers?: TrayReceiver[];
  /** The picked side changed. */
  onReceiverChange?: (id: string | null) => void;
}

export interface UseGiftTray {
  gifts: Gift[];
  balance: number;
  /** The signed-in user, as named by the token. */
  user: string | null;
  loading: boolean;
  /** The last problem: loading failed, or the last send failed. Cleared by the next success. */
  error: GiftingError | null;
  /** The token was made with a test key: pass it to `GiftTray` (`testMode`) for the badge. */
  testMode: boolean;
  send: (gift: Gift) => Promise<void>;
  /** Reload the catalog and the balance, for example after the person buys coins. */
  refresh: () => Promise<void>;
  /** The tray is open (`GiftTray tray={tray}` shows itself only while this is true). */
  isOpen: boolean;
  /** Show the tray (the sheet comes back at its `initialSnap`). */
  open: () => void;
  /** Hide the tray. */
  close: () => void;
  /**
   * Open if closed, close if open: the host's Gift button is `tray.toggle()`. With `input` it is
   * the keyboard swap (spec 20.2): closing puts the focus back on the field.
   */
  toggle: () => void;
  /** A text field is bound (`input`). */
  inputBound: boolean;
  /** The last keyboard height seen (0: none yet). The tray opens about this tall. */
  keyboardHeight: number;
  /** The `receivers` option (a battle's sides), or undefined. */
  receivers: TrayReceiver[] | undefined;
  /** The receiver the next gift goes to. */
  receiver: string | null;
  /** Pick the side the next gift goes to (a tap on the battle bar). An id not in `receivers` is ignored. */
  selectReceiver: (id: string) => void;
}

function controllerOptions(options: UseGiftTrayOptions): GiftTrayControllerOptions {
  const { client, receiver, effects, playOn, reference, roomId, receiverOf, onSent, onError } =
    options;
  return {
    client,
    receiver,
    playOn,
    reference,
    roomId,
    receiverOf,
    onSent,
    onError,
    effects: () => effects?.current,
    prefetch,
  };
}

/**
 * Everything a gift tray needs besides drawing: loads the catalog and balance, sends gifts,
 * keeps the balance right while the person taps fast (combos), and plays the effect for each
 * gift. The logic lives in `GiftTrayController` (core), shared with the other platforms.
 */
export function useGiftTray(options: UseGiftTrayOptions): UseGiftTray {
  // A battle (spec 21.2): the pick and the side this tray last sent to decide the receiver.
  const [picked, setPicked] = useState<string | null>(null);
  const [last, setLast] = useState<string | null>(null);
  const ids = (options.receivers ?? []).map((r) => r.id);
  const receiver = resolveReceiver(ids, { selected: picked, last, fallback: options.receiver });
  const sendOptions: UseGiftTrayOptions = {
    ...options,
    receiver: receiver ?? options.receiver,
    onSent: (tx) => {
      setLast(tx.receiver);
      options.onSent?.(tx);
    },
  };
  const ref = useRef<GiftTrayController | null>(null);
  if (!ref.current) ref.current = new GiftTrayController(controllerOptions(sendOptions));
  const controller = ref.current;
  controller.setOptions(controllerOptions(sendOptions));
  const reported = useRef<string | null | undefined>(undefined);
  const onReceiverChange = useRef(options.onReceiverChange);
  onReceiverChange.current = options.onReceiverChange;
  useEffect(() => {
    if (reported.current !== undefined && reported.current !== receiver)
      onReceiverChange.current?.(receiver);
    reported.current = receiver;
  }, [receiver]);
  const state = useSyncExternalStore(controller.subscribe, controller.getState);
  const openRef = useRef<TrayOpenState | null>(null);
  const inputRef = useRef(options.input);
  if (!openRef.current)
    openRef.current = new TrayOpenState({
      // A bound text field: the tray waits for the gift button (spec 20.3).
      open: options.open ?? (options.input ? false : undefined),
    });
  const openState = openRef.current;
  openState.setOnChange(options.onOpenChange);
  const isOpen = useSyncExternalStore(openState.subscribe, openState.isOpen, openState.isOpen);

  useEffect(() => {
    controller.attach();
    return () => controller.dispose();
  }, [controller]);

  useEffect(() => {
    void controller.refresh();
  }, [controller, options.client]);

  // The keyboard swap (spec 20): the keyboard's height, and a focus on the field closes the tray.
  const [keyboardHeight, setKeyboardHeight] = useState(0);
  const bound = !!inputRef.current;
  useEffect(() => {
    if (!bound) return;
    const onShow = (e: KeyboardEvent): void => {
      const h = e?.endCoordinates?.height ?? 0;
      if (h >= KEYBOARD_MIN_HEIGHT) setKeyboardHeight(h);
      if (inputRef.current?.current?.isFocused?.()) swap(openState, inputRef.current, "inputFocus");
    };
    const subs = [Keyboard.addListener("keyboardDidShow", onShow)];
    if (Platform.OS === "ios") subs.push(Keyboard.addListener("keyboardWillShow", onShow));
    // react-native-web has no keyboard events: there the field is a DOM element with a focus event.
    // The field may mount after this hook (another screen), so it is looked up whenever the tray
    // opens, and let go when it closes.
    let node: DomLike | null = null;
    const onFocus = (): void => {
      if (inputRef.current) swap(openState, inputRef.current, "inputFocus");
    };
    const watch = (): void => {
      const next = openState.isOpen()
        ? ((inputRef.current?.current as unknown as DomLike | null | undefined) ?? null)
        : null;
      if (next === node) return;
      node?.removeEventListener?.("focus", onFocus);
      node = next;
      node?.addEventListener?.("focus", onFocus);
    };
    watch();
    const unsubscribe = openState.subscribe(watch);
    return () => {
      for (const sub of subs) sub?.remove?.();
      unsubscribe();
      node?.removeEventListener?.("focus", onFocus);
    };
  }, [bound, openState]);

  return {
    ...state,
    send: controller.send,
    refresh: controller.refresh,
    isOpen,
    open: () => {
      // The keyboard and the tray are never up together (spec 20.3).
      if (inputRef.current && !openState.isOpen()) blur(inputRef.current);
      openState.open();
    },
    close: () => void openState.close(),
    toggle: () => {
      if (inputRef.current) swap(openState, inputRef.current, "button");
      else openState.toggle();
    },
    inputBound: bound,
    keyboardHeight,
    receivers: options.receivers,
    receiver,
    selectReceiver: (id: string) => {
      if (options.receivers?.some((r) => r.id === id)) setPicked(id);
    },
  };
}

function blur(input: RefObject<FocusableInput | null>): void {
  input.current?.blur();
  Keyboard.dismiss();
}

/** One step of the keyboard swap (spec 20.2): blur before open, close before focus. */
function swap(
  openState: TrayOpenState,
  input: RefObject<FocusableInput | null>,
  event: InputSwapEvent,
): void {
  const step = inputSwapStep(openState.isOpen(), event);
  if (step.input === "blur") blur(input);
  if (step.tray === "open") openState.open();
  else if (step.tray === "close") openState.close();
  if (step.input === "focus") input.current?.focus();
}

/** A react-native-web field: the DOM element itself. */
interface DomLike {
  addEventListener?: (type: string, cb: () => void) => void;
  removeEventListener?: (type: string, cb: () => void) => void;
}
