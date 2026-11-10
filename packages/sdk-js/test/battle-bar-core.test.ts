import { describe, expect, it } from "vitest";
import {
  type BattleView,
  BATTLE_MIN_SHARE_PCT,
  battleBarModel,
  battleGains,
  battleSideColors,
  battleSidePalette,
  battleView,
  contrastRatio,
  darkTheme,
  defaultTheme,
  formatBattleClock,
  formatBattleScore,
  lightTheme,
} from "../src/core";
import { type Json, fixture } from "./client-runner";

const view = (
  a: number,
  b: number,
  patch: Partial<BattleView> = {},
  remainingMs = 61_000,
): BattleView => {
  const total = a + b;
  const open = remainingMs > 0;
  return {
    round: "r1",
    open,
    remainingMs,
    total,
    sides: [
      { id: "mia", units: a, gifts: 1, share: total ? a / total : 0.5 },
      { id: "theo", units: b, gifts: 1, share: total ? b / total : 0.5 },
    ],
    leader: a === b ? null : a > b ? "mia" : "theo",
    ...patch,
  };
};

describe("battle bar model", () => {
  it("formats scores and the clock", () => {
    expect(formatBattleScore(0)).toBe("0");
    expect(formatBattleScore(9_999)).toBe("9,999");
    expect(formatBattleScore(135_484)).toBe("135K");
    expect(formatBattleScore(135_484, { thousand: "B" })).toBe("135B");
    expect(formatBattleClock(61_000)).toBe("1:01");
    expect(formatBattleClock(59_100)).toBe("1:00");
    expect(formatBattleClock(0)).toBe("0:00");
    expect(formatBattleClock(-5)).toBe("0:00");
  });

  it("is null without a round or with fewer than two sides", () => {
    expect(battleBarModel(null)).toBeNull();
    const one = view(1, 1);
    expect(battleBarModel({ ...one, sides: one.sides.slice(0, 1) })).toBeNull();
  });

  it("splits by share inside the visible band and names the sides", () => {
    const m = battleBarModel(view(300, 100), { nameOf: (id) => id.toUpperCase() })!;
    expect(m.pct).toBe(75);
    expect(m.sides[0]!.name).toBe("MIA");
    expect(m.sides[0]!.leads).toBe(true);
    expect(m.spoken).toBe("MIA 300, THEO 100");
    expect(battleBarModel(view(1, 0))!.pct).toBe(100 - BATTLE_MIN_SHARE_PCT);
    expect(battleBarModel(view(0, 1))!.pct).toBe(BATTLE_MIN_SHARE_PCT);
    expect(battleBarModel(view(0, 0))!.pct).toBe(50);
  });

  it("counts down, turns urgent in the last 10 s and ends with a winner", () => {
    expect(battleBarModel(view(5, 1, {}, 61_000))!.urgent).toBe(false);
    const late = battleBarModel(view(5, 1, {}, 9_200))!;
    expect(late.urgent).toBe(true);
    expect(late.clock).toBe("0:10");
    expect(late.banner).toBe("");
    const end = battleBarModel(view(5, 1, {}, 0))!;
    expect(end).toMatchObject({ final: true, urgent: false, clock: "Final", winner: "mia" });
    expect(end.banner).toBe("mia wins the round");
    expect(end.sides[0]).toMatchObject({ won: true, lost: false });
    expect(end.sides[1]).toMatchObject({ won: false, lost: true });
  });

  it("calls a level round a draw and lets labels translate", () => {
    const draw = battleBarModel(view(4, 4, {}, 0))!;
    expect(draw.winner).toBeNull();
    expect(draw.banner).toBe("Draw: nobody wins this round");
    expect(draw.sides.every((s) => !s.won && !s.lost)).toBe(true);
    const tr = battleBarModel(view(4, 1, {}, 0), {
      labels: { final: "Bitti", wins: "{name} kazandı" },
    })!;
    expect([tr.clock, tr.banner]).toEqual(["Bitti", "mia kazandı"]);
  });

  it("finds which sides gained", () => {
    expect(battleGains(null, [3, 4])).toEqual([false, false]);
    expect(battleGains([3, 4], [3, 9])).toEqual([false, true]);
    expect(battleGains([3, 4], [3, 4])).toEqual([false, false]);
  });

  it("colours the sides from the theme with readable text, or from an override", () => {
    for (const theme of [darkTheme, lightTheme]) {
      const [a, b] = battleSideColors(theme);
      expect(a.color).toBe(theme.accent);
      expect(b.color).toBe(theme.coin);
      expect(contrastRatio(a.color, a.text)).toBeGreaterThanOrEqual(4.5);
      expect(contrastRatio(b.color, b.text)).toBeGreaterThanOrEqual(4.5);
    }
    const [x, y] = battleSideColors(undefined, ["#000000", "#ffffff"]);
    expect([x.text, y.text]).toEqual(["#ffffff", "#000000"]);
    expect(battleSideColors(undefined, ["red", "blue"])[0].text).toBe("#ffffff");
  });
});

/** battle-bar.json (SPEC 18.7): the numbers every platform is held to. */
describe("conformance: battle-bar.json", () => {
  const f = fixture("battle-bar.json");
  const themes = { dark: darkTheme, light: lightTheme, default: defaultTheme } as const;

  for (const c of f.score as Json[])
    it(`score ${c.units} ${JSON.stringify(c.labels ?? {})}`, () => {
      expect(formatBattleScore(c.units, c.labels)).toBe(c.expect);
    });

  for (const c of f.clock as Json[])
    it(`clock ${c.remainingMs}`, () => {
      expect(formatBattleClock(c.remainingMs)).toBe(c.expect);
    });

  for (const c of f.model as Json[])
    it(`model: ${c.name}`, () => {
      const m = battleBarModel(battleView(c.battle, c.serverNow), {
        nameOf: (id) => c.names?.[id] ?? id,
        labels: c.labels,
      });
      if (c.expect === null) return expect(m).toBeNull();
      const { sides, pct, pcts, ...rest } = c.expect;
      expect(m).toMatchObject(rest);
      if (pct !== undefined) expect(Math.abs(m!.pct - pct)).toBeLessThan(1e-6);
      if (pcts !== undefined) {
        expect(m!.pcts).toHaveLength(pcts.length);
        (pcts as number[]).forEach((p, i) => expect(Math.abs(m!.pcts[i]! - p)).toBeLessThan(1e-6));
        expect(m!.pcts.reduce((a, b) => a + b, 0)).toBeCloseTo(100, 6);
      }
      if (sides !== undefined) expect(m!.sides).toHaveLength(sides.length);
      (sides ?? []).forEach((s: Json, i: number) => expect(m!.sides[i]).toMatchObject(s));
    });

  for (const c of f.gains as Json[])
    it(`gains ${JSON.stringify(c.before)} -> ${JSON.stringify(c.after)}`, () => {
      expect(battleGains(c.before, c.after)).toEqual(c.expect);
    });

  for (const c of f.palette as Json[])
    it(`palette: ${c.name}`, () => {
      expect(
        battleSidePalette(themes[c.theme as keyof typeof themes], c.count, c.override),
      ).toEqual(c.expect);
    });

  for (const c of f.colors as Json[])
    it(`colors: ${c.name}`, () => {
      expect(battleSideColors(themes[c.theme as keyof typeof themes], c.override)).toEqual(
        c.expect,
      );
    });
});
