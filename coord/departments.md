# Departments — muse-fleet (DRAFT)

- **Status:** draft for coordinator landing. Proposed by the swarm coordinator, 2026-11-13. D-numbers below are **PROPOSED only** — the coordinator awards them; no number here is taken.
- **Scope:** the fleet that builds the product in the 5-hour run, plus the kit work that feeds it. The frontend-agent-kit is one branch inside muse-fleet and keeps developing; the fleet is the whole workflow.
- **Hygiene:** codenames and roles only. No event name, venue, date, person, or team detail in this file.
- **Rules in force:** council 1/2/5 (one fabricated claim voids the piece; every claim verified with URL + access date; dedicated red team); builder never grades its own work; 60% slop-free bar; free legal sources only (unread material marked CHƯA ĐỌC); FULL ACCESS for agents the coordinator drives.

## 0. Work map (compact)

| Area | DONE | IN PROGRESS | BLOCKED (blocker) | MISSING |
|---|---|---|---|---|
| Kit loop (frontend) | M1 (D15) + M2 landed; lint green x3 (install step red on pre-existing fixture failure — M2 territory; M1 row stale per audit gap 32); reference-sites backbone landed | M3 (D16–D19 reserved; no M3 branch on the Milo fork; council/implementation status UNVERIFIED in repo — audit gap 13); PR #5 MIE-2 (D21, CI 3/3 green, verification done 09:40 — NOT LANDABLE, docs-only fix); MIE-4..MIE-10 assigned (D72, D36–D41) | MIE-1 + MIE-3 unblocked 09:21 (SSH fixed, known_hosts) and running | Full-loop proof end-to-end (two re-probes: NOT proven); D16–D40 now in `decisions.md` (D41 not yet recorded; D72 by design has no entry — board DoD "nothing else changed"); probe coverage gaps below 50: 48, 49, 50; 8 covered above 50 (51, 62, 74, 77, 80, 83, 85, 86); coverage above 90 UNVERIFIED |
| Backend | Research: Convex free tier (data) + Supabase Edge Function free tier (AI endpoint); Convex AI Gateway OUT (paid); one-AI-endpoint-first plan | All 8 deep briefs landed 09:24–09:33 (research/*-deep-20261113.md); AI-integration brief's GPT-6 Luna via Convex AI Gateway pick INVALID under free-only (parent 09:41; no verifiable source found for GPT-6 Luna — CHƯA ĐỌC) | — | Convex free-tier dev deployment per agent; free-only endpoint contract (no paid model APIs); results/counter schema; free-tier rate-limit defences |
| Mobile | Research: Expo SDK 58 stack (store Expo Go is SDK 58-only; SDK 57 dead); `mobile-kit` skill landed; `theme.ts` tokens exist | Deep brief exists (mobile only) | — | Tonight's phone check on the exact demo phone (SDK version unproven on the store); kill/reopen rehearsal; degraded rungs; state wiring (Zustand + TanStack offline) |
| Security | — | Security deep brief landed 09:32 | — | Secrets audit; endpoint abuse guards; no-keys-in-bundle enforcement |
| Coordination / runbook | FLEET-MODE + BUFFET-MODE runbooks landed; board current to HEAD 907aeaa | PR #4 MIG-2 (coordinator review 04:57: NOT LANDABLE yet — docs-only D23/D30 cites +9 AND ubuntu-24.04 CI green still required) | 12 gaps block the run (see §2): no deputy, no rehearsal, no inventory, no product repo, empty run trigger, `buffet/main` does not exist, B3/B4 never run, ownership table empty, no task files, stale "never posts" lines, stale "no chatter" lines | FLEET-2 rehearsal; FLEET-3 run start (product repo); deputy + backup; TOOLS/MODELS inventory per agent; run-log transcription for 13/11 events; board status vocabulary fix |
| Evidence / growth | Method briefed (evidence artefact, share link + counter, first-users wall) | — | — | `docs/EVIDENCE.md` template in the product repo; 3 pre-consented strangers (human recruits); live counter implementation (backend) |
| App quality (a11y / perf / state) | Method briefed; `theme.ts` contrast audit done (2 text tokens fail: `success` 3.46:1, `warning` 3.30:1; `border` 1.26:1 also fails non-text 3:1 — never the sole indicator) | — | — | Contrast fixes; native a11y gate (pa11y is web-only — cannot gate the native app); perf budget measured on the demo phone; degraded rungs A1–A3 |
| Phone / submission / pitch | Method briefed (tokens, phone checklist, submission checklist, 5:00 pitch arc) | — | — | Demo-phone identity (two sources conflict — NEEDS-HUMAN); submission artefact format/portal (CHƯA XÁC MINH — NEEDS-HUMAN) |
| Feasibility / cost / backup | Method briefed (15-min triage, scorecard, kill-switches, $0 spend rule — free tiers only, rungs F0–F5, backup video) | — | — | Fallback idea (human picks); morning-of free-tier dashboard + quota check; backup video (recorded at freeze) |
| Rename / hygiene | Repo renamed to muse-fleet; old slug redirects to same HEAD (verified live) | — | — | 63 RENAME lines in 25 files (83 lines / 31 files total incl. KEEP 2 + DECIDE 18; plugin manifests + docs must rename as one set); 13 board scrub rows (15 lines); GOAL.md staleness (11 rows) |

## 1. The departments

### (a) Ban Ý tưởng & Khả thi — Idea & Feasibility

- **Owner:** Muse (integrator). Draws on the product/idea-validation research (parent-owned); this department owns the method and the artefacts, not the research itself.
- **Responsibilities:** the 15-minute idea-feasibility triage (one-sentence idea → user-evidence test → AI-essentiality test → A/B/C scorecard → 30% cut test → pre-mortem → kill-switches); the fallback-idea protocol (one simpler idea, same user, same evidence, one AI action); the scoring-fit lens (40 live demo / 35 problem + evidence / 25 first users + global); the evidence-artefact requirements (`docs/EVIDENCE.md` §1–§6, ≥2 rows from ≥2 types); the demo-insurance five (evidence file, one-sentence idea + scorecard in `CONTRACT.md`, demo script on paper, before-capture, 3 named first users).
- **Must NOT do:** choose the idea (humans decide); validate a specific idea without evidence; present a scorecard as proof when the artefact is missing; build the product (that is Ban Frontend / Backend / Mobile).
- **DoD:** triage template + scorecard live in the runbook; kill-switches written in `CONTRACT.md` before the run starts; fallback idea named; the one-sentence idea is verbatim in `CONTRACT.md` and in `docs/EVIDENCE.md`.
- **Work queue (proposed):**
  - D42 — Land the 15-minute triage + A/B/C scorecard as a runbook section (proceed only ≥4/6, no 0; A=0 kills outright).
  - D43 — Kill-switches in `CONTRACT.md`: T+1:20 cut-to-smallest-form; T+2:20 abandon + fall back to the pre-agreed simpler idea; Integrator calls them, no vote on the day.
  - Evidence template (D44, full row in §1(f)): lives in department (f) under the D-assignee — FLEET §1 assigns the evidence artefact to D, not to the integrator (see the S7 role note in §1(f)).

### (b) Ban Frontend — Frontend

- **Owner:** Mie. She owns the kit loop and the Q1–Q4 fixes.
- **Responsibilities:** the taste-locked deterministic-gate loop (taste lock before HTML; gate first; screenshots 1440/768/390; independent grade Type/Layout/Colour/Space 1–5; fix top 2; 3-round cap); the kit skills (`frontend-kit`, `frontend-judge`); the probe backlog (verification records, blocked-record pattern, fix prompts for held probes); the Yates reference-sites backbone (advisory, never a grading input); the rename follow-through for kit-facing docs.
- **Must NOT do:** grade its own work (independent judge only); touch backend or mobile code; claim a loop is proven without a full end-to-end run (two re-probes: NOT proven — the floor is still open).
- **DoD:** kit loop proven end-to-end on a fresh run (taste lock → gate green → independent grade → scores, no self-grade); all open probes have a canonical record or a written unblock spec.
- **Work queue (proposed; MIE-4..MIE-10 already awarded on the board):**
  - D45 — Rename follow-through, kit-facing set: 63 RENAME lines in 25 files (83 lines / 31 files total incl. KEEP 2 + DECIDE 18); plugin manifests + install docs + clone URLs rename as one set; state-dir + kit-marker rows 66–70 (DECIDE) rename only together, tested on a fresh + an existing install.
  - D46 — Land D16–D41 into `skills/frontend-kit/references/decisions.md` (currently stops at D15); owners land their own decisions — Milo (D16–D19) + Migga (D20–D35); Mie verifies the landing; re-verify each number free on latest main first.
  - D47 — Gate correction: pa11y stays web-only; the native-app a11y gate is the manual checklist (VoiceOver/TalkBack + 200% text on the real phone). Record "N/A — native app" for pa11y on the app; never fake a pass.
  - D48 — Probe-backlog triage: count Drive zips with no canonical record, list probe numbers, prioritise the lowest-numbered uncovered zips. Probe verification is parent-owned — its canonical records land under `clean-env-test/` (`clone-probe-*/` dirs + run-log entries); read those, do not redo the verification.

### (c) Ban Backend — Backend

- **Owner:** Milo (after M3 lands). Backend track announced on the board.
- **Responsibilities:** Convex free tier for persistence + Supabase Edge Function free tier for the AI endpoint (free-tier model API only); Convex AI Gateway is OUT — it needs a paid plan. One TS codebase; per-agent scoped dev deployments on free tiers; one AI endpoint first, live on the real phone by halfway; share-link persistence (`/r/<id>`, no accounts); server-side demo-run counter (increments only on a completed real-AI run; no personal data stored); cost caps enforced in code (`max_tokens`, 1 retry max, 15 s timeout, abort on navigate-away); free-tier rate-limit defences.
- **Must NOT do:** build auth, profiles, or an admin panel (no sign-up wall before the AI flow); store names, emails, device IDs, IPs, or raw personal input; put provider keys anywhere the client can read them; depend on a mid-window cloud build; use Convex AI Gateway (paid) or any paid model API.
- **DoD:** walking skeleton (deployed page + real endpoint + real AI call, or a stub through the real endpoint) in hour 1; real AI flow live on the real phone twice by T+2:20; counter increments server-side, verified by the QC department on the phone (positive + negative test).
- **Work queue (proposed):**
  - D49 — Per-agent Convex free-tier dev deployments (one per agent, scoped); Supabase free-tier project for the AI endpoint, created close to build day and verified live — free tier pauses after 7 days idle.
  - D50 — AI endpoint = Supabase Edge Function (free tier) calling a free-tier model API only. Primary model `gemini-3.5-flash-lite` (verified 'Free of charge' in/out, no shutdown announced); `gemini-3.8-flash` tried first only if the morning AI Studio check confirms it free-tier-eligible for the team's project; fallback Groq `openai/gpt-oss-120b` (30 RPM / 1,000 RPD / 8,000 TPM / 200,000 TPD, 429 on exceed). `gemini-2.5-flash` is deprecated, shutdown 1 Dec 2026 — do NOT pin it. Over-limit fails 429, never bills — only if no billing account is linked (Tier 1 requires linking one — do NOT link one). NEVER: Convex AI Gateway (paid — AiGatewayDisabled otherwise; Starter '$0/month' still counts as a paid plan for the gateway), GPT-6 Luna (no verifiable source — CHƯA ĐỌC), GPT-5 mini/nano, Sonnet/Haiku, any OpenAI/Anthropic key, any paid model API. Spend rule: $0.00 — no paid key exists in the plan. Cost caps in code (`max_tokens`, 1 retry max, 15 s timeout, abort on navigate-away) still apply. Exact quotas: `swarm/free-tier-ai-path.md`.
  - D51 — Results + counter schema (one results table, one counter record; `source: demo | share-link | first-user | pitch`; stub runs excluded from the pitch number; no personal data; live log + first-users wall read from the same table — Migga builds the screens, D verifies).
  - D52 — Free-tier rate-limit defences (Gemini free tier fails rather than bills): 1 retry max with 2 s back-off, then cached last-good result; rehearsed "rate-limited" line; never fire two AI calls for one tap.

### (d) Ban Mobile — Mobile

- **Owner:** Migga (after MIG-3 lands). Mobile track announced on the board.
- **Responsibilities:** Expo + React Native + TypeScript, SDK 58 (store Expo Go is SDK 58-only; SDK 57 dead — tonight's phone check confirms on the exact demo phone); `theme.ts` tokens before any screen (semantic colours, 4-pt spacing, radius, type 34/28/20/16/14/12, system font only); Expo Router; Zustand (client) + TanStack Query (server, never duplicated); `expo-image`, `expo-secure-store`; AI streaming via `expo/fetch` only (Hermes `response.body` is null); kill-and-reopen on the real phone; degraded rungs R1–R3.
- **Must NOT do:** start an EAS build mid-window (free queue 90+ min at peak); EAS free tier only — no paid builds, no paid plans anywhere; use `localhost` URLs; load a custom font in 5 hours; switch to NativeWind v4 (SDK 57 pairing UNVERIFIED); introduce a new native module after T+2:20 (13:20); use `expo-glass-effect` (iOS 26+ only — buys nothing on the demo phone).
- **DoD:** sample SDK 58 project opens in Expo Go on the exact demo phone tonight (tunnel, mobile data, kill-and-reopen passing); Slice 1 live on the real phone by T+2:20; freeze-gate kill-and-reopen in front of a human at 15:00 with the exact pitch input.
- **Work queue (proposed):**
  - D53 — SDK 58 scaffold + tonight's phone check (Expo Go version read aloud; 5 native modules install-checked: reanimated, linear-gradient, @expo/ui, blur, haptics).
  - D54 — `theme.ts` lock + 10–15-line DESIGN.md (human-written from 2–3 references; Yates backbone as principles, not pixels).
  - D55 — State wiring: Zustand `persist` + `partialize`, TanStack offline queue (mutation defaults at module load, `shouldDehydrateMutation` filter), kill/reopen matrix (last result + draft + theme survive; in-flight stream correctly does not).
  - D56 — Degraded rungs A1 (canned result, labelled "Example result") / A2 (last good, timestamped) / A3 (bundled seed JSON, labelled "Offline demo data"); rehearse all three at 15:00. Naming: degraded rungs are A1–A3; fallback rungs are F0–F5 (§1(g)). A1≠F1 (A1 is canned-result, F1 is bundled-JS live AI); A3≠F3 (A3 is bundled seed, F3 is backup video).
  - D70 — Run the a11y gate on the demo phone 15:00–15:30 (owner: Migga, verified by D): contrast, tap targets, labels, dynamic type 200%, screen reader walkthrough, reduced motion, safe area.

### (e) Ban Security — Security

- **Owner:** Mie (after MIE-4..MIE-10). Security track announced on the board.
- **Responsibilities:** secrets hygiene (no provider keys in the repo or the bundle; `.env` in `.gitignore`; gitleaks green); keys live in backend secrets only, tokens in `expo-secure-store` (never AsyncStorage, never `EXPO_PUBLIC_` vars); AI-endpoint abuse guards (input validation, per-call caps, no double-submit); the endpoint's negative tests (empty / adversarial input → graceful message, never a crash or blank screen).
- **Must NOT do:** build an auth system for the demo (the demo has no sign-up wall); store personal data anywhere (counter proves use, it does not surveil users); invent a threat model without evidence.
- **DoD:** gitleaks green on the product repo; endpoint passes the adversarial-input test on the real phone; no secret appears in any submitted artefact.
- **Work queue (proposed):**
  - D57 — Secrets audit of the product repo + submitted artefacts (gitleaks + manual `.env` / key grep before 16:00).
  - D58 — Endpoint abuse guards: input validation + per-call caps + 1-retry rule, verified by QC with empty/adversarial input.
  - D59 — Secure-store-only rule for tokens, enforced in code review (no AsyncStorage token, no `EXPO_PUBLIC_` key).

### (f) Ban QC & Điều phối — QC & Coordination

- **Owner:** Muse (integrator, role A). Owns `main`, `CONTRACT.md`, merges, decisions, the board, and the run log.
- **Role note (red-team S7):** FLEET §1 separates A (Integrator — only merger, does not grade) from D (QC/evidence — never merges, assigned at run start by fit). The parent's track split names Muse 'Integrator/QC'. Until the coordinator confirms whether Muse holds both hats (grading then done in a fresh context by a subagent not directed on that slice) or D is assigned to another agent at run start, D-owned rows below are marked 'D-assignee (TBD at run start)'.
- **Responsibilities:** independent verification of every claim (URL + access date; QC opens every link); dedicated red teams; merge order and ownership enforcement (file → agent → round); the coordination machinery (§2 — the 12 blocking gaps); rehearsal FLEET-2 and run start FLEET-3; the 5-minute group watch; group protocol: agents @muse in the team group, never the human owner — Muse is the coordinator (standing rule 13/11); run-log transcription at every merge; the cut order (evidence/growth extras cut before the core; never cut the live AI flow, the demo script, the backup recording, the deterministic gate, or the final human verification).
- **Must NOT do:** build features; merge its own unreviewed work; grade a builder's work (independent judge only); silently skip a rehearsal (record it as explicitly skipped with the risks accepted, or run it).
- **DoD:** FLEET-2 run (or explicitly skipped with risks accepted); deputy + backup named from agents whose machines pass the §9 gate-tooling check; TOOLS + MODELS inventory blocks filled for every agent; ownership table filled for every live slice; run log current (no event older than one merge behind).
- **Work queue (proposed):**
  - D44 — `docs/EVIDENCE.md` template in the product repo (D-owned file; in-app "Why this exists" screen reads from it, never the reverse — Migga builds the screen, D verifies; the screen is Slice 2 at the earliest); also covers the demo-insurance 'before' capture (30 s of the user's current workaround, filed before 11:00). Depends on: FLEET-3 (product repo exists).
  - D69 — Pre-consent 3 target users before build day (owner: D-assignee, TBD at run start): target 3, floor 1; consent + contact recorded privately by D, never in the repo; link sent only after T+2:20 Slice-1-green.
  - D60 — Fix the 12 blocking coordination gaps (§2) before the run starts — including FLEET-3 (product repo created + push access + branch protection + URL on board), B3, and B4.
  - D61 — FLEET-2 rehearsal: one small vertical slice + phone smoke test (inventory, dispatch, product-repo merge, CONTRACT-in-20-min, deploy).
  - D62 — Run-log transcription (owner: Muse — transcription is integrator work per protocol; independent verification of the entries is D's): all 13/11 coordination events (PR #4 opened/reviewed, PR #5 opened/CI-green/verification done 09:40 NOT LANDABLE docs-only, MIE-4..MIE-10 awards, D33–D35 awards, coordinator notes to Mie 09:07 and to Migga 23:50 + 02:09) + adopt the BUFFET-MODE.md §3 schema (`ts`, `actor`, `term`, `event`, `slice`, `board-row`, `board-fields`) for new entries. Note: 57 of 58 existing lines lack `board-row`/`board-fields` (line 4, B6 land, carries both); 0 carry `actor` or a standalone `term`.
  - D71 — Submission pack by 16:00 (owner: Muse): format-independent checklist + verbatim pre-built/day-built disclosure; artefact format confirmed at venue before 11:00 (NEEDS-HUMAN).
  - D63 — Board status vocabulary fix: rewrite every row to the binding set (`submitted → working → completed / failed / canceled`, plus `input-required`, `declined`); "done" / "assigned" / "in review" are not in the set.
  - D64 — Merge order for `verify.sh`: MIE-5/6/7 + MIG-3 all touch it — record the explicit order on the board and fill the ownership rows.

### (g) Ban Dự phòng & Khôi phục — Resilience & Recovery (creative addition)

- **Owner:** D-assignee (TBD at run start — see §1(f) role note) owns the plan and rehearsal; Migga (Mobile) executes the phone-side rungs; Milo (Backend) owns the cached-result path.
- **Responsibilities:** the fallback rungs F0–F5 (F0 live phone → F1 bundled-JS preview build → F2 cached last-good, timestamped → F3 backup video → F4 honestly-labelled canned stub "demo mode" → F5 pitch without the phone, conceding the 40); the backup video (real phone, one continuous take, kill + reopen + tap + AI working, <90 s, recorded at freeze and at final rehearsal, copied to a second device, timestamp-labelled, never presented as live); the 15:50 rule (freeze code, never start EAS, restart Metro only, submit by 15:55); the "before" capture (30 s of the user's current workaround).
- **Must NOT do:** present a lower rung as a higher one (the pitch never pretends); hand-write a stub response to look better than the model (the stub is a real model output from that day, pasted in); delete the Slice-0 stub "to be safe" (it is the last rung).
- **DoD:** backup video exists on two devices before 16:00; every rung rehearsed at 15:00; the presenter can name the current rung in one sentence at any moment.
- **Work queue (proposed):**
  - D65 — Backup-video protocol: two takes (freeze + final rehearsal), second-device copy, timestamp label, intro line ("recorded live at [time] today").
  - D66 — Rung rehearsal checklist at 15:00 (owner: D-assignee + Migga phone-side; degraded rungs A1 key-kill, A2 airplane mode + kill/reopen, A3 airplane mode + clear data).

### (h) Ban Tốc độ & Chi phí — Speed & Cost (creative addition)

- **Owner:** Muse (QC) owns the clock; Milo (Backend) owns the spend; Migga measures the perf budget (D68). Independent grading of cost/perf claims is D's (D-assignee, §1(f) role note).
- **Responsibilities:** the 5-hour clock (agents stop 15:00, hard stop 15:30, humans verify 15:30–16:00 — the runbook's §6 times govern; the goal file's "4:15–5:00 humans finalize" line is stale and must be aligned); spend: **$0.00 — free tiers only. The $5 cap is RETIRED; the binding constraint is free-tier rate limits (Gemini free tier fails rather than bills — the safe failure mode, but still a failure on stage). Any call that would bill must not happen; if a paid path leaks in, stop and fix.** The paid-model per-call table in the feasibility brief is a record of the retired plan, not the plan. The perf budget (cold start ≤2 s perceived, hard fail >3.5 s; JS bundle ≤5 MB; AI first token ≤3 s, full ≤15 s; tap feedback ≤100 ms; 60 fps lists); the cut order when slow (Lottie/heavy animation → blur → off-screen images → second AI feature → dark-mode variants; never cut skeleton/loading states, error + retry, 48px targets, contrast fixes).
- **Must NOT do:** spend on a paid tier on the day — $0.00 rule: no paid plan, no paid model API, no paid tool anywhere in the plan (Convex free tier, no pause; Supabase free tier pauses after 7 days idle — verify live on the morning); quote a rate limit that was never read (Gemini free-tier RPM/TPM/RPD: Google no longer publishes per-model limits — the AI Studio dashboard check is the only source; 10 rapid test calls instead).
- **DoD:** morning-of check done (free-tier dashboards: Gemini quota/usage, Supabase usage; 10 rapid demo calls, none throttled); perf budget measured on the demo phone at freeze; spend $0.00 (free tiers only).
- **Work queue (proposed):**
  - D67 — Free-tier enforcement + morning check (owner: Milo): no paid key or paid plan anywhere in the product (grep the repo for paid model IDs/keys before 11:00); NO billing account linked to the Gemini project (linking one enables Tier 1 billing — forbidden under the $0 rule); free-tier dashboard checks per `swarm/free-tier-ai-path.md` §d (Gemini quota/usage in AI Studio — Google no longer publishes per-model free-tier RPM/TPM/RPD, limits 'not guaranteed', so the dashboard check is the only source of truth; Supabase usage; Convex plan = Free, no payment method on file; Groq limits; no card on file anywhere) + 10 rapid test calls, sequential ~10 s apart, on the exact demo input, none throttled (incl. one deliberate 429-observation call and one end-to-end phone → Edge Function → model → Convex counter check); keep ALL demo-day Gemini calls under ~20 (rest go to Groq, 1,000 RPD verified, or the cached answer); fallback = Groq `openai/gpt-oss-120b`, else honest stub + cached last-good (never a paid model). Paid-model lifecycle warnings RETIRED (GPT-5/Sonnet no longer in the plan); `gemini-2.5-flash` deprecated, shutdown 1 Dec 2026 — re-check the model ID on the morning. Biggest open risks: Gemini free-tier limits for the team's exact project are UNVERIFIED until the AI Studio check, and `gemini-3.5-flash-lite` quality on structured-JSON + short prose is UNVERIFIED until the 10-call morning test.
  - D68 — Perf budget measurement on the demo phone at freeze (cold start, bundle size, first token, full answer, tap feedback) — measured, not claimed. Cut order enforced (Lottie/blur/off-screen images/second AI feature/dark variants first; never cut skeleton, error+retry, 48px targets, contrast fixes).

## 2. Coordination machinery — the 12 gaps that block the run (Ban QC & Điều phối, D60)

All verified 2026-11-13 by an independent read of the runbooks + board + coord files (file:line in the audit file `swarm/coord-gap-audit.md`).

| # | Gap | Fix |
|---|---|---|
| 1 | No deputy / backup named (board: both TBD) | Name deputy + backup before 11:00, only from agents whose machines pass the §9 gate-tooling check. |
| 2 | FLEET-2 rehearsal never run (board: `submitted`) | Run it today (D61) or record it explicitly skipped with risks accepted. FLEET §10: "Build day does not start on an unrehearsed workflow." |
| 3 | FLEET-3 run start never run (board: `submitted`) | Create the product repo, grant push access, set branch protection on `main`, record its URL on the board before 11:00. |
| 4 | No TOOLS / MODELS inventory on main for any agent (0 filled blocks) | One verified TOOLS + MODELS block per agent in its own `coord/<name>.md` before dispatching any build-day slice. FLEET §2 forbids publishing a slice before the inventory is read. |
| 5 | Mainline `buffet/main` does not exist (no `buffet/*` refs on the remote; all real work is on `main`) | Create `buffet/main` from `main` and push it, or amend the board + runbook to name `main` as the mainline. |
| 6 | Run trigger empty (`Brief: — / Figma link: — / Target: — / Return time: —`) | Fill it verbatim before the humans leave; the idea choice is NEEDS-HUMAN (§4). |
| 7 | B4 three-agent cold-clone test never run | Run B4 today (cold clone + install + verify + one slice + TOOLS + CENSUS) or record the §9 gate-tooling assertion as unproven. |
| 8 | B3 Figma converter scripts do not exist | Build the two scripts today, or strike Figma paths A/B and run Figma-degraded. |
| 9 | Ownership table empty (gap 10) | Fill the ownership table (file → agent → round) for every live slice before the run. |
| 10 | No task files beyond B6 (gap 11) | Write one six-field `coord/tasks/<slice-id>.md` per live slice and link it from the board row. No board row is claimable until all six fields are filled. |
| 11 | Stale "Mie never posts" lines (gap 17) | Strike the ban in BUFFET-MODE §1/§2/§5/§10, `coord/mie.md`, and `coord/muse.md`, replacing it with the board's 09:07 instruction (Mie posts in the group and must answer when called). |
| 12 | Stale "no agent-to-agent chatter, ever" lines (gap 18) | Amend both runbooks to the discussion-channel rule (repo = official record, group = discussion + @mentions). |

Also fixed under D60 (slows-tomorrow, same pass): delete the shared-D20 rule (D20–D32 = Migga, D21 = Mie — already allocated); file the missing M1/M2 cross-check reports (or record them skipped with reason); assign MIE-1 (highest priority, the remaining real-world check) or record it as the first run-start task; align the goal file's human-window times to FLEET §6; assign the next free GAP number (GAP-13 is already spent — MIE-1 must not reuse it) and keep a GAP registry on the board.

## 3. Full missing-area list (swarm coverage)

Beyond the parent's 8 research topics (backend, database, mobile, security + AI integration, DevOps/release, Testing/demo rehearsal, Product/idea-validation — NOT the swarm's), the crawl found these missing areas, all covered by a swarm brief or a gap row above:

1. **Coordination / runbook gaps** — 32 gaps (12 block, 13 slow, 7 cosmetic) — `swarm/coord-gap-audit.md`.
2. **Evidence & growth** — evidence artefact, share link + counter, first-users wall, live log — `swarm/evidence-growth-brief.md`.
3. **Accessibility** — WCAG 2.1 AA checklist, contrast audit of `theme.ts` (2 tokens fail), tap targets, screen reader, dynamic type 200%, reduced motion; pa11y-is-web-only correction — `swarm/app-quality-brief.md`.
4. **Performance** — budget (cold start ≤2 s, bundle ≤5 MB, first token ≤3 s, full ≤15 s), waiting-state spec (skeleton, never bare spinner), cut order — `swarm/app-quality-brief.md`.
5. **State management** — Zustand + TanStack split, offline queue, kill/reopen matrix, degraded rungs — `swarm/app-quality-brief.md`.
6. **Design tokens (mobile)** — `theme.ts` verbatim, Yates backbone as principles, ban list, visual stack order — `swarm/phone-submission-pitch-brief.md`.
7. **Phone checks** — Expo Go / SDK trap, tonight's checklist, run-start / mid-sprint / freeze gates — `swarm/phone-submission-pitch-brief.md`.
8. **Submission** — checklist + verbatim disclosure wording + 15:50 rule; format/portal CHƯA XÁC MINH — `swarm/phone-submission-pitch-brief.md`.
9. **Pitch** — 5:00 arc mapped to 40/35/25, demo beats, anti-patterns — `swarm/phone-submission-pitch-brief.md`.
10. **Feasibility method** — 15-min triage, scorecard, cut test, pre-mortem, kill-switches — `swarm/feasibility-cost-backup-brief.md`.
11. **Cost** — FREE-ONLY (parent 09:41): $0 spend rule; paid-model per-call table + $5 cap SUPERSEDED (kept in the brief as a record of the retired plan, not the plan); verified free path `gemini-3.5-flash-lite` primary + Groq `openai/gpt-oss-120b` fallback; rate-limit defences on free tiers (Gemini free tier fails 429 rather than bills, only if no billing account linked) — `swarm/feasibility-cost-backup-brief.md` + `swarm/free-tier-ai-path.md`.
12. **Backup / resilience** — rungs 0–5, backup video, canned stub honesty rules, cached last-good — `swarm/feasibility-cost-backup-brief.md` + department (g).
13. **Rename follow-through** — 63 RENAME lines in 25 files (83 lines / 31 files total incl. KEEP 2 + DECIDE 18), 3 functional risks (plugin manifests + docs as one set; clone URLs + `cd` steps; state-dir + kit-marker coupling) — `swarm/rename-hygiene-list.md`.
14. **Repo hygiene** — 13 board scrub rows (15 lines); GOAL.md 11 stale rows (5 flatly wrong) — `swarm/rename-hygiene-list.md`.
15. **Analytics (counter / live log)** — server-side demo-run counter + public live log, no personal data — `swarm/evidence-growth-brief.md` §3–§4.
16. **Cross-check discipline** — M1/M2 cross-check reports missing; report-before-land rule unenforced — audit gap 22.
17. **GAP registry** — GAP-13 collision risk; no registry — audit gap 24.
18. **Merge serialisation** — `verify.sh` shared by MIE-5/6/7 + MIG-3 with no recorded order — audit gap 23 (D64).

**Not covered by the swarm (parent-owned, in flight):** backend/database/security deep briefs (all 8 landed 09:24–09:33); AI integration, DevOps/release, Testing/demo rehearsal, Product/idea-validation research subagents.

## 4. NEEDS-HUMAN (do not decide — exact questions)

1. **The hackathon idea.** Which idea do the humans hand the agents? (No triage can run without it; the fallback idea must be picked the night before.)
2. **Demo-phone identity.** Which single phone is the demo phone — the Android phone (GOAL.md) or the iPhone 11 Pro Max (mobile toolkit report)? Every phone check in §1(d) runs on that exact phone.
3. **Submission artefact format.** Where to submit, required artefacts, demo-video required or optional, exact 16:00 cutoff mechanics — confirm with the organisers at the venue before 11:00.
4. **Spending.** Free-only ($0.00 rule): any spend at all needs an explicit human yes — no paid tier, no paid model API, no paid tool is in the plan.
5. **Credentials / accounts.** Any account creation, key, or access grant (product repo push access, backend project ownership, Expo account) — humans grant; agents never create credentials.
6. **Free-tier model fallback.** If the Gemini free tier cannot serve the demo (quota/retirement), the fallback is the second verified free-tier model API in `swarm/free-tier-ai-path.md` — or the honest stub + cached last-good. No paid fallback exists under free-only.

## 5. Boundaries

- The swarm does NOT commit, push, merge, message the group, SSH to any laptop, or spend money. The coordinator lands repo changes and sends group messages.
- The swarm does NOT redo: PR #5 verification, the probe recoveries, the backend/mobile 12/11 reports, or the parent's 4 research subagents (AI integration, DevOps/release, Testing/demo rehearsal, Product/idea-validation).
- The clone probe backlog is verified by the parent's probe-verification work; the swarm only triages the count (D48) — coverage gaps below 50 are 48, 49, 50; coverage above 90 is UNVERIFIED.
- Pitch delivery is human-owned; no D-row covers it (decision, not an omission).
- M3 (Milo), MIG-2/MIG-3 (Migga), MIE-2/MIE-4..MIE-10 (Mie) keep their existing owners and D-numbers; this draft adds departments around them, it does not reassign them.
- **Free-only (parent 09:41):** no paid plans, no paid model APIs, no paid tools anywhere in the plan — Convex AI Gateway, GPT-5/Sonnet/Haiku, paid EAS builds, and the $5 spend cap are OUT; the demo path is $0 (Supabase Edge Function free tier + free-tier model API).
