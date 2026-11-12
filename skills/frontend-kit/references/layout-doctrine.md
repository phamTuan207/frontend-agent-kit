# Layout doctrine — what the checker measures, and how to build so it passes

Source: `scripts/gate/consistency.mjs` (vendored taste-skill 2.5.1), section-rhythm
rules SR-1–SR-8 + the `no-visual` / `empty-area` / `product-shown` checks.
Added 2026-11-10 (probe 2 reconciliation): before this file existed, the skill
never taught any of this, yet `gate.mjs` failed builds on all of it. Every rule
below is TAUGHT here — a build that follows this file can pass the gate; a
build that does not will fail it, and that failure is a build failure, not a
kit contradiction. Where a check is SCOPED OUT instead of taught, the scope
is stated in `gate.mjs`'s header, in `frontend-kit/SKILL.md` step 3, and in
`references/grader-rubric.md` — all three, so nobody re-discovers it.

## 0. Page kind first — it decides which checks fire

Mark the kind on the page itself (`<html data-type="…">` + matching
`<meta name="site-kind" content="…">`) AND pass it to the gate
(`gate.mjs --kind <kind>` — forwarded to consistency as `--page`):

| Kind | When | Checks that fire |
|---|---|---|
| `software` | An app / SaaS / tool (a language-learning app, a dashboard) | All layout + visual checks; `product-shown` does NOT fire |
| `service` | A service business / agency / studio | Same as software |
| `product` | A PHYSICAL thing with client photographs (or a 3D render the brief asks for) | All of the above PLUS `product-shown` (hero must show the product at ≥80% of the content width: a photograph by its frame, a render or cut-out by its subject — D18) |
| `place` | A venue / location page | Place rules (rooms, menus, goods shown as themselves) |

A language-learning app marked `data-type="product"` is a MIS-MARK, not a
product page: fix the kind, do not fake photographs. The kit vendors no photo
pipeline (no `photos.mjs`, no `assets/objects/product-render`): a
physical-product brief with no client photographs cannot pass
`product-shown`, and that is a stated kit limit, not a build failure to fix
by inventing photos.

## 1. One container — SR-6 container-edges

- ONE `.wrap` per page, shared by the nav, every section, and the footer.
  `.wrap { width: 100%; max-width: var(--max-width); margin: 0 auto; }`
- `--max-width` must give 64–120px margins at 1440px: 1200px gives exactly
  120px; 1120px gives 160px and FAILS.
- **Desktop (viewport ≥1241px): NO horizontal padding on `.wrap`.**
  Padding puts text off the container line and fails SR-6 T3 (probe 2's
  exact failure: `.wrap` `padding: 0 var(--space-5)`). Vertical breathing
  lives on the SECTION (`padding: var(--space-section) 0`), never on the
  container.
- **Below the container breakpoint (viewport ≤1240px): the phone gutter —
  20px side MARGINS on `.wrap`, not padding** (F-2/F-9, probe 3 + judge
  W-JUDGE-2): `.wrap { width: auto; margin-left: 20px; margin-right: 20px; }`
  inside `@media (max-width: 1240px)`. Below 1240px the auto margins would
  fall under 20px and reach 0 at phone widths, so text touches the screen
  edges (x=0) — measured in all three probe-3 briefs at 390px, and the
  judge's #1 cross-brief defect (brief 1's hero even clips mid-glyph at
  390: glyph ink reaches x=389 while every DOM box reports "fits" — see
  §8). 20px is the midpoint of the checker's 16–24px phone band (SR-6).
  MARGIN, not padding, and the reason is the checker's own read:
  `consistency.mjs` takes the container from the `.wrap`'s BOX
  (`ctns`: `if (s.wrap) rectOf(s.wrap)`), and SR-6 T1 measures that box
  while T3 measures text against the box's left line. Padding leaves the
  box at 0–768 while the text sits at 20 — the box fails T1 (0px margin)
  and the text fails T3 (20px off the line). Moving the box with margins
  passes both at phone widths (fixture proof in `build-notes/w-fix-f.md`
  §F-2/F-9: padding and margin variants place text identically at 20px;
  only the margin variant moves the box — in a full run the margin
  variant scores 54 FAIL against the padding variant's 63, the whole
  9-FAIL difference in `container-edges`: at 390 the 20px margins pass
  T1's 16–24px phone band and T3, and at 768 the margin variant passes
  T3 while the padding variant fails it. T1 at 768 still fails for BOTH
  variants — 20px against the checker's 64–120px tablet band — see the
  known limit below.)
- **The nav lives in the SAME `.wrap` and gets NO extra padding.**
  Probe builds use `<div class="wrap nav-wrap">`; the nav inherits the
  `.wrap`'s 20px inset below 1240px, and the CTA is pushed to the right
  edge with `margin-left: auto` (the nav-links' own `margin-left: auto`
  disappears with them at ≤820px — that is what collapsed the CTA next
  to the wordmark and failed the `nav` check in brief 3 round 2: the
  nav's pieces spanned 0–309px against content edges 25–795px). The
  probe's `.nav-wrap { padding: 0 25px; }` fix is SUPERSEDED: it was
  tuned to that build's incidental 25px content margin; under the new
  doctrine the nav and the content share one 20px edge at every width.
- **Known limit (not chased):** in a full (non-`--quick`) consistency
  run, SR-6 at 768 expects 64–120px margins (or a declared `--gut`) —
  the checker's tablet model. The kit gate runs rhythm at 1440 only
  (`--quick` runs the rhythm module at the first rhythm width), so this
  never affects the gate, and widening the tablet gutter to 64px would
  waste a fifth of a tablet screen to satisfy a run the kit never makes.
  Do not chase it.
- Text starts exactly on the container's left line (or on the one split
  line, §3). Text is left-aligned (`text-align: start`); centred body text
  fails SR-6 T4. Full-width is for background layers and grounds only —
  nothing content-bearing sits past the container lines.
- Page shell: `header.nav` + `main` of `<section>`s (each containing one
  in-flow `.wrap`) + `footer.closing`. Bands inside a section, or blocks of
  `<main>` that are not `<section>`, fail SR-6 T1 / SR-4.

## 2. Overlay nav — the header must not eat the first screen

The nav sits ON the hero, not above it: `header.nav { position: absolute;
top: 0; left: 0; right: 0; }` (or `fixed` for a sticky nav). The hero is
`min-height: 100svh` and carries `padding-top` for the nav height so its
content starts below the nav, not under it. The checker measures the hero
against the screen grid starting at the top of the screen: an in-flow 65px
header pushes the hero 65px down that grid, so the hero's height and top
have to compensate exactly (`calc(100svh - 65px)`) at every width — probe
2's build did the compensation and still carried the offset as a residual
against SR-1/SR-6. Overlay nav removes the offset at the source; it is the
taught pattern. The hero must end exactly at the fold (1px either way),
its content between the nav and 24px above the fold, with nothing of the
next section on the first screen.

## 3. Splits and rows — SR-8 split-pair, SR-7 row-lines

- Splits (text + visual side by side): a 12-column grid,
  `grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 24px;`, text in
  the left column, visual in the right, top-aligned (`align-items: start`).
  Text spans 5 columns (`grid-column: 1 / span 5`), visual spans 7
  (`grid-column: 6 / span 7`) — the right column then starts on the shared
  line k=5, one of the checker's allowed lines (k = 5, 6 or 7). EVERY split
  on the page shares that ONE line; a second split on a different line
  fails SR-8 T-pair. The split runs edge to edge on the container.
- Rows (cards): the first item starts on the container's left line, the
  last ends on the right line, every item one height. No sideways scroller,
  no half-cut carousel, no cut row item.

## 4. Section rhythm — SR-1–SR-5

- Hero: exactly one screen (`min-height: 100svh`, §2) — **at desktop
  widths**. See the F-3 rule below for where the one-screen hero stops.
- Every other section: one screen or two (`height: calc(var(--h,1) *
  100svh)`), tops on the screen grid, content fitting above the bottom
  padding. One screen shows ONE section: the next section may peek at most
  8px (24px WARN).
- Air between sections: **128–288px at desktop widths** (112–420px on a
  phone). The token-consistent gap is 2× the `--space-section` token
  (2×96px = 192px); a gap over **288px (1.5×) at vw ≥ 1024 is a dead band
  and FAILs** `section-gaps` outright (kit patch, 2026-11-10, probe 3 +
  judge W-JUDGE-2 — the old 480px ceiling passed brief 1's 297/350/398px
  and brief 3's 350/371px gaps at 1440, all measured first-hand, while the
  judge failed all three pages on them). The old median-relative rule
  alone cannot catch dead bands: it only flags a gap that deviates from
  the page's OWN median, so a page whose gaps are ALL dead passes it.
  **Fill ≥55% does not catch dead bands either:** brief 1's sections
  fill 56–67% yet carry 297–398px gaps — fill is necessary, not
  sufficient; the gap ceiling is the instrument for dead bands. No
  divider rules (`<hr>` between sections fails SR-3 — use space, not a
  rule).
- **F-3 — the gap check reads a 100svh section's empty bottom as a
  spacing decision.** The gap is measured content-to-content, so at
  tablet widths (768×1024, 820×1180) a short-content 100svh section
  inflates it: brief 3's hero/projects gap was 520px (+67% FAIL) at 768
  because the hero is 1024px tall and its content is ~500px, and the
  about/footer gap was 492px at 820 because section#about is 1180px
  tall with its content ending ~400px above its bottom edge. (First
  hypothesis — the footer's top — was WRONG and is corrected here:
  measured at 820, the footer's first content sits 96px below its top
  edge, just its padding; the 398px is about's empty bottom.) The fix is
  STRUCTURAL, not padding cuts: **below 820px NO section is 100svh —
  every section's height follows its content**
  (`section, footer.closing { min-height: 0; }` inside
  `@media (max-width: 820px)`). The one-screen section model is a desktop
  (1440) rule; below 820px sections flow at content height. Cutting the two paddings that meet at the gap
  (brief 3's round-2 workaround) only shrinks the symptom and is
  superseded by this rule — and it is worse than a workaround: it keeps
  the median inflated, which masks the 492px footer gap (the footer gap
  passed in the probe's final build only because the 676px hero gap at
  820 held the median at 492px).
- **F-3, why the hero-fill check yields below 1024px (kit patch).**
  With a short-content hero at tablet widths, hero-fill and section-gaps
  are mutually exclusive — proven, not assumed: brief 3 with the hero
  kept at 100svh FAILs section-gaps at 768 (520px, +67%); the same page
  with the hero at content height (721px) clears the gap but FAILs
  hero-fill at 820 and 768 (the next section starts at 815px on a
  1024px screen). No 100svh hero passes the honest median at 820 either:
  even with its content vertically centred, the bottom air is ~340px and
  the gap reads ~436px against a 217px median (+101% FAIL). So one of
  the two rules must yield below 1024px, and the gap rule wins: the
  ~500px of dead air inside a 100svh hero is the same defect the
  dead-band ceiling above FAILs, while the next section peeking onto the
  first screen (209px at 768) is normal tablet/phone UX, not a defect.
  `hero-fill` is therefore scoped to desktop widths (vw ≥ 1024) in
  `consistency.mjs` (kit patch, 2026-11-10; upstream fires it at every
  sweep width). At 1024 and 1440 the hero stays 100svh and hero-fill
  still fires. The dead-band ceiling above is scoped to vw ≥ 1024 for
  the same reason: below that, gaps inflate with the viewport, and the
  structural section-height rule governs instead.
- **Fill ≥55% or merge (SR-3 / empty-area):** a section's content must fill
  ≥55% of its screen (40% WARN; empty-area FAILs over 50% empty). A short
  section — a closing call, a thin band — must be MERGED into the section
  above it or given a second column / a visual of its own. Stretching a
  200px section to 100svh with centring does not fill it; it empties it.
  One heading per section (h2 first in its `.wrap`); the hero holds only
  its h1.
- **SR-2 fill rule (D11 — judge fix drops `100vh`).** When a judge fix drops
  the `100vh` rule on `.section` and SR-2 then fails on short sections, the
  builder resolves it by growing *internal* spacing by minimal token sums
  until each section's content reaches the one-screen content window (708px
  at 1440 with 96px pads), keeping non-hero section pads uniform at
  `--space-section` and non-hero inter-section gaps uniform at 2×
  `--space-section`. (The hero is governed by SR-1, not SR-2.) Restoring
  `100vh` is forbidden — it undoes the judge fix. A content-height
  exemption to SR-2 is forbidden. Per-section bottom pads (candidate A)
  are a fallback only, when a section has no internal spacing that can
  grow, and must be declared as such in the round record.
  - **Bound.** Total shortfall **|S| ≤ 72px** (the doctrine's own add/cut
    number, `layout-v4.md` §2: "add or cut up to 72px"). The bound governs
    when the B-pattern applies: a shortfall within it (content in the
    495–708px window) is filled by the pattern; a shortfall outside it, or
    content under 495px, is not stretched in a fix round.
  - **Fix-round vs direction remedies — split by who may apply them,
    whatever the content band.** Fix-round remedies (builder,
    D2-compliant — same content, same copy, same section inventory): the
    B-pattern itself, the candidate-A fallback, `.g2` (structural,
    inventory unchanged), shrinking internal spacing by token sums.
    Direction remedies (human gate, re-pick — they change content, copy,
    or inventory): merge, add a picture/content, cut copy, split into two
    sections. If no remedy in either class fits, escalate — never stretch.
  - **Minimal-sum rule.** The growth or cut is the token sum landing the
    section's content closest to 708px, inside the 706–710px band where a
    token sum reaches it (height 898–902px, i.e. 900px ± SR-2's 2px
    tolerance); ties prefer the smaller sum. In the ordinary case that is
    the smallest sum of `--space-*` token values ≥ S for a shortfall, and
    the smallest sum cutting to the band for an overshoot — a single token
    step alone is not the rule (e.g. an overshoot of 28px cut by a single
    32px step lands at 896px, WARN, where the sum 28 lands exactly at
    900px). A single growable gap is grown by the minimal-sum rule like any
    other. **Margin collapse:** adjacent-sibling vertical margins collapse
    to their max, not their sum — when distributing growth across margins,
    count the collapsed value, not the sum of the two margins. Prefer
    row-gap (which does not collapse); the gate verifies the result.
  - **Tolerance declaration.** The builder records, per section, the
    shortfall, the token sum, and whether the result is exact or passes by
    SR-2's 2px tolerance — a tolerance pass (e.g. 901px) must be declared,
    never silent.
  - **Contingent cap (not a binding bound).** No per-gap cap applies now.
    IF a full-shot grade penalises a B-pattern build's internal spacing,
    the pattern gains a per-gap cap — the recorded candidate is B's 32px
    (= one `--space-6`) per gap per round, with shortfalls spread across
    two or more internal gaps — and the verdict is revisited with that
    grading evidence in hand. If a cap ever applies, a single growable gap
    that cannot reach the height within the cap falls back to candidate A
    for the remainder, or escalates.
  - **Worked instance (probe run-2, R3 → candidate B as-built, gate GREEN
    0 FAIL 15 WARN — verified, not predicted):** about panel margin 24 →
    52 (+28 = 16+12); projects grid row-gap 16 → 84 (+68 = 64+4); tools
    panel margin 32 → 28 (−4). Contents 708/709/708, heights 900/901/900
    — **the 901px projects height is a DECLARED tolerance pass under
    SR-2's 2px tolerance** (shortfall 67px has no exact token sum; the
    smallest sum ≥ 67 is 68). **Caveat, recorded not hidden:** the 84px
    projects row-gap (against a 16px column gap) is a gate-blind cost —
    the gate measures section heights and inter-section gaps, not
    internal-gap proportionality. The next full-shot grade is the check
    on it.

  Decision table (content c at 1440, px):

  | c | Remedy | Class | Source |
  |---|---|---|---|
  | < 360 | merge into the section above, or add the picture it lacks | direction (human gate) | `layout-v4.md` §2 windows |
  | 360–495 | one screen, with a warning: give it its picture | direction (human gate) | `layout-v4.md` §2 windows |
  | 495–708, shortfall ≤ 72 | B-pattern: fill internally by token sums | fix-round | D11 |
  | 495–708, shortfall > 72 | add a picture / merge — do not stretch in a fix round | direction (human gate) | D11 bound + routing (the doctrine prescribes merge/add-picture only for content under 495px; for this band the direction routing is D11's) |
  | 708–1,320 | `.g2` (fix-round, inventory unchanged); cut copy / split into two sections (direction) | split by remedy | `layout-v4.md` §2 windows + D11 routing |
  | slightly over 708 | shrink internal spacing by token sums (tools: −4) | fix-round | D11 (minimal-sum, symmetric case) |

## 5. Visuals — no-visual, empty-area, text-only

- EVERY feature section needs a visual covering ≥25% of the section
  (under 15% FAILs, 15–25% WARNs): a photograph (`<img>` with alt text)
  or a UI mock. For a DIGITAL product the app's own UI mock IS the visual.
- Mark the mock `[data-ui]` and make it LARGE (≥120×80px — the checker
  ignores anything smaller). **The one definition (D17):** a mock is a
  `[data-ui]` element — the attribute's value names the fragment; the
  checker reads the mark, never the value — or a `.ui` root carrying
  `ui-*` classes; every checker test uses the one selector for it, and
  the ≥120×80px size is what earns the section's visual credit. An
  element with only a `ui-*` class (no `[data-ui]`, no `.ui` root) is
  NOT a mock: it is page content. A small inline SVG icon (32px) does NOT count:
  probe 2's four 32px card icons covered ~0% and all four sections failed
  `no-visual`. Put the mock in the split's right column (§3) or full-width
  in its own row; a lesson-card mock the size of a postage stamp is not a
  visual.
- Sections the checker excuses from visuals: prices, FAQs, quotes, and the
  closing call — but a closing call that is ONLY text still fails
  `text-only` when two or more sections are text-only. Give the closing
  call a visual or merge it (§4).
- **F-5 — a text-only `[data-ui]` mock IS a band (SR-4 T-dom), at desktop
  widths.** A box ≥80% of the section wide, ≥48px tall, on a ground of
  its own (a background different from the section's), that holds only
  text FAILs `one-section` as "a band … that holds only text". The
  exemption is a visual mark: any descendant `img`, `video`, `svg`,
  `canvas` or `picture` breaks "holds only text"
  (`consistency.mjs`, SR-4 T-dom). So every text-only mock needs a small
  svg in its header bar — the probe added a `>_` svg, a grid svg and a
  `</>` svg to three mocks purely to satisfy the rule. **That svg is
  load-bearing for the gate, not decoration: say so in the build, do not
  silently decorate.** Alternatives that also exempt the mock: mark it
  `[data-visual]` (or wrap it in `.frame`), or use `<pre>` for terminal
  text (never a band). A mock on the section's own ground (transparent
  background) is not a band at all, and the rule fires at desktop widths
  only (`!phone` in the code). This is TAUGHT, not scoped out: a
  ≥80%-wide box on its own ground holding only text reads as a band, and
  the svg genuinely changes that read.
- Drawn mocks are fine for a digital product's own UI. They are NOT a
  substitute for photographs on a physical-product page (`product-shown`:
  "never a drawing").

## 6. Contrast — decorative vs functional accent (the coral case, G-9c)

- Body / muted text: the kit's 7:1 rule (stricter than WCAG AA). Muted text
  never sits on a tinted card it fails on — check every ground it sits on.
- CTA / large text: WCAG AA 4.5:1.
- **A vendored reference's component that fails the contrast rule is NOT
  shippable verbatim.** Claude's `callout-card-coral` — white text on coral
  #d97757, 3.12:1 — fails WCAG AA and the kit's 7:1 body rule. Copy the
  reference's LOOK, not its literal component: coral stays DECORATIVE ONLY
  (brand mark, rule, accent line — never behind text); text-bearing
  surfaces use the darkened functional accent (#a9583e, white text 5.06:1,
  passes AA). The checker (`text-contrast`) enforces this; this file
  teaches it. The same rule applies to any reference: if its signature
  component cannot pass the gate as documented, adapt the component —
  never silently lower the contrast rule to green the build.

## 7. What the gate still cannot check for you

- Whether the visual is the RIGHT visual (a stock photo of a beach on a
  language app passes `no-visual` and fails the human gate). That is the
  judge's job, not the gate's.
- Whether the copy is true. `copy-lint` catches residue and slop words,
  not invented facts.

## 8. Mid-glyph clipping at the viewport edge (390px) — no box check catches it

Brief 1's hero at 390px clips mid-glyph at BOTH edges ("at" cut, lede
"and a" cut, logo asterisk half-cut) while every DOM measurement reports
"fits": `documentElement.scrollWidth` == `clientWidth` == 390, the H1's
box is 0–390 with `scrollWidth` == `clientWidth`, the word "at" has a
Range rect ending at 389.7 — yet a pixel scan of the 390 screenshot shows
glyph ink at x=389, the last column. The mechanism is ink overhang: with
zero side padding the text starts exactly at x=0 and ends exactly at
x=390, and glyph ink (serif fallback, −1.2px tracking) overhangs its
layout advance past the viewport edge. No box-based check can catch this:
SR-6 T5-overflow only fires when `scrollWidth > clientWidth` (it is not
wider — the ink is), and it runs at 1440 only under `--quick` anyway;
`spill`/`cut-text` measure boxes, not ink. **The structural prevention
is the §1 phone gutter** (text never touches the edge, so overhang stays
inside the viewport), and **the detection is the step-4 eyes procedure**:
look at the 390 screenshot for glyphs cut at the edges. Do not add a
box-based gate check for this — there is no DOM measurement that
distinguishes a cut glyph from a fitting one; a check that cannot see the
defect would only add false confidence.
