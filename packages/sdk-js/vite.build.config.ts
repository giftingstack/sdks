import path from "node:path";
import { defineConfig } from "vite";

// The published build: ESM only, one file per entry (`.`, `/web`, `/react-native`, `/elements`)
// plus the chunks they share. React and React Native stay external: they are the app's own.
// Types are made by tsc (tsconfig.build.json) and fixed up by scripts/fix-dts.mjs.
const src = path.resolve(import.meta.dirname, "src");

export default defineConfig({
  build: {
    outDir: "dist",
    emptyOutDir: false, // the `build` script cleans dist first, so the types survive
    sourcemap: true,
    minify: false, // readable stack traces; the apps minify their own bundle
    target: "es2022",
    lib: {
      entry: {
        index: path.join(src, "core/index.ts"),
        web: path.join(src, "web/index.ts"),
        "react-native": path.join(src, "react-native/index.ts"),
        elements: path.join(src, "web/elements-register.ts"),
      },
      formats: ["es"],
    },
    rollupOptions: {
      external: ["react", "react/jsx-runtime", "react-native"],
      output: { entryFileNames: "[name].js", chunkFileNames: "chunks/[name]-[hash].js" },
    },
  },
});
