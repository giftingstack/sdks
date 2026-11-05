import type { RoomSocketFactory } from "../core";

/** The part of the WHATWG `WebSocket` (browsers and React Native) the room transport uses. */
export interface WebSocketLike {
  onopen: ((ev: unknown) => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onclose: ((ev: { code: number; reason: string }) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  send(data: string): void;
  close(code?: number, reason?: string): void;
}

export type WebSocketConstructor = new (url: string, protocols: string[]) => WebSocketLike;

/**
 * A `RoomSocketFactory` over the global `WebSocket` (or the one given): protocols
 * `["gs.v1", token]`, text frames only, `onClose` exactly once (an error is followed by a close
 * event; a constructor that throws is a close with 1006).
 */
export function webSocketRoomFactory(ctor?: WebSocketConstructor): RoomSocketFactory {
  return (url, protocols, handlers) => {
    const Ctor =
      ctor ?? (globalThis as unknown as { WebSocket?: WebSocketConstructor }).WebSocket ?? null;
    if (!Ctor) throw new Error("WebSocket is not available");
    const ws = new Ctor(url, protocols);
    let done = false;
    const close = (code: number, reason: string) => {
      if (done) return;
      done = true;
      ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
      handlers.onClose(code, reason);
    };
    ws.onopen = () => handlers.onOpen();
    ws.onmessage = (ev) => {
      if (typeof ev.data === "string") handlers.onMessage(ev.data);
    };
    ws.onclose = (ev) => close(ev.code || 1006, ev.reason ?? "");
    // Browsers fire `close` after `error`; React Native too. This only covers runtimes that do not.
    ws.onerror = () => {};
    return {
      send: (data) => ws.send(data),
      close: (code, reason) => {
        done = true;
        ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
        try {
          ws.close(code, reason);
        } catch {
          // Already closed or closing.
        }
      },
    };
  };
}
