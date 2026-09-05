# tethercam.app — Design Brief for the Onepager Rebuild

**Date:** 2026-09-05 · **Author:** design-research pass · **Status:** ready to implement
**Target:** `web/index.html`, `web/style.css`, one new `web/main.js`. Static, no framework, no build step.
**Why:** the current page is correct but flat — one 72ch column, system font, generic `#0a5ad6`, zero motion,
no full-bleed moment, no proof strip. It does not read as part of the Götzendorfer family.

---

## 1. Findings — what the sibling projects actually do

| Project | Fonts (load) | Palette (light / dark) | Radius | Motion | Hero pattern | Distinctive |
|---|---|---|---|---|---|---|
| **GotzendorferV2** (`src/styles/theme.css`, `docs/brand/DESIGN-TOKENS.md`) | Bricolage Grotesque 600/700 (display) + Inter var (body) + JetBrains Mono 400/500 + Instrument Serif 400 (dark-h1 only) — all `next/font/google`, only 2 preloaded (LCP fix, 298→91 KB) | bg `#F5F1EA` putty / `#1A1714`; fg `#171412` / `#EDE8E0`; accent Ink-Blue `#1E3A5F` / Amber `#E8A657`; border `#D8CFC0` / `#2F2C28` | `0.5rem`, scale ×0.5/×1/×1.5/×2 | **No framer-motion** (ripped out, 39.6 KB). IO `threshold .15`, `opacity 0→1 + translateY(16px)`, `500ms cubic-bezier(.16,1,.3,1)`, stagger `i*80ms`, entry-only, `unobserve` | Anti-SaaS: portrait + kicker + huge h1 + **scribble underline** + link row. **No CTA button at all**. Flat `bg-background` | SVG **scribble underline** drawn via `pathLength=1` dashoffset, 600ms; fractal-noise grain `opacity .04 mix-blend-overlay`; **accent used in exactly 3 places per page** |
| **EventDrop.at** (`src/app/globals.css`, `design/DESIGN-DIRECTION.md`) | Outfit var (all H1/body/UI) + Fraunces 400/600 italic (**max 1 italic line per section**, `preload:false`) + IBM Plex Mono 400/500 (uppercase micro-labels only, ≥1px tracking) | bg `#faf7f2` warm cream / `#0d0d12`; brand violet `#7c3aed` / `#a78bfa`; **Ink slab `#1b1626`** (same in both modes); `--glow #a78bfa` | `0.75rem` base, **`--radius-card: 20px`** for marketing cards, CTAs `rounded-full` | `MotionConfig reducedMotion="user"`; hidden state in `motion-safe:` classes only (never inline `style=opacity:0`); reveal `duration .45–.6, ease easeOut, viewport once, margin -80px`, stagger `i*80–100ms`; pricing cards spring `stiffness 50 damping 14`; marquee 40 s transform-only | Two-column: static left (LCP never animates) + right **photo stage** — brand-soft circular glow, phone mockup `rounded-[38px] p-2.5`, **3 floating chips at ±5–8° rotation** revealed at 900/1600 ms | Page **dramaturgy light→light→DARK(live wall)→light→DARK(CTA+footer)** with a gradient seam `h-16 md:h-24`; mono eyebrow `01` + `h-px w-6` dash; `shadow-brand-glow 0 8px 24px #7c3aed40` |
| **agenticbuilders-site** (`src/app/globals.css`) | Bricolage Grotesque var (`display:optional`, deliberate) + Figtree (body) + Spline Sans Mono | bg `#F8FAF8` / `#0D1F17`; primary Tannengrün `#1A5C44` / Phosphor `#52D196`; **`.surface-ink`** = one sanctioned dark block re-declaring dark tokens locally | `0.375rem`, scale r−4/−2/r/+4 | **Pure CSS, zero client JS.** `--ease-brand: cubic-bezier(.16,1,.3,1)`, `--duration-entrance: 620ms`, `--duration-draw: 700ms`, `--stagger-step: 90ms`. `.rise` on load (hero 0/160/200/260/300/360ms), `.reveal` via `animation-timeline: view()`, `.lift` hover `translateY(-2px) 180ms`, SVG `dashoffset 24→0` checkmark draw | 12-col grid, text 7/12 + portrait 5/12 `aspect-[4/5]`. Frozen order: mono eyebrow → h1 `leading-[1.05] text-balance` → sub → **exactly one** CTA → guide → mono facts line | Paper grain as a **pre-baked 160×160 AVIF tile at `opacity .025`** (a runtime `feTurbulence` had become the LCP element); hairline `gap-px bg-border` proof grid; editorial `border-l pl-5` rules instead of cards |
| **FeedFoundryV2** (`src/app/globals.css`) | Funnel Sans (h1–h6) + Geist (body) + Geist Mono | **Dark-only**, hex: bg `#000`, panel `#0d0f13`, border `#282d35`, accent orange `#ff9800`, semantic `--color-source/-human/-success` | `0.5rem` | **None.** Only `transition-colors`. No `prefers-reduced-motion` handling — an unguarded gap | Asymmetric `lg:grid-cols-[.84fr_1.16fr]`; right = product mockup panel `shadow-2xl shadow-black/25` with a live OG render + StatusRow chips | A11y minimums as tokens: `--ff-target-min 44px`, `--ff-text-body-min 16px` |
| **projects-baseline** style-matrix (`docs/superpowers/specs/2026-04-02-frontend-design-system-design.md`, `packages/shadcn-registry/registry/lyra/base-lyra.css`) | **Lyra** preset = Space Grotesk + JetBrains Mono | dark-first zinc; bg `hsl(240 10% 4%)`, card `240 8% 7%`, border `240 5% 13%`, primary violet `263 70% 58%` | **`0.25rem`** | — | — | **Lyra is the sanctioned default for "Developer Tools / Technical UIs".** TetherCam is exactly that archetype. This is not an invention; it is the house preset we have never yet used |

Live heroes verified 2026-09-05 (`curl -sI` 200/301, screenshots at `/tmp/design-gotzendorfer.png`,
`/tmp/design-eventdrop.png`, `/tmp/design-tethercam.png`): both siblings render a warm off-white canvas,
a pill or eyebrow above the headline, a very large tight-tracked display headline with **one** colored
word, a two-column split with a framed image right, and pill/`md` CTAs. tethercam.app renders a narrow
grey column of prose. The gap is structural, not decorative.

---

## 2. The common thread — and what TetherCam inherits

**What makes it ours.** Three things repeat across all three shipped sites and none of them is a
gradient. First, a **warm, never-pure-white canvas** paired with a near-black that is tinted, not
neutral — `#F5F1EA/#1A1714`, `#faf7f2/#0d0d12`, `#F8FAF8/#0D1F17`. Second, a **three-role type system**:
a geometric display face for headlines set very large with negative tracking and `text-balance`, a
neutral body face at ~17px/1.6, and a monospace reserved exclusively for uppercase micro-labels —
eyebrows, `01/02/03` step numbers, stat captions — always tracked ≥1px and never used for prose.
Third, **accent discipline as an enforced rule**, not a preference: one accent, two or three
appearances per page, written down in the design doc and guarded by tests. Nobody in this family
uses a rainbow, a mesh gradient, or a glassmorphic card.

**Motion is a shared grammar too.** Every site converges on the same curve —
`cubic-bezier(0.16, 1, 0.3, 1)` — at 450–620 ms, an entry-only IntersectionObserver reveal of
`opacity 0→1 + translateY(16–24px)`, an 80–90 ms per-item stagger, a −2px hover lift, and exactly one
**signature draw**: an SVG path animated via `stroke-dashoffset` (the scribble underline, the checkmark).
The hero above the fold deliberately does *not* animate on load, to protect LCP. Reduced motion is
double-guarded: a JS `matchMedia` check before any observer is armed, plus a global
`animation-duration: .01ms !important` net (0.01 ms, never 0, so `animationend` still fires).
The other repeating structural device is **surface dramaturgy** — one full-bleed dark slab per page
(the contact slab, `.surface-ink`, the Night-Dip live wall) that the eye reads as a change of chapter.

**What TetherCam inherits, and where it may differ.** Inherit: the type triad, the reveal grammar and
its exact curve, the accent-discipline rule, the mono eyebrow with `01/02/03`, the −2px hover lift, the
grain tile at `opacity ≈ .03`, the 48px touch floor, the `ring-[3px]` focus ring, the FAQ-as-cards
accordion, and the dark-slab chapter break. Differ: TetherCam is a hardware-adjacent developer tool —
a cable, a camera, a black OBS canvas. It ships **dark-first** (Lyra), it uses the **tight 4px radius**
instead of the 12–20px consumer radius, its mono carries more weight (protocol names, `7878`,
`usbmuxd`, HEVC), and it earns one animation the consumer sites do not have: a **living signal**. It
does *not* get EventDrop's rotated floating chips or Fraunces italic — those are consumer-warmth
devices and would read as costume here.

---

## 3. Spec for the new onepager

### 3.1 Tokens

Dark is the primary mode. Both ship; switch with `prefers-color-scheme` only (no toggle, no JS).

```css
:root {                                  /* DARK — the primary identity */
  --bg:            #0B0C10;   /* zinc-tinted near-black, matches OBS canvas */
  --bg-elevated:   #121319;
  --card:          #16181F;
  --border:        #242731;
  --border-strong: #333846;
  --fg:            #F2F3F5;
  --fg-muted:      #9AA0AD;   /* 6.4:1 on --bg */
  --accent:        #8B7CF6;   /* family violet, dark cut (EventDrop #a78bfa lineage / Lyra 263 70% 58%) */
  --accent-fg:     #0B0C10;
  --accent-soft:   rgba(139,124,246,0.12);
  --signal:        #4ADE80;   /* STATUS ONLY: live dot, travelling pulse, "connected" */
  --signal-dim:    rgba(74,222,128,0.18);
  --code-bg:       #101219;
  --grain:         0.030;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #F7F6F3; --bg-elevated: #FFFFFF; --card: #FFFFFF;
    --border: #E2DFD9; --border-strong: #CFCBC3;
    --fg: #16181D; --fg-muted: #575D68;              /* 6.1:1 */
    --accent: #6D28D9; --accent-fg: #FFFFFF;          /* 7.4:1 on light bg */
    --accent-soft: rgba(109,40,217,0.09);
    --signal: #15803D; --signal-dim: rgba(21,128,61,0.14);
    --code-bg: #F0EEE9; --grain: 0.022;
  }
}
:root {
  --radius: 4px; --radius-lg: 8px; --radius-card: 10px; --radius-pill: 999px;
  --ease: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-std: cubic-bezier(0.4, 0, 0.2, 1);
  --dur-micro: 180ms; --dur-quick: 320ms; --dur-entrance: 560ms; --dur-draw: 900ms;
  --stagger: 80ms;
  --shadow-sm: 0 1px 2px rgb(0 0 0 / .25);
  --shadow-md: 0 4px 16px rgb(0 0 0 / .30);
  --shadow-lg: 0 18px 48px rgb(0 0 0 / .40);
  --shadow-glow: 0 6px 28px rgb(139 124 246 / .28);
  --wide: 1180px; --prose: 68ch; --gutter: clamp(1.25rem, 4vw, 3rem);
}
```

**Accent rule (binding).** Violet appears at most **four** times per viewport: the primary CTA, the
mono eyebrow dashes, the `01/02/03` step numbers, and the hero cable path. Green `--signal` is
**status only** — the travelling pulse, the live dot, the "Streaming 1080p30" chip. Green is never a
button, a border, or a heading. No other hue enters the page.

### 3.2 Typography

Self-hosted from `/web/fonts/`, **two files total**, both variable woff2, `latin` subset,
`font-display: swap`. Preload only the display face.

| Role | Stack | Notes |
|---|---|---|
| Display / headings / UI | `"Space Grotesk Variable", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif` | The Lyra display face; also already in the GotzendorferV2 font set for its technical sub-brand. ~38 KB subset. `@font-face { font-weight: 400 700 }` |
| Body prose | `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` | **Zero bytes.** Keeps the display/body split the family uses without spending a third file |
| Mono | `"JetBrains Mono Variable", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` | ~34 KB subset. Eyebrows, step numbers, stat labels, `code`, protocol terms |

Scale (clamp, no media queries at call sites):

| Token | Size | Line-height | Tracking |
|---|---|---|---|
| `--t-display` (h1) | `clamp(2.6rem, 7vw, 4.5rem)` | `1.03` | `-0.03em`, `text-wrap: balance` |
| `--t-h2` | `clamp(1.75rem, 4vw, 2.75rem)` | `1.12` | `-0.02em` |
| `--t-h3` | `clamp(1.15rem, 2vw, 1.375rem)` | `1.3` | `-0.01em` |
| `--t-lede` | `clamp(1.125rem, 1.6vw, 1.3125rem)` | `1.55` | `0`, `max-width: 54ch`, `--fg-muted` |
| `--t-body` | `1.0625rem` | `1.65` | `0`, `max-width: 68ch` |
| `--t-meta` | `0.8125rem` | `1.45` | `0.02em` |
| `--t-eyebrow` | `0.6875rem` mono 500 uppercase | `1` | `0.16em` |

Weights: display 600 for h1/h2, 500 for h3. Never 400 on a headline.

### 3.3 Grid & rhythm

Full-bleed `<section>`; each holds `.wrap { max-width: var(--wide); margin-inline: auto; padding-inline: var(--gutter) }`.
Section vertical rhythm: standard `padding-block: clamp(4rem, 9vw, 7rem)`; the two accent (dark-slab)
sections get `clamp(5rem, 11vw, 9rem)`. Prose blocks inside a wide section are capped at `--prose`.
Delete the site-wide 72ch cage and the `border-bottom` on every section — chapter breaks come from
surface changes, not hairlines. `[id] { scroll-margin-top: 5.5rem }`.

### 3.4 Sections, in order, with the job each does

| # | Section | Emotional job | Construction |
|---|---|---|---|
| 0 | **Header** | Stay out of the way | `position: sticky; top:0; background: color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter: blur(12px); border-bottom: 1px solid var(--border)`. The *only* glass on the page. Icon + wordmark left, 5 anchors right, `min-height: 44px` each |
| 1 | **Hero** | "Oh — the cable *is* the product" | Full-bleed, grain tile overlay. Asymmetric split `grid-template-columns: 1.05fr 0.95fr` (stacks < 900px). **Left, static, never animates on load:** eyebrow `— OPEN SOURCE · macOS · NO WI-FI` (mono, `h-px w-6` violet dash) → h1 `Your iPhone as an OBS camera, over the cable` with "over the cable" in `--accent` → lede → two CTAs → license/version meta line. **Right:** the signature — see §3.6. Below both, full-width: the `obs-iphone-live.png` in a **window-chrome frame**, revealed on scroll |
| 2 | **Proof strip** | Make the claim checkable in 3 seconds | One row, 5 cells, `gap: 1px; background: var(--border)` hairline grid (the agenticbuilders device). Each: big number in display 600 + mono uppercase caption. Values from `README.md`: **1 ms** ping RTT over USB · **~90 ms** to first frame · **~1.3 s** reconnect · **13 Mbit/s** HEVC · **30.0 fps / ~6 %** CPU. Below in `--t-meta`: "Measured on one setup — iPhone 15 Pro Max, M4 Pro, OBS 32.2.2. Yours will differ." Numbers **do not count up** (family rule: numbers that carry a claim never animate) |
| 3 | **Quick start** | "I could do this in five minutes" | Three `<article class="step">` cards, `--radius-card`, `bg: var(--card)`, `border: 1px solid var(--border)`, hover `translateY(-2px)` + `border-color: var(--border-strong)`. Each opens with a mono `01/02/03` in `--accent`. Step 2 carries the phone screenshots in a **device frame**, step 3 the OBS shots in **window chrome**. The `curl` one-liner gets a `<pre>` with a copy button (2 lines of JS, `navigator.clipboard`, label swaps to "Copied" for 1.6 s, `aria-live="polite"`) |
| 4 | **How it works** | "This is not magic, it is three boxes" | **Dark slab** — the chapter break. In light mode this section keeps the dark tokens (the `.surface-ink` device); in dark mode it steps to `--bg-elevated` with a `--border-strong` top edge so it still reads as a change. Contains the **animated data-path diagram**: recolor `docs/images/architecture.svg` to the tokens (drop the Tokyo-Night `#7aa2f7/#9ece6a/#e0af68`), inline it, and animate on scroll — see §3.6. Bullets below in two columns |
| 5 | **Download & requirements** | Remove the last doubt | Two-column: left the `.pkg` / `.zip` / releases list plus the terminal one-liner; right a requirements card (macOS 12+, OBS 30+, iOS 17+, a data-carrying cable) with mono labels and check marks that draw in |
| 6 | **FAQ** | Answer the objection before it is voiced | `<details>/<summary>` accordion, native — **no JS**. Each item is its own card (`--radius-card`, `bg: var(--card)`, `border`, `margin-bottom: .75rem`, `padding-inline: 1.25rem`). Chevron rotates 180° over `--dur-micro`. Content stays in the DOM for crawlers and the existing FAQPage JSON-LD. Keep all 8 current questions verbatim |
| 7 | **Source & license** | Prove the openness claim | Back to `--bg`. Repo links as a hairline grid; the GPL/MIT split spelled out |
| 8 | **Footer** | Close quietly | **Dark slab** (second and last), `--fg-muted` text, `border-top: 1px solid var(--border)`, built-by line linking `gotzendorfer.at`, the non-affiliation note, and a small `— TETHERCAM 0.1.0` mono mark |

**CTA hierarchy.** Exactly one primary per viewport. Primary = `background: var(--accent); color: var(--accent-fg); border-radius: var(--radius-lg); min-height: 48px; padding: 0 1.4rem; font-weight: 600; box-shadow: var(--shadow-glow)`, hover `translateY(-1px)` + brighter accent, with a `→` that moves `translateX(2px)` on hover. Secondary = `background: transparent; border: 1px solid var(--border-strong); color: var(--fg)`, hover `border-color: var(--accent)`. Tertiary = plain underlined links. The download `.pkg` is primary in the hero and in §5; everywhere else the primary slot is empty.

### 3.5 Image treatment

- **Phone screenshots** (`app-live.png`, `app-settings-sheet.png`): device frame — a wrapper with
  `background: #0B0C10; border-radius: 34px; padding: 9px; box-shadow: var(--shadow-lg)`, inner
  `border-radius: 26px; overflow: hidden`, plus a `6px × 46px` rounded notch bar centred at the top.
- **OBS / macOS screenshots** (`obs-iphone-live.png`, `obs-tools-menu.png`, `obs-plugin-properties.png`):
  window chrome — `border: 1px solid var(--border); border-radius: var(--radius-card)`, a `34px`
  title bar in `--bg-elevated` carrying three `10px` dots (`#FF5F57 #FEBC2E #28C840`) and the caption
  text in mono `--t-meta`, `box-shadow: var(--shadow-lg)`.
- All figures get `figcaption` in `--fg-muted` `--t-meta` (keep the existing wording, it is good).
- Grain: one **pre-baked 160×160 PNG/AVIF tile**, `position: absolute; inset: 0; pointer-events: none;
  opacity: var(--grain); mix-blend-mode: overlay; background-size: 160px`, on the hero and the two dark
  slabs only. **Do not** use a runtime `feTurbulence` filter — it became the LCP element on
  agenticbuilders-site and had to be ripped out (GitLab #66).

### 3.6 Motion spec

Curve `var(--ease)` everywhere except colour transitions, which use `var(--ease-std)`.

1. **Page load (hero only, CSS, no JS).** `.rise` keyframe: `opacity 0→1`, `translateY(18px)→0`,
   `var(--dur-entrance)`. Staggered by inline `style="--d:160ms"` → eyebrow 0, h1 **transform-only,
   no opacity, no delay** (LCP protection — copy the `.rise-lcp` trick), lede 160, CTAs 240, meta 320,
   signature panel 400 ms.
2. **Scroll reveal (JS).** One `IntersectionObserver`, `threshold: 0.15`, `rootMargin: 0px 0px -40px 0px`,
   `unobserve` on first entry. Elements carry `data-reveal`; the observer adds `.is-in`. Hidden state
   lives in a CSS class the reduced-motion query can override — **never** inline `style="opacity:0"`
   (EventDrop learned this the hard way). Group children stagger via `style="--d: calc(var(--i) * 80ms)"`.
   Arm the observer only after `matchMedia('(prefers-reduced-motion: reduce)').matches === false`;
   otherwise add `.is-in` to everything immediately.
3. **Signature animation — the live cable.** In the hero's right panel, an inline SVG (~200 lines,
   no image): a stylised iPhone silhouette on the left, a Mac/OBS window on the right, joined by a
   single bezier **USB-C cable path** (`stroke: var(--accent)`, `stroke-width: 2.5`, `stroke-linecap: round`,
   `fill:none`). On load the cable **draws itself** — `pathLength="1"`, `stroke-dasharray: 1`,
   `stroke-dashoffset: 1 → 0` over `var(--dur-draw)`. Once drawn, a **travelling pulse** rides it
   forever: a second, identical path on top in `var(--signal)` with
   `stroke-dasharray: 0.06 0.94; animation: pulse-travel 2.4s linear infinite` animating
   `stroke-dashoffset: 1 → 0`, plus a `<circle r="4" fill="var(--signal)">` on an `<animateMotion>`
   along the same path (`dur="2.4s" repeatCount="indefinite"`) with a soft
   `filter: drop-shadow(0 0 6px var(--signal))`. At the Mac end, the OBS window's inner rect fades
   between `--card` and a faint frame-preview fill in sync with each pulse arrival. This one element
   carries the whole page's personality: **the cable is alive and something is flowing through it.**
   Sibling motif: a `7px` `--signal` dot with `animation: breathe 4s ease-in-out infinite` (opacity
   `.45 → 1`) next to the words "Streaming 1080p30" in the hero eyebrow.
4. **Diagram on scroll (§4).** When the how-it-works slab enters, the inlined `architecture.svg`
   plays once: the three boxes rise+fade at `0 / 120 / 240 ms`, then the two arrow paths draw
   (`stroke-dashoffset`, `700ms`, sequential), then a single `--signal` pulse travels iPhone → usbmuxd
   → Mac over 1.4 s. Once, not looped — a looping diagram mid-page competes with the hero.
5. **Micro-interactions.** Cards and step tiles `transition: transform 180ms var(--ease), border-color 180ms var(--ease-std)`,
   hover `translateY(-2px)`. Nav and body links `transition: color 180ms`. Buttons as in §3.4.
   `<summary>` chevron `transform: rotate(180deg)` over `--dur-micro`. Copy button label swap.
6. **Reduced motion.** Two guards, both required.
   ```css
   @media (prefers-reduced-motion: reduce) {
     *, *::before, *::after {
       animation-duration: .01ms !important; animation-iteration-count: 1 !important;
       transition-duration: .01ms !important; scroll-behavior: auto !important;
     }
     [data-reveal] { opacity: 1 !important; transform: none !important; }
     .cable-pulse, .signal-dot { display: none; }      /* the pulse is decorative, remove it entirely */
     .cable-path { stroke-dashoffset: 0; }             /* show the cable already drawn */
   }
   ```
   `.01ms`, never `0` — `animationend`/`transitionend` must still fire.
   Plus the JS check in (2). Nothing on the page conveys meaning through motion alone: the live pulse
   is decorative, and every state it hints at is also stated in text.

### 3.7 Accessibility constraints

- Contrast AA minimum on every pair, AAA on body: verify `--fg/--bg` ≥ 12:1, `--fg-muted/--bg` ≥ 4.5:1,
  `--accent/--bg` ≥ 4.5:1 for text and ≥ 3:1 for the CTA fill, `--accent-fg/--accent` ≥ 4.5:1.
  Re-check `--signal` on both slab surfaces; if the green fails, darken the light-mode value further —
  do not lighten the dark one into neon.
- Focus: `:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; border-radius: var(--radius) }`,
  never removed, visible on the dark slabs too (swap to `--fg` there if the violet muddies).
- 48px minimum hit target on every link and button (already in the current CSS — keep it).
- Keep the skip link. Keep semantic `<section>/<article>/<h2>/<h3>` order; do not skip heading levels.
- Decorative SVGs get `aria-hidden="true"`; the architecture diagram keeps its `role="img"` +
  `<title>/<desc>` (already present and well written).
- `<details>` accordion is keyboard-native — do not replace it with div+JS.
- The copy button announces via `aria-live="polite"`.

### 3.8 Performance budget

| Item | Budget |
|---|---|
| Total page weight (HTML + CSS + JS + fonts + above-fold images) | **≤ 1.5 MB**, target ≤ 900 KB |
| External JS | **zero.** No CDN, no analytics, no font host. One same-origin `main.js`, **≤ 4 KB** unminified (observer + copy button, that is all) |
| CSS | one file, ≤ 22 KB |
| Fonts | **2 files**, ≤ 80 KB combined, self-hosted, `swap`, only the display face preloaded |
| Images | **currently `web/img/` is ~3.6 MB — this alone blows the budget.** Re-export every screenshot to AVIF with a PNG fallback via `<picture>`, cap the served width at 2× the CSS box, and `loading="lazy" decoding="async"` on everything except the hero. Target `web/img/` ≤ 800 KB |
| LCP element | the h1. It must ship in the static HTML, must not fade in, and must not wait on a font — hence `font-display: swap` and the transform-only hero rise |
| CLS | 0. Every `<img>` keeps its explicit `width`/`height` (already correct today) |

Keep everything already in the file that works: the JSON-LD blocks, the OG tags, the `hreflang`,
`vercel.json`'s cache headers, `llms.txt`, `humans.txt`, and the existing English copy. This is a
visual and structural rebuild, **not** a rewrite of the words.

---

## 4. Do-not list

1. **No second accent hue.** Violet + one status green. No blue, no orange, no teal, no gradient ramp between them.
2. **No mesh gradients, aurora blobs, or animated background gradients.** Nothing in this family has one; it would read as an AI-generated template immediately.
3. **No glassmorphism** beyond the single sticky header. No frosted cards, no `backdrop-blur` on tiles.
4. **No pure `#FFFFFF` page background and no pure `#000000`.** Both modes stay tinted.
5. **No runtime `feTurbulence` grain** — pre-baked tile only (it became the LCP element elsewhere).
6. **Do not animate the h1's opacity**, and do not animate the proof-strip numbers. Claims that carry evidence appear instantly and completely.
7. **No inline `style="opacity:0"`** for reveal hidden states — a reduced-motion user would get a blank page.
8. **No `animation-duration: 0`** in the reduced-motion block; `.01ms`.
9. **No parallax, bounce, spring, spin, or infinite pulse anywhere except the one hero cable pulse and the one live dot.** Two looping animations on the page, maximum.
10. **No external requests at all** — no Google Fonts link, no CDN script, no third-party analytics. The page must render fully offline from its own origin.
11. **No mono for prose** and no display face below 1.1rem.
12. **Do not replace `<details>` with a JS accordion**, and do not hide FAQ answers from the DOM — the FAQPage JSON-LD must stay truthful.
13. **Do not overstate the numbers.** The "measured on one setup" caveat travels with the proof strip; it is a credibility asset, not fine print to be dropped.
14. **No dark-mode toggle.** `prefers-color-scheme` only; the existing `<meta name="theme-color">` pair already matches.

---

## 5. Assets available

`web/img/` — served today (sizes are the current, unoptimised PNGs):

| File | Dimensions | Size | Use |
|---|---|---|---|
| `obs-iphone-live.png` | 1600 × 1166 | 788 K | Hero, window chrome. The money shot |
| `app-live.png` | 1400 × 646 | 928 K | Step 2, device frame. **Worst offender — re-export** |
| `app-settings-sheet.png` | 1600 × 738 | 100 K | Step 2, device frame |
| `obs-tools-menu.png` | 900 × 480 | 252 K | Step 3, window chrome |
| `obs-plugin-properties.png` | 1084 × 1400 | 844 K | Step 3, window chrome (tall) |
| `icon-192.png` / `icon-512.png` | 192² / 512² | 44 K / 264 K | Wordmark, manifest |
| `og.png` | 1200 × 630 | 404 K | Social card, unchanged |

`docs/images/` — higher-resolution masters to re-export from, not to link directly:

| File | Dimensions | Size |
|---|---|---|
| `app-live.png` | 2796 × 1290 | 3.3 M |
| `obs-plugin-properties.png` | 1440 × 1860 | 1.2 M |
| `obs-simulator.png` | 1600 × 1166 | 336 K |
| `tethercam-icon-1024.png` / `-256.png` | 1254² / 256² | 1.5 M / 68 K |
| **`architecture.svg`** | 980 × 330 | 4 K |

`docs/images/architecture.svg` is the important one: it is already a clean, hand-authored,
accessible SVG with `role="img"`, `<title>` and `<desc>`, three boxes, two marker-ended arrows and
mono labels. **Inline it into §4, replace its hardcoded Tokyo-Night colours
(`#7aa2f7 / #9ece6a / #e0af68 / #8b93a7`) with `var(--accent)`, `var(--signal)`, `var(--fg-muted)`,
`var(--border-strong)`, and animate it as specified in §3.6(4).** It is the single highest-value
asset on the page and today it is not used on the site at all.

Still to create: `web/fonts/space-grotesk-var.woff2`, `web/fonts/jetbrains-mono-var.woff2`,
`web/img/grain.png` (160 × 160 tile), and the AVIF re-exports.
