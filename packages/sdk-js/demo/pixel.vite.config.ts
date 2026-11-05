import path from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const here = import.meta.dirname;
const repo = path.resolve(here, "../../..");

/** Metro's require("./x.webp") becomes an import, so the generated gift list and the logo load in Vite. */
function metroRequire() {
  return {
    name: "metro-require",
    enforce: "pre" as const,
    transform(code: string, id: string) {
      if (!id.endsWith("gifts.generated.ts") && !id.endsWith("brand.ts")) return null;
      const imports: string[] = [];
      const body = code.replace(/require\("([^"]+)"\)/g, (_m, p: string) => {
        imports.push(`import img${imports.length} from "${p}";`);
        return `img${imports.length - 1}`;
      });
      return imports.join("\n") + "\n" + body;
    },
  };
}

// Runs examples/expo-demo on react-native-web (no Expo needed), for a quick browser check.
export default defineConfig({
  root: here,
  plugins: [react(), metroRequire()],
  resolve: {
    alias: [
      {
        find: "react-native-safe-area-context",
        replacement: path.resolve(here, "stubs/safe-area.tsx"),
      },
      { find: "expo-status-bar", replacement: path.resolve(here, "stubs/status-bar.tsx") },
      { find: "react-native", replacement: "react-native-web" },
      {
        find: /^@giftingstack\/sdk\/react-native$/,
        replacement: path.resolve(here, "../src/react-native/index.ts"),
      },
      { find: /^@giftingstack\/sdk$/, replacement: path.resolve(here, "../src/core/index.ts") },
    ],
    dedupe: ["react", "react-dom", "react-native-web"],
  },
  publicDir: path.resolve(repo, "apps/assets/public"),
  server: { port: 5801, strictPort: true, fs: { allow: [repo] } },
  define: { __DEV__: true, global: "globalThis" },
  optimizeDeps: { esbuildOptions: { define: { global: "globalThis" } } },
});
