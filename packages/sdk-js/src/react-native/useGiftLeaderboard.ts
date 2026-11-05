import { useEffect, useRef, useSyncExternalStore } from "react";
import {
  type GiftingClient,
  type GiftingError,
  LeaderboardController,
  type LeaderboardBoard,
  type LeaderboardControllerOptions,
  type LeaderboardMetric,
  type LeaderboardPeriod,
  type LeaderboardState,
  leaderboardPollMs,
} from "../core";
import { useDisposable } from "./use-disposable";

export interface UseGiftLeaderboardOptions {
  client: GiftingClient;
  /** Default `"senders"`. */
  board?: LeaderboardBoard;
  /** Tabs, in this order. Default day, week, month, all. */
  periods?: readonly LeaderboardPeriod[];
  /** Default `"week"`. */
  initialPeriod?: LeaderboardPeriod;
  /** Default `"units"` (`"gifts"` for receivers). */
  metric?: LeaderboardMetric;
  /** Rows, 1 to 100. Default 10. */
  limit?: number;
  /** 0 (default): no polling. Otherwise the current tab is fetched again this often (ms, at least 5,000). */
  refreshIntervalMs?: number;
  onError?: (error: GiftingError) => void;
}

export interface UseGiftLeaderboard {
  state: LeaderboardState;
  controller: LeaderboardController;
  setPeriod: (period: LeaderboardPeriod) => void;
  setMetric: (metric: LeaderboardMetric) => void;
  /** Fetch the current tab again now. */
  refresh: () => void;
}

function controllerOptions(o: UseGiftLeaderboardOptions): LeaderboardControllerOptions {
  return {
    client: o.client,
    board: o.board,
    periods: o.periods,
    initialPeriod: o.initialPeriod,
    metric: o.metric,
    limit: o.limit,
    onError: o.onError,
  };
}

/**
 * The state of a leaderboard: the current tab, a per-tab cache that answers at once and refetches
 * in the background when older than 30 s, and the viewer's pinned row. The logic lives in
 * `LeaderboardController` (core).
 */
export function useGiftLeaderboard(options: UseGiftLeaderboardOptions): UseGiftLeaderboard {
  const latest = useRef(options);
  latest.current = options;
  const controller = useDisposable(
    () => new LeaderboardController(controllerOptions(latest.current)),
    [
      options.client,
      options.board ?? "senders",
      options.limit ?? 10,
      options.initialPeriod ?? "week",
      options.metric ?? null,
      (options.periods ?? []).join(","),
    ],
    (c) => c.start(),
  );
  controller.setOptions(controllerOptions(options));
  const state = useSyncExternalStore(controller.subscribe, controller.getState);

  const every = leaderboardPollMs(options.refreshIntervalMs);
  useEffect(() => {
    if (every <= 0) return;
    const id = setInterval(() => controller.refresh(), every);
    return () => clearInterval(id);
  }, [controller, every]);

  return {
    state,
    controller,
    setPeriod: controller.setPeriod,
    setMetric: controller.setMetric,
    refresh: controller.refresh,
  };
}
