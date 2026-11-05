import { defineConfig } from "vitest/config";

// The React Native components run on react-native-web here, in a DOM: that checks the
// logic and the layout. Frame rate and feel on a real phone still need a real phone.
export default defineConfig({
  resolve: { alias: { "react-native": "react-native-web" } },
  test: {
    environment: "jsdom",
    include: ["test/**/*.test.{ts,tsx}"],
    setupFiles: ["./test/env.ts"],
    // Many suites run in parallel on a busy machine: a slow start is not a failure.
    testTimeout: 15_000,
  },
});
