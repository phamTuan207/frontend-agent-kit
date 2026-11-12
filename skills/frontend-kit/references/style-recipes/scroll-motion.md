# Recipe: Scroll motion — the refined bar (Anthropic / Apple / SpaceX + award sites)

## Sources (observed 2026-11-10)

Live observation with headless Chrome 140 (CDP) at 1440×900 and 390×844,
plus the user's own screenshots of anthropic.com. Screenshots:
`templates/design/references/motion/`. Every number below was measured
on the live site that day; anything not measured is labelled
DOCUMENTED (library docs) or UNOBSERVED.

- **Anchor, measured:** anthropic.com (full wordmark condense + hero-card
  expand, geometry measured at scroll 0–900 — see Patterns 1–2);
  apple.com (fixed 44px nav, full-bleed stacked sections);
  spacex.com (full-viewport video sections, scroll height 7518px at
  1440×900); openai.com — UNOBSERVED (Cloudflare "Just a moment…"
  challenge page; `openai-top-1440-cloudflare-blocked.png` records it).
- **Award sites, measured:** scoutmotors.com (Lenis in page HTML; hero
  image scale 1.09 → 1.00 over the first scroll); victorfuruya.com
  (Lenis in page HTML; hero image scale 1.69 → 1.15); landonorris.com
  (Lenis in page HTML; loader "LOAD NORRIS" never completed in headless
  — visual motion UNOBSERVED); lenis.studiofreight.com now redirects
  to studiofreight.com (Lenis in page HTML; minimal single screen).
- **Library examples, loaded:** examples.motion.dev/react/scroll-linked
  (Motion / framer-motion in page HTML; reduced-motion rule present).
- **DOCUMENTED (library docs, read via Google search 2026-11-10, not
  live-measured):** GSAP ScrollTrigger patterns (scrub / pin / parallax
  ranges — lab.good-fella.com, motionkit.io); Lenis setup
  (`new Lenis({ autoRaf: true })`, lerp smoothing, reduced-motion
  honoured automatically in 1.3.x); Motion `useScroll` + `useTransform`
  and `whileInView` (motion.dev examples + skill docs).
- **UNOBSERVED:** GSAP CodePen parallax demo (Cloudflare challenge);
  eclettica.bulgari.com, storytelling.noomoagency.com, studionamma.com
  (blank / never painted in headless — no pattern taken from them).
  By-Kin and the other Awwwards winners were surveyed only as
  secondary write-ups (case-study / roundup text); no pattern in this
  file rests on them alone.
- **User's taste input (2026-11-10 22:31):** the bar is big-company
  sites — Anthropic, OpenAI, SpaceX, Apple — "refined and beautiful,
  with very nice subtle scroll-driven motion: enough but not cluttered".
  The two Anthropic patterns are his named examples; they are Patterns
  1–2 below, with his screenshots as the reference captures
  (`anthropic-top-user-1440.png`, `anthropic-scrolled-user-1440.png`).

## School

Restraint as the direction. The page earns its motion the way the
Aesop recipe earns its colour: one or two deliberate moments, everything
else still. Motion is a change of state the reader can follow, never
decoration the reader has to endure.

## Best for

Landing pages and product pages that need to feel expensive. Dashboards
and dense app screens: no scroll motion beyond the fixed header — the
page is a tool, not a film.

## The bar (what "refined" means, in checkable terms)

- **One moving thing per viewport.** At any scroll position, at most
  one element is mid-transform. Anthropic at scroll 300: only the hero
  card is changing (its clip insets); the header, the intro text, the
  cards below are all still.
- **Small distances.** Reveals rise ≤24px. Hero settle scales ≤1.08.
  Parallax layers move ≤200px over a full viewport of scroll.
- **Short durations.** Reveals finish in ≤420ms (`--motion-slow`).
  Scroll-linked (scrubbed) motion has no duration at all — it is
  bound to scroll position, `ease: 'none'`.
- **One scroll range per effect.** A scroll-linked transform completes
  inside ~300px of scrolling (Anthropic's hero completes at ~300px),
  then stays done. Nothing keeps moving for the whole page.
- **The header is the only permanent motion.** It is fixed or sticky,
  and at most it condenses (Pattern 1). It never slides, bounces, or
  re-lays-out.

## Patterns

### Pattern 1 — Condensing wordmark (Anthropic, user-named)

- **What it is:** the header wordmark "ANTHROP\C" is written out in
  full at the top of the page; on scroll it condenses to just the
  "A\" mark. The header itself does not move, shrink, or change
  colour — only the mark changes.
- **Measured (anthropic.com, 2026-11-10, 1440px):** header is
  `position: sticky`, 84px tall, background `#faf9f5`, no backdrop
  blur, `transition: 0.3s / transform` only. At scroll 0 the visible
  mark is a static SVG, class `ZrbDXq_logo-static`, viewBox
  `0 0 570 64`, 170×24 at x=628. At scroll 900 the header shows a
  different element: a Lottie logo, viewBox `0 0 143 16`, in a 170×24
  box at x=699, parent class `ZrbDXq_logo-lottie`. The swap is a DOM
  swap (static SVG out, Lottie in), not a width animation — the home
  link stays 170×24 throughout. The exact scroll threshold of the
  swap is UNOBSERVED (seen between 0 and 900); builders pick their
  own (120px is a sane default). At 390px the same condensed mark
  shows top-left with "Try Claude" + search + menu (`anthropic-scrolled-390.png`).
- **Why it works:** the header keeps its height and its layout; the
  nav pills never reflow. Only the centre mark changes, and it
  changes once. The reader's eye never has to re-find anything.
- **Build it:** two logo variants (full + mark) in the header; swap
  on a scroll threshold with a single class toggle; no width/height
  animation on the header itself. Never animate the nav links.
  Implementation skill: none — a vanilla class toggle; no GSAP skill,
  no threeui.

### Pattern 2 — Expanding hero card → full-bleed (Anthropic, user-named)

- **What it is:** the hero video starts as a floating card with
  margins and rounded corners; on scroll it expands to full-bleed,
  touching the viewport edges. The video itself never scales or
  moves — the *card's clip* grows.
- **Measured (anthropic.com, 2026-11-10, 1440px):** the card wrapper
  (`._1cyytq_card`) carries an inline custom property `--scroll-grow`
  set by script from scroll position: `0` at scroll 0, `0.359` at
  100px, `0.730` at 200px, `0.992` at 300px, `1` from 400px on. The
  card's `clip-path: inset()` interpolates from that variable:
  `inset(0px 78.5px 47.1px round 3.9px)` at scroll 0 →
  `inset(0px 36.4px 21.8px round 1.8px)` at 150px →
  `inset(0px 0.6px 0.3px round 0.03px)` at 300px (effectively
  full-bleed). The video, its media wrapper, and the frame keep a
  constant 1425×802 layout box with `radius: 0px` and no transition
  (`transition: 0s`) — the motion is the clip, scrubbed per scroll
  frame, not a CSS transition. At 390px the same expansion is visible
  (card → edge-to-edge video, pause control bottom-right).
- **Why it works:** one property (`--scroll-grow`) drives one visual
  (the clip). The content inside never reflows; the video never
  resizes. The effect completes in ~300px of scrolling and then stops.
- **Build it:** a hero card whose `clip-path: inset()` is driven by a
  `--scroll-grow: 0→1` custom property over the first ~300px of
  scroll (set it from an `IntersectionObserver` + scroll listener, or
  from GSAP ScrollTrigger `scrub: true` — read
  `vendor/gsap/gsap-scrolltrigger/SKILL.md` before implementing;
  vanilla `IntersectionObserver` + scroll listener is the only
  alternative, and the choice is recorded in the Design Read).
  Horizontal inset ~64–80px → 0, bottom inset ~48px → 0, radius
  ~4px → 0. Do not animate width/height/margin on the card — those
  reflow; clip does not.

### Pattern 3 — Hero settle: scale-on-scroll (Scout Motors, Victor Furuya)

- **What it is:** the hero image starts slightly zoomed in and
  settles to 1:1 as you scroll past it. The image never moves
  sideways; it only de-zooms.
- **Measured:** Scout Motors hero image `transform: scale(1.09053)`
  at scroll 0 → `scale(1)` at scroll 900. Victor Furuya hero image
  `scale(1.6932)` at scroll 0 → `scale(1.1499)` at scroll 900
  (a portfolio extreme — the 1.69 start is the outer bound seen, not
  the default). Both pages carry Lenis in their HTML. Both use a
  fixed header (Scout: white bar; Victor: 46px minimal nav).
- **Why it works:** the scale change is slow (bound to scroll, not
  timed), small at the restrained end (≤1.09), and it is the only
  thing moving in the hero. The text over it stays still.
- **Build it:** `transform: scale(1.08) → scale(1)`, scrubbed to
  scroll over the hero's own height, `ease: 'none'`, `transform-origin:
  center`. Never scale text with the image. Never combine with
  Pattern 2 on the same hero — one hero moment per page.
  Implementation skill: `vendor/gsap/gsap-scrolltrigger/SKILL.md` —
  the scale is scrubbed to scroll, so it is a ScrollTrigger scrub.

### Pattern 4 — Full-viewport stacked sections (SpaceX, Apple)

- **What it is:** the page is a stack of full-viewport bands, one
  product (or one launch) per band, alternating light/dark. The
  scroll motion is the *structure*: each band fills the screen, so
  scrolling feels like turning pages. Nothing inside a band moves
  while you read it.
- **Measured:** SpaceX hero video is exactly one viewport
  (1425×900 at 0,0); page height 7518px ≈ 8 viewports; 1 fixed
  element (the nav), 27 elements with transitions. Apple nav is
  `position: fixed`, 44px; hero imagery is full-bleed and centred by
  a translate transform (`matrix(1,0,0,1,-1280,0)` on a 2560px-wide
  image); 559 elements carry transitions (mostly hover states),
  6 animated.
- **Why it works:** the bands do the pacing, so no element needs to
  animate to create rhythm. The fixed nav is the only chrome that
  persists.
- **Build it:** one section per viewport (the kit's Layout axis
  already demands this for landings); a fixed header; bands
  alternate canvas/surface. No reveals inside a band beyond Pattern 5
  (one per band, max). Implementation skill: none — layout, not
  animation; no GSAP skill, no threeui.

### Pattern 5 — Reveal-on-scroll (fade + short rise)

- **What it is:** a section's content fades in and rises a short
  distance as it enters the viewport, once, and never replays.
- **Status — KIT PRESCRIPTION, not a measured reference value.** No
  reference site yielded a measured reveal duration in this run:
  headless instant scrolling jumps past the transition, so the live
  reveal itself was not captured frame-by-frame; cards were observed
  fully rendered after scroll on every loaded site. The values below
  are the kit's prescription, chosen to match the observed restraint
  and the Motion docs' `whileInView` example (initial
  `{ opacity: 0, y: 20 }` → `{ opacity: 1, y: 0 }`,
  `viewport={{ once: true, margin: '-100px' }}`,
  `transition={{ duration: 0.4, ease: 'easeOut' }}` — DOCUMENTED,
  motion.dev / Motion skill docs, read 2026-11-10).
- **Prescription:** `opacity 0 → 1`, `translateY(24px) → 0`,
  `420ms` (`--motion-slow`), `cubic-bezier(0.22, 1, 0.36, 1)`
  (`--motion-ease`), trigger when the element's top crosses ~85% of
  the viewport, `once: true` (never replays on scroll-up). One reveal
  per section, at most — never stagger a whole grid (if a grid must
  stagger, cap it at 3 items, 60ms apart, and the grid counts as the
  section's one moment — the gate counts animated parts, so the grid
  must move as ONE wrapped part, a single fade/rise on the grid
  container, to count as one; separately animated items are separate
  reveals).
- **Build it:** `IntersectionObserver` with `threshold: 0.15` and
  `rootMargin: '0px 0px -15% 0px'`, adding one class; or GSAP
  ScrollTrigger `toggleActions: 'play none none none'` (see
  `vendor/gsap/gsap-scrolltrigger/SKILL.md`); or Motion
  `whileInView` (React). Never use a scroll listener that sets
  `style.opacity` per frame for reveals — that is what scrubbing is
  for (Patterns 2–3); reveals are state changes, not scrubbed values.
- **The gate (D16):** `scroll-reveal` allows exactly this recipe —
  one reveal per section, a fade (from opacity 0) and/or a rise of
  24px at most, played once, ending at rest. Anything past it (a
  second reveal in the section, a rise over 24px, a slide, turn,
  scale or unmask, a replay) FAILs as before. The allowance is in
  `scroll-reveal` ONLY: `hidden-content` has no carve-out, so the
  pre-reveal state must never be the plain-CSS state — put it under
  a class the script adds on its live path (progressive
  enhancement), or a script that never runs and reduced-motion
  readers leave the section blank and the page FAILs
  `hidden-content` instead.

### Pattern 6 — Pinned / sticky section (sticky storytelling)

- **What it is:** a section pins in place while its content changes
  inside the pinned frame — the scroll drives a sequence, not a page
  move. The classic use is a step-by-step product explainer or a
  before/after.
- **Status — DOCUMENTED, not live-observed in action.** Sticky
  elements were counted live (Anthropic 1, Scout 4, Lando Norris 4,
  Victor Furuya 1, all at 1440px) and the pattern is the GSAP
  ScrollTrigger pin (DOCUMENTED: `pin: true`, `scrub: 1`,
  `end: '+=' + container.offsetWidth` for horizontal; gsap.com /
  lab.good-fella.com, read 2026-11-10), but no pinned sequence was
  captured mid-pin in this run, so no site is cited as the pin
  exemplar. The implementation detail lives in
  `vendor/gsap/gsap-scrolltrigger/SKILL.md` (pin/scrub).
- **Prescription:** at most ONE pinned section per page; pin distance
  ≤ 2 viewports of scroll; the pinned content changes by discrete
  steps (not continuous motion); a calm section follows it. Never pin
  on mobile (≤768px the pinned section becomes a normal stacked
  section). Never stack two pinned sections.

### Pattern 7 — Smooth scroll (Lenis)

- **What it is:** wheel/trackpad scrolling glides to its target
  instead of jumping — the page feels weighted. It is a *feel* layer,
  not a visible effect: nothing on the page moves except the scroll
  position itself, eased.
- **Observed:** the string `lenis` appears in the page HTML of
  landonorris.com, scoutmotors.com, victorfuruya.com and
  studiofreight.com (the current home of the old Lenis demo URL).
  The glide itself is not measurable in headless instant scrolling —
  presence is verified, feel is not.
- **DOCUMENTED (upstream Lenis docs, https://github.com/darkroomengineering/lenis, read 2026-11-10):** `npm i lenis`,
  `new Lenis({ autoRaf: true })` (or `anchors: true`); ~3kB
  gzipped; it keeps the browser's native scroll position and only
  eases wheel/trackpad input toward the target (lerp), so sticky
  headers, anchor links and keyboard scrolling keep working; drive
  it from the GSAP ticker when combined with ScrollTrigger
  (`lenis.on('scroll', ScrollTrigger.update)`); Lenis 1.3.x honours
  `prefers-reduced-motion` automatically (never start it when the
  setting is on). Skip Lenis on dashboards, docs and data tables —
  readers there expect the page to stop the instant their finger does.
  **Kind-scope warning:** on place/service/non-technical-product pages
  the textual Lenis signal FAILs effect-kind `scroll`
  (`scripts/gate/consistency.mjs:1215`) — a Lenis mention on such a
  page is not evidence of scroll motion, and "skip on dashboards,
  docs and data tables" is not the whole scope; do not route Pattern 7
  on kind alone (see `SKILL.md` Pattern 7 routing).
- **Build it:** Lenis only, never Lenis + `scroll-behavior: smooth`
  (the CSS property only affects navigation scrolls, not user
  scrolls, and the two fight). If the page has no scrubbed pattern
  (2, 3, 6) and no pinned section, Lenis alone is not enough motion
  to matter — do not add it for feel alone on a short page.

### Pattern 8 — Parallax layers (background slower than foreground)

- **What it is:** background and foreground layers move at different
  rates as you scroll, giving depth. The subtle version is nearly
  invisible: the background drifts a little while the foreground
  reads normally.
- **Status — DOCUMENTED, not live-measured.** No parallax transform
  was measured on any site in this run. Ranges below are from the
  GSAP ScrollTrigger docs (DOCUMENTED, lab.good-fella.com /
  motionkit.io, read 2026-11-10): background `-80px` to `-120px`
  over a full viewport of scroll, foreground `-150px` to `-200px`,
  `scrub: 1`, `ease: 'none'`. The Bulgari "Emerald Strata" roundup
  note (secondary write-up, not live-visited) describes the same
  idea as "layered backgrounds shift at different speeds".
- **Implementation skill:** `vendor/gsap/gsap-scrolltrigger/SKILL.md`.

### 3D hero (ThreeUI catalog component)

Patterns 1–8 cover scroll motion only. A brief that wants a 3D or
shader hero moment uses a named component from the ThreeUI catalog:
read `skills/threeui/SKILL.md` before implementing, and name the
component in the Design Read (SKILL.md step 1.2). threeui is a
component catalog, not a general Three.js skill — do not invoke it
for general Three.js work.
- **Prescription:** at most two layers; total travel ≤200px; only
  `transform: translateY` (never `background-position` — it repaints);
  never parallax text. If the travel is visible as "movement" rather
  than felt as "depth", it is too much — halve it.

### Effect sources — GetLayers free AI design tools (optional)

Patterns 1–8 and the ThreeUI hero above name the motion. Where an
effect itself — not a scroll pattern — needs a source, the 13 free
GetLayers AI design tools in the browser are an optional effect
source. Full list, names, and the free/paid boundary:
`references/getlayers.md` §3. The 13, by name: Text Animations,
Custom Cursors, ASCII Studio, Particle Forms, Holographic Cloth,
Image Compressor, Image Motion, SVG to 3D, Refract, Liquid Colour,
Orb Studio, Dither Art, Shader Backgrounds.

- **Free in the browser:** every tool is free to run, tune, copy,
  and download, signed out included; saving a look needs a free
  account — https://www.getlayers.ai/docs (accessed 2026-11-11).
  Pick a preset in the tool, preview it, copy the prompt that
  rebuilds it, and build the effect from that prompt. The prompt
  text itself was not observed via text fetch
  (`references/getlayers.md` §2.3) — do not describe it.
- **An effect is still one dealt moment.** A tool-supplied effect
  counts as one of the page's 1–2 dealt moments (restraint rule 1)
  and obeys every restraint rule in this file: transform/opacity
  only, once and short, reduced motion respected, mobile calmer.
  Naming a tool never exempts its effect from the bar.
- **Mutual exclusions.** A page with a GetLayers effect carries neither
  an animated icon nor an animated Grainient gradient — and one
  background treatment per page: a GetLayers background effect and a
  Grainient gradient background do not stack.
- **Image Compressor is a utility, not an effect source.** It
  compresses images and has no saved looks; it supplies no visual
  effect.
- **Record it in the Design Read** on its own line (`Effect source:
  GetLayers <tool name> — free in-browser tool`), per SKILL.md step
  1.2. No tool named = no tool effect.
- **Browser route only.** Agent use of these tools via the MCP is
  paid-only (Full Stack Lifetime — `references/getlayers.md` §9);
  the kit never routes an effect through the MCP. Only 12 of the 13
  tools work via MCP at all (Image Compressor does not).

### Effect sources — animated icons (optional)

Patterns 1–8 and the ThreeUI hero above name the motion. Where an
animated icon itself — not a scroll pattern — is the effect, the
free animated-icon sources are an optional effect source. Full
per-source table, licences, and the embedding rules:
`references/animated-icons.md`. Default source: useAnimations (MIT,
300 micro-icons, agent-readable catalog); LottieFiles (≈5,900 free
icons) and Lordicon (9,700+ free, attribution required) only when
the brief needs an icon useAnimations does not have.

- **One icon consumes one unit of the dealt-moment budget.** An
  animated icon counts as one unit of the page's 1–2 dealt-moment
  budget (restraint rule 1) — it consumes budget but does not satisfy
  the gate's dealt-moment requirement (the gate counts only
  `[data-moment]` sections mounted by moments.js) — and obeys every
  restraint rule in this file: transform/opacity only, once and
  short, reduced motion respected, mobile calmer.
  `references/animated-icons.md` §4 states the cap plainly: at most
  1–2 animated icons per build, loop only loaders, hover/click icons
  play once per trigger and stop. Naming a source never exempts its
  icon from the bar.
- **Mutual exclusions.** A page with a GetLayers effect carries no icon;
  a page with an animated icon carries no GetLayers effect and no
  animated gradient.
- **Embedding (kit shape):** lottie-web 5.13.0 pinned jsDelivr +
  SVG renderer + inline `animationData`, static SVG rendered in the
  container first (replaced on `DOMLoaded`, kept on load error),
  reduced motion wired by hand (`matchMedia` +
  `goToAndStop(0, true)`, re-checked on change) —
  `references/animated-icons.md` §3. Never
  `@lottiefiles/lottie-player` / `<lottie-player>` (deprecated;
  versions 2.0.5–2.0.7 compromised Oct 2024) and never any `@latest`
  CDN URL — always pin exact versions. dotLottie-wc is not the
  single-icon player (~500 kB WASM, canvas rendering loses
  `currentColor`).
- **Record it in the Design Read** on its own line, in this format:
  `Effect source: <source> <icon name> — <licence>, <player/route>`
  — one worked example per authorised source: `Effect source:
  useAnimations arrow-right — MIT, Lottie JSON inlined via lottie-web
  5.13.0`; `Effect source: LottieFiles <icon name> — Lottie Simple
  License, Lottie JSON via dotLottie-wc / DotLottie JS API (free
  account required to download)`; `Effect source: Lordicon <icon
  name> — free licence based on CC BY-ND 4.0 (modified),
  @lordicon/element, self-hosted JSON — attribution link in the
  footer: <a href="https://lordicon.com/">Animated icons by
  Lordicon.com</a>`, per SKILL.md step 1.2. No icon named = no
  animated icon.

### Effect sources — Grainient gradients (optional)

Patterns 1–8 and the ThreeUI hero above name the motion. Where a
gradient background itself — not a scroll pattern — is the effect, a
Grainient gradient is an optional effect source. Full per-source
detail, licence, and the free/paid boundary:
`references/design-galleries.md` §1. Reference-only: the agent picks
one gradient and recreates its feel as CSS tokens — it never copies or
downloads a Grainient file into the build.

- **A still gradient is a background token, not a moment; an animated
  gradient is the motion moment.** A still Grainient background consumes
  no budget and is placement-restrained to the hero (never on every
  section) — it is ambient depth, not a located moment, so restraint
  rule 1's section-separation does not apply to it. An animated
  gradient counts as one of the page's 1–2 dealt moments (restraint
  rule 1) and obeys rules 1–2 like a scroll moment — it replaces, not
  adds to, a scroll-motion moment. A page with a GetLayers effect
  carries no animated Grainient gradient, and one background treatment
  per page: a Grainient gradient background and a GetLayers background
  effect do not stack. Naming a gradient never exempts its effect from
  the bar.
- **Gate caveat: neither satisfies moment-none.** A gradient — still or
  animated — is not a `[data-moment]` / `[data-scroll-moment]` section;
  the gate counts only sections mounted by moments.js. The checker
  emits moment-none as WARN (`scripts/gate/consistency.mjs:1199-1201`)
  and no gate code promotes it to FAIL, so a page whose only effects
  are gradients and/or animated icons passes leg 2 with the WARN
  outstanding — requiring a mounted moments.js moment is a house rule,
  not a gate FAIL. Clear it with a mounted moments.js moment in its own
  section, which is itself one of the page's 2 budget units
  (`references/design-galleries.md` §4).
- **Record it in the Design Read** — a still gradient on the Gradient
  source line (`Gradient source: Grainient — <gradient description> —
  recreated as CSS tokens, hero background only`), an animated gradient
  on the Effect source line (`Effect source: Grainient <gradient
  description> (animated) — recreated as CSS tokens, no file copied`),
  per SKILL.md step 1.2. No gradient named = no gradient background.
- **No price, no purchase.** Grainient prices were not readable on
  primary and secondaries disagree — do not quote a price; the loop's
  reference-only use needs no purchase and no download
  (`references/design-galleries.md` §1.3).

## Motion tokens (copy-ready)

Add to `tokens.css` at the taste lock (the lock replaces the starter
values with the reference's own; the snippet below is the starter).
It extends the existing motion tokens (`--motion-fast: 120ms`,
`--motion-base: 220ms`, `--motion-slow: 420ms`,
`--motion-ease: cubic-bezier(0.22, 1, 0.36, 1)`), which stay
unchanged.

```css
/* --- Motion: scroll (starter — the taste lock replaces these) --- */
--motion-reveal-distance: 24px;   /* Pattern 5: max rise on reveal */
--motion-reveal-duration: var(--motion-slow); /* 420ms, once */
--motion-scroll-range: 300px;     /* Patterns 2–3: scroll distance
                                     over which a scroll-linked
                                     transform completes (Anthropic
                                     hero: ~300px, measured) */
--motion-hero-scale: 1.08;        /* Pattern 3: max hero settle scale
                                     (Scout measured 1.09; Victor's
                                     1.69 is the outer bound, not the
                                     default) */
--motion-clip-inset-x: 72px;      /* Pattern 2: hero card horizontal
                                     inset at rest (Anthropic measured
                                     78.5px at 1440px; 72px = the kit's
                                     container margin) */
--motion-clip-inset-b: 48px;      /* Pattern 2: hero card bottom inset
                                     at rest (Anthropic measured 47px) */
--motion-clip-radius: 4px;        /* Pattern 2: hero card radius at
                                     rest (Anthropic measured 3.9px) */
--motion-parallax-bg: -100px;     /* Pattern 8: background travel per
                                     viewport of scroll */
--motion-parallax-fg: -180px;     /* Pattern 8: foreground travel */
```

Scrubbed (scroll-linked) transforms always use `ease: 'none'` — the
scroll position is the easing. Timed transitions (reveals, hovers,
state changes) always use `var(--motion-ease)`. Never invent a third
easing.

## Restraint rules (hard — the bar, not advice)

1. **At most 1–2 dealt moments per page** (the motion expert's rule,
   `experts/motion.md` criterion 2 — the recipe picks the moments,
   the expert judges them). One hero moment (Pattern 2 OR 3, never
   both) + at most one pinned section (Pattern 6) OR reveals
   (Pattern 5) elsewhere. Never two moments in one section or in
   neighbouring sections; a calm section between them; the back third
   of the page calm before the close. The budget counts motion /
   attention effects (scroll patterns, GetLayers effects, animated
   icons, animated gradients, moments.js moments). A still gradient
   background is a background token, not a moment: it consumes no
   budget and this rule's section-separation does not apply to it —
   but it is placement-restrained to the hero
   (`references/design-galleries.md` §4).
2. **One moving element per viewport.** If two things visibly move at
   the same scroll position, remove one.
3. **Transform and opacity only.** No animated width, height, margin,
   padding, top/left, or `background-position`. Clip-path inset is the
   one exception (Pattern 2) — it does not reflow.
4. **Reveals are once and short.** `once: true`, ≤24px, ≤420ms.
   Nothing replays on scroll-up; nothing loops except a hero video
   or a loader icon (a hero video is pausable, with a visible pause
   control — Anthropic shows one bottom-right of the hero).
5. **Scrubbed motion completes fast.** A scroll-linked transform
   finishes inside ~300px of scrolling, then stays done. A transform
   that is still changing a full viewport later is a bug, not a feature.
6. **Mobile is calmer, not busier.** ≤768px: no pinned sections, no
   parallax, hero scale ≤1.04, reveals unchanged. The Anthropic
   patterns hold at 390px (condensed mark + full-bleed hero observed),
   but nothing is added there.
7. **Reduced motion is respected, always.** With
   `prefers-reduced-motion: reduce`, all of this collapses to instant
   state changes: no reveals, no parallax, no hero scale, no clip
   growth, no Lenis, no autoplay. The kit's `tokens.css` already
   zeroes `--motion-fast/base/slow` under the media query — the
   scroll patterns must read the same query (skip the
   `--scroll-grow` update; render the final state). Anthropic,
   Scout Motors and the Motion example all ship a
   `prefers-reduced-motion` rule in their stylesheets (measured
   2026-11-10); Apple and SpaceX did not show one in their
   accessible stylesheets — the kit's rule is stricter than theirs,
   and stays.
8. **No autoplay that fights the reader.** A hero video may autoplay
   only if it is pausable and stops on interaction; no autoplaying
   carousel or marquee while the reader is reading.

## Anti-patterns (do not do these in this direction)

- A reveal on every element ("everything flies in") — the page
  reads as a demo reel, not a product.
- Parallax on text, or parallax travel over 200px — the 2013 look.
- Two hero moments (expanding card AND scaling image AND a pinned
  intro) — pick one.
- A scroll-linked transform that never completes (still changing a
  viewport later) or one driven by a timed transition instead of the
  scroll position (it will lag the scroll and feel broken).
- Lenis on a dashboard, docs page, or data table.
- A pinned section on mobile.
- Motion that only exists in the demo video: if the gate screenshots
  (1440/768/390, static) cannot show the motion's rest state, the
  motion is ungradeable — the builder proves it with the demo page
  and the run log notes the pattern by name.

## How to use this recipe (step 1)

1. The brief names a motion direction (or the Design Read points at
   one): read this ONE file (plus the anchor style recipe, if any).
2. Pick at most two patterns from the list above and name them in the
   Design Read (DESIGN-READ.md) — by pattern name and number, e.g.
   "Pattern 2 (expanding hero card) + Pattern 5 (reveals)".
   No pattern named = no motion beyond the fixed header and hover
   states. A build that adds motion no pattern names is direction
   drift, not initiative.
3. Derive the concrete values from the locked reference into
   `tokens.css` (the snippet above is the starter). The recipe's
   restraint rules are the check on that derivation: if the locked
   tokens reproduce an anti-pattern, the lock is wrong, not the recipe.
4. After P10 merges, variant briefs name the motion patterns per
   variant the same way they name the style anchor — a variant that
   needs a different hero moment says so in its brief; the recipe
   does not change per variant, the *choice* does.

## What this recipe does NOT do

- It does not judge motion. `experts/motion.md` carries the criteria
  (durations from tokens, one-or-two moments, motion helps
  understanding, reduced motion, states, no shift/jank, no fighting
  autoplay) and the 1–5 domain score. If this recipe and the expert
  brief disagree, the expert brief governs the grade and this file
  is fixed.
- It does not teach the libraries. GSAP ScrollTrigger pin/scrub
  detail lives in `vendor/gsap/gsap-scrolltrigger/SKILL.md`
  (timelines in `vendor/gsap/gsap-timeline/SKILL.md`; performance in
  `vendor/gsap/gsap-performance/SKILL.md`); Lenis setup lives in the
  upstream Lenis docs at https://github.com/darkroomengineering/lenis
  (no vendored Lenis doc exists in the kit); Motion
  `useScroll`/`whileInView` lives in the Motion docs at
  https://motion.dev/docs/react-scroll-animations. This file names
  the pattern and its restraint, and points at the implementation.
- It does not set the grade. Motion has no axis (see the grading
  proposal in `build-notes/w-motion.md`); motion is graded as evidence
  under Layout by the judge, with the motion expert as second opinion
  (see `skills/frontend-kit/references/grader-rubric.md`).

## Values

Derive them from the locked reference (the reference screenshots in
`templates/design/references/motion/` or a vendored DESIGN.md), not
from memory: the hero's rest inset and radius, the reveal distance,
the scroll range. Do not ship a number as "Anthropic's" or "Apple's"
without checking it against the live site — the kit's standing rule
for vendored values applies here too. Where this file gives a number
with a site's name on it, the number was measured on that site on
2026-11-10 and the measurement is recorded in
`build-notes/w-motion.md`.
