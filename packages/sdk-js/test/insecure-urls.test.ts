/**
 * Plain-text base URLs (SPEC 3.1): `http://` and `ws://` only to loopback hosts or with
 * `allowInsecure`, for the client and for rooms; and the idempotency key fallback (SPEC 3.3).
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  RoomClient,
  assertSecureUrl,
  createGiftingClient,
  isLoopbackHost,
  newIdempotencyKey,
  urlHost,
} from "../src/core";

const getToken = async () => "tok";
const never = () => {
  throw new Error("no socket in this test");
};

describe("urlHost", () => {
  it("reads the host: no userinfo, port or brackets, lower case", () => {
    expect(urlHost("http://LocalHost:8787/x")).toBe("localhost");
    expect(urlHost("ws://user:pw@10.0.2.2:8788")).toBe("10.0.2.2");
    expect(urlHost("http://[::1]:8787")).toBe("::1");
    expect(urlHost("https://api.giftingstack.com")).toBe("api.giftingstack.com");
    expect(urlHost("api.giftingstack.com")).toBeNull();
  });

  it("knows the four loopback hosts and nothing else", () => {
    for (const h of ["localhost", "127.0.0.1", "::1", "10.0.2.2", "LOCALHOST"]) {
      expect(isLoopbackHost(h), h).toBe(true);
    }
    for (const h of ["127.0.0.2", "192.168.1.5", "localhost.evil.com", "example.com", ""]) {
      expect(isLoopbackHost(h), h).toBe(false);
    }
  });
});

describe("createGiftingClient base URL", () => {
  it("accepts https, and http to loopback hosts", () => {
    for (const baseUrl of [
      undefined,
      "https://api.example.com",
      "HTTPS://api.example.com/",
      "http://localhost:8787",
      "http://127.0.0.1:8787/proxy/",
      "http://[::1]:8787",
      "http://10.0.2.2:8787",
    ]) {
      expect(() => createGiftingClient({ getToken, baseUrl }), String(baseUrl)).not.toThrow();
    }
  });

  it("refuses http to any other host, naming the option and never the userinfo", () => {
    for (const baseUrl of [
      "http://api.example.com",
      "HTTP://api.example.com",
      "http://192.168.1.20:8787",
      "http://localhost.evil.com",
    ]) {
      expect(() => createGiftingClient({ getToken, baseUrl }), baseUrl).toThrow(/allowInsecure/);
    }
    expect(() =>
      createGiftingClient({ getToken, baseUrl: "http://me:secret@api.example.com" }),
    ).toThrow(/^((?!secret).)*$/s);
  });

  it("allowInsecure: true lets a plain http URL through", () => {
    expect(() =>
      createGiftingClient({ getToken, baseUrl: "http://staging.example.com", allowInsecure: true }),
    ).not.toThrow();
  });

  it("assertSecureUrl lets https and wss pass whatever the flag", () => {
    expect(() => assertSecureUrl("wss://rt.example.com", false, "url")).not.toThrow();
    expect(() => assertSecureUrl("https://x.example.com", undefined, "url")).not.toThrow();
  });
});

describe("RoomClient url", () => {
  const make = (url?: string, allowInsecure?: boolean) =>
    new RoomClient({ room: "live_1", getToken, socket: never, url, allowInsecure });

  it("accepts the default, wss and ws to loopback hosts", () => {
    for (const url of [
      undefined,
      "wss://rt.example.com",
      "ws://localhost:8788",
      "ws://127.0.0.1:8788/",
      "ws://[::1]:8788",
      "ws://10.0.2.2:8788",
    ]) {
      expect(() => make(url), String(url)).not.toThrow();
    }
  });

  it("refuses ws to any other host unless allowInsecure", () => {
    expect(() => make("ws://rt.example.com")).toThrow(/allowInsecure/);
    expect(() => make("ws://192.168.1.20:8788")).toThrow(/allowInsecure/);
    expect(() => make("ws://rt.example.com", true)).not.toThrow();
  });

  it("setOptions checks the new url too", () => {
    const room = make();
    expect(() =>
      room.setOptions({ room: "live_1", getToken, socket: never, url: "ws://rt.example.com" }),
    ).toThrow(/allowInsecure/);
  });
});

describe("newIdempotencyKey", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("uses crypto.randomUUID when there is one", () => {
    vi.stubGlobal("crypto", { randomUUID: () => "uuid-from-crypto" });
    expect(newIdempotencyKey()).toBe("uuid-from-crypto");
  });

  it("without randomUUID it draws from crypto.getRandomValues, not Math.random", () => {
    const math = vi.spyOn(Math, "random");
    vi.stubGlobal("crypto", {
      getRandomValues: (a: Uint32Array) => {
        a.set([0x00000001, 0xdeadbeef, 0xffffffff, 0x10]);
        return a;
      },
    });
    expect(newIdempotencyKey()).toBe("00000001-deadbeef-ffffffff-00000010");
    expect(math).not.toHaveBeenCalled();
    math.mockRestore();
  });

  it("without any crypto it falls back to four groups of 8 hex digits from Math.random", () => {
    vi.stubGlobal("crypto", undefined);
    expect(newIdempotencyKey()).toMatch(/^[0-9a-f]{8}(-[0-9a-f]{8}){3}$/);
  });

  it("a getRandomValues that throws falls back too", () => {
    vi.stubGlobal("crypto", {
      getRandomValues: () => {
        throw new Error("no entropy");
      },
    });
    expect(newIdempotencyKey()).toMatch(/^[0-9a-f]{8}(-[0-9a-f]{8}){3}$/);
  });
});
