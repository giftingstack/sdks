/** A scripted browser/React Native `WebSocket` for the room wrapper tests. */
export class FakeWebSocket {
  static all: FakeWebSocket[] = [];
  static reset(): void {
    FakeWebSocket.all = [];
  }
  static last(): FakeWebSocket {
    const ws = FakeWebSocket.all[FakeWebSocket.all.length - 1];
    if (!ws) throw new Error("no socket was opened");
    return ws;
  }

  onopen: ((ev: unknown) => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  onclose: ((ev: { code: number; reason: string }) => void) | null = null;
  onerror: ((ev: unknown) => void) | null = null;
  readonly sent: string[] = [];
  closedWith: { code?: number; reason?: string } | null = null;

  constructor(
    readonly url: string,
    readonly protocols: string[],
  ) {
    FakeWebSocket.all.push(this);
  }

  send(data: string): void {
    this.sent.push(data);
  }

  close(code?: number, reason?: string): void {
    this.closedWith = { code, reason };
  }

  // ---- server side
  serverOpen(): void {
    this.onopen?.({});
  }
  serverSend(data: unknown): void {
    this.onmessage?.({ data: typeof data === "string" ? data : JSON.stringify(data) });
  }
  serverClose(code: number, reason = ""): void {
    this.onclose?.({ code, reason });
  }
  serverError(): void {
    this.onerror?.({});
  }
}

export const welcome = (over: Record<string, unknown> = {}) => ({
  t: "welcome",
  v: 1,
  viewers: 2,
  gap: false,
  replay: [],
  ttl: 3600,
  now: Date.now(),
  ...over,
});

export const giftFrame = (id: number, tx: string, sender = "ayla", name?: string) => ({
  t: "gift",
  id,
  at: Date.now(),
  tx,
  gift: { id: "rose", name: "Rose", price: 10, icon_url: "https://assets.test/rose/256.webp" },
  quantity: 2,
  sender: name ? { id: sender, name } : { id: sender },
  receiver: { id: "host" },
});
