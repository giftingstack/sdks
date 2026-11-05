import path from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Local playground: the React Native components on react-native-web, with the gift pictures
// served from apps/assets. Not part of the published package.
export default defineConfig({
  root: import.meta.dirname,
  plugins: [react()],
  resolve: { alias: { "react-native": "react-native-web" } },
  publicDir: path.resolve(import.meta.dirname, "../../../apps/assets/public"),
  server: { port: 5800, strictPort: true },
  define: { __DEV__: true, global: "globalThis" },
  optimizeDeps: { esbuildOptions: { define: { global: "globalThis" } } },
});
