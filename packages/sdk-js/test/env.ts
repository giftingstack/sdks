// react-native-web swaps Animated for an instant mock when NODE_ENV is "test", which would
// make every effect finish at once. These tests check real timing, so ask for the real one.
// Runs before any test file imports react-native.
process.env.NODE_ENV = "development";

// Remote recipes (spec section 13): a web effect layer fetches recipes.json by default. Tests
// never reach the network; a test that wants a response stubs `fetch` itself.
globalThis.fetch = (() => Promise.reject(new Error("network is off in tests"))) as typeof fetch;

// The picture failure memory (spec section 7.6) is module state: a test that fires an image
// `error` must not make the same URL a placeholder in the next test.
import { beforeEach } from "vitest";
import { pictureFailures } from "../src/core/pictures";
beforeEach(() => pictureFailures.clear());
