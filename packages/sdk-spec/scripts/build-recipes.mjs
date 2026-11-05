// Writes recipes.json from the reference code (packages/sdk-js/src/core, `specData()`).
// Run: pnpm --filter @giftingstack/sdk-spec build:recipes
// packages/sdk-js/test/spec.test.ts fails when the file and the code disagree.
import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const sdk = new URL("../../sdk-js/", import.meta.url);
// Vite is a dev dependency of the reference SDK; it loads the TypeScript source directly.
const require = createRequire(new URL("package.json", sdk));
const { runnerImport } = await import(pathToFileURL(require.resolve("vite")).href);
const { module: core } = await runnerImport(fileURLToPath(new URL("src/core/index.ts", sdk)), {
  configFile: false,
  logLevel: "silent",
});

const out = new URL("../recipes.json", import.meta.url);
writeFileSync(out, JSON.stringify(core.specData(), null, 2) + "\n");
console.log(`wrote ${fileURLToPath(out)}`);
