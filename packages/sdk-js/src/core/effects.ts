/**
 * Decides which gift effects are on screen, which wait and what the notice says. No drawing,
 * no timers: a player (React Native today, other platforms later) tells it when an effect really
 * started and when it finished, and draws what the listener reports.
 */
import { createComboTracker, type ComboTracker } from "./combo";
import {
  type EffectQuality,
  type EffectRecipe,
  type EffectTier,
  type TierThresholds,
  recipeFor,
  tierFor,
} from "./recipes";
import { type RecipeSet, embeddedRecipeSet, mergeRecipeSet } from "./remote-recipes";
import type { GiftEffectEvent, GiftEffectReceiver } from "./types";

/** The built-in set, used when no remote set is given. */
const EMBEDDED_SET = embeddedRecipeSet();

/** At most this many effects of a kind on screen at once. Large ones queue instead. */
export const MAX_CONCURRENT_EFFECTS: Readonly<Record<EffectTier, number>> = {
  small: 6,
  medium: 2,
  large: 1,
};
/** Large gifts waiting their turn. A new one beyond this drops the oldest waiting one. */
export const MAX_QUEUED_LARGE = 5;
/** Shown in the notice when an event has no sender. */
export const DEFAULT_SENDER_NAME = "Someone";
/** Notice ids remembered at once, one per (sender, gift) pair; the oldest is dropped beyond this. */
export const MAX_NOTICE_KEYS = 32;

/**
 * What tells two receivers apart for the combo and the notice key: the side and the name (two
 * hosts that share a display name still sit on different sides). null without a receiver.
 */
function receiverKey(receiver: GiftEffectReceiver | undefined): string | null {
  return receiver ? `${receiver.side ?? ""}:${receiver.name}` : null;
}

export interface ScheduledEffect {
  id: number;
  event: GiftEffectEvent;
  recipe: EffectRecipe;
  /** Combo count for the notice, fixed when the gift was sent. */
  count: number;
}

export interface NoticeData {
  /** Changes when a different gift or sender starts a new notice; the slide-in plays again. */
  id: number;
  senderName: string;
  giftName: string;
  image: string | null;
  /** Gifts in a row, 1 for a single gift. */
  count: number;
  big: boolean;
  /** Only in a battle (SPEC 7.4): who got the gift and the side's colour. */
  receiver?: GiftEffectReceiver;
}

export interface EffectSchedulerListener {
  /** An effect enters the screen. Draw it; call `started(id)` once its picture is ready. */
  enter?(effect: ScheduledEffect): void;
  /** An effect leaves the screen (finished or cancelled). Remove it. */
  exit?(effect: ScheduledEffect): void;
  /** An effect played to its end. Not called for cancelled or cleared effects. */
  end?(effect: ScheduledEffect): void;
  /** Show this notice now and call `noticeExpired()` after `durationMs`, replacing any earlier timer. */
  notice?(notice: NoticeData, durationMs: number): void;
  /** Hide the notice and drop its timer. */
  noticeHide?(): void;
  /** Every effect is gone at once (`clear`). */
  clear?(): void;
}

export interface EffectSchedulerOptions {
  thresholds?: Partial<TierThresholds>;
  quality?: EffectQuality;
  /** Only the notice shows, no effect. */
  reducedMotion?: boolean;
  /**
   * A remote recipe set (spec section 13), read at each `play`. Default: the embedded one.
   * `thresholds` above and the constructor's `comboWindowMs` still win over it.
   */
  recipes?: RecipeSet;
  /**
   * How many small or medium effects may play at once, instead of the built-in 6 and 2 (spec
   * section 6 step 6). Whole numbers from 1 to 12; anything else keeps the built-in value. Large
   * effects are always one at a time. An app choice: it is not part of the shared conformance
   * numbers, so other platforms keep their default until they offer the same option.
   */
  maxConcurrent?: Partial<Record<"small" | "medium", number>>;
}

export class EffectScheduler {
  listener: EffectSchedulerListener = {};
  private options: EffectSchedulerOptions = {};
  private readonly combo: ComboTracker;
  private readonly now: () => number;
  private nextId = 1;
  private running: Record<EffectTier, number> = { small: 0, medium: 0, large: 0 };
  private queue: ScheduledEffect[] = [];
  private readonly onScreen = new Map<number, ScheduledEffect>();
  /** (sender, gift) pair -> notice id, oldest first. */
  private readonly noticeIds = new Map<string, number>();
  private lastNoticeKey = "";
  private noticeId = 0;
  /** The play() id that wrote the notice now on screen. */
  private noticeOwner = 0;
  private noticeData: NoticeData | null = null;
  private noticeVisible = false;

  /** The combo window the app gave; when absent the recipe set's window applies. */
  private readonly appComboWindowMs: number | undefined;
  private comboWindowMs: number;

  constructor(config: { comboWindowMs?: number; now?: () => number } = {}) {
    this.appComboWindowMs = config.comboWindowMs;
    this.comboWindowMs = config.comboWindowMs ?? EMBEDDED_SET.comboWindowMs;
    this.combo = createComboTracker(() => this.comboWindowMs);
    this.now = config.now ?? (() => Date.now());
  }

  setOptions(options: EffectSchedulerOptions): void {
    this.options = options;
  }

  /** The cap for small and medium effects: the app's own number when valid, else the built-in. */
  private capFor(tier: "small" | "medium"): number {
    const own = this.options.maxConcurrent?.[tier];
    return typeof own === "number" && Number.isInteger(own) && own >= 1 && own <= 12
      ? own
      : MAX_CONCURRENT_EFFECTS[tier];
  }

  /** Effects on screen, in the order they entered. */
  active(): ScheduledEffect[] {
    return [...this.onScreen.values()];
  }

  /** Large effects waiting their turn, oldest first. */
  queued(): ScheduledEffect[] {
    return [...this.queue];
  }

  /** The last notice written (it stays after hiding) and whether it is showing. */
  notice(): { data: NoticeData | null; visible: boolean; owner: number } {
    return { data: this.noticeData, visible: this.noticeVisible, owner: this.noticeOwner };
  }

  /**
   * Show a gift. Large gifts wait their turn; small and medium ones play at once, or show only
   * the notice when too many are on screen. Returns an id for `cancel`.
   */
  play(event: GiftEffectEvent): number {
    // Merge order: embedded < remote < app (spec 13.4). The recipe is fixed here, so effects
    // already playing or waiting keep it when a new remote set arrives.
    const set = mergeRecipeSet(EMBEDDED_SET, this.options.recipes ?? null, {
      thresholds: this.options.thresholds,
      comboWindowMs: this.appComboWindowMs,
    });
    this.comboWindowMs = set.comboWindowMs;
    const tier = tierFor(event.gift.price, set.thresholds);
    const recipe = recipeFor(tier, this.options.quality ?? "high", set);
    const sender = event.sender ?? DEFAULT_SENDER_NAME;
    const quantity = event.quantity ?? 1;
    const id = this.nextId++;
    // A combo counts per receiver too: gifts to two hosts of a battle are two runs.
    const rkey = receiverKey(event.receiver);
    const run = this.combo.hit(
      sender,
      rkey === null ? event.gift.id : JSON.stringify([event.gift.id, rkey]),
      this.now(),
    );
    const count = quantity > 1 ? quantity : run;
    const item: ScheduledEffect = { id, event, recipe, count };
    // Without an effect the notice shows now; with one, it shows when the effect starts.
    if (this.options.reducedMotion) {
      this.showNotice(item);
      return id;
    }
    if (tier === "large") {
      if (this.running.large >= MAX_CONCURRENT_EFFECTS.large) {
        if (this.queue.length >= MAX_QUEUED_LARGE) this.queue.shift();
        this.queue.push(item);
      } else {
        this.start(item);
      }
    } else if (this.running[tier] < this.capFor(tier)) {
      this.start(item);
    } else {
      this.showNotice(item); // too many on screen: notice only
    }
    return id;
  }

  /** The effect's picture is ready (or the wait ran out): it really starts, with its notice. */
  started(id: number): void {
    const item = this.onScreen.get(id);
    if (item) this.showNotice(item);
  }

  /** The effect's animation ran to its end. */
  finished(id: number): void {
    const item = this.onScreen.get(id);
    if (!item) return;
    this.release(item);
    this.listener.end?.(item);
  }

  /** Take back a gift that was shown too early, for example because its send failed. */
  cancel(id: number): void {
    this.queue = this.queue.filter((i) => i.id !== id);
    const item = this.onScreen.get(id);
    if (item) this.release(item);
    if (this.noticeOwner === id) this.hideNotice();
  }

  /** Stop everything, forget the queue and the combo run. */
  clear(): void {
    this.queue = [];
    this.onScreen.clear();
    this.running = { small: 0, medium: 0, large: 0 };
    this.listener.clear?.();
    this.hideNotice();
    this.noticeIds.clear();
    this.combo.reset();
  }

  /** The notice's time is up. */
  noticeExpired(): void {
    this.noticeVisible = false;
    this.noticeIds.clear();
    this.lastNoticeKey = "";
    this.listener.noticeHide?.();
  }

  private start(item: ScheduledEffect): void {
    this.running[item.recipe.tier]++;
    this.onScreen.set(item.id, item);
    this.listener.enter?.(item);
  }

  /** Takes an effect off the screen and lets the next large one in. */
  private release(item: ScheduledEffect): void {
    const tier = item.recipe.tier;
    this.onScreen.delete(item.id);
    this.running[tier] = Math.max(0, this.running[tier] - 1);
    this.listener.exit?.(item);
    if (tier === "large") {
      const next = this.queue.shift();
      if (next) this.start(next);
    }
  }

  private showNotice(item: ScheduledEffect): void {
    const { event, recipe, count, id } = item;
    const sender = event.sender ?? DEFAULT_SENDER_NAME;
    const receiver = event.receiver;
    // The receiver is part of the key: a combo to one host and one to the other are two notices.
    const rkey = receiverKey(receiver);
    const key = rkey === null ? `${sender}|${event.gift.id}` : `${sender}|${event.gift.id}|${rkey}`;
    this.noticeOwner = id;
    // Every pair keeps its own id while it is remembered, so a combo returns to its own line
    // even when other people sent gifts in between.
    let noticeId = this.noticeIds.get(key);
    if (noticeId === undefined) noticeId = ++this.noticeId;
    this.noticeIds.delete(key);
    this.noticeIds.set(key, noticeId);
    if (this.noticeIds.size > MAX_NOTICE_KEYS) {
      this.noticeIds.delete(this.noticeIds.keys().next().value as string);
    }
    this.lastNoticeKey = key;
    this.noticeData = {
      id: noticeId,
      senderName: sender,
      giftName: event.gift.name,
      image: event.gift.icon ?? event.gift.image,
      count,
      big: recipe.noticeBig,
    };
    if (receiver) {
      this.noticeData.receiver = {
        name: receiver.name,
        ...(receiver.side !== undefined ? { side: receiver.side } : {}),
        color: receiver.color ?? null,
      };
    }
    this.noticeVisible = true;
    this.listener.notice?.(this.noticeData, recipe.noticeMs);
  }

  private hideNotice(): void {
    this.noticeVisible = false;
    this.noticeIds.delete(this.lastNoticeKey);
    this.lastNoticeKey = "";
    this.listener.noticeHide?.();
  }
}
