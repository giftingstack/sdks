/**
 * Inline SVG pictures for the posts of the demo feed (no image files, no text, no real places or
 * people). Every scene is the same recipe: a gradient sky with a glow, layered silhouettes that
 * fade with distance, a few warm accents, then a vignette and a little film grain on top.
 * Not part of the SDK.
 */
import type { Post } from "./shared";

type Kind = Post["art"];

/** A tiny seeded random, so a picture is the same on every render. */
const rng = (seed: number): (() => number) => {
  let s = seed;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
};

const f = (n: number): string => String(Math.round(n * 10) / 10);

/** `<linearGradient>` from top to bottom with evenly spaced stops. */
const vgrad = (id: string, ...colors: string[]): string =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">${colors
    .map((c, i) => `<stop offset="${f(i / (colors.length - 1))}" stop-color="${c}"/>`)
    .join("")}</linearGradient>`;

/** A soft glow: a radial gradient that fades to nothing. */
const glow = (id: string, color: string, alpha = 1): string =>
  `<radialGradient id="${id}"><stop offset="0" stop-color="${color}" stop-opacity="${alpha}"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></radialGradient>`;

const stars = (n: number, seed: number, maxY: number): string => {
  const r = rng(seed);
  return `<g fill="#fff">${Array.from({ length: n }, () => {
    const x = r() * 400;
    const y = r() * maxY;
    const big = r() > 0.9;
    return `<circle cx="${f(x)}" cy="${f(y)}" r="${f(big ? 1.5 + r() * 0.6 : 0.4 + r() * 0.8)}" opacity="${f(0.35 + r() * 0.65)}"/>`;
  }).join("")}</g>`;
};

/** A jagged-then-smoothed ridge line filled down to the bottom edge. */
const ridge = (
  seed: number,
  base: number,
  amp: number,
  fill: string,
  opacity = 1,
  peaks = 7,
): string => {
  const r = rng(seed);
  const pts: [number, number][] = [];
  for (let i = 0; i <= peaks; i++) pts.push([(i / peaks) * 400, base - r() * amp]);
  let d = `M-10 300V${f(pts[0]![1])}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, y0] = pts[i]!;
    const [x1, y1] = pts[i + 1]!;
    const mx = (x0 + x1) / 2;
    d += `Q${f(x0)} ${f(y0)} ${f(mx)} ${f((y0 + y1) / 2)}`;
  }
  d += `L410 ${f(pts[peaks]![1])}V300z`;
  return `<path d="${d}" fill="${fill}" opacity="${opacity}"/>`;
};

/** Pine trees as stacked triangles, along a baseline. */
const pines = (seed: number, y: number, color: string, from = 0, to = 400, h = 34): string => {
  const r = rng(seed);
  let out = "";
  for (let x = from; x < to; x += 9 + r() * 14) {
    const t = h * (0.6 + r() * 0.6);
    const w = t * 0.36;
    out += `M${f(x)} ${f(y)}l${f(-w)} 0 ${f(w * 0.45)} ${f(-t * 0.4)} ${f(-w * 0.35)} 0 ${f(w * 0.4)} ${f(-t * 0.35)} ${f(-w * 0.3)} 0 ${f(w * 0.5)} ${f(-t * 0.35)} ${f(w * 0.5)} ${f(t * 0.35)} ${f(-w * 0.3)} 0 ${f(w * 0.4)} ${f(t * 0.35)} ${f(-w * 0.35)} 0 ${f(w * 0.45)} ${f(t * 0.4)}z`;
  }
  return `<path d="${out}" fill="${color}"/>`;
};

/** Lit windows scattered over a building block. */
const windows = (
  seed: number,
  x: number,
  y: number,
  w: number,
  h: number,
  color: string,
  density = 0.45,
): string => {
  const r = rng(seed);
  let out = "";
  for (let wy = y + 8; wy < y + h - 6; wy += 11)
    for (let wx = x + 6; wx < x + w - 8; wx += 11)
      if (r() < density)
        out += `<rect x="${f(wx)}" y="${f(wy)}" width="5" height="6" opacity="${f(0.45 + r() * 0.55)}"/>`;
  return `<g fill="${color}">${out}</g>`;
};

/** Skyline blocks, left to right, with the given colour. */
const skyline = (seed: number, base: number, minH: number, maxH: number, fill: string): string => {
  const r = rng(seed);
  let out = "";
  for (let x = -6; x < 400;) {
    const w = 24 + r() * 34;
    const h = minH + r() * (maxH - minH);
    out += `<rect x="${f(x)}" y="${f(base - h)}" width="${f(w)}" height="${f(h + 4)}"/>`;
    if (r() > 0.6)
      out += `<rect x="${f(x + w / 2 - 1)}" y="${f(base - h - 12)}" width="2" height="12"/>`;
    x += w + r() * 4;
  }
  return `<g fill="${fill}">${out}</g>`;
};

const svg = (id: string, defs: string, body: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" role="img" aria-hidden="true"><defs>${defs}<radialGradient id="${id}-vg" cx=".5" cy=".5" r=".75"><stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".5"/></radialGradient><filter id="${id}-gr" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="3"/><feColorMatrix type="saturate" values="0"/></filter></defs>${body}<rect width="400" height="300" fill="url(#${id}-vg)"/><rect width="400" height="300" filter="url(#${id}-gr)" opacity=".09" style="mix-blend-mode:overlay"/></svg>`;

type Scene = (id: string) => string;

const SCENES: Record<Kind, Scene> = {
  // A rooftop at dusk: warm sun, hazy skyline, string lights over a parapet.
  sunset: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#2a2275", "#b23c8f", "#ff7a6b", "#ffc46b")}${glow(`${id}-sun`, "#ffe2a0")}${glow(`${id}-lamp`, "#ffd27a", 0.8)}`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>
       <circle cx="262" cy="168" r="120" fill="url(#${id}-sun)" opacity=".75"/>
       <circle cx="262" cy="168" r="30" fill="#fff0c4"/>
       <g fill="#fff" opacity=".22"><rect x="40" y="70" width="120" height="5" rx="2.5"/><rect x="70" y="84" width="84" height="4" rx="2"/><rect x="250" y="52" width="110" height="5" rx="2.5"/><rect x="290" y="64" width="70" height="4" rx="2"/></g>
       ${skyline(5, 214, 20, 62, "#7a3a8e").replace("<g ", '<g opacity=".55" ')}
       ${skyline(9, 226, 14, 46, "#3d1c63")}
       <path d="M0 232h400v68H0z" fill="#1d0f3a"/>
       <rect x="0" y="228" width="400" height="9" fill="#2e1855"/>
       <rect x="30" y="196" width="38" height="34" rx="3" fill="#1d0f3a"/><rect x="26" y="192" width="46" height="6" rx="2" fill="#2e1855"/><rect x="48" y="170" width="2" height="22" fill="#1d0f3a"/>
       <path d="M0 150Q100 190 200 156T400 140" fill="none" stroke="#1d0f3a" stroke-width="1.5" opacity=".8"/>
       ${[40, 100, 160, 226, 300, 360]
         .map((x, i) => {
           const y = 150 + Math.sin(x / 60) * 12 + (i % 2 ? 4 : 0);
           return `<circle cx="${x}" cy="${f(y)}" r="16" fill="url(#${id}-lamp)"/><circle cx="${x}" cy="${f(y)}" r="2.6" fill="#ffe9b5"/>`;
         })
         .join("")}
       <ellipse cx="330" cy="268" rx="46" ry="9" fill="#ff7a6b" opacity=".12"/>
       <rect x="296" y="248" width="70" height="4" rx="2" fill="#3a2168"/><rect x="302" y="252" width="3" height="22" fill="#3a2168"/><rect x="357" y="252" width="3" height="22" fill="#3a2168"/>`,
    ),
  // A night skyline: moon halo, two layers of towers, lit windows, street haze.
  city: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#080b2b", "#2b2a78", "#7a49b8", "#e98bb0")}${glow(`${id}-moon`, "#f6f1d6", 0.9)}
       <linearGradient id="${id}-fog" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e98bb0" stop-opacity="0"/><stop offset="1" stop-color="#e98bb0" stop-opacity=".55"/></linearGradient>`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>${stars(50, 7, 120)}
       <circle cx="318" cy="64" r="64" fill="url(#${id}-moon)" opacity=".5"/><circle cx="318" cy="64" r="19" fill="#f6f1d6"/><circle cx="326" cy="59" r="17" fill="#2b2a78" opacity=".28"/>
       ${skyline(21, 252, 50, 120, "#3a2a82").replace("<g ", '<g opacity=".8" ')}
       ${skyline(33, 280, 40, 150, "#150f45")}
       ${windows(2, 30, 160, 60, 140, "#ffd27a")}${windows(4, 130, 140, 70, 160, "#ffd27a")}${windows(6, 230, 120, 62, 180, "#ffe6a8")}${windows(8, 320, 150, 80, 150, "#ffd27a")}
       <rect y="200" width="400" height="100" fill="url(#${id}-fog)"/>
       <rect y="284" width="400" height="16" fill="#0b0830"/>
       <g stroke="#ff9ac8" stroke-width="2" opacity=".7"><path d="M0 292h400" stroke-dasharray="26 18"/></g>`,
    ),
  // Open sea: high sun, clouds, lighthouse on a rock, a sail, sparkles on the water.
  ocean: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#4aa8f0", "#9fdcff", "#eaf9ff")}${vgrad(`${id}-sea`, "#2cc0d4", "#1478b4", "#0a3d78")}${glow(`${id}-sun`, "#fff7cf")}`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>
       <circle cx="316" cy="68" r="86" fill="url(#${id}-sun)" opacity=".8"/><circle cx="316" cy="68" r="24" fill="#fffbe2"/>
       <g fill="#fff" opacity=".92"><ellipse cx="86" cy="72" rx="48" ry="11"/><ellipse cx="116" cy="60" rx="30" ry="12"/><ellipse cx="236" cy="106" rx="42" ry="8"/><ellipse cx="262" cy="98" rx="22" ry="8"/></g>
       <rect y="142" width="400" height="158" fill="url(#${id}-sea)"/>
       <rect y="142" width="400" height="3" fill="#fff" opacity=".5"/>
       <path d="M0 176q25-10 50 0t50 0 50 0 50 0 50 0 50 0 50 0 50 0v16H0z" fill="#fff" opacity=".16"/>
       <path d="M0 218q25-12 50 0t50 0 50 0 50 0 50 0 50 0 50 0 50 0v34H0z" fill="#7fe0f2" opacity=".18"/>
       <path d="M0 262q25-12 50 0t50 0 50 0 50 0 50 0 50 0 50 0 50 0v40H0z" fill="#031f4a" opacity=".3"/>
       <g stroke="#fff" stroke-linecap="round" opacity=".7"><path d="M286 156h30M276 170h50M292 186h24M270 204h60" stroke-width="2.4"/></g>
       <path d="M30 168c10-30 70-34 100-8l30 10v10H30z" fill="#37465c"/><path d="M60 150l4-14h18l6 14z" fill="#243349"/>
       <path d="M64 150l4-52h12l4 52z" fill="#f4efe6"/><path d="M66 128h16l-1 12H65zM68 108h12l-1 10H69z" fill="#e0453d"/>
       <rect x="62" y="90" width="22" height="8" rx="2" fill="#243349"/><path d="M60 90h26l-13-12z" fill="#e0453d"/>
       <path d="M82 92l40-8v16z" fill="#fff3b0" opacity=".5"/>
       <g transform="translate(212 126)"><path d="M0 0l0-34 18 30z" fill="#fff"/><path d="M-3 0l0-26-14 26z" fill="#ffe3a3"/><path d="M-18 4h40l-6 8h-28z" fill="#3b2a1f"/></g>`,
    ),
  // A cabin under northern lights, pines in front, a lit window.
  aurora: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#030820", "#0e2a63", "#1c5a8a")}
       <linearGradient id="${id}-a1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5bffb8" stop-opacity="0"/><stop offset=".45" stop-color="#5bffb8" stop-opacity=".75"/><stop offset="1" stop-color="#7a6bff" stop-opacity="0"/></linearGradient>
       <linearGradient id="${id}-a2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b86bff" stop-opacity="0"/><stop offset=".5" stop-color="#7affd0" stop-opacity=".5"/><stop offset="1" stop-color="#3a6bff" stop-opacity="0"/></linearGradient>${glow(`${id}-win`, "#ffc861", 0.9)}`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>${stars(70, 11, 170)}
       <path d="M-10 118C70 30 150 170 230 78S350 50 410 108V20C330 0 280 74 220 26 150-26 80 66-10 26z" fill="url(#${id}-a1)" transform="translate(0 22)"/>
       <path d="M-10 160C90 96 160 196 250 124S360 96 410 156V84C340 54 290 126 230 84 160 36 90 112-10 84z" fill="url(#${id}-a2)" transform="translate(0 20)"/>
       ${ridge(14, 200, 54, "#123566", 1, 6)}${ridge(23, 226, 38, "#0a1d44", 1, 8)}
       <rect y="236" width="400" height="64" fill="#050f2a"/>
       <ellipse cx="270" cy="250" rx="90" ry="9" fill="#5bffb8" opacity=".12"/>
       ${pines(3, 252, "#030b20", 0, 200, 52)}${pines(8, 258, "#02071a", 316, 410, 60)}
       <g><rect x="232" y="224" width="46" height="30" fill="#24150d"/><path d="M226 226l29-24 29 24z" fill="#120a06"/><rect x="236" y="206" width="6" height="12" fill="#120a06"/><circle cx="256" cy="238" r="26" fill="url(#${id}-win)"/><rect x="249" y="232" width="14" height="12" fill="#ffd27a"/></g>
       ${pines(5, 262, "#02071a", 296, 340, 38)}`,
    ),
  // Layered alpine ridges in dawn light with a mirror lake.
  mountains: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#3c4f9e", "#c07fb8", "#ffb68a", "#ffe2b8")}${glow(`${id}-sun`, "#fff0cf")}${vgrad(`${id}-lake`, "#e9a98f", "#4a5aa0")}`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>${stars(18, 4, 60)}
       <circle cx="140" cy="148" r="100" fill="url(#${id}-sun)" opacity=".85"/><circle cx="140" cy="150" r="22" fill="#fff6dc"/>
       ${ridge(2, 160, 70, "#a9689f", 0.65, 6)}${ridge(7, 180, 80, "#7b55a3", 0.8, 5)}
       <path d="M200 100l30 30-12-6-10 10-8-8-10 6z" fill="#fff" opacity=".55"/>
       ${ridge(12, 206, 70, "#4a4a94", 1, 6)}${ridge(19, 232, 46, "#2b2f72", 1, 7)}
       <rect y="236" width="400" height="64" fill="url(#${id}-lake)"/>
       <g opacity=".55" transform="translate(0 472) scale(1 -1)">${ridge(19, 232, 46, "#2b2f72", 1, 7)}</g>
       <rect y="236" width="400" height="64" fill="url(#${id}-lake)" opacity=".55"/>
       <g stroke="#fff" stroke-linecap="round" opacity=".4"><path d="M100 252h60M120 262h38M250 248h40M230 270h70" stroke-width="2"/></g>
       ${pines(6, 244, "#161a52", 0, 120, 44)}${pines(10, 246, "#161a52", 300, 410, 52)}`,
    ),
  // A cosy studio: window light, a lamp, shelf, plant and a canvas on an easel.
  studio: (id) =>
    svg(
      id,
      `${vgrad(`${id}-wall`, "#3a2a57", "#6b3f6d", "#b8627a")}${glow(`${id}-lamp`, "#ffcb7a", 0.85)}${vgrad(`${id}-floor`, "#4a2d3f", "#241226")}
       <linearGradient id="${id}-beam" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffe0a8" stop-opacity=".55"/><stop offset="1" stop-color="#ffe0a8" stop-opacity="0"/></linearGradient>`,
      `<rect width="400" height="300" fill="url(#${id}-wall)"/>
       <rect y="214" width="400" height="86" fill="url(#${id}-floor)"/><rect y="212" width="400" height="4" fill="#2a1a35"/>
       <rect x="40" y="46" width="108" height="112" rx="4" fill="#1d1233"/><rect x="46" y="52" width="96" height="100" fill="#ffb98a"/><rect x="46" y="52" width="96" height="60" fill="#ff8aa0"/><circle cx="108" cy="102" r="14" fill="#fff0c4"/><rect x="92" y="52" width="4" height="100" fill="#1d1233"/><rect x="46" y="100" width="96" height="4" fill="#1d1233"/>
       <path d="M46 152h96l120 74H80z" fill="url(#${id}-beam)"/>
       <rect x="196" y="58" width="84" height="6" rx="3" fill="#2a1a35"/><g fill="#ffc46b"><rect x="204" y="38" width="12" height="20" rx="2"/></g><g fill="#7ad6c0"><rect x="222" y="30" width="10" height="28" rx="2"/></g><g fill="#ff7a8a"><rect x="236" y="42" width="14" height="16" rx="2"/></g><circle cx="266" cy="48" r="9" fill="#b9a2ff"/>
       <g transform="translate(300 74)"><rect width="76" height="96" rx="3" fill="#1d1233"/><rect x="5" y="5" width="66" height="86" fill="#f3d9c1"/><circle cx="34" cy="40" r="22" fill="#e0457b"/><circle cx="46" cy="52" r="20" fill="#7b61ff" opacity=".8"/><path d="M5 91V70q30-18 66 0v21z" fill="#2f9e8f"/></g>
       <circle cx="214" cy="170" r="70" fill="url(#${id}-lamp)"/>
       <g fill="#2a1a35"><rect x="212" y="176" width="3" height="46"/><path d="M196 178l16-26 16 26z"/></g><path d="M200 178h24" stroke="#ffe0a8" stroke-width="2"/>
       <g transform="translate(40 168)"><path d="M10 50h34l-4 36H14z" fill="#c4553d"/><g fill="#3fa066"><path d="M27 50C14 36 6 22 14-2 24 14 28 30 27 50z"/><path d="M27 50C32 30 44 16 58 14 54 34 42 46 27 50z"/><path d="M27 50C26 28 26 8 32-10 40 10 34 34 27 50z" fill="#2e8a54"/></g></g>
       <g transform="translate(262 150)" fill="#1d1233"><path d="M0 76l16-70h4L36 76h-5L18 20 5 76z"/><rect x="-4" y="46" width="48" height="4"/></g>
       <rect x="296" y="214" width="84" height="8" rx="3" fill="#2a1a35"/><rect x="304" y="222" width="5" height="40" fill="#2a1a35"/><rect x="368" y="222" width="5" height="40" fill="#2a1a35"/>
       <rect x="320" y="204" width="22" height="10" rx="2" fill="#7ad6c0"/><circle cx="360" cy="208" r="6" fill="#ff7a8a"/>`,
    ),
  // Synthwave: striped sun over a perspective grid with neon tubes.
  neon: (id) =>
    svg(
      id,
      `${vgrad(`${id}-sky`, "#12062e", "#4a0f6e", "#c0267e")}${vgrad(`${id}-sun`, "#ffe86b", "#ff4fa2")}${glow(`${id}-halo`, "#ff4fa2", 0.9)}${vgrad(`${id}-gnd`, "#2a0a4a", "#0a0220")}
       <mask id="${id}-cut"><rect width="400" height="300" fill="#fff"/>${[0, 1, 2, 3, 4]
         .map(
           (i) =>
             `<rect x="0" y="${130 + i * 12}" width="400" height="${2 + i * 1.6}" fill="#000"/>`,
         )
         .join("")}</mask>`,
      `<rect width="400" height="300" fill="url(#${id}-sky)"/>${stars(40, 17, 120)}
       <circle cx="200" cy="140" r="130" fill="url(#${id}-halo)" opacity=".6"/>
       <circle cx="200" cy="140" r="64" fill="url(#${id}-sun)" mask="url(#${id}-cut)"/>
       <path d="M0 170l60-24 40 14 50-36 40 30 30-20 40 26 40-30 50 34 50-16v52H0z" fill="#1a0838"/>
       <rect y="170" width="400" height="130" fill="url(#${id}-gnd)"/>
       <rect y="169" width="400" height="2" fill="#ff4fa2"/>
       <g stroke="#ff4fa2" stroke-width="1.2" opacity=".8">${Array.from({ length: 17 }, (_, i) => {
         const x = -300 + i * 62.5;
         return `<path d="M${f(200 + (x - 200) * 0.06)} 170L${f(x)} 300"/>`;
       }).join(
         "",
       )}${[178, 188, 202, 222, 252, 290].map((y) => `<path d="M0 ${y}h400"/>`).join("")}</g>
       <g fill="#fff" opacity=".5"><path d="M60 70l2 7 7 2-7 2-2 7-2-7-7-2 7-2zM338 52l1.5 5 5 1.5-5 1.5-1.5 5-1.5-5-5-1.5 5-1.5z"/></g>`,
    ),
};

/** The SVG markup of a post's picture. `id` keeps the gradient ids of several pictures apart. */
export const postArt = (post: Post): string => SCENES[post.art](`${post.id}-${post.art}`);
