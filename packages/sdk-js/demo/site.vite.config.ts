import fs from "node:fs";
import path from "node:path";
import { defineConfig, mergeConfig } from "vite";
import { demoHeadersFile } from "./headers";
import pixel from "./pixel.vite.config";

const here = import.meta.dirname;
const repo = path.resolve(here, "../../..");
const out = path.resolve(repo, "apps/demo/dist");
// Only what the demo fetches itself: the gift list and a redirect. The gift pictures come
// from assets.giftingstack.com, so the 600 picture files are not copied.
const pub = path.resolve(repo, "apps/demo/.public");

/** Builds the two demo pages (web.html: the web SDK, react-native.html: the Expo app on react-native-web). */
export default mergeConfig(
  pixel,
  defineConfig({
    publicDir: pub,
    plugins: [
      {
        name: "demo-public",
        buildStart() {
          fs.rmSync(pub, { recursive: true, force: true });
          fs.mkdirSync(pub, { recursive: true });
          fs.copyFileSync(
            path.resolve(repo, "apps/assets/public/library.json"),
            path.join(pub, "library.json"),
          );
          // /pixel.html is the old name of the Expo page (the demo used to be called Pixel).
          fs.writeFileSync(
            path.join(pub, "_redirects"),
            "/ /web.html 302\n/pixel.html /react-native.html 301\n",
          );
          // Security headers (the site frames the demo, nobody else may): see demo/headers.ts.
          fs.writeFileSync(path.join(pub, "_headers"), demoHeadersFile());
        },
      },
    ],
    build: {
      outDir: out,
      emptyOutDir: true,
      rollupOptions: {
        input: {
          web: path.resolve(here, "web.html"),
          "react-native": path.resolve(here, "react-native.html"),
        },
      },
    },
    define: { __DEV__: false },
  }),
);
