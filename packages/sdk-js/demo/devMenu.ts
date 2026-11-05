/**
 * The hidden developer menu of the demo: the only debug surface. Folded by default; opened by a
 * 1 s long-press (or 5 quick clicks for a mouse) on the app logo. Not part of the SDK.
 */

export type IncomingMode = "tray" | "random" | "cheapest" | "priciest";
export type DemoTheme = "dark" | "light" | "pink";
/** How the demo shows the "while you were away" data: the SDK card, a badge and a plain box, or your own body in the card. */
export type AwayPattern = "card" | "badge" | "custom";

export interface TriggerOptions {
  holdMs?: number;
  clicks?: number;
  /** All the clicks must land within this time. */
  clickWindowMs?: number;
}

/** Long-press (default 1000 ms) or 5 clicks within 3 s on `target` call `onOpen`. Returns a detach function. */
export function attachDevTrigger(
  target: HTMLElement,
  onOpen: () => void,
  o: TriggerOptions = {},
): () => void {
  const holdMs = o.holdMs ?? 1000;
  const need = o.clicks ?? 5;
  const windowMs = o.clickWindowMs ?? 3000;
  let hold: ReturnType<typeof setTimeout> | undefined;
  let stamps: number[] = [];
  const cancel = (): void => {
    clearTimeout(hold);
    hold = undefined;
  };
  const down = (): void => {
    cancel();
    hold = setTimeout(() => {
      hold = undefined;
      stamps = [];
      onOpen();
    }, holdMs);
  };
  const click = (): void => {
    const now = Date.now();
    stamps = [...stamps.filter((t) => now - t <= windowMs), now];
    if (stamps.length >= need) {
      stamps = [];
      onOpen();
    }
  };
  const noMenu = (e: Event): void => e.preventDefault();
  target.addEventListener("pointerdown", down);
  for (const type of ["pointerup", "pointerleave", "pointercancel"]) {
    target.addEventListener(type, cancel);
  }
  target.addEventListener("click", click);
  target.addEventListener("contextmenu", noMenu);
  return () => {
    cancel();
    target.removeEventListener("pointerdown", down);
    for (const type of ["pointerup", "pointerleave", "pointercancel"]) {
      target.removeEventListener(type, cancel);
    }
    target.removeEventListener("click", click);
    target.removeEventListener("contextmenu", noMenu);
  };
}

export interface DevMenuActions {
  playIncoming(mode: IncomingMode): void;
  combo(mode: IncomingMode): void;
  awayAgain(): void;
  wallPlus(): void;
  setAwayPattern(pattern: AwayPattern): void;
  setQuality(quality: "high" | "low"): void;
  setTheme(theme: DemoTheme): void;
  setMotion(motion: "system" | "reduced"): void;
  reset(): void;
  setOffline(offline: boolean): void;
}

export interface DevMenu {
  element: HTMLElement;
  open(): void;
  close(): void;
  isOpen(): boolean;
}

/** Builds the menu into `host`, closed. */
export function createDevMenu(host: HTMLElement, actions: DevMenuActions): DevMenu {
  const doc = host.ownerDocument;
  const make = <K extends keyof HTMLElementTagNameMap>(
    tag: K,
    cls = "",
    text = "",
  ): HTMLElementTagNameMap[K] => {
    const e = doc.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  };
  const root = make("div", "dev-root");
  root.hidden = true;
  root.setAttribute("data-dev-menu", "");
  const scrim = make("div", "dev-scrim");
  const sheet = make("section", "dev-sheet");
  sheet.setAttribute("role", "dialog");
  sheet.setAttribute("aria-label", "Developer menu");
  const head = make("div", "dev-head");
  const titles = make("div");
  titles.append(make("h2", "", "Developer menu"), make("p", "", "Not part of the SDK"));
  const done = make("button", "dev-btn dev-done", "Done");
  done.type = "button";
  head.append(titles, done);
  sheet.append(head);

  const row = (label: string, ...items: HTMLElement[]): void => {
    const r = make("div", "dev-row");
    r.append(make("span", "dev-label", label));
    const box = make("div", "dev-ctl");
    box.append(...items);
    r.append(box);
    sheet.append(r);
  };
  const button = (text: string, on: () => void): HTMLButtonElement => {
    const b = make("button", "dev-btn", text);
    b.type = "button";
    b.addEventListener("click", on);
    return b;
  };
  /** A row of exclusive choices; `on` runs for the picked value. */
  const choice = <T extends string>(
    label: string,
    options: [T, string][],
    start: T,
    on: (v: T) => void,
  ): void => {
    const buttons = options.map(([value, text]) => {
      const b = make("button", "dev-btn", text);
      b.type = "button";
      b.dataset.value = value;
      b.setAttribute("aria-pressed", String(value === start));
      b.addEventListener("click", () => {
        for (const o of buttons) o.setAttribute("aria-pressed", String(o === b));
        on(value);
      });
      return b;
    });
    row(label, ...buttons);
  };

  let mode: IncomingMode = "tray";
  choice<IncomingMode>(
    "Incoming gift",
    [
      ["tray", "Same as tray"],
      ["random", "Random"],
      ["cheapest", "Cheapest"],
      ["priciest", "Priciest"],
    ],
    "tray",
    (v) => (mode = v),
  );
  row(
    "Play",
    button("Play gift", () => actions.playIncoming(mode)),
    button("x5 combo", () => actions.combo(mode)),
    button("Away summary again", actions.awayAgain),
    button("Wall +5", actions.wallPlus),
  );
  choice<AwayPattern>(
    "Example integration",
    [
      ["card", "Card"],
      ["badge", "Badge + box"],
      ["custom", "Custom"],
    ],
    "card",
    actions.setAwayPattern,
  );
  choice(
    "Quality",
    [
      ["high", "High"],
      ["low", "Low"],
    ],
    "high",
    actions.setQuality,
  );
  choice<DemoTheme>(
    "Theme",
    [
      ["dark", "Dark"],
      ["light", "Light"],
      ["pink", "Pink"],
    ],
    "dark",
    actions.setTheme,
  );
  choice(
    "Motion",
    [
      ["system", "System"],
      ["reduced", "Reduced"],
    ],
    "system",
    actions.setMotion,
  );
  const off = make("input");
  off.type = "checkbox";
  off.setAttribute("aria-label", "Mock failure: go offline");
  off.addEventListener("change", () => actions.setOffline(off.checked));
  row("Mock failure", off, make("span", "dev-note", "Go offline"));
  row("Demo", button("Reset demo", actions.reset));

  const close = (): void => {
    root.hidden = true;
  };
  const onKey = (e: KeyboardEvent): void => {
    if (e.key === "Escape" && !root.hidden) close();
  };
  scrim.addEventListener("click", close);
  done.addEventListener("click", close);
  doc.addEventListener("keydown", onKey);
  root.append(scrim, sheet);
  host.append(root);
  return {
    element: root,
    open() {
      root.hidden = false;
      (sheet.querySelector("button") as HTMLElement | null)?.focus();
    },
    close,
    isOpen: () => !root.hidden,
  };
}
