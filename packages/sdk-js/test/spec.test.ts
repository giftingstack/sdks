import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { specData } from "../src/core";

// Vitest runs in packages/sdk-js.
const file = join(process.cwd(), "..", "sdk-spec", "recipes.json");

describe("packages/sdk-spec/recipes.json", () => {
  it("matches the reference code (regenerate: pnpm --filter @giftingstack/sdk-spec build:recipes)", () => {
    const json = JSON.parse(readFileSync(file, "utf8")) as unknown;
    expect(json).toEqual(specData());
  });
});
