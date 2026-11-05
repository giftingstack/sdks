import { type RefObject, useEffect, useRef, useSyncExternalStore } from "react";
import { AppState } from "react-native";
import {
  AwayController,
  type AwayAckOn,
  type AwayControllerOptions,
  type AwayState,
  type EffectQuality,
  type GiftingClient,
  type GiftingError,
  type AwaySummary,
  type TierThresholds,
} from "../core";
import type { GiftEffectLayerHandle } from "./GiftEffectLayer";
import { useDisposable } from "./use-disposable";

export interface UseGiftAwayOptions {
  client: GiftingClient;
  /** The effect layer: the replay plays through it. Absent: card only. */
  effects?: RefObject<GiftEffectLayerHandle | null>;
  /** `true` (default): check when mounted and whenever the app returns to the foreground. */
  autoCheck?: boolean;
  /** `"shown"` (default), `"finished"` or `"manual"` (call `ack()` yourself). */
  ackOn?: AwayAckOn;
  maxEffects?: number;
  budgetMs?: number;
  /** Groups asked from the server, 1 to 10. Server default 5. */
  maxGroups?: number;
  /** Show the card only with at least this many gifts (default 1); fewer: nothing shows, still acknowledged. */
  minGifts?: number;
  thresholds?: Partial<TierThresholds>;
  quality?: EffectQuality;
  /** Reads the phone's setting when the card appears. No replay under reduced motion. */
  reducedMotion?: () => boolean;
  /** Display name of a sender, for the replay's notice. Default: the id. */
  resolveName?: (user: string) => string;
  someone?: string;
  onShow?: (summary: AwaySummary) => void;
  onDone?: () => void;
  onError?: (error: GiftingError) => void;
}

export interface UseGiftAway {
  state: AwayState;
  controller: AwayController;
  /** Ask the server now (ignored while a card is up). */
  check: () => Promise<void>;
  dismiss: () => void;
  ack: () => Promise<void>;
}

function controllerOptions(o: UseGiftAwayOptions): AwayControllerOptions {
  return {
    client: o.client,
    effects: () => o.effects?.current,
    reducedMotion: o.reducedMotion,
    ackOn: o.ackOn,
    maxEffects: o.maxEffects,
    budgetMs: o.budgetMs,
    maxGroups: o.maxGroups,
    minGifts: o.minGifts,
    thresholds: o.thresholds,
    quality: o.quality,
    resolveName: o.resolveName,
    labels: o.someone ? { someone: o.someone } : undefined,
    onShow: o.onShow,
    onDone: o.onDone,
    onError: o.onError,
  };
}

/**
 * Everything the "while you were away" card needs besides drawing: checks on mount and on return
 * to the foreground (at most once a minute), and runs the replay and the acknowledgement. The
 * logic lives in `AwayController` (core). The card calls `controller.start()` once it is on screen.
 */
export function useGiftAway(options: UseGiftAwayOptions): UseGiftAway {
  const autoCheck = options.autoCheck ?? true;
  const latest = useRef(options);
  latest.current = options;
  const controller = useDisposable(
    () => new AwayController(controllerOptions(latest.current)),
    [options.client],
    (c) => {
      if (latest.current.autoCheck ?? true) void c.check();
    },
  );
  controller.setOptions(controllerOptions(options));
  const state = useSyncExternalStore(controller.subscribe, controller.getState);

  useEffect(() => {
    if (!autoCheck) return;
    const sub = AppState.addEventListener("change", (s) => {
      if (s === "active") void controller.foreground();
    });
    return () => sub.remove();
  }, [controller, autoCheck]);

  return {
    state,
    controller,
    check: controller.check,
    dismiss: controller.dismiss,
    ack: controller.ack,
  };
}
