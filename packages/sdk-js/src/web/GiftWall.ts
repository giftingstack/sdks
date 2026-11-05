import {
  type GiftingClient,
  type GiftingError,
  type ReceivedGift,
  type WallChip,
  type WallOrder,
  GiftWallLoader,
  asGiftingError,
  groupThousands,
  wallChips,
} from "../core";
import { type GiftLabels, type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";
import { type RenderResult, giftIcon, make, motionOff, runRender, shortCount } from "./ui";

export type WallGift = ReceivedGift["gift"];

/** What `renderChip` receives for one gift chip. */
export interface WallChipContext {
  gift: WallGift;
  /** The exact count. */
  count: number;
  /** The count as the default chip shows it (`1.2K`). */
  countText: string;
  /** The document to create elements with. */
  doc: Document;
}

export interface GiftWallOptions {
  client: GiftingClient;
  /** The receiver's external id. */
  user: string;
  /** Your content id (for example a post id). Absent: the person's profile wall. */
  reference?: string;
  /** Chips shown, the overflow chip included. Default 6. */
  max?: number;
  /** `"count"` (default): most received first. `"catalog"`: the server's order. */
  order?: WallOrder;
  /** `sm`: icon 16, text 11. `md` (default): icon 20, text 12.5. */
  size?: "sm" | "md";
  /** Preloaded counters: no request is made. */
  data?: ReceivedGift[];
  /** Change it to ask the server again (for example after the person sent a gift). */
  refreshKey?: string | number;
  /**
   * Draw the inside of each gift chip yourself (web only / pending native port). The wall still
   * loads, orders and caps the chips and keeps the chip element (button or not, its label and the
   * press). Return a node or a string; nothing (`null` / `undefined`) draws the default icon and
   * count. The "+37" overflow chip is not passed here. Not called while loading.
   */
  renderChip?: (chip: WallChipContext) => RenderResult;
  /** Makes every gift chip a button. */
  onPressChip?: (gift: WallGift) => void;
  /** A wall never shows an error; it comes here. */
  onError?: (error: GiftingError) => void;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
}

/** One loader per client, so every wall of a screen shares its batch calls and cache. */
const loaders = new WeakMap<GiftingClient, GiftWallLoader>();
export function wallLoaderFor(client: GiftingClient): GiftWallLoader {
  let loader = loaders.get(client);
  if (!loader) {
    loader = new GiftWallLoader({ query: (items) => client.queryGiftWalls(items) });
    loaders.set(client, loader);
  }
  return loader;
}

const SKELETONS = 3;
const FADE_MS = 120;

/**
 * Gift chips under a post or on a profile: `[rose 12] [heart 3] [+37]`. Read-only; with
 * `onPressChip` each chip is a button. The walls of a feed are fetched together: calls made
 * within 50 ms share one request and each answer is reused for a minute. Nothing is drawn when
 * there is nothing to show or the request failed (a wall is decoration).
 */
export class GiftWall {
  /** The wall's root element, a child of the container. */
  readonly element: HTMLElement;
  private o: GiftWallOptions;
  private readonly doc: Document;
  private gifts: ReceivedGift[] | null = null;
  private generation = 0;
  private destroyed = false;

  constructor(container: HTMLElement, options: GiftWallOptions) {
    this.doc = container.ownerDocument;
    this.o = options;
    acquireStyles(this.doc);
    this.element = make(this.doc, "div", "gs-wall");
    this.element.setAttribute("data-gs-wall", "");
    container.appendChild(this.element);
    this.begin();
  }

  /** Change options later. A new `user`, `reference` or `data` starts over; `refreshKey` refetches. */
  update(patch: Partial<GiftWallOptions>): void {
    if (this.destroyed) return;
    const prev = this.o;
    this.o = { ...prev, ...patch };
    const o = this.o;
    const sameWall =
      o.user === prev.user &&
      (o.reference ?? null) === (prev.reference ?? null) &&
      o.client === prev.client;
    if (!sameWall || o.data !== prev.data) {
      this.begin();
    } else if (o.refreshKey !== prev.refreshKey && !o.data) {
      wallLoaderFor(o.client).invalidate(o.user, o.reference);
      this.load(false);
    } else {
      this.render();
    }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.generation++;
    this.element.remove();
    releaseStyles();
  }

  /** (Re)start for the current wall: preloaded data, a fresh cache hit, or a request. */
  private begin(): void {
    this.generation++;
    const o = this.o;
    if (o.data) {
      this.gifts = o.data;
      this.render(false);
      return;
    }
    const cached = wallLoaderFor(o.client).peek(o.user, o.reference);
    this.gifts = cached ?? null;
    this.render(false);
    if (!cached) this.load(true);
  }

  private load(fresh: boolean): void {
    const generation = ++this.generation;
    const { client, user, reference } = this.o;
    wallLoaderFor(client)
      .load(user, reference)
      .then(
        (gifts) => {
          if (this.destroyed || generation !== this.generation) return;
          this.gifts = gifts;
          this.render(fresh);
        },
        (err: unknown) => {
          if (this.destroyed || generation !== this.generation) return;
          // A wall is decoration: keep what is shown (nothing, on the first load) and tell the app.
          if (this.gifts === null) this.gifts = [];
          this.render(false);
          this.o.onError?.(asGiftingError(err));
        },
      );
  }

  private render(fadeIn = false): void {
    const o = this.o;
    const labels = resolveLabels(o.labels);
    const root = this.element;
    root.className = `gs-wall gs-wall-${o.size ?? "md"}`;
    applyTheme(root, o.theme);
    root.replaceChildren();
    root.removeAttribute("role");
    root.removeAttribute("aria-label");
    root.removeAttribute("aria-hidden");
    root.hidden = false;

    if (this.gifts === null) {
      // Loading: static grey chips.
      root.setAttribute("aria-hidden", "true");
      for (let i = 0; i < SKELETONS; i++) make(this.doc, "span", "gs-chip gs-chip-skeleton", root);
      return;
    }
    const chips = wallChips(this.gifts, { max: o.max, order: o.order });
    if (chips.length === 0) {
      if (labels.emptyText) {
        const t = make(this.doc, "span", "gs-wall-empty", root);
        t.textContent = labels.emptyText;
        return;
      }
      root.hidden = true;
      return;
    }

    const press = o.onPressChip;
    const summary = this.summary(chips, labels);
    if (press) {
      root.setAttribute("role", "group");
      root.setAttribute("aria-label", summary);
    } else {
      // One element for a screen reader; the chips are pictures of it.
      root.setAttribute("role", "img");
      root.setAttribute("aria-label", summary);
    }
    for (const chip of chips) {
      if (chip.type === "overflow") {
        const el = make(this.doc, "span", "gs-chip gs-chip-more", root);
        el.textContent = `+${shortCount(chip.count, labels)}`;
        el.setAttribute("data-gs-overflow", "");
        continue;
      }
      const name = chip.gift.name;
      const el = make(this.doc, press ? "button" : "span", "gs-chip", root);
      el.setAttribute("data-gs-gift", chip.gift.id);
      const countText = shortCount(chip.count, labels);
      const render = o.renderChip;
      const custom = render
        ? runRender(
            this.doc,
            () => render({ gift: chip.gift, count: chip.count, countText, doc: this.doc }),
            (err) => o.onError?.(asGiftingError(err)),
          )
        : null;
      if (custom) el.append(custom);
      else {
        el.append(giftIcon(this.doc, chip.gift.icon_url));
        make(this.doc, "span", "gs-chip-count", el).textContent = countText;
      }
      if (press) {
        (el as HTMLButtonElement).type = "button";
        el.setAttribute(
          "aria-label",
          fill(labels.wallChip, { name, count: groupThousands(chip.count) }),
        );
        el.addEventListener("click", () => this.o.onPressChip?.(chip.gift));
      }
    }
    if (fadeIn && !motionOff(this.doc)) {
      root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: FADE_MS, easing: "ease-out" });
    }
  }

  /** `"Gifts: 12 Roses, 3 Hearts, and 37 more"`. */
  private summary(chips: WallChip[], labels: GiftLabels): string {
    const parts: string[] = [];
    let more = "";
    for (const chip of chips) {
      if (chip.type === "overflow") {
        more = fill(labels.wallMore, { n: groupThousands(chip.count) });
        continue;
      }
      const name = chip.gift.name + (chip.count > 1 ? labels.plural : "");
      parts.push(`${groupThousands(chip.count)} ${name}`);
    }
    if (more) parts.push(more);
    return fill(labels.wallSummary, { list: parts.join(", ") });
  }
}
