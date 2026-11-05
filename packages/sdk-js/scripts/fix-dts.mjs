// tsc writes `.d.ts` files whose relative imports have no extension ("./client", "./core"). A
// consumer on `moduleResolution: node16/nodenext` cannot resolve those, so spell them out:
// "./client" -> "./client.js", "./core" -> "./core/index.js". Run after `tsc -p tsconfig.build.json`.
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "../dist/types");

/** All `.d.ts` files below `dir`. */
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : p.endsWith(".d.ts") ? [p] : [];
  });
}

function resolveSpecifier(file, spec) {
  const base = path.resolve(path.dirname(file), spec);
  if (fs.existsSync(`${base}.d.ts`)) return `${spec}.js`;
  if (fs.existsSync(path.join(base, "index.d.ts"))) return `${spec.replace(/\/$/, "")}/index.js`;
  throw new Error(`${file}: cannot resolve ${spec}`);
}

let changed = 0;
for (const file of walk(root)) {
  const before = fs.readFileSync(file, "utf8");
  const after = before.replace(
    /(\bfrom\s+|\bimport\s*\(\s*|\bimport\s+)(["'])(\.{1,2}\/[^"']*)\2/g,
    (match, lead, quote, spec) =>
      /\.(js|json|css)$/.test(spec)
        ? match
        : `${lead}${quote}${resolveSpecifier(file, spec)}${quote}`,
  );
  if (after !== before) {
    fs.writeFileSync(file, after);
    changed++;
  }
}
process.stdout.write(`fix-dts: ${changed} declaration files updated
`);
