/**
 * Content-Security-Policy friendliness of the web SDK's stylesheet (audit R-11): a constructable
 * stylesheet where the browser has them, else a <style> with the page's nonce.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { acquireStyles, configureStyles, installCss, releaseStyles } from "../src/web/styles";

/** jsdom has no constructable stylesheets: give this document the minimum. */
function withAdoptedSheets() {
  const win = window as unknown as { CSSStyleSheet: unknown };
  const saved = win.CSSStyleSheet;
  const hadAdopted = Object.getOwnPropertyDescriptor(document, "adoptedStyleSheets");
  class FakeSheet {
    css = "";
    replaceSync(css: string) {
      this.css = css;
    }
  }
  win.CSSStyleSheet = FakeSheet;
  (document as unknown as { adoptedStyleSheets: unknown[] }).adoptedStyleSheets = [];
  return () => {
    win.CSSStyleSheet = saved;
    if (hadAdopted) Object.defineProperty(document, "adoptedStyleSheets", hadAdopted);
    else delete (document as unknown as Record<string, unknown>).adoptedStyleSheets;
  };
}

const adopted = () =>
  (document as unknown as { adoptedStyleSheets: { css: string }[] }).adoptedStyleSheets;

beforeEach(() => {
  document.head.innerHTML = "";
  configureStyles({ nonce: undefined, adoptedStyleSheets: true });
});
afterEach(() => {
  while (document.querySelector("style")) document.querySelector("style")!.remove();
  configureStyles({ nonce: undefined, adoptedStyleSheets: true });
});

describe("web styles and Content-Security-Policy", () => {
  it("adopts a constructable stylesheet when the browser has them: no <style> element at all", () => {
    const restore = withAdoptedSheets();
    try {
      acquireStyles(document);
      acquireStyles(document);
      expect(document.head.querySelector("style")).toBeNull();
      expect(adopted()).toHaveLength(1);
      expect(adopted()[0]!.css).toContain(".gs-");
      releaseStyles();
      expect(adopted()).toHaveLength(1);
      releaseStyles();
      expect(adopted()).toHaveLength(0);
    } finally {
      restore();
    }
  });

  it("without constructable stylesheets it adds one <style> carrying the nonce option", () => {
    configureStyles({ nonce: "abc123" });
    acquireStyles(document);
    const style = document.head.querySelector("style[data-giftingstack]")!;
    expect(style.getAttribute("nonce")).toBe("abc123");
    releaseStyles();
    expect(document.head.querySelector("style")).toBeNull();
  });

  it('takes the nonce from <meta name="csp-nonce"> when none is configured', () => {
    document.head.innerHTML = '<meta name="csp-nonce" content="from-meta">';
    acquireStyles(document);
    expect(document.head.querySelector("style")!.getAttribute("nonce")).toBe("from-meta");
    releaseStyles();
  });

  it("adoptedStyleSheets: false forces the <style> element", () => {
    const restore = withAdoptedSheets();
    try {
      configureStyles({ adoptedStyleSheets: false, nonce: "n1" });
      acquireStyles(document);
      expect(adopted()).toHaveLength(0);
      expect(document.head.querySelector("style")!.getAttribute("nonce")).toBe("n1");
      releaseStyles();
    } finally {
      restore();
    }
  });

  it("no nonce, no attribute", () => {
    acquireStyles(document);
    expect(document.head.querySelector("style")!.hasAttribute("nonce")).toBe(false);
    releaseStyles();
  });

  it("installCss reports whether it is still on the page and undoes itself", () => {
    const css = installCss(document, ".x { color: red; }", "data-x");
    expect(css.alive()).toBe(true);
    document.head.innerHTML = "";
    expect(css.alive()).toBe(false);
    css.remove();
  });
});
