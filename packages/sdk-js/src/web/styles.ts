/**
 * The only CSS the web layer needs, injected once into the page (spec 7.1: no external file).
 * Every selector starts with `.gs-`. The colours come from CSS variables with the default
 * theme as fallback, so a `theme` option or your own CSS can override them.
 */
export const CSS: string = `
.gs-layer, .gs-tray, .gs-wall, .gs-away, .gs-board, .gs-battle, .gs-gift-button {
  --gs-background: #14141f; --gs-surface: #1e1e2e; --gs-border: #2d2d44; --gs-text: #f4f2ff;
  --gs-muted: #a3a1c2; --gs-accent: #8b7bff; --gs-accent-text: #ffffff; --gs-coin: #ffd27a;
  --gs-danger: #ff8fa3; --gs-notice-background: rgba(123, 107, 255, 0.92);
  --gs-notice-text: #ffffff; --gs-notice-big-background: #e8a93a; --gs-notice-big-text: #2a1600;
  --gs-glow: #ffdc8c; --gs-coin-text: #2a1600; --gs-selected: #221f45; --gs-combo-text: #fff3c4;
  box-sizing: border-box;
}
.gs-layer *, .gs-tray *, .gs-wall *, .gs-away *, .gs-board *, .gs-battle * { box-sizing: border-box; }
.gs-layer {
  position: absolute; inset: 0; overflow: hidden; pointer-events: none; z-index: 1000;
  font-family: var(--gs-font, inherit);
}
.gs-effect, .gs-effects { position: absolute; inset: 0; pointer-events: none; }
.gs-abs { position: absolute; left: 0; top: 0; pointer-events: none; }
.gs-dim { inset: 0; background: #000; opacity: 0; }
.gs-rays { overflow: visible; opacity: 0; }
.gs-spark, .gs-coin-rain { border-radius: 50%; opacity: 0; }
.gs-picture { width: 100px; height: 100px; opacity: 0; will-change: transform, opacity; }
.gs-picture img { display: block; width: 100%; height: 100%; object-fit: contain; }
/* A page-wide rule such as "img { position: absolute }" or "#player img { transform: ... }" must
   not move or squeeze the pictures of the tray and the effects: these few properties are fixed. */
.gs-layer img, .gs-tray img:not(.gs-warmup), .gs-wall img, .gs-away img, .gs-board img {
  position: static !important; transform: none !important; max-width: none !important;
  margin: 0 !important; left: auto !important; top: auto !important; float: none !important;
}
.gs-picture-fallback { width: 100%; height: 100%; border-radius: 50%; background: var(--gs-coin); }
.gs-glow { opacity: 0; }
.gs-glow > div { position: absolute; border-radius: 50%; background: var(--gs-glow); opacity: 0.16; }

.gs-notice-region {
  position: absolute; left: 12px; max-width: 92%; pointer-events: none;
  display: flex; flex-direction: column; align-items: flex-start; gap: 6px;
}
.gs-notice {
  display: flex; align-items: center; gap: 8px; padding: 5px 16px 5px 5px; border-radius: 999px;
  background: var(--gs-notice-background); color: var(--gs-notice-text);
}
.gs-notice.gs-big {
  padding-top: 7px; padding-bottom: 7px; background: var(--gs-notice-big-background);
  color: var(--gs-notice-big-text);
}
.gs-avatar {
  flex: none; display: flex; align-items: center; justify-content: center; width: 28px;
  height: 28px; border-radius: 50%; background: var(--gs-accent); color: var(--gs-accent-text);
  font-weight: 700; font-size: 12px;
}
.gs-big .gs-avatar { width: 34px; height: 34px; }
.gs-notice-text { display: flex; flex-direction: column; min-width: 0; }
.gs-notice-name, .gs-notice-what {
  font-size: 12.5px; line-height: 15px; white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis;
}
.gs-notice-name { font-weight: 700; }
.gs-notice-what { opacity: 0.92; }
.gs-notice-img { flex: none; width: 36px; height: 36px; object-fit: contain; }
.gs-big .gs-notice-img { width: 46px; height: 46px; }
.gs-combo {
  flex: none; display: inline-block; min-width: 40px; text-align: center; font-size: 28px;
  line-height: 1.15; font-weight: 800; font-style: italic; color: var(--gs-combo-text);
}
.gs-big .gs-combo { color: var(--gs-notice-big-text); }

.gs-tray {
  position: relative; display: flex; flex-direction: column; gap: 12px; padding: 14px;
  border: 1px solid var(--gs-border); border-bottom: 0; border-radius: 24px 24px 0 0;
  background: var(--gs-surface); color: var(--gs-text);
  font-family: var(--gs-font, system-ui, sans-serif);
}
.gs-warmup {
  position: absolute !important; left: -200px !important; top: 0; width: 100px; height: 100px;
  opacity: 0; object-fit: contain; pointer-events: none;
}
.gs-head { display: flex; align-items: center; gap: 10px; }
.gs-title {
  flex: 1; min-width: 0; margin: 0; font-size: 15px; font-weight: 700; color: var(--gs-text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.gs-test-badge {
  flex: none; padding: 2px 8px; border-radius: 6px; background: #f5a524; color: #1a1300;
  font-size: 11px; font-weight: 800; letter-spacing: 0.04em; text-transform: uppercase;
}
.gs-balance {
  display: flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px;
  background: var(--gs-background); font-size: 13px; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.gs-dot { flex: none; width: 14px; height: 14px; border-radius: 50%; background: var(--gs-coin); }
.gs-dot-small { width: 9px; height: 9px; }
.gs-sr {
  position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0; overflow: hidden;
  clip: rect(0 0 0 0); white-space: nowrap; border: 0;
}
:where(.gs-tray button) {
  font: inherit; color: inherit; cursor: pointer; -webkit-tap-highlight-color: transparent;
  touch-action: manipulation;
}
.gs-tray button:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-topup {
  padding: 4px 2px; border: 0; background: none; font-size: 13px; font-weight: 700;
  color: var(--gs-coin);
}
.gs-grid { display: grid; overflow-y: auto; scrollbar-width: thin; scrollbar-color: var(--gs-border) transparent; grid-template-columns: repeat(var(--gs-columns, 4), 1fr); }
.gs-cell {
  display: flex; flex-direction: column; align-items: center; gap: 2px; margin: 4px;
  padding: 8px 0; border: 1.5px solid transparent; border-radius: 14px;
  background: var(--gs-background); transition: transform 90ms;
}
.gs-cell:active { transform: scale(0.96); }
.gs-cell[aria-checked="true"] { background: var(--gs-selected); border-color: var(--gs-accent); }
.gs-icon { width: var(--gs-icon-size, min(72px, 78%)); aspect-ratio: 1 / 1; height: auto; object-fit: contain; }
.gs-icon-empty { border-radius: 12px; background: var(--gs-border); }
.gs-price {
  display: flex; align-items: center; gap: 3px; font-size: 11.5px; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.gs-send {
  width: 100%; padding: 13px; border: 0; border-radius: 999px; font-size: 15px; font-weight: 700;
  background: var(--gs-accent); color: var(--gs-accent-text);
}
.gs-send.gs-coin-state { background: var(--gs-coin); color: var(--gs-coin-text); }
.gs-send[aria-disabled="true"] { background: var(--gs-border); cursor: default; }
.gs-send:not([aria-disabled="true"]):active { transform: scale(0.98); }

.gs-tray.gs-sheet {
  position: absolute; left: 0; right: 0; bottom: 0; z-index: 1; gap: 0; padding: 0; border: 0;
  border-radius: 0; background: transparent; pointer-events: none;
}
.gs-sheet-body {
  position: relative; z-index: 0; flex: 1; min-height: 0; display: flex; flex-direction: column;
  gap: 12px; padding: 0 14px; border: 1px solid var(--gs-border); border-bottom: 0;
  border-radius: 24px 24px 0 0; background: var(--gs-surface); pointer-events: auto;
  will-change: transform; transition: transform 280ms cubic-bezier(0.22, 1, 0.36, 1);
}
.gs-handle {
  flex: none; display: flex; justify-content: center; margin: 0 -14px; padding: 8px 0 4px;
  border: 0; background: none; cursor: grab; touch-action: none;
}
.gs-dragging .gs-handle { cursor: grabbing; }
.gs-tray .gs-handle:focus-visible { outline: none; }
.gs-handle:focus-visible .gs-handle-pill { outline: 2px solid var(--gs-accent); outline-offset: 3px; opacity: 1; }
.gs-handle-pill { width: 36px; height: 5px; border-radius: 3px; background: var(--gs-muted); opacity: 0.7; }
.gs-sheet .gs-head { touch-action: none; user-select: none; -webkit-user-select: none; }
.gs-sheet .gs-grid { flex: 1; min-height: 0; overflow-y: hidden; overscroll-behavior: contain; align-content: start; }
.gs-sheet[data-gs-grid-scroll="true"] .gs-grid { overflow-y: auto; }
.gs-dragging .gs-grid { user-select: none; -webkit-user-select: none; }
.gs-footer {
  position: relative; z-index: 1; flex: none; display: flex; align-items: center; gap: 10px;
  padding: 10px 14px calc(14px + env(safe-area-inset-bottom, 0px)); border: 1px solid var(--gs-border);
  border-top: 0; border-bottom: 0;
  background: var(--gs-surface); pointer-events: auto;
}
.gs-footer .gs-send { flex: 1; width: auto; min-width: 0; }
/* The footer stays put (spec 9.1) and takes no drag, but a finger on it must not scroll or pull the
   page behind the sheet either (the header does the same). Taps still work. */
.gs-sheet .gs-footer { touch-action: none; user-select: none; -webkit-user-select: none; }
.gs-picked { flex: none; display: flex; align-items: center; gap: 8px; max-width: 45%; min-width: 0; }
.gs-picked-icon { flex: none; width: 36px; height: 36px; object-fit: contain; }
.gs-picked-text { display: flex; flex-direction: column; min-width: 0; }
.gs-picked-name {
  font-size: 12.5px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
@media (prefers-reduced-motion: reduce) { .gs-sheet-body { transition: none; } }
/* Entrance (SPEC 9.4, same values as Flutter and iOS): fades in over 200 ms while rising from 3 % of its
   height below its place over 220 ms. Set once the sheet is placed, removed when it has played. */
@keyframes gs-sheet-fade { from { opacity: 0; } to { opacity: 1; } }
@keyframes gs-sheet-rise { from { transform: translateY(3%); } to { transform: none; } }
.gs-tray.gs-sheet[data-gs-entering] {
  animation: gs-sheet-fade 200ms ease-out both, gs-sheet-rise 220ms cubic-bezier(0.215, 0.61, 0.355, 1) both;
}
@media (prefers-reduced-motion: reduce) { .gs-tray.gs-sheet[data-gs-entering] { animation: none; } }

.gs-scrim { position: absolute; inset: 0; z-index: 1; background: #000; opacity: 0; pointer-events: none; transition: opacity 200ms ease-out; }
.gs-scrim[data-gs-visible] { opacity: 0.4; }
.gs-scrim[data-gs-active] { pointer-events: auto; }
@media (prefers-reduced-motion: reduce) { .gs-scrim { transition: none; } }
.gs-tray[hidden], .gs-tray [hidden] { display: none !important; }
.gs-tray.gs-popover, .gs-tray.gs-inline { gap: 0; padding: 0; overflow: hidden; }
.gs-tray.gs-popover {
  position: fixed; left: 0; top: 0; z-index: 999; width: 380px; max-width: calc(100vw - 16px);
  max-height: 70vh; border: 1px solid var(--gs-border); border-radius: 16px;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35), 0 2px 8px rgba(0, 0, 0, 0.2);
}
.gs-tray.gs-inline { height: 100%; min-height: 0; border: 1px solid var(--gs-border); border-radius: 16px; }
.gs-body { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 10px; padding: 14px 14px 0; }
.gs-popover .gs-grid, .gs-inline .gs-grid {
  flex: 1; min-height: 0; overflow-y: auto; overscroll-behavior: contain; align-content: start;
  margin: 0 -4px;
}
.gs-inline .gs-grid[data-gs-fill] { grid-template-columns: repeat(auto-fill, minmax(84px, 1fr)); }
.gs-tray[data-gs-compact] .gs-grid { display: none; }
.gs-more {
  flex: none; height: 36px; padding: 0 10px; border: 1px solid var(--gs-border); border-radius: 10px;
  background: transparent; color: var(--gs-text); font: inherit; font-size: 12px; font-weight: 700;
  cursor: pointer;
}
.gs-more:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-popover .gs-footer, .gs-inline .gs-footer {
  border: 0; border-top: 1px solid var(--gs-border); padding: 10px 14px 14px;
}
.gs-battle { font-family: var(--gs-font, system-ui, sans-serif); color: var(--gs-text); }
.gs-battle[hidden] { display: none; }
.gs-vs { display: grid; gap: 10px; --gs-ease: cubic-bezier(0.22, 1, 0.36, 1); }
.gs-vs-top { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); align-items: center; gap: 8px; }
.gs-vs-side { position: relative; display: flex; align-items: center; gap: 8px; min-width: 0; transition: opacity 0.5s, filter 0.5s; }
.gs-vs-s1 { flex-direction: row-reverse; text-align: right; }
.gs-vs-avatar { display: grid; place-items: center; width: 44px; height: 44px; font-size: 19px; font-weight: 800; }
.gs-vs-s0 .gs-vs-avatar { background: var(--gs-side-a); color: var(--gs-side-a-text); box-shadow: 0 0 0 2px var(--gs-surface), 0 0 0 4px var(--gs-side-a); }
.gs-vs-s1 .gs-vs-avatar { background: var(--gs-side-b); color: var(--gs-side-b-text); box-shadow: 0 0 0 2px var(--gs-surface), 0 0 0 4px var(--gs-side-b); }
.gs-vs-avatar { display: grid; place-items: center; overflow: hidden; }
.gs-vs-avatar .gs-avatar-img { width: 100%; height: 100%; border-radius: 50%; object-fit: cover; }
.gs-vs-avatar .gs-avatar-letter { grid-area: 1 / 1; }
.gs-vs-who { display: grid; min-width: 0; }
.gs-vs-name { overflow: hidden; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; color: var(--gs-text); }
.gs-vs-score { overflow: hidden; font-size: 22px; font-weight: 800; line-height: 1.1; text-overflow: ellipsis; font-variant-numeric: tabular-nums; color: var(--gs-text); }
.gs-vs-crown { position: absolute; top: -13px; left: 14px; display: none; width: 18px; height: 18px; color: #ffc83d; filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.5)); transform: rotate(-12deg); }
.gs-vs-s1 .gs-vs-crown { right: 14px; left: auto; transform: rotate(12deg); }
.gs-vs-crown svg { width: 100%; height: 100%; fill: currentColor; }
.gs-vs-mid { display: grid; justify-items: center; gap: 3px; }
.gs-vs-tag { font-size: 10px; font-weight: 900; letter-spacing: 0.18em; color: var(--gs-muted); }
.gs-vs-clock { min-width: 56px; padding: 4px 10px; border: 1px solid var(--gs-border); border-radius: 999px; background: var(--gs-background); color: var(--gs-text); font-size: 13px; font-weight: 800; text-align: center; font-variant-numeric: tabular-nums; }
.gs-vs-clock.gs-urgent { border-color: var(--gs-danger); color: var(--gs-danger); animation: gs-vs-tick 1s ease-in-out infinite; }
.gs-vs.gs-done .gs-vs-clock { border-color: transparent; background: var(--gs-accent); color: var(--gs-accent-text); }
.gs-vs-bar { position: relative; display: flex; height: 16px; border-radius: 8px; background: var(--gs-background); box-shadow: inset 0 0 0 1px var(--gs-border); }
.gs-vs-a, .gs-vs-b { display: block; width: 50%; height: 100%; transition: width 0.8s var(--gs-ease); }
.gs-vs-a { border-radius: 8px 0 0 8px; background: linear-gradient(90deg, color-mix(in srgb, var(--gs-side-a) 55%, #000), var(--gs-side-a)); }
.gs-vs-b { border-radius: 0 8px 8px 0; background: linear-gradient(270deg, color-mix(in srgb, var(--gs-side-b) 55%, #000), var(--gs-side-b)); }
.gs-vs-spark { position: absolute; top: 50%; left: 50%; width: 4px; height: 26px; border-radius: 2px; background: #fff; box-shadow: 0 0 6px 2px #fff, 0 0 16px 6px color-mix(in srgb, var(--gs-accent) 70%, #fff); transform: translate(-50%, -50%); transition: left 0.8s var(--gs-ease); }
.gs-vs-multi .gs-vs-cells { display: grid; grid-template-columns: repeat(var(--gs-vs-n), minmax(0, 1fr)); gap: 6px; }
.gs-vs-multi .gs-vs-side { flex-direction: column; justify-content: flex-start; gap: 4px; text-align: center; }
.gs-vs-multi .gs-vs-avatar { width: 36px; height: 36px; font-size: 16px; background: var(--gs-side); color: var(--gs-side-text); box-shadow: 0 0 0 2px var(--gs-surface), 0 0 0 4px var(--gs-side); }
.gs-vs-multi[data-gs-sides="many"] .gs-vs-avatar { width: 30px; height: 30px; font-size: 13px; }
.gs-vs-multi .gs-vs-crown { left: 50%; top: -14px; margin-left: -9px; }
.gs-vs-multi .gs-vs-who { justify-items: center; width: 100%; }
.gs-vs-multi .gs-vs-name { max-width: 100%; font-size: 12px; }
.gs-vs-multi .gs-vs-score { max-width: 100%; font-size: 17px; }
.gs-vs-multi[data-gs-sides="many"] .gs-vs-name { font-size: 11px; }
.gs-vs-multi[data-gs-sides="many"] .gs-vs-score { font-size: 14px; }
.gs-vs-multi .gs-vs-bar { overflow: hidden; }
.gs-vs-seg { display: block; width: 0; height: 100%; background: linear-gradient(90deg, color-mix(in srgb, var(--gs-side) 55%, #000), var(--gs-side)); transition: width 0.8s var(--gs-ease); }
.gs-vs-seg + .gs-vs-seg { border-left: 2px solid #fff; }
.gs-vs-side.gs-pulse { animation: gs-vs-pop 0.5s var(--gs-ease); }
.gs-vs-a.gs-pulse, .gs-vs-b.gs-pulse, .gs-vs-seg.gs-pulse { animation: gs-vs-flash 0.6s ease-out; }
.gs-vs-side.gs-lose { opacity: 0.5; filter: saturate(0.5); }
.gs-vs-side.gs-win .gs-vs-crown { display: block; }
.gs-vs-side.gs-win .gs-vs-avatar { box-shadow: 0 0 0 2px var(--gs-surface), 0 0 0 4px #ffc83d, 0 0 18px 2px rgba(255, 200, 61, 0.55); }
.gs-vs.gs-done .gs-vs-spark { opacity: 0.5; }
.gs-vs-banner { margin: 0; color: var(--gs-text); font-size: 13px; font-weight: 800; text-align: center; }
.gs-vs-banner:empty { display: none; }
.gs-vs.gs-finish .gs-vs-banner { animation: gs-vs-rise 0.6s var(--gs-ease); }
@keyframes gs-vs-pop { 40% { transform: scale(1.07); } }
@keyframes gs-vs-flash { 30% { filter: brightness(1.7) saturate(1.2); } }
@keyframes gs-vs-tick { 50% { opacity: 0.55; } }
@keyframes gs-vs-rise { from { opacity: 0; transform: translateY(6px) scale(0.96); } }
.gs-battle[data-calm] *, .gs-battle[data-calm] *::before { transition: none !important; animation: none !important; }
@media (hover: hover) {
  .gs-cell:hover { border-color: var(--gs-border); }
  .gs-cell[aria-checked="true"]:hover { border-color: var(--gs-accent); }
  .gs-send:not([aria-disabled="true"]):hover { filter: brightness(1.08); }
  .gs-topup:hover { text-decoration: underline; }
}
.gs-tray .gs-cell:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 0; }

/* Gift wall, "while you were away" card and leaderboard. */
.gs-wall, .gs-away, .gs-board { font-family: var(--gs-font, system-ui, sans-serif); color: var(--gs-text); }
.gs-wall[hidden], .gs-board [hidden] { display: none !important; }
:where(.gs-wall button, .gs-away button, .gs-board button) {
  font: inherit; color: inherit; cursor: pointer; -webkit-tap-highlight-color: transparent;
  touch-action: manipulation;
}
.gs-wall button:focus-visible, .gs-away button:focus-visible, .gs-board button:focus-visible,
.gs-away-card:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-avatar-letter { grid-area: 1 / 1; }
.gs-away .gs-avatar, .gs-board .gs-avatar { display: grid; place-items: center; overflow: hidden; }
.gs-avatar-img { grid-area: 1 / 1; width: 100%; height: 100%; object-fit: cover; }

.gs-wall { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
.gs-chip {
  position: relative; flex: none; display: inline-flex; align-items: center; gap: 4px; height: 24px;
  padding: 0 8px 0 3px; border: 1px solid var(--gs-border); border-radius: 999px;
  background: var(--gs-surface); color: var(--gs-text); font-size: 12.5px; font-weight: 700;
  line-height: 1; font-variant-numeric: tabular-nums; white-space: nowrap;
}
.gs-wall-sm .gs-chip { height: 20px; padding: 0 6px 0 2px; font-size: 11px; }
.gs-chip-icon { flex: none; width: 20px; height: 20px; object-fit: contain; }
.gs-wall-sm .gs-chip-icon { width: 16px; height: 16px; }
.gs-chip-fallback { border-radius: 50%; background: var(--gs-coin); }
.gs-chip-more { padding-left: 8px; }
.gs-chip-skeleton { width: 46px; padding: 0; border-color: transparent; background: var(--gs-border); opacity: 0.6; }
.gs-wall-empty { font-size: 12.5px; color: var(--gs-muted); }
button.gs-chip { cursor: pointer; }
/* A tappable chip keeps a 44 px target without growing: the hit area reaches past the pill. */
button.gs-chip::after { content: ""; position: absolute; inset: -10px -3px; }
.gs-wall-sm button.gs-chip::after { inset: -12px -3px; }

.gs-away { position: absolute; inset: 0; z-index: 900; display: flex; align-items: center; justify-content: center; padding: 16px; pointer-events: none; }
.gs-away-card {
  position: relative; width: 100%; max-width: 360px; padding: 16px 16px 16px 18px; border-radius: 20px;
  border: 1px solid var(--gs-border); background: var(--gs-surface); color: var(--gs-text);
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.4), 0 2px 8px rgba(0, 0, 0, 0.2); pointer-events: auto;
  cursor: pointer; outline: none;
}
.gs-away-head { display: flex; align-items: flex-start; gap: 8px; }
.gs-away-titles { flex: 1; min-width: 0; }
.gs-away-title { margin: 2px 0 0; font-size: 13px; font-weight: 700; color: var(--gs-muted); }
.gs-away-headline { margin: 2px 0 0; font-size: 20px; line-height: 1.25; font-weight: 800; }
.gs-away-close {
  flex: none; display: flex; align-items: center; justify-content: center; width: 32px; height: 32px;
  margin: -4px -4px 0 0; padding: 0; border: 0; border-radius: 50%; background: var(--gs-background);
  color: var(--gs-muted);
}
.gs-away-senders { list-style: none; display: flex; flex-direction: column; gap: 8px; margin: 14px 0 0; padding: 0; }
.gs-away-sender { display: flex; align-items: center; gap: 10px; font-size: 14px; }
.gs-away-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; }
.gs-away-count { flex: none; font-weight: 700; color: var(--gs-muted); font-variant-numeric: tabular-nums; }
.gs-away-gifts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 14px; }
.gs-away-gifts .gs-chip { height: 28px; font-size: 13px; background: var(--gs-background); border-color: transparent; }
.gs-away-gifts .gs-chip-icon { width: 22px; height: 22px; }

.gs-board {
  --gs-rank1: #e8a93a; --gs-rank2: #b8bcc8; --gs-rank3: #c07a45;
  display: flex; flex-direction: column; gap: 8px; padding: 10px; border: 1px solid var(--gs-border);
  border-radius: 16px; background: var(--gs-surface);
}
.gs-board-head { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; min-height: 28px; }
.gs-board-fill { flex: 1; }
.gs-tabs { flex: 1 1 250px; min-width: 0; display: flex; gap: 2px; padding: 3px; border-radius: 999px; background: var(--gs-background); }
.gs-tab {
  flex: 1; min-width: 0; padding: 6px 2px; border: 0; border-radius: 999px; background: transparent;
  color: var(--gs-muted); font-size: 13px; font-weight: 700; white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis;
}
.gs-tab[aria-selected="true"] { background: var(--gs-accent); color: var(--gs-accent-text); }
.gs-metric { flex: none; display: flex; padding: 3px; border-radius: 999px; background: var(--gs-background); }
.gs-metric-btn { padding: 6px 10px; border: 0; border-radius: 999px; background: transparent; color: var(--gs-muted); font-size: 13px; font-weight: 700; }
.gs-metric-btn[aria-pressed="true"] { background: var(--gs-selected); color: var(--gs-text); }
.gs-spin {
  flex: none; width: 14px; height: 14px; border: 2px solid var(--gs-border); border-top-color: var(--gs-accent);
  border-radius: 50%; animation: gs-spin 0.8s linear infinite;
}
@keyframes gs-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .gs-spin { animation: none; } }
.gs-rows { list-style: none; display: flex; flex-direction: column; margin: 0; padding: 0; }
.gs-row { display: flex; align-items: center; height: 52px; border-radius: 12px; }
.gs-row-main {
  flex: 1; min-width: 0; height: 100%; display: flex; align-items: center; gap: 10px; padding: 0 10px;
  border: 0; border-radius: 12px; background: none; text-align: left; color: inherit;
}
.gs-row[data-gs-me] { background: var(--gs-selected); }
.gs-rank {
  flex: none; display: flex; align-items: center; justify-content: center; width: 28px; height: 28px;
  border-radius: 50%; font-size: 13px; font-weight: 800; color: var(--gs-muted);
  font-variant-numeric: tabular-nums;
}
.gs-rank[data-gs-medal] { color: var(--gs-notice-big-text); }
.gs-rank[data-gs-medal="1"] { background: var(--gs-rank1); }
.gs-rank[data-gs-medal="2"] { background: var(--gs-rank2); }
.gs-rank[data-gs-medal="3"] { background: var(--gs-rank3); }
.gs-row-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 14.5px; font-weight: 600; }
.gs-score { flex: none; display: flex; align-items: center; gap: 5px; font-size: 14px; font-weight: 700; font-variant-numeric: tabular-nums; }
.gs-score-unit { font-size: 12px; font-weight: 600; color: var(--gs-muted); }
.gs-pinned { margin-top: 4px; border-top: 1px solid var(--gs-border); border-radius: 0 0 12px 12px; padding-top: 0; }
.gs-pinned-rank { flex: none; font-weight: 800; font-size: 14px; }
.gs-pinned { height: 56px; }
.gs-skel { flex: none; border-radius: 6px; background: var(--gs-border); opacity: 0.6; }
.gs-skel-disc { width: 28px; height: 28px; border-radius: 50%; }
.gs-skel-bar { flex: 1; height: 12px; max-width: 55%; margin: 0 8px; }
.gs-skel-score { width: 44px; height: 12px; margin-left: auto; }
.gs-row-skeleton { gap: 10px; padding: 0 10px; }
.gs-board-empty, .gs-board-message { margin: 0; color: var(--gs-muted); font-size: 14px; text-align: center; }
.gs-board-empty { padding: 28px 8px; }
.gs-board-error { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 22px 8px; }
.gs-board-message { color: var(--gs-danger); }
.gs-retry {
  padding: 8px 18px; border: 0; border-radius: 999px; background: var(--gs-accent);
  color: var(--gs-accent-text); font-size: 14px; font-weight: 700;
}
.gs-inbox-row { height: 56px; }
.gs-inbox .gs-avatar { flex: none; font-size: 15px; }
.gs-inbox-text { font-weight: 500; }
.gs-inbox-text b { font-weight: 700; }
.gs-inbox .gs-chip-icon { width: 28px; height: 28px; }
.gs-inbox-time { flex: none; min-width: 2.2em; text-align: right; color: var(--gs-muted); font-size: 12.5px; font-weight: 600; font-variant-numeric: tabular-nums; }
.gs-inbox-more {
  align-self: center; padding: 8px 18px; border: 1px solid var(--gs-border); border-radius: 999px;
  background: transparent; color: var(--gs-text); font-size: 14px; font-weight: 700;
}
.gs-inbox-more:disabled { opacity: 0.6; }
@media (hover: hover) {
  .gs-tab:not([aria-selected="true"]):hover, .gs-metric-btn:hover { color: var(--gs-text); }
  button.gs-row-main:hover { background: var(--gs-background); }
  .gs-retry:hover { filter: brightness(1.08); }
}

/* The gift button in the app's message bar (spec 20.4). */
.gs-gift-button {
  --gs-size: 36px; display: inline-grid; place-items: center; flex: none; width: var(--gs-size);
  height: var(--gs-size); padding: 0; margin: 0; border: 0; border-radius: 50%;
  background: transparent; color: var(--gs-accent); cursor: pointer; position: relative;
  -webkit-tap-highlight-color: transparent; transition: background-color 120ms ease-out;
}
.gs-gift-button::after { content: ""; position: absolute; inset: min(0px, calc((var(--gs-size) - 44px) / 2)); }
.gs-gift-button[data-gs-filled] { background: var(--gs-accent); color: var(--gs-accent-text); }
.gs-gift-button[aria-expanded="true"] { background: var(--gs-selected); color: var(--gs-accent); }
.gs-gift-button:disabled, .gs-gift-button[aria-disabled="true"] { opacity: 0.5; cursor: default; }
.gs-gift-button:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-gift-glyph {
  display: grid; place-items: center; flex: none; overflow: hidden; color: inherit; pointer-events: none;
  width: calc(var(--gs-size) * 22 / 36); height: calc(var(--gs-size) * 22 / 36);
  /* A definite cell: the percentages below resolve against the fixed box, not against the icon. */
  grid-template: 100% / 100%;
}
.gs-gift-glyph > * { display: block; min-width: 0; min-height: 0; max-width: 100%; max-height: 100%; }
.gs-gift-glyph > svg.gs-gift-default {
  width: 100%; height: 100%; fill: none; stroke: currentColor; stroke-width: 1.8;
  stroke-linejoin: round; stroke-linecap: round;
}
.gs-gift-glyph > img { object-fit: contain; }
@media (hover: hover) {
  .gs-gift-button:not(:disabled):hover { filter: brightness(1.12); }
}

/* The "Send to" row of a battle (spec 21.3). */
.gs-receivers {
  position: relative; flex: none; display: flex; align-items: center; gap: 8px; overflow-x: auto; overflow-y: hidden;
  scrollbar-width: none; padding: 2px 2px 4px; margin-top: 10px;
}
.gs-receivers[hidden] { display: none; }
.gs-receivers::-webkit-scrollbar { display: none; }
/* The row never shrinks (a popover or inline tray is a height-capped column): the avatars stay round. */
.gs-receivers > * { flex-shrink: 0; }
.gs-receivers-label { flex: none; font-size: 12px; font-weight: 700; color: var(--gs-muted); }
.gs-receiver {
  flex: none; display: flex; align-items: center; gap: 6px; padding: 3px; margin: 0;
  border: 0; border-radius: 999px; background: transparent; color: var(--gs-text); cursor: pointer;
  font: inherit; opacity: 0.55; -webkit-tap-highlight-color: transparent;
  transition: opacity 120ms ease-out;
}
.gs-receiver[aria-checked="true"] { opacity: 1; padding-right: 8px; }
.gs-receiver:not([aria-checked="true"]) .gs-receiver-name { display: none; }
.gs-receiver:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-receiver-avatar {
  display: grid; place-items: center; overflow: hidden; flex: none; width: 30px; height: 30px;
  border-radius: 50%; background: var(--gs-side); color: var(--gs-side-text); font-size: 13px;
  font-weight: 800; box-shadow: 0 0 0 2px var(--gs-side);
}
.gs-receiver[aria-checked="true"] .gs-receiver-avatar {
  box-shadow: 0 0 0 2px var(--gs-side), 0 0 0 4px var(--gs-text);
}
.gs-receiver-avatar .gs-avatar-img { width: 100%; height: 100%; border-radius: 50%; object-fit: cover; }
.gs-receiver-avatar .gs-avatar-letter { grid-area: 1 / 1; }
.gs-receiver-name {
  max-width: 72px; font-size: 12px; font-weight: 700; white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis;
}
.gs-receiver[aria-checked="true"] .gs-receiver-name { color: var(--gs-accent); }
/* A tappable side of the battle bar (spec 21.4). */
.gs-vs-pick {
  display: inline-grid; place-items: center; min-width: 44px; min-height: 44px; padding: 0;
  margin: 0; border: 0; border-radius: 50%; background: transparent; cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.gs-vs-pick:focus-visible { outline: 2px solid var(--gs-accent); outline-offset: 2px; }
.gs-vs-pick:active .gs-vs-avatar { transform: scale(0.94); }
`;

/** How the stylesheet reaches the page (see `configureStyles`). */
export interface StyleOptions {
  /**
   * The Content-Security-Policy nonce of your page. A `<style>` element the SDK has to add (a
   * browser without constructable stylesheets) carries it, so `style-src 'nonce-...'` allows it.
   * Default: the `content` of `<meta name="csp-nonce">` when the page has one.
   */
  nonce?: string;
  /**
   * Default `true`: add the stylesheet as a constructable stylesheet (`adoptedStyleSheets`),
   * which a Content-Security-Policy `style-src` does not govern, so no nonce or
   * `'unsafe-inline'` is needed. `false` always uses a `<style>` element.
   */
  adoptedStyleSheets?: boolean;
}

let nonceOption: string | undefined;
let adoptedOption = true;

/**
 * Call once at start-up, before the first component is created. `@giftingstack/sdk/web` and
 * `@giftingstack/sdk/elements` both export it. See "Content-Security-Policy" in the README.
 */
export function configureStyles(options: StyleOptions): void {
  if ("nonce" in options) nonceOption = options.nonce || undefined;
  if (options.adoptedStyleSheets !== undefined) adoptedOption = options.adoptedStyleSheets;
}

function nonceOf(doc: Document): string | undefined {
  if (nonceOption) return nonceOption;
  const meta = doc.head?.querySelector('meta[name="csp-nonce"]');
  return meta?.getAttribute("content") || undefined;
}

interface SheetWindow {
  CSSStyleSheet?: { new (): CSSStyleSheet; prototype: { replaceSync?: unknown } };
}

/** A constructable stylesheet for `doc`, or null where the browser has none (or it is off). */
function makeSheet(doc: Document, css: string): CSSStyleSheet | null {
  if (!adoptedOption) return null;
  try {
    const win = doc.defaultView as (Window & SheetWindow) | null;
    const Sheet = win?.CSSStyleSheet;
    if (!Sheet || typeof Sheet.prototype.replaceSync !== "function") return null;
    if (!Array.isArray((doc as { adoptedStyleSheets?: unknown }).adoptedStyleSheets)) return null;
    const sheet = new Sheet();
    sheet.replaceSync(css);
    return sheet;
  } catch {
    return null;
  }
}

/**
 * Adds `css` to the page: as an adopted stylesheet when the browser has them (no CSP nonce
 * needed), else as a `<style ${attr}>` element with the nonce.
 */
export function installCss(doc: Document, css: string, attr: string): InstalledCss {
  const sheet = makeSheet(doc, css);
  if (sheet) {
    doc.adoptedStyleSheets = [...doc.adoptedStyleSheets, sheet];
    return {
      alive: () => doc.adoptedStyleSheets.includes(sheet),
      remove: () => {
        doc.adoptedStyleSheets = doc.adoptedStyleSheets.filter((s) => s !== sheet);
      },
    };
  }
  const el = doc.createElement("style");
  el.setAttribute(attr, "");
  const nonce = nonceOf(doc);
  if (nonce) el.setAttribute("nonce", nonce);
  el.textContent = css;
  doc.head.appendChild(el);
  return { alive: () => el.isConnected, remove: () => el.remove() };
}

/** What `installCss` added: still on the page?, and the undo. */
export interface InstalledCss {
  alive(): boolean;
  remove(): void;
}

let count = 0;
let installed: InstalledCss | null = null;

/** Adds the stylesheet if it is not there yet. Pair every call with `releaseStyles`. */
export function acquireStyles(doc: Document): void {
  count++;
  if (installed?.alive()) return;
  installed?.remove();
  installed = installCss(doc, CSS, "data-giftingstack");
}

/** Removes the stylesheet again when the last user is gone. */
export function releaseStyles(): void {
  count = Math.max(0, count - 1);
  if (count === 0) {
    installed?.remove();
    installed = null;
  }
}
