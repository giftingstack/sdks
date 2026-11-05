import { useRef, useSyncExternalStore } from "react";
import {
  type GiftingClient,
  type GiftingError,
  InboxController,
  type InboxItem,
  type InboxState,
} from "../core";
import { useDisposable } from "./use-disposable";

export interface UseGiftInboxOptions {
  client: GiftingClient;
  /** Rows per page, 1 to 100. Default 20. */
  pageSize?: number;
  /** Called with every loaded item after each load (count your own badge with `inboxUnread`). */
  onLoaded?: (items: InboxItem[]) => void;
  onError?: (error: GiftingError) => void;
}

export interface UseGiftInbox {
  state: InboxState;
  controller: InboxController;
  /** Load again from the first page. */
  refresh: () => void;
  /** Append the next (older) page. */
  loadMore: () => void;
}

/**
 * The state of the gift inbox: the first page loads on mount, `loadMore` appends older pages,
 * `refresh` reloads. The logic lives in `InboxController` (core).
 */
export function useGiftInbox(options: UseGiftInboxOptions): UseGiftInbox {
  const latest = useRef(options);
  latest.current = options;
  const controller = useDisposable(
    () => new InboxController(latest.current),
    [options.client],
    (c) => c.start(),
  );
  controller.setOptions({
    client: options.client,
    pageSize: options.pageSize,
    onLoaded: options.onLoaded,
    onError: options.onError,
  });
  const state = useSyncExternalStore(controller.subscribe, controller.getState);
  return { state, controller, refresh: controller.refresh, loadMore: controller.loadMore };
}
