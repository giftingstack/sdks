// Writes the hosted copies of the recipes (SPEC.md section 13.6) into packages/sdk-spec/dist/:
// `recipes.json` (latest) and `recipes.<specVersion>.json` (pinned). dist/ is gitignored.
// Run: pnpm --filter @giftingstack/sdk-spec build:remote [path/to/tuned.json]
// Without an argument the embedded recipes.json is copied. This script never uploads anything:
// hosting the files on assets.giftingstack.com is a separate, manual deploy step.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const sdk = new URL("../../sdk-js/", import.meta.url);
const require = createRequire(new URL("package.json", sdk));
const { runnerImport } = await import(pathToFileURL(require.resolve("vite")).href);
const { module: core } = await runnerImport(fileURLToPath(new URL("src/core/index.ts", sdk)), {
  configFile: false,
  logLevel: "silent",
});

const source = process.argv[2]
  ? resolve(process.argv[2])
  : fileURLToPath(new URL("../recipes.json", import.meta.url));
const doc = JSON.parse(readFileSync(source, "utf8"));

// Refuse what the SDKs would ignore or change: the hosted file must mean exactly what it says.
const parsed = core.parseRemoteRecipes(doc);
if (!parsed) {
  console.error(`${source}: SDK ${core.SPEC_VERSION} would ignore this document (specVersion).`);
  process.exit(1);
}
const problems = [];
const compare = (path, given, used) => {
  if (given === undefined) return;
  if (JSON.stringify(given) !== JSON.stringify(used)) {
    problems.push(`${path}: ${JSON.stringify(given)} would be used as ${JSON.stringify(used)}`);
  }
};
compare("comboWindowMs", doc.comboWindowMs, parsed.comboWindowMs);
for (const k of ["mediumFrom", "largeFrom"]) {
  compare(`thresholds.${k}`, doc.thresholds?.[k], parsed.thresholds[k]);
}
for (const q of ["high", "low"]) {
  for (const t of ["small", "medium", "large"]) {
    const given = doc.recipes?.[q]?.[t] ?? {};
    for (const [k, v] of Object.entries(given)) {
      if (k !== "tier") compare(`recipes.${q}.${t}.${k}`, v, parsed.recipes[q][t][k]);
    }
  }
}
if (problems.length) {
  console.error(
    `${source}: values outside the limits or of the wrong type:\n  ${problems.join("\n  ")}`,
  );
  process.exit(1);
}

const dist = new URL("../dist/", import.meta.url);
mkdirSync(dist, { recursive: true });
const text = JSON.stringify(doc, null, 2) + "\n";
for (const name of ["recipes.json", `recipes.${doc.specVersion}.json`]) {
  const out = new URL(name, dist);
  writeFileSync(out, text);
  console.log(`wrote ${fileURLToPath(out)}`);
}
console.log("Not uploaded. Hosting on assets.giftingstack.com is a separate deploy step.");
