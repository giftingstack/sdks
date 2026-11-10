import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { GiftEffectEvent } from "../src/core";
import { GiftEffectLayer, type GiftEffectLayerOptions } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const gift = (id: string, price: number, extra: Partial<GiftEffectEvent["gift"]> = {}) => ({
  id,
  name: id.charAt(0).toUpperCase() + id.slice(1),
  price,
  image: `https://assets.test/${id}/512.webp`,
  icon: `https://assets.test/${id}/256.webp`,
  ...extra,
});
const rose = (sender = "ayla"): GiftEffectEvent => ({ gift: gift("rose", 10), sender });
const hat = (sender = "ayla"): GiftEffectEvent => ({ gift: gift("hat", 350), sender });
const dragon = (sender = "ayla"): GiftEffectEvent => ({ gift: gift("dragon", 40_000), sender });

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let layers: GiftEffectLayer[];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
  layers = [];
});
afterEach(() => {
  for (const l of layers) l.destroy();
  container.remove();
  vi.useRealTimers();
  env.restore();
});

function makeLayer(options: GiftEffectLayerOptions = {}): GiftEffectLayer {
  const layer = new GiftEffectLayer(container, { pictureWaitMs: 0, ...options });
  layers.push(layer);
  return layer;
}
const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const effects = (tier?: string) =>
  container.querySelectorAll(tier ? `[data-gs-effect="${tier}"]` : "[data-gs-effect]");
const noticeEl = () => container.querySelector("[data-gs-notice]") as HTMLElement | null;

describe("web GiftEffectLayer: DOM", () => {
  it("adds one layer that does not take pointer events and one style element", () => {
    const layer = makeLayer();
    expect(container.querySelectorAll("[data-gs-layer]")).toHaveLength(1);
    expect(layer.element.parentElement).toBe(container);
    expect(getComputedStyle(layer.element).pointerEvents).toBe("none");
    expect(document.head.querySelectorAll("style[data-giftingstack]")).toHaveLength(1);
    makeLayer();
    expect(document.head.querySelectorAll("style[data-giftingstack]")).toHaveLength(1);
  });

  it("a click goes through the layer to what is below", () => {
    const button = document.createElement("button");
    container.appendChild(button);
    const layer = makeLayer();
    layer.play(dragon());
    const onClick = vi.fn();
    button.addEventListener("click", onClick);
    button.click();
    expect(onClick).toHaveBeenCalled();
    // Everything the layer draws opts out of pointer events, in CSS.
    const css = document.head.querySelector("style[data-giftingstack]")!.textContent!;
    expect(css).toMatch(/\.gs-layer \{[^}]*pointer-events: none/);
    expect(css).toMatch(/\.gs-abs \{[^}]*pointer-events: none/);
  });

  it("an effect appears when it starts and is removed when it ends", async () => {
    const onEnd = vi.fn();
    const layer = makeLayer({ onEffectEnd: onEnd });
    layer.play(rose());
    expect(effects("small")).toHaveLength(1);
    await advance(1599);
    expect(effects("small")).toHaveLength(1);
    expect(onEnd).not.toHaveBeenCalled();
    await advance(1);
    expect(effects()).toHaveLength(0);
    expect(onEnd).toHaveBeenCalledTimes(1);
    expect(onEnd.mock.calls[0]?.[1]).toBe("small");
  });

  it.each([
    ["small", rose, "high", 1600],
    ["medium", hat, "high", 2100],
    ["large", dragon, "high", 3850],
    ["large", dragon, "low", 3050],
  ] as const)("a %s effect (%s quality) ends after %i ms", async (tier, make, quality, ms) => {
    const layer = makeLayer({ quality });
    layer.play(make());
    await advance(ms - 1);
    expect(effects(tier)).toHaveLength(1);
    await advance(1);
    expect(effects()).toHaveLength(0);
  });

  it("caps are visible in the DOM: 6 small, 2 medium, 1 large and the rest wait", () => {
    const layer = makeLayer();
    for (let i = 0; i < 8; i++) layer.play(rose(`u${i}`));
    expect(effects("small")).toHaveLength(6);
    for (let i = 0; i < 4; i++) layer.play(hat(`u${i}`));
    expect(effects("medium")).toHaveLength(2);
    for (let i = 0; i < 3; i++) layer.play(dragon(`u${i}`));
    expect(effects("large")).toHaveLength(1);
    expect(effects()).toHaveLength(9);
  });

  it("the next large gift enters when the first leaves", async () => {
    const layer = makeLayer();
    const first = layer.play(dragon("a"));
    layer.play(dragon("b"));
    expect(effects("large")[0]?.getAttribute("data-gs-effect-id")).toBe(String(first));
    await advance(3850);
    expect(effects("large")).toHaveLength(1);
    expect(effects("large")[0]?.getAttribute("data-gs-effect-id")).toBe("2");
  });

  it("cancel removes a playing effect at once, without the end callback", () => {
    const onEnd = vi.fn();
    const layer = makeLayer({ onEffectEnd: onEnd });
    const id = layer.play(hat());
    expect(effects()).toHaveLength(1);
    layer.cancel(id);
    expect(effects()).toHaveLength(0);
    expect(onEnd).not.toHaveBeenCalled();
  });

  it("ids start at 1, grow by 1 and are not reset by clear", () => {
    const layer = makeLayer();
    expect(layer.play(rose())).toBe(1);
    expect(layer.play(rose())).toBe(2);
    layer.clear();
    expect(layer.play(rose())).toBe(3);
  });

  it("clear removes every effect and stops their timers", async () => {
    const onEnd = vi.fn();
    const layer = makeLayer({ onEffectEnd: onEnd });
    layer.play(rose());
    layer.play(hat());
    layer.play(dragon());
    layer.clear();
    expect(effects()).toHaveLength(0);
    await advance(10_000);
    expect(onEnd).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
    expect(noticeEl()).toBeNull();
  });

  it("destroy removes the layer, the style, the timers and puts the container back", async () => {
    container.style.position = "";
    const layer = makeLayer();
    expect(container.style.position).toBe("relative");
    layer.play(dragon());
    layer.play(rose());
    await advance(100);
    layer.destroy();
    expect(container.children).toHaveLength(0);
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
    expect(container.style.position).toBe("");
    expect(vi.getTimerCount()).toBe(0);
    expect(layer.play(rose())).toBe(0);
    layer.destroy(); // twice is fine
    expect(env.animations.every((a) => a.cancelled)).toBe(true);
  });
});

describe("web GiftEffectLayer: animation", () => {
  it("animates only transform and opacity", async () => {
    const layer = makeLayer();
    layer.play(dragon());
    layer.play(hat());
    layer.play(rose());
    layer.play(rose());
    await advance(5000);
    expect(env.animations.length).toBeGreaterThan(50);
    const allowed = new Set(["transform", "opacity", "offset", "easing", "composite"]);
    for (const a of env.animations) {
      for (const f of a.frames) {
        for (const key of Object.keys(f)) expect(allowed, key).toContain(key);
      }
    }
  });

  it("quality changes the particle count: 50 sparks and 34 coins, or 16 sparks and none", async () => {
    const high = makeLayer();
    high.play(dragon());
    await advance(0);
    expect(container.querySelectorAll(".gs-spark")).toHaveLength(50);
    expect(container.querySelectorAll(".gs-coin-rain")).toHaveLength(34);
    expect(container.querySelectorAll(".gs-rays")).toHaveLength(2);
    expect(container.querySelectorAll(".gs-dim")).toHaveLength(1);
    high.destroy();

    const low = makeLayer({ quality: "low" });
    low.play(dragon());
    await advance(0);
    expect(container.querySelectorAll(".gs-spark")).toHaveLength(16);
    expect(container.querySelectorAll(".gs-coin-rain")).toHaveLength(0);
    expect(container.querySelectorAll(".gs-rays")).toHaveLength(0);
  });

  it("medium bursts 24 sparks and has no dim; small has neither", async () => {
    const layer = makeLayer();
    layer.play(hat());
    layer.play(rose());
    await advance(0);
    expect(container.querySelectorAll(".gs-spark")).toHaveLength(24);
    expect(container.querySelectorAll(".gs-dim")).toHaveLength(0);
  });

  it("starts nothing while the layer has no size, then starts when it gets one", async () => {
    let size = 0;
    let resized: () => void = () => {};
    vi.stubGlobal(
      "ResizeObserver",
      class {
        constructor(cb: () => void) {
          resized = cb;
        }
        observe() {}
        disconnect() {}
      },
    );
    Object.defineProperty(HTMLElement.prototype, "clientWidth", {
      configurable: true,
      get: () => size,
    });
    const layer = makeLayer();
    layer.play(hat());
    await advance(100);
    expect(env.animations).toHaveLength(0);
    expect(noticeEl()).toBeNull();
    size = 390;
    resized();
    expect(env.animations.length).toBeGreaterThan(0);
    expect(noticeEl()).not.toBeNull();
    vi.unstubAllGlobals();
  });
});

describe("web GiftEffectLayer: picture wait", () => {
  const imgOf = (id: number) =>
    container.querySelector(`[data-gs-effect-id="${id}"] img`) as HTMLImageElement;

  it("waits for the picture, then starts the effect and the notice together", async () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    const id = layer.play(hat());
    await advance(100);
    expect(env.animations).toHaveLength(0);
    expect(noticeEl()).toBeNull();
    imgOf(id).dispatchEvent(new Event("load"));
    await advance(0);
    expect(env.animations.length).toBeGreaterThan(0);
    expect(noticeEl()).not.toBeNull();
  });

  it("starts anyway after pictureWaitMs, and the notice is complete with its icon", async () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    layer.play(hat("mert"));
    await advance(299);
    expect(noticeEl()).toBeNull();
    await advance(1);
    const notice = noticeEl()!;
    expect(notice.textContent).toContain("mert");
    expect(notice.textContent).toContain("sent Hat");
    expect(notice.querySelector("img")!.getAttribute("src")).toBe(
      "https://assets.test/hat/256.webp",
    );
  });

  it("a failed picture starts the effect at once", async () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    const id = layer.play(rose());
    imgOf(id).dispatchEvent(new Event("error"));
    await advance(0);
    expect(noticeEl()).not.toBeNull();
  });

  it("without a picture the effect starts at once and draws a coin disc", async () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    layer.play({ gift: gift("dot", 5, { image: null, icon: null }) });
    await advance(0);
    expect(container.querySelector(".gs-picture-fallback")).not.toBeNull();
    expect(noticeEl()).not.toBeNull();
  });

  it("starts exactly once", async () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    const id = layer.play(rose());
    imgOf(id).dispatchEvent(new Event("load"));
    imgOf(id).dispatchEvent(new Event("error"));
    await advance(1000);
    const pictureAnimations = env.animations.filter((a) =>
      (a.el as HTMLElement).classList.contains("gs-picture"),
    );
    expect(pictureAnimations).toHaveLength(1);
  });
});

describe("web GiftEffectLayer: notice", () => {
  it("shows who sent what, bottom-left, with a live region", async () => {
    const layer = makeLayer({ noticeBottom: 200 });
    layer.play(rose("ayla"));
    await advance(0);
    const region = container.querySelector(".gs-notice-region") as HTMLElement;
    expect(region.getAttribute("role")).toBe("alert");
    expect(region.getAttribute("aria-live")).toBe("polite");
    expect(region.style.bottom).toBe("200px");
    const notice = noticeEl()!;
    expect(notice.querySelector(".gs-avatar")!.textContent).toBe("A");
    expect(notice.querySelector(".gs-notice-name")!.textContent).toBe("ayla");
    expect(notice.querySelector(".gs-notice-what")!.textContent).toBe("sent Rose");
    expect(notice.querySelector("[data-gs-combo]")).toBeNull();
  });

  it("a battle gift names the receiver and borders the pill in the side colour", async () => {
    const layer = makeLayer();
    layer.play({ ...rose("ayla"), receiver: { name: "Mia", side: 1, color: "#00aa88" } });
    await advance(0);
    const notice = noticeEl()!;
    expect(notice.querySelector(".gs-notice-what")!.textContent).toBe("sent Rose to Mia");
    expect(notice.style.boxShadow.toLowerCase()).toMatch(/00aa88|0, 170, 136/);
    expect(notice.style.boxShadow).toContain("2px");
  });

  it("an unreadable side colour falls back to the side's default", async () => {
    const layer = makeLayer();
    layer.play({ ...rose("ayla"), receiver: { name: "Mia", side: 1, color: "not a colour" } });
    await advance(0);
    expect(noticeEl()!.style.boxShadow).toContain("var(--gs-coin)");
  });

  it("without a receiver the pill has no border", async () => {
    const layer = makeLayer();
    layer.play(rose("ayla"));
    await advance(0);
    expect(noticeEl()!.style.boxShadow).toBe("");
  });

  it("counts a combo and keeps one notice element for the run", async () => {
    const layer = makeLayer();
    layer.play(rose());
    await advance(0);
    const first = noticeEl()!;
    layer.play(rose());
    await advance(0);
    expect(noticeEl()).toBe(first);
    expect(first.querySelector("[data-gs-combo]")!.textContent).toBe("x2");
    layer.play(rose());
    await advance(0);
    expect(first.querySelector("[data-gs-combo]")!.textContent).toBe("x3");
    // The counter pops: a scale animation on the combo element.
    const pops = env.animations.filter((a) => (a.el as HTMLElement).hasAttribute("data-gs-combo"));
    expect(pops).toHaveLength(2);
    expect(String((pops[0]!.frames[0] as { transform: string }).transform)).toBe("scale(1.9)");
  });

  it("a large gift gets the big, golden notice", async () => {
    const layer = makeLayer();
    layer.play(dragon());
    await advance(0);
    expect(noticeEl()!.classList.contains("gs-big")).toBe(true);
    layer.clear();
    layer.play(rose());
    await advance(0);
    expect(noticeEl()!.classList.contains("gs-big")).toBe(false);
  });

  it("slides out after its time and leaves nothing behind", async () => {
    const layer = makeLayer();
    layer.play(rose());
    await advance(2399);
    expect(noticeEl()!.getAttribute("data-gs-visible")).toBe("true");
    await advance(1);
    expect(noticeEl()!.getAttribute("data-gs-visible")).toBe("false");
    await advance(260);
    expect(noticeEl()).toBeNull();
    expect(container.querySelector(".gs-notice-region")!.childElementCount).toBe(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("each new picture gets a fresh <img>", async () => {
    const layer = makeLayer();
    layer.play(rose("ayla"));
    await advance(0);
    const before = noticeEl()!.querySelector("img")!;
    layer.play(hat("mert"));
    await advance(0);
    const pills = container.querySelectorAll("[data-gs-notice]");
    const after = pills[pills.length - 1]!.querySelector("img")!;
    expect(after).not.toBe(before);
    expect(before.isConnected).toBe(true);
    expect(after.getAttribute("src")).toContain("hat");
  });

  const pills = () => Array.from(container.querySelectorAll("[data-gs-notice]")) as HTMLElement[];
  const shown = () =>
    pills()
      .filter((p) => p.getAttribute("data-gs-visible") === "true")
      .map((p) => p.querySelector(".gs-notice-name")!.textContent);

  it("two different senders show two lines, the newest below", async () => {
    const layer = makeLayer();
    layer.play(rose("ayla"));
    layer.play(rose("mert"));
    await advance(0);
    expect(shown()).toEqual(["ayla", "mert"]);
    const region = container.querySelector(".gs-notice-region") as HTMLElement;
    expect(Array.from(region.children)).toEqual(pills());
    expect(getComputedStyle(region).pointerEvents).toBe("none");
  });

  it("the same notice updates its own line in place", async () => {
    const layer = makeLayer();
    layer.play(rose("ayla"));
    layer.play(rose("mert"));
    await advance(0);
    const second = pills()[1]!;
    layer.play(rose("mert"));
    await advance(0);
    expect(pills()).toHaveLength(2);
    expect(pills()[1]).toBe(second);
    expect(second.querySelector("[data-gs-combo]")!.textContent).toBe("x2");
  });

  it("a fourth line drops the oldest at once", async () => {
    const layer = makeLayer();
    for (const n of ["a", "b", "c", "d"]) layer.play(rose(n));
    await advance(0);
    expect(shown()).toEqual(["b", "c", "d"]);
    await advance(260);
    expect(pills()).toHaveLength(3);
  });

  it("each line expires on its own timer", async () => {
    const layer = makeLayer();
    layer.play(rose("a"));
    await advance(1000);
    layer.play(rose("b"));
    await advance(1400);
    expect(shown()).toEqual(["b"]);
    await advance(260);
    expect(pills()).toHaveLength(1);
    await advance(1000);
    expect(shown()).toEqual([]);
    await advance(260);
    expect(pills()).toHaveLength(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("cancel hides only the newest line, clear removes all", async () => {
    const layer = makeLayer();
    layer.play(rose("a"));
    const b = layer.play(rose("b"));
    await advance(0);
    layer.cancel(b);
    await advance(0);
    expect(shown()).toEqual(["a"]);
    layer.play(rose("c"));
    await advance(0);
    layer.clear();
    expect(pills()).toHaveLength(0);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("slides in with transform and opacity only", async () => {
    const layer = makeLayer();
    layer.play(rose());
    await advance(0);
    const slide = env.animations.find((a) => (a.el as HTMLElement).hasAttribute("data-gs-notice"))!;
    expect(slide.options.duration).toBe(380);
    expect(Object.keys(slide.frames[0]!).sort()).toEqual(["offset", "opacity", "transform"]);
    expect(slide.frames[0]).toMatchObject({ transform: "translateX(-260px)", opacity: 0 });
  });
});

describe("web GiftEffectLayer: reduced motion", () => {
  it("shows only the notice, at once; the notice keeps its slide (spec 7.5, like React Native)", async () => {
    const layer = makeLayer({ reducedMotion: true });
    layer.play(dragon());
    expect(effects()).toHaveLength(0);
    expect(noticeEl()).not.toBeNull();
    expect(noticeEl()!.classList.contains("gs-big")).toBe(true);
    // The only animation is the notice's slide: translateX -260 to 0 in 380 ms, not a fade.
    expect(env.animations).toHaveLength(1);
    const slide = env.animations[0]!;
    expect((slide.el as HTMLElement).hasAttribute("data-gs-notice")).toBe(true);
    expect(slide.options.duration).toBe(380);
    expect(slide.frames[0]).toMatchObject({ transform: "translateX(-260px)", opacity: 0 });
    expect(slide.frames[slide.frames.length - 1]).toMatchObject({
      transform: "translateX(0px)",
      opacity: 1,
    });
    await advance(2800);
    expect(noticeEl()!.getAttribute("data-gs-visible")).toBe("false");
    const out = env.animations[env.animations.length - 1]!;
    expect(out.options.duration).toBe(260);
    expect(out.frames[out.frames.length - 1]).toMatchObject({ transform: "translateX(-260px)" });
  });

  it("follows prefers-reduced-motion, live", () => {
    const layer = makeLayer({ pictureWaitMs: 300 });
    env.setReducedMotion(true);
    layer.play(hat());
    expect(effects()).toHaveLength(0);
    expect(noticeEl()).not.toBeNull();
    layer.clear();
    env.setReducedMotion(false);
    layer.play(hat());
    expect(effects()).toHaveLength(1);
  });

  it("the option wins over the system setting", () => {
    env.setReducedMotion(true);
    const layer = makeLayer({ reducedMotion: false });
    layer.play(hat());
    expect(effects()).toHaveLength(1);
  });
});

describe("web GiftEffectLayer: no Web Animations API", () => {
  it("shows the notice, fully visible, and no flying effect, even when the option says motion is on", () => {
    delete (Element.prototype as { animate?: unknown }).animate;
    const layer = makeLayer({ reducedMotion: false });
    layer.play(dragon());
    expect(effects()).toHaveLength(0);
    const notice = noticeEl();
    expect(notice).not.toBeNull();
    expect(notice!.style.opacity).toBe("1");
    expect(notice!.style.transform).toBe("translateX(0px)");
    expect(notice!.textContent).toContain("ayla");
    expect(env.animations).toHaveLength(0);
  });
});
