import {
  type EffectPlayer,
  type GiftTransaction,
  type GiftingClient,
  type GiftingError,
  GiftTrayController,
  type GiftTrayControllerOptions,
  type GiftTrayState,
} from "../core";
import { GiftTray, type GiftTrayOptions } from "./GiftTray";
import { prefetch } from "./images";

export interface CreateGiftTrayOptions extends Omit<
  GiftTrayOptions,
  "gifts" | "balance" | "onSend" | "prefetch"
> {
  /** The element the tray is added to. */
  container: HTMLElement;
  client: GiftingClient;
  /** Who gets the gifts: the owner of the post or profile on screen. */
  receiver: string;
  /** The effect layer (or anything with `play` and `cancel`) that shows each gift. */
  effects?: EffectPlayer | (() => EffectPlayer | null | undefined);
  /**
   * When the effect starts. `"tap"` (default) plays it the moment the person presses Send, so it
   * feels instant, and takes it back if the send fails. `"success"` waits for the server first.
   */
  playOn?: "tap" | "success";
  /** Your own context id, for example the post id. Saved with each gift. */
  reference?: string;
  /** Room on screen: every send names it (see `joinRoom`). */
  roomId?: string;
  /** In a battle: `room.receiverFor`, so your own gift says who got it (SPEC 18.4). */
  receiverOf?: GiftTrayControllerOptions["receiverOf"];
  onSent?: (transaction: GiftTransaction) => void;
  /** Called for every failed send. `error.insufficientBalance` means: open your coin store. */
  onError?: (error: GiftingError) => void;
  /** Called whenever the tray's data changes (catalog, balance, error). */
  onState?: (state: GiftTrayState) => void;
}

export interface GiftTrayHandle {
  tray: GiftTray;
  controller: GiftTrayController;
  /** Reload the catalog and the balance, for example after the person buys coins. */
  refresh(): Promise<void>;
  /** `tray.open()`: show the sheet (or the popover). */
  open(): void;
  /** `tray.close()`: hide it. */
  close(): void;
  /** `tray.toggle()`: open if closed, close if open. The host's Gift button is one line. */
  toggle(): void;
  /** `tray.isOpen()`. */
  isOpen(): boolean;
  /** Battle (spec 21): pick the side the next gift goes to (`tray.selectReceiver`). */
  selectReceiver(id: string): void;
  /** The receiver the next gift goes to. */
  getReceiver(): string | null;
  destroy(): void;
}

/**
 * A ready tray: loads the gifts and the balance, shows them, sends gifts, keeps the balance right
 * while the person taps fast and plays each gift in `effects`. Web counterpart of React Native's
 * `useGiftTray` + `GiftTray`; all the logic is `GiftTrayController` from the core.
 */
export function createGiftTray(options: CreateGiftTrayOptions): GiftTrayHandle {
  const { container, client, receiver, effects, playOn, reference, onSent, onError, onState } =
    options;
  const trayOptions: GiftTrayOptions = {
    title: options.title,
    coinName: options.coinName,
    sendLabel: options.sendLabel,
    notEnoughLabel: options.notEnoughLabel,
    getCoinsLabel: options.getCoinsLabel,
    columns: options.columns,
    gridMaxHeight: options.gridMaxHeight,
    defaultSelectedId: options.defaultSelectedId,
    disabled: options.disabled,
    theme: options.theme,
    onTopUp: options.onTopUp,
    sheet: options.sheet,
    placement: options.placement,
    anchor: options.anchor,
    input: options.input,
    onOpenChange: options.onOpenChange,
    open: options.open,
    scrim: options.scrim,
    scrimTap: options.scrimTap,
    onDismiss: options.onDismiss,
    onPlacementChange: options.onPlacementChange,
    initialSnap: options.initialSnap,
    snaps: options.snaps,
    onSnapChange: options.onSnapChange,
    collapseOnSelect: options.collapseOnSelect,
    onInsetChange: options.onInsetChange,
    receivers: options.receivers,
    receiver,
    onReceiverChange: options.onReceiverChange,
    sendToLabel: options.sendToLabel,
  };
  const base: GiftTrayControllerOptions = {
    client,
    receiver,
    effects: typeof effects === "function" ? effects : () => effects,
    playOn,
    reference,
    roomId: options.roomId,
    receiverOf: options.receiverOf,
    onSent: (tx: GiftTransaction) => {
      // A battle (spec 21.2): the side this tray last sent to is the default next time.
      tray.noteSent(tx.receiver);
      onSent?.(tx);
    },
    onError,
    prefetch,
  };
  const controller = new GiftTrayController(base);
  const tray: GiftTray = new GiftTray(container, {
    ...trayOptions,
    onSend: (gift) => {
      // Every send goes to the picked side (or the plain receiver).
      controller.setOptions({ ...base, receiver: tray.getReceiver() ?? receiver });
      return controller.send(gift);
    },
  });
  const unsubscribe = controller.subscribe(() => {
    const state = controller.getState();
    tray.update({ gifts: state.gifts, balance: state.balance, testMode: state.testMode });
    onState?.(state);
  });
  controller.attach();
  void controller.refresh();
  return {
    tray,
    controller,
    refresh: controller.refresh,
    open: () => tray.open(),
    close: () => tray.close(),
    toggle: () => tray.toggle(),
    isOpen: () => tray.isOpen(),
    selectReceiver: (id) => tray.selectReceiver(id),
    getReceiver: () => tray.getReceiver(),
    destroy() {
      controller.dispose();
      unsubscribe();
      tray.destroy();
    },
  };
}
