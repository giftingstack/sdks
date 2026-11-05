/**
 * A pretend coin store for the web demo. In a real app `onTopUp` opens YOUR store (in-app
 * purchase, checkout); your server confirms the payment and credits the coins through the API.
 * Not part of the SDK.
 */
export interface CoinPack {
  coins: number;
  price: string;
}

export const COIN_PACKS: readonly CoinPack[] = [
  { coins: 1_000, price: "$0.99" },
  { coins: 5_000, price: "$4.49" },
  { coins: 20_000, price: "$15.99" },
];

const fmt = (n: number): string => n.toLocaleString("en-US");

const CSS = `
.demo-store { position: absolute; inset: 0; z-index: 2000; display: flex; align-items: flex-end;
  background: rgba(0, 0, 0, 0.55); font-family: system-ui, sans-serif; }
.demo-store-card { box-sizing: border-box; width: 100%; padding: 18px 16px 22px; border-radius: 24px 24px 0 0;
  background: #1e1e2e; color: #f4f2ff; display: flex; flex-direction: column; gap: 10px; }
.demo-store-card h2 { margin: 0 0 4px; font-size: 16px; }
.demo-store-card p { margin: 0 0 6px; font-size: 12px; color: #a3a1c2; }
.demo-store-pack { display: flex; justify-content: space-between; align-items: center; padding: 14px 16px;
  border: 1px solid #2d2d44; border-radius: 14px; background: #14141f; color: inherit; font: inherit;
  font-size: 15px; font-weight: 700; cursor: pointer; }
.demo-store-pack span:last-child { color: #ffd27a; }
.demo-store-close { padding: 10px; border: 0; background: none; color: #a3a1c2; font: inherit; cursor: pointer; }
`;

/**
 * Opens the store over `parent` (a positioned element). `onBuy` gets the chosen number of coins.
 * Closes on a pack, on "Not now", on Escape and on a click outside the card. Returns `close`.
 */
export function openCoinStore(
  parent: HTMLElement,
  onBuy: (coins: number) => void,
  packs: readonly CoinPack[] = COIN_PACKS,
): () => void {
  const doc = parent.ownerDocument;
  if (!doc.querySelector("style[data-demo-store]")) {
    const style = doc.createElement("style");
    style.setAttribute("data-demo-store", "");
    style.textContent = CSS;
    doc.head.appendChild(style);
  }
  const before = doc.activeElement as HTMLElement | null;
  const overlay = doc.createElement("div");
  overlay.className = "demo-store";
  overlay.setAttribute("data-demo-store", "");
  const card = doc.createElement("div");
  card.className = "demo-store-card";
  card.setAttribute("role", "dialog");
  card.setAttribute("aria-modal", "true");
  card.setAttribute("aria-label", "Coin store");
  card.innerHTML = "<h2>Get coins</h2><p>Demo store: nothing is charged.</p>";
  const close = (): void => {
    overlay.remove();
    doc.removeEventListener("keydown", onKey);
    before?.focus?.();
  };
  const onKey = (e: KeyboardEvent): void => {
    if (e.key === "Escape") close();
  };
  for (const pack of packs) {
    const b = doc.createElement("button");
    b.type = "button";
    b.className = "demo-store-pack";
    b.setAttribute("data-coins", String(pack.coins));
    b.innerHTML = `<span>+${fmt(pack.coins)} coins</span><span></span>`;
    (b.lastChild as HTMLElement).textContent = pack.price;
    b.addEventListener("click", () => {
      close();
      onBuy(pack.coins);
    });
    card.appendChild(b);
  }
  const later = doc.createElement("button");
  later.type = "button";
  later.className = "demo-store-close";
  later.textContent = "Not now";
  later.addEventListener("click", close);
  card.appendChild(later);
  overlay.appendChild(card);
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });
  doc.addEventListener("keydown", onKey);
  parent.appendChild(overlay);
  (card.querySelector("button") as HTMLElement | null)?.focus();
  return close;
}
