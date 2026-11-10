import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { type BattleView, battleView } from "../src/core";
import { BattleBar, type BattleBarProps } from "../src/react-native";

const at = (a: number, b: number, now = 1_000, ends = 60_000): BattleView =>
  battleView(
    {
      round: "r1",
      started: 0,
      ends,
      scores: [
        { id: "mia", units: a, gifts: 1 },
        { id: "theo", units: b, gifts: 1 },
      ],
    },
    now,
  );

const bar = (props: Partial<BattleBarProps> & { view: BattleView | null }) => (
  <BattleBar reducedMotion {...props} />
);
const text = (id: string) => screen.getByTestId(id).textContent;

describe("React Native BattleBar", () => {
  afterEach(cleanup);

  it("draws three sides as cells with their scores and one spoken sentence", () => {
    const view = battleView(
      {
        round: "r3",
        started: 0,
        ends: 60_000,
        scores: [
          { id: "mia", units: 300, gifts: 1 },
          { id: "theo", units: 100, gifts: 1 },
          { id: "noor", units: 100, gifts: 1 },
        ],
      },
      1_000,
    );
    render(bar({ view, users: { noor: { name: "Noor" } } }));
    expect(text("battle-score-0")).toBe("300");
    expect(text("battle-score-1")).toBe("100");
    expect(text("battle-score-2")).toBe("100");
    expect(screen.getByText("Noor")).toBeTruthy();
    expect(screen.getByTestId("battle-bar").getAttribute("aria-label")).toBe(
      "mia 300, theo 100, Noor 100",
    );
    expect(text("battle-clock")).toBe("0:59");
  });

  it("draws nothing without a round", () => {
    render(bar({ view: null }));
    expect(screen.queryByTestId("battle-bar")).toBeNull();
  });

  it("shows names, scores and the clock, and describes the round to a screen reader", () => {
    render(
      bar({ view: at(1_800, 640), users: { mia: { name: "Mia" }, theo: { name: "Theo M." } } }),
    );
    expect(text("battle-score-0")).toBe("1,800");
    expect(text("battle-score-1")).toBe("640");
    expect(text("battle-clock")).toBe("0:59");
    expect(screen.getByText("Mia")).toBeTruthy();
    expect(screen.getByText("Theo M.")).toBeTruthy();
    expect(screen.getByTestId("battle-bar").getAttribute("aria-label")).toBe(
      "Mia 1,800, Theo M. 640",
    );
    expect(screen.queryByTestId("battle-banner")).toBeNull();
  });

  it("falls back to the id and to an initial avatar; a picture replaces the initial", () => {
    render(
      bar({ view: at(1, 2), users: { mia: { name: "Mia", avatarUrl: "https://img.test/m.png" } } }),
    );
    expect(screen.getAllByTestId("battle-avatar-image")).toHaveLength(1);
    expect(screen.getAllByTestId("battle-avatar")).toHaveLength(1);
    expect(screen.getByText("theo")).toBeTruthy();
    expect(screen.getByText("T")).toBeTruthy();
  });

  it("follows new frames and ends with a winner banner", () => {
    const { rerender } = render(bar({ view: at(10, 10) }));
    rerender(bar({ view: at(10, 500) }));
    expect(text("battle-score-1")).toBe("500");
    rerender(bar({ view: at(10, 500, 61_000) }));
    expect(text("battle-clock")).toBe("Final");
    expect(text("battle-banner")).toBe("theo wins the round");
    expect(screen.getByTestId("battle-bar").getAttribute("aria-label")).toBe(
      "mia 10, theo 500. theo wins the round",
    );
    rerender(bar({ view: at(7, 7, 61_000) }));
    expect(text("battle-banner")).toBe("Draw: nobody wins this round");
  });

  it("shortens big scores and translates through labels", () => {
    render(bar({ view: at(135_484, 20_000), labels: { thousand: "k" } }));
    expect(text("battle-score-0")).toBe("135k");
    expect(text("battle-score-1")).toBe("20k");
  });

  it("counts up with motion on and arrives at the score", async () => {
    // Date too, because the Animated library times itself with Date.now().
    vi.useFakeTimers({
      toFake: [
        "setTimeout",
        "clearTimeout",
        "requestAnimationFrame",
        "cancelAnimationFrame",
        "performance",
        "Date",
      ],
    });
    try {
      const { rerender } = render(<BattleBar view={at(0, 0)} reducedMotion={false} />);
      rerender(<BattleBar view={at(900, 0)} reducedMotion={false} />);
      await act(async () => {
        await vi.advanceTimersByTimeAsync(200);
      });
      const mid = Number(text("battle-score-0")!.replace(",", ""));
      expect(mid).toBeGreaterThan(0);
      expect(mid).toBeLessThan(900);
      await act(async () => {
        await vi.advanceTimersByTimeAsync(900);
      });
      expect(text("battle-score-0")).toBe("900");
    } finally {
      vi.useRealTimers();
    }
  });
});
