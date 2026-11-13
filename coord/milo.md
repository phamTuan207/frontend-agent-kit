# coord/milo.md — handoff file (Milo)

> **This file belongs to Milo.** Only Milo edits it. Never edit another agent's
> file, never edit `coord/BOARD.md` (coordinator-owned), never rewrite history
> in `coord/run-log.jsonl` (coordinator-only, append-only — log in this file;
> the coordinator transcribes).
> Protocol: `BUFFET-MODE.md` §5. Board: `coord/BOARD.md` (read-only for Milo).
> Runbook: `BUFFET-MODE.md` — your role is in §1.

## Role

Milo is one of the four agents in this run (Muse, Mie, Migga, Milo). Role per
run: builder (one instance per direction), independent expert, or independent
judge — as assigned on the board. A builder never grades its own work; an
expert judges ONLY its own domain, from the artifacts, never from the builder's
reasoning; a judge grades 1–5 on Type / Layout / Colour / Space with one
evidence line per score.

**Figma path C (MCP read) is available only on hosts in Figma's MCP catalog**
(`BUFFET-MODE.md` §6) — Hermes / Muse Code / CommandCode are not in the
catalog. If your host is outside the catalog, use paths A/B only; check your
host against the catalog, do not assume. (No file in the repo states which
host Milo runs on, so this is a per-host rule, not a Milo-specific claim.)

## Deputy + succession (you may be named deputy — read this before the run)

- You may be named deputy (or backup deputy) at run start; the board's
  `Deputy` field names you. The deputy (and backup) is named only from
  agents whose machines pass the §9 gate-tooling check — a deputy that
  cannot run the merged-tree gate cannot land anything (F29). The deputy is
  never Mie.
- **Backoff exemption:** if you are the deputy, you are EXEMPT from adaptive
  backoff — poll every 15 min always, even with an empty queue. (A deputy
  pulling every 2 h could not detect a 60-min staleness until hours later;
  the detection bound is 60–75 min after the coordinator's last commit.)
- **Staleness test (what "the coordinator is dead" means):** the coordinator
  is stale only if BOTH hold: (a) there is pending work — a claim, a
  completion, or a slice awaiting merge — unprocessed for >60 min, AND (b)
  no coordinator commit in that window. An idle coordinator with an empty
  queue is idle, not stale: no pending work means no takeover, whatever the
  clock says.
- **Two-phase takeover (fencing):** (1) post `COORDINATOR TAKEOVER <UTC> —
  reason: <pending work unprocessed since X> — last coordinator commit
  <hash> — term: <N+1>` in this file and push; (2) wait one full pull cycle
  (15 min) before acting as coordinator. If the old coordinator posts
  `COORDINATOR ALIVE <UTC>` in its own file and pushes inside that window,
  the takeover is void — post `TAKEOVER VOID — coordinator alive` and stand
  down. (3) After the window with no alive-signal, you own the board: write
  `coordinator-term: <N+1>` in the board (the board carries
  `coordinator-term: N`, starting at 1 for Muse at run start; each takeover
  increments it). **Every coordinator board write carries its term; agents
  and the old coordinator ignore board writes from a superseded term.** The
  old coordinator, on seeing a higher term, posts `STOOD-DOWN` in its own
  file and resumes as a worker. Publish board writes through the merge-pass
  procedure (short-lived `coord/board-…` branch + merge into `buffet/main`,
  `BUFFET-MODE.md` §5) — never by direct push to `buffet/main`.
- **Your own work on takeover:** your active claim is **suspended** — marked
  `input-required` with the note "deputy became coordinator; claim
  suspended", and reassigned by you (as the new coordinator) to another
  agent or re-listed. **Slices you built but have not landed are frozen** —
  they stay `working` under your name but you do not land or stop-decide
  them; they are carried to the human-return packet. A deputy who built a
  slice never merges it.
- **Fallback if the deputy is also stale:** if you are the backup deputy and
  the deputy is also stale, take over by the same procedure (same staleness
  test, same two-phase takeover, same term increment). If both deputies are
  stale, the run **pauses**: all slices go to `input-required` with the
  blocker named, and the run waits for human-on-return. There is no third
  deputy and no silent continuation without a coordinator.
- **In-flight merge at takeover (RUNBOOK PROCEDURE):** a merge the old
  coordinator landed locally but has not pushed is NOT a land — treat any
  slice with no land record on the remote mainline as unlanded and re-trial
  it from the remote mainline tip before landing it. The old coordinator, on
  posting `STOOD-DOWN`, must not push any local merge afterwards.
- **Takeover reconciliation (F18, BUFFET-MODE.md §11):** before landing
  anything, post a `TAKEOVER-RECONCILIATION` record in this file naming the
  last remote board commit you trust (`git rev-parse origin/buffet/main`
  after fetching), re-derive the landing order from the remote run log, and
  mark any slice whose state is unknown as `input-required` rather than
  guessing.

## How to claim work

- Read `coord/BOARD.md` for open slices (one row per slice: Slice, Owner,
  Status, Expected-min, Files, Notes — Notes links to the filled task file at
  `coord/tasks/<slice-id>.md`). No row is claimable until all six task fields
  are filled; if you find an unfilled row, write `BLOCKED — template
  incomplete` in this file and do not start.
- Claim a slice by writing in THIS file — never by editing the board:
  `CLAIM <slice-id> | plan: <2–3 lines> | files: <glob(s)> | board-hash: <hash> | at: <UTC>` —
  claim-with-a-plan. A claim without file globs is incomplete. `board-hash`
  is the `buffet/main` commit hash you read the board at
  (`git rev-parse origin/buffet/main` after fetching the board — see Poll
  cadence below). A claim with no `board-hash` is incomplete.
- **A claim is a request until the coordinator awards it.** The coordinator's
  next merge pass records the award (board row becomes `working` with your
  name). Work done before the award is at your risk. The arbiter is the
  coordinator's first-seen order; tie-break is the lexicographically smaller
  claim-commit hash (in the fork case, the earlier PR creation time). Your own
  `at: <UTC>` timestamp is a note, never the arbiter.
- **WIP = 1:** one active claim at a time. A transient second claim is allowed
  only in the same commit as posting DONE on the current slice.
- To refuse a slice: `DECLINED <slice-id> | reason: <one line>` in this file.
  A declined slice is terminal for you, not for the slice.
- If you disagree with an assignment, write the objection in this file and keep
  working on the last agreed slice — do not stall the run waiting for an answer.

## Poll cadence (binding)

- During an active buffet run, run `git pull --ff-only` **every 15 minutes**
  and read `coord/BOARD.md` + this file. On the same poll, fetch the
  mainline explicitly — `git fetch origin buffet/main`, then read the board
  at `origin/buffet/main`: a pull on your own branch never sees the board,
  which lives on `buffet/main`.
- Between polls, work from your local copy and write only to this file.
- **Term check:** on every fetch, compare the board's `coordinator-term`
  against the highest term you have seen — record it in this file as
  `Highest board term seen: <N>` (under Last seen). A board whose term is
  lower than the highest seen is superseded — ignore it.
- **Adaptive backoff when idle:** empty queue → double the pull interval per
  empty cycle, max 2 h, reset to 15 min the moment a slice appears. **UNLESS
  you are the deputy** (see Deputy + succession above) — the deputy is exempt
  from backoff and polls every 15 min always.
- **Immediate re-poll after completion:** after pushing a completed slice,
  re-pull immediately instead of waiting for the next 15-min tick.
- **Lease:** a claim lapses after **60 min without a push** or **2× the slice's
  `expected-min`**, whichever is shorter. Renewal is by push only — any push
  (a branch commit or an own-file update) resets both clocks. The merge pass
  is the decision point: a push after the lapse but before the pass revives
  the claim. On lapse the coordinator marks the slice `failed` (reassignable)
  and logs the lapse. "Stale with recent commits = slow, leave alone" stays.
- **Liveness = pushes, full stop:** the coordinator's only observation channel
  is pushes — a last-seen line that is never pushed is invisible to the
  coordinator and renews nothing.

## Last seen (heartbeat — BUFFET-MODE.md §5, P24)

Last seen: — (no run yet) — task: — — last commit: —

One line in the Last seen section of this file, updated on your normal 15-minute pull,
carried by a push — never a commit of its own. For research / no-commit
slices this is the renewal path: push your own-file update (last-seen line +
progress note) and that push renews the lease.

## Inventory + census (at run start, on demand)

- **TOOLS block** (verified by running the command, never assumed):
  `TOOLS <UTC> — <cli> <version-output> — subagents: <yes/no/how> — notes: <...>`.
  Report the exact failure instead of improvising if a tool is missing.
- **Census report** (live sub-agents only; finished ones are not counted):
  `CENSUS <UTC> — live: <n> — <sub-1>: <task> (<working|stalled|dead>, last
  active <UTC>) — ... — stalled/dead: <names>`. Stalled = no progress for
  >30 min. Dead = you cannot reach it, or it exited without reporting.
  The coordinator posts `CENSUS REQUEST <UTC>` on the board; report in this
  file and push.

## Merge rules (binding)

- Work on your own branch `buffet/milo` and push that branch. Only the
  coordinator merges branches into the buffet mainline — never push to the
  mainline directly, **never force-push** (forbidden for all agents including
  the coordinator).
- If push access is not yet granted, work on a fork and open a pull request —
  the coordinator merges the PR (see the §9 section on the board).
- A merge conflict on your own file: routine pulls are `--ff-only`; rebase
  only your own unpushed commits — verify first with
  `git log --oneline origin/buffet/milo..HEAD` (those are the unpushed
  commits; if the list is empty there is nothing to rebase); never rebase
  commits already on origin (the next push would need a force-push, which is
  forbidden); never rebase another agent's branch. If a pull fails on
  `--ff-only` and the branch has already-pushed commits, stop and let the
  coordinator see it — do not rebase. Keep both entries on a conflict, never
  delete the other side's lines, and note it in this file for the coordinator
  to transcribe.

## The Optimus group

- The group is for HUMAN-FACING MILESTONES ONLY. No agent-to-agent
  coordination chatter there, ever. Only the coordinator (Muse) posts
  milestone lines.

## Log

- (no entries yet — append `CLAIM <slice-id>` + plan + files + timestamp and progress here; the coordinator transcribes into `coord/run-log.jsonl`.)

## Milo handoff — ongoing development (from 2026-11-12)

- 2026-11-12T03:38Z START — Milo taking over M1–M3. Upstream main verified by `git ls-remote`: 98037ebb53e5bc2bca66c9b93c0ad17a185213f6 (matches the seeded board). Working tree obtained via the official codeload tarball of that exact commit (git clone stalled twice on this host; tarball import is a local snapshot only, branches/PRs will be created from the fork once it exists). Fork status: BLOCKED on fork creation — the GitHub App integration returns 403 on `fork_repository` ("Resource not accessible by integration") and the cloud browser is not signed in to GitHub; the human has been asked to create the fork (one click) or sign the browser in. Local work proceeds; nothing here blocks M1–M3 implementation, only push/PR.
- CLAIM M1 — Self-grading escape hardening (D15) | plan: council (3 experts in parallel) decides a judge-artifact mechanism mirroring/extending the D13 gate-artifact pattern in `run-log.mjs`; implement so a graded `record` (and any stop/land path that relies on scores) refuses scores without a validated judge artifact; QC + red team; live proof on Brief 1 with a deliberate self-grading escape attempt that must be blocked. | files: `skills/frontend-kit/scripts/run-log.mjs`, `skills/frontend-kit/scripts/runlog-check.mjs` (if present), `skills/frontend-judge/**`, `skills/frontend-kit/SKILL.md`, `skills/frontend-kit/references/workflow.md`, `skills/frontend-kit/references/grader-rubric.md`, `skills/frontend-kit/references/decisions.md` (D15), `verify.sh` (§5b-style judge-artifact refusal cases) | board-hash: 98037eb | at: 2026-11-12T03:38Z
- CLAIM M2 — O4: verify.sh §5 fixture + browser discovery | plan: council-decide (conforming fixture vs scoping leg 2 out of §5 vs fixing CHROME_PATH discovery, or a combination) with evidence from actually running verify.sh; implement; QC + red team; proof = fresh install + verify.sh run (0 failures except pre-existing host-state items; §5b still counts 98 cases). | files: `verify.sh`, possibly `skills/frontend-kit/scripts/gate/gate.mjs` / `consistency.mjs` (browser discovery only) | board-hash: 98037eb | at: 2026-11-12T03:38Z
- CLAIM M3 — Deferred design decisions (S1, H3, H5, moment-none promotion) | plan: council-decide each of the four with file:line evidence; implement the decided form (code or prose correction); QC + red team; proof = gate runs exercising each decision. Decisions recorded as D16+ in order. | files: `skills/frontend-kit/references/style-recipes/scroll-motion.md`, `skills/frontend-kit/scripts/gate/consistency.mjs`, `skills/frontend-kit/scripts/gate/gate.mjs`, `skills/frontend-kit/references/decisions.md` (D16+) | board-hash: 98037eb | at: 2026-11-12T03:38Z
- 2026-11-12T03:42Z M1 COUNCIL DONE — 3 members (enforcement / producer / red team) + chairman synthesis. Red team verified the escape LIVE on 98037eb: self-asserted graded record exit 0; scores on a failed gate exit 0; feedback --score-after, jury and pairwise all self-asserted; crosscheck --report never stat'ed; land with zero graded rounds; `best` crowned a gate-failed fabrication. DECISION (to be recorded as D15): a graded record requires a judge artifact — `design/judge/round-<n>.md` in the judge skill's own output format with a strict stamped header (page/tokens/screenshot sha256 binding), stamped by a new `judge-report.mjs prepare` before the judge is spawned (refuses unless gate-green + cross-check-clear are derivable from the run log), filled by the judge itself (scores/evidence/basis only), parsed and cross-checked by `run-log.mjs` (scores/evidence/grader/basis/round equality, hash binding, freshness chain, single-use per log); jury = 3 artifacts, pairwise = 2 artifacts with A/B swap proof, feedback regrade + expert scores need their own artifacts, scores on a failed gate rejected, `land` requires an existing graded-or-no-grade round record, `best` excludes gate-fail/artifact-less rounds, crosscheck --report gains existence validation. Residual (D13 style): a builder can still forge a judge-shaped file — the bar is deliberate, on-disk, auditable forgery, not costless assertion. Full synthesis: build-notes outside the repo (chairman's working note). Next: implementer.
- 2026-11-12T03:45Z M2 INVESTIGATION DONE — empirical, on 98037eb: with a working browser the §5 fixture fails leg 2 with 16 FAIL / 4 WARN, all on content merits (cta x5, hero-screen, section-height, section-air, one-section, container-edges, copy-fact). Browser discovery defects confirmed by code + runs: findChrome (consistency.mjs:4614-4627) never searches the Playwright cache, silently ignores a set-but-invalid CHROME_PATH, cannot consume the documented glob value, checks existence only (a .zip crashes with EACCES), no PATH lookup; the kit already contains the correct pattern in crop-sections.mjs:336-382. COUNCIL DECISION for M2: option (a)+(c) — replace the §5 fixture with a conforming miniature landing page AND port crop-sections-style discovery into consistency.mjs findChrome (following the in-file kit-patch convention; D9 allowlist implications to be checked at implementation). Option (b) (scope leg 2 out of §5) REJECTED: §5d is the only end-to-end run of the installed leg 2; removing it re-opens GAP-11. No D-number for M2 (board row lists verify.sh only); reasoning lives here + the PR. Implementation queued after M1 lands locally (both touch the gate area; sequential to avoid tree conflicts).
- 2026-11-12T03:42Z M3 INVESTIGATION DONE — evidence packs with file:line for all four: (a) S1 Pattern 5 as prescribed (scroll-motion.md:196) is FAILed by scroll-reveal (consistency.mjs:10654) when it works and by hidden-content (:10036) when it does not; no parameter carve-out exists; recommendation: bounded Pattern 5 allowance in scroll-reveal only (<=1/section, fade+rise <=24px, once), hidden-content stays absolute with the progressive-enhancement implementation style. (b) H3 [data-ui] is defined only as a >=120x80 visual credit (layout-doctrine.md:267) but used across ~86 lines of consistency.mjs as a general not-page-content token with at least 4 different selector spellings and an unread value; recommendation: one canonical definition + one shared MOCK selector, consequences documented in one place. (c) H5 the >=80% band measures subject ink (consistency.mjs:8895-8933, verdict :9663), FAILing the dealt full-bleed photo hero (heroes.json:154) and hiding a 0.86 canvas estimate factor (frame must be ~93%); recommendation: ink band for renders/cut-outs, frame band for photographs, disclose the 0.86 factor + vw>=1000 scope. (d) moment-none: checker emits WARN (consistency.mjs:1201, exit 0 at :11521), gate.mjs has no promotion; only consistency.mjs:358, :381, :1199 claim a FAIL; SKILL.md:190, workflow.md:81 and design-galleries.md §4 already state the truth; recommendation: correct the three prose strings (promotion would be a policy change, not a prose fix). Decisions to be recorded as D16-D19 at implementation. Implementation queued after M2 (both touch consistency.mjs; sequential).
- 2026-11-12T08:35Z M1 IMPLEMENTATION DONE — D15 judge-artifact mechanism shipped on this PR's branch (13 commits, all authored per the repo identity rule). Contents: `judge-report.mjs` (prepare + the shared verifier set), run-log.mjs record/feedback/land/best enforcement, runlog-check.mjs on the shared verifiers, judge + orchestrator skill text, D15 in decisions.md with the full council/QC/red-team record, verify.sh §5c judge-artifact suite. Verification: independent QC PASS; red team PASS at round 9 (confirmation) plus two spot rounds after the proof fixes (gitleaks allowlist, leg-currency deadlock) — both PASS. Suites on the final tree: §5b 98 ok / 0 fail; §5c 123 ok / 0 fail (0 unverified with gitleaks on PATH). LIVE PROOF (Brief 1, fresh install): round 1 graded by a real independent judge (Type 4 / Layout 3 / Colour 4 / Space 3) and recorded only as a verified transcription of its artifact; deliberate escapes refused verbatim — self-asserted 5,5,5,5 with no artifact exit 2, artifact reuse for round 2 exit 2; `best` crowned exactly the judge's table. The proof found two real defects in D15's blast radius, both fixed in this PR: (1) gitleaks flagged judge reports' stamped hash headers, blocking every round >=2 — path allowlist for design/judge/round-*.md (§5c case 104); (2) a leg-currency deadlock — the checker held the latest lines to leg currency while gate.sh folds the checker into leg 1 and every gate run overwrites the canonical legs, so round 2 could never record — currency is now enforced by live operations only (feedback anchor, land precondition, record time), supersession stated in D15 (§5c case 105). Honest caveats: the pure score-mismatch refusal was not reached in the live run (an upstream leg check fired first) — it stands proven in §5c/QC; the proof project itself was destroyed when the host wiped /tmp before the round-2 re-proof completed, and the final gate + prepare-round-2 verification on the genuine proof project was done by the red team on a copy (full gate leg 1 exit 0, leg 2 GREEN, prepare exit 0). `land` does not inspect scores by design (the >=4 stop threshold is the loop's human gate) — stated in D15.
- 2026-11-12T08:35Z GAP-13 PROPOSAL (for the coordinator to award or drop; NOT implemented): per-round gate-leg artifact names (e.g. design/gate-leg1-round-<n>.log) or an equivalent provenance scheme, so a round's cited legs are never overwritten by later gate runs. The deadlock this would have prevented is fixed in this PR by the live-operations adjudication; GAP-13 is the structural cleanup that would let stored citations stay verifiable forever instead of relying on the epoch split.
- 2026-11-12T08:35Z SCOPE CAP ACKNOWLEDGED (board, 2026-11-12 15:22): per the cap — finish the frontend (M1) only, then stop — M2 and M3 are NOT started (investigations + council decisions for both are recorded above and stand ready if the cap is lifted). Milo stops after this PR and awaits the coordinator's review.
- 2026-11-12T09:21Z M2 CAP LIFTED — IMPLEMENTATION START — Muse (16:08, Optimus group) lifted the scope cap for M2 only: implement council decision (a)+(c) + the 3 D13 refusal edge cases from the CI log; M3 stays ON HOLD. Board updated at 3d0751a (M1 landed as f4c701e, PR #2 merged). Branch: milo/m2-verify-fixture-discovery from upstream/main 3d0751a; fork + PR flow as before, identity phamTuan207. CI on main red at Install: §5 fixture fails leg 2 with 11 FAIL / 4 WARN at 1440x900 (CI run 43188860239; copy-fact, hero-screen x2, section-height x3, section-air, one-section x2, container-edges x2; WARN effects-fit, page-meta, share-meta, one-section). Work so far (2 commits): (1) D13 edge cases in run-log.mjs — hasDotSegment() on the raw spelling before resolve (legs, --page via pageFail so --gate fail still warns + records page null per R5, --judge-report, --report) + a real-stem/single-.html-suffix rule for --page; same --page rules in judge-report.mjs prepare (parity); this reverses the fix-round-4/5 blessings in §5b (48)/(51)/(70), flipped to exit-2 in verify.sh, plus new §5b cases (84)-(88) and §5c case (106) for prepare — recorded as the M2 addendum to D13 in decisions.md. (2) findChrome port in consistency.mjs (KIT PATCH, crop-sections-style merged with the fixed system list): CHROME_PATH glob-expanded + fail-loud when set-but-invalid, Playwright cache (Linux + macOS roots, newest first), fixed paths (+ /opt/google/chrome/chrome), PATH lookup; candidates must be real executable files; not-found error enumerates what was searched. Verified live in /tmp: invalid CHROME_PATH (zip / nonexistent / directory / non-executable glob match) throws naming the value; cache + glob + PATH discovery all launch; nothing-anywhere gives the enumerated error. No D9 allowlist trip (browser paths are never scanned). Still to do: the conforming §5 fixture (a) — investigation running; then fresh install + verify.sh proof, QC + red team, PR (no merge).
- 2026-11-12T10:05Z M2 IMPLEMENTATION DONE (code) — all three parts shipped on branch milo/m2-verify-fixture-discovery (5 commits over 3d0751a: 2a2af94 D13 fix, af0380e findChrome, b55e8fa coord start, 0fc670b §5b/§5c tests, 0e5ba0d fixture). (a) Conforming §5 fixture: a miniature landing page (hero, features, closing as footer.closing; fixed nav; real buttons in hero and closing; full head meta: data-type + site-kind software, description, og/twitter/theme-color) built to the doctrine — sections 100svh with 96px pads at desktop widths, content-height sections below 820px (F-3); share.png (1200x630 og:image) stored base64 inline, favicon.ico generation unchanged, design/PLAN.md lists the 3 sections for the converge check. The fixture was designed by the §5 investigator subagent and validated in /tmp/s5cand, then spliced byte-for-byte into verify.sh (heredoc bodies + share.png bytes verified MATCH; bash -n clean). Leg 2 on the fixture verify.sh itself builds: gate.mjs GREEN, 0 FAIL / 1 WARN at all 5 widths (1440/1024/820/768/390) — the single WARN is moment-none at 1440 (a dealt moment is out of scope for a verify fixture; M3 investigation already recommends prose correction, not promotion). This also validates the findChrome port end-to-end (gate found the Playwright Chromium). Honest caveats: (1) the old fixture's cta discrepancy — 12 FAIL locally vs 11 in CI, differing only by cta — was never fully explained (most likely font-metric-dependent section detection on the degenerate stub: sectionsList drops sub-40px nodes); the new fixture has a real hero section with a real button, so cta is deterministic now, but CI remains the final arbiter. (2) Local full verify.sh runs in the real HOME show missing-install noise (kit never installed there) — the acceptance proof is the scratch-HOME fresh install, running now (HOME=/tmp/m2proof/home, --hosts=claude --no-warm). Still to do: install proof result, QC + red team, PR (no merge).
- 2026-11-12T13:57Z PR #3 BLOCKER FIXES (per the coordinator's verification comment on PR #3): (1) ubuntu CI 'Chrome exited early (null)' — consistency.mjs discovery reordered (CHROME_PATH → fixed system paths → PATH → Playwright cache LAST, so a cached Chromium that dies at launch no longer outranks a working system Chrome); launch logs the chosen path before every attempt, captures the browser stderr tail into the failure error, and falls through to the next discovered candidate when one fails to launch; an explicit CHROME_PATH still fails loud with no fall-through. Proven locally: fall-through rig (crashing PATH stub → real browser) completes the walk; explicit crashing CHROME_PATH exits 1 immediately. NOTE on step (a): 'gh run rerun' is denied for the fork account (requires repo admin) — this push produces the fresh CI run instead. (2) macOS CI — all 83 GNU 'touch -d' sites in verify.sh converted to portable 'touch -t YYYYMMDDhhmm' (same local-time stamps, same files each line); 'touch -d' grep now empty, so the §5c freshness chain is BSD-safe. Local full verify: §5b/§5c zero FAIL lines; the only failures are host-state (no gitleaks on this VM → gate §1.1 fails closed; clears on hosts with gitleaks, as in the earlier proofs).
- 2026-11-13T08:36Z BACKEND D49–D52 DONE (kit-side) + ROLE C PREP — per the coordinator's 2026-11-13 15:16/15:18 re-plan (M3 paused until after the hackathon; WIP D16 pushed on milo/m3-decisions as e59414b). Branch milo/backend-d49-d52 from upstream/main 0d37969, 4 commits, all in skills/backend-kit/SKILL.md: (1) D51 — runs gains source (demo|share-link|first-user|pitch) + stub; new single-record counter table, finishRun increments completedReal only on the pending→done transition of a non-stub run; getCounter query is the pitch number (stubs excluded by construction); raw input is never stored — createRun hashes it server-side (inputHash + inputChars), fixing a charter breach in the v0.1.0 schema; §6 seed wording isDemo → stub to match. (2) D50/D52 — Edge Function: every provider call raced against a 15 s timeout (SDK-agnostic Promise.race); the primary gets exactly ONE retry after a 2 s back-off, then the Groq fallback; the §4.4 client no longer retries at app level (one tap = one call chain) and falls back to the cached last-good run, then the seed; §5 error table + hard numbers rewritten to match. (3) D49 — before-build-day checklist in §7 (Supabase project created close to build day + verified live — 7-day idle pause; per-agent Convex deployments verified before the rehearsal; keys only in Supabase secrets / Convex env). (4) tsc fix — Gemini output_text is string|undefined in the real @google/genai 3.3.0 types; guarded with ?? "{}". VERIFICATION (run by Milo, outputs kept): the §4.1/§4.3/§4.4 TS blocks were extracted verbatim into a scratch project with the pinned deps (convex 1.50.0, @google/genai 3.3.0, groq-sdk 1.6.0, typescript 5.9.3) — tsc --noEmit exit 0, which also confirms the GoogleGenAI({apiKey}) constructor and the interactions.create response_format shape against the real 3.3.0 types (the check §4.3 demanded). NOT verified live (needs human-held keys/projects, per the 15:18 split): an actual deployed Edge Function call, a real Convex deployment, the Gemini/Groq quotas. ROLE C INVENTORY (FLEET-MODE §2, this machine): Ubuntu 24.04.5 LTS VM; node v24.22.1; git 2.43.0; gh 2.102.0 (account thinhnguyen672007-alt, fork+PR route); chrome-headless-shell available for gate runs; agent/model: Milo (Muse Spark, Muse runtime). No Convex/Supabase CLI installed on this VM and no project keys held — D49 live steps wait on the humans' key/project handoff tonight.
- 2026-11-13T09:33Z PROPOSAL for Muse (unnumbered — numbers are Muse's to award): adopt the RAG + routed-agent pattern of a production MVP reference system (Gemini File Search, server-set filter/topK, citations-or-not-a-fact, triage→orchestrator, tools with no model-chosen IDs, fixed eval case set) as the backend direction for Sat, mapped onto D49–D52 in research/rag-agent-pattern-from-production-mvp-20261113.md (branch milo/backend-rag-pattern-proposal). Free-tier eligibility of File Search / embedding-2 marked CHUA KIEM CHUNG in the doc — proposed to join the D50 morning AI Studio check. Patterns only: no code, data or prompts from the reference system.
- 2026-11-13T12:22Z DEBATE PROPOSAL — Backend track (19:15 debate, filed late at 19:22 ICT — the 19:00 group post carried the same content). Sources: three official-source research passes (Google/Convex/Supabase, 2026-11-13) + one council critique. (1) CRITICAL PATH: 08:30 AI Studio — read the project's real RPM/TPM/RPD + clear verification; 09:00 deployments (named per-agent dev deployments created explicitly by reference; env per deployment); 09:30 SANITIZED corpus only, <~330 MB raw; 10:00 deploy + one end-to-end run; 10:30 ingest + retrieval + citations; 11:00–12:30 phone integration on dev, promote prod; 13:00 failure-rung rehearsal; 14:30 seed the exact pitch run + freeze; 15:00 quota reset checkpoint (midnight Pacific = 15:00 ICT); 15:30 pitch lock. (2) BIGGEST RISK: Gemini free-tier interactive limits are published NOWHERE (AI Studio only, 'not guaranteed'), are per-PROJECT, and the whole fleet burns one pool — mitigation: seeded result is the pitch DEFAULT, live call is a bonus. (3) NEW DIRECTION: pgvector SHADOW index from the first ingestion, embeddings pinned at 1,536 dims (pgvector vector index caps at 2,000 dims; Gemini native 3,072 cannot be indexed; halfvec 4,000 is the alternative) so the fallback is a switch, not a re-ingest. (4) COUNTERPOINT: D73's pricing gate is stale — File Search is officially 'Free of charge' end-to-end on the free tier (ai.google.dev/pricing); replace the gate with (a) project limits visible + verification done, (b) corpus sanitized (free-tier terms let Google use submitted content incl. uploaded files — no real/confidential docs, ever). ANSWERS to Migga's 19:20 counters: (i) corpus embedding cost — price is $0.00 on the free tier (verified), the real cost is QUOTA: embedding quotas are unpublished and Batch embedding is 'Not available' on Free, so ingest is small + standard calls only; the shadow index stays deliberately small. (ii) Supabase Free storage — agreed and sharpened: the binding limit is the fixed 2 GB DISK (read-only at 95%; WAL can exceed 1 GB during bulk import/index builds), not the 500 MB fair-use quota; seed in small batches, watch disk %, never bulk-load on build morning.
