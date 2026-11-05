/** The web demo's pretend coin store (demo/coinStore.ts): not SDK code, but the demo relies on it. */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { COIN_PACKS, openCoinStore } from "../demo/coinStore";

let parent: HTMLElement;
beforeEach(() => {
  parent = document.createElement("div");
  document.body.appendChild(parent);
});
afterEach(() => parent.remove());

const store = () => parent.querySelector("[data-demo-store]");

describe("demo coin store", () => {
  it("offers the packs as a modal dialog and credits the chosen one", () => {
    const bought: number[] = [];
    openCoinStore(parent, (coins) => bought.push(coins));
    const dialog = parent.querySelector('[role="dialog"]')!;
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    const packs = [...parent.querySelectorAll<HTMLButtonElement>("[data-coins]")];
    expect(packs.map((b) => Number(b.dataset.coins))).toEqual(COIN_PACKS.map((p) => p.coins));
    expect(packs[1]!.textContent).toContain("+5,000 coins");
    expect(document.activeElement).toBe(packs[0]);
    packs[1]!.click();
    expect(bought).toEqual([5000]);
    expect(store()).toBeNull();
  });

  it("closes without buying on Not now, Escape or a click outside", () => {
    const bought: number[] = [];
    openCoinStore(parent, (c) => bought.push(c));
    (parent.querySelector(".demo-store-close") as HTMLElement).click();
    expect(store()).toBeNull();
    openCoinStore(parent, (c) => bought.push(c));
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    expect(store()).toBeNull();
    openCoinStore(parent, (c) => bought.push(c));
    (store() as HTMLElement).click();
    expect(store()).toBeNull();
    expect(bought).toEqual([]);
  });
});
