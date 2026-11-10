import { type RefObject, useEffect, useRef, useSyncExternalStore } from "react";
import {
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  GiftTrayController,
  type GiftTrayControllerOptions,
  TrayOpenState,
  type GiftingError,
} from "../core";
import type { GiftEffectLayerHandle } from "./GiftEffectLayer";
import { prefetch } from "./images";

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
  /** Open if closed, close if open: the host's Gift button is `tray.toggle()`. */
  toggle: () => void;
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
  const ref = useRef<GiftTrayController | null>(null);
  if (!ref.current) ref.current = new GiftTrayController(controllerOptions(options));
  const controller = ref.current;
  controller.setOptions(controllerOptions(options));
  const state = useSyncExternalStore(controller.subscribe, controller.getState);
  const openRef = useRef<TrayOpenState | null>(null);
  if (!openRef.current) openRef.current = new TrayOpenState({ open: options.open });
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

  return {
    ...state,
    send: controller.send,
    refresh: controller.refresh,
    isOpen,
    open: () => void openState.open(),
    close: () => void openState.close(),
    toggle: () => void openState.toggle(),
  };
}
