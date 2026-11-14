# coord/mie.md — handoff file (Mie)

> **This file belongs to Mie.** Only Mie edits it. Never edit another agent's
> file, never edit `coord/BOARD.md` (coordinator-owned), never rewrite history
> in `coord/run-log.jsonl` (coordinator-only, append-only — log in this file;
> the coordinator transcribes).
> Protocol: `BUFFET-MODE.md` §5. Board: `coord/BOARD.md` (read-only for Mie).
> Runbook: `BUFFET-MODE.md` — your role is in §1.

## Role

Mie is one of the four agents in this run (Muse, Mie, Migga, Milo). Role per
run: builder (one instance per direction), independent expert, or independent
judge — as assigned on the board. A builder never grades its own work; an
expert judges ONLY its own domain, from the artifacts, never from the builder's
reasoning; a judge grades 1–5 on Type / Layout / Colour / Space with one
evidence line per score.

**Mie cannot speak in the Optimus group at all.** Coordination is through this
file + the repo only. If a milestone needs to reach the humans, the coordinator
(Muse) posts it.

**Mie is never deputy and never backup deputy** — a Mie coordinator would
either stop milestone posting for the rest of the run or post in violation
of the rule above. If the board ever names Mie as deputy, that is an error:
write it in this file and keep working as a worker; do not take over.

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
  empty cycle, max 2 h, reset to 15 min the moment a slice appears.
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

- Work on your own branch `buffet/mie` and push that branch. Only the
  coordinator merges branches into the buffet mainline — never push to the
  mainline directly, **never force-push** (forbidden for all agents including
  the coordinator).
- If push access is not yet granted, work on a fork and open a pull request —
  the coordinator merges the PR (see the §9 section on the board).
- A merge conflict on your own file: routine pulls are `--ff-only`; rebase
  only your own unpushed commits — verify first with
  `git log --oneline origin/buffet/mie..HEAD` (those are the unpushed
  commits; if the list is empty there is nothing to rebase); never rebase
  commits already on origin (the next push would need a force-push, which is
  forbidden); never rebase another agent's branch. If a pull fails on
  `--ff-only` and the branch has already-pushed commits, stop and let the
  coordinator see it — do not rebase. Keep both entries on a conflict, never
  delete the other side's lines, and note it in this file for the coordinator
  to transcribe.

## The Optimus group

- **Mie never speaks in the Optimus group at all.** The group is for
  HUMAN-FACING MILESTONES ONLY, posted by the coordinator (Muse). Do NOT
  propose adding Mie to it.

## Log

- (no entries yet — append `CLAIM <slice-id>` + plan + files + timestamp and progress here; the coordinator transcribes into `coord/run-log.jsonl`.)

## Mie handoff — ongoing development (from 2026-11-12)

- 2026-11-13 01:08 UTC — START. Main moved: the brief's d92fbda / 80d04a5 are stale; work starts from aa93e75 (`git ls-remote` HEAD = aa93e750766fbb507f9ae334b5cdc391cad74285, "board: PR #4 review (NOT LANDABLE yet — D23/D30 cites +9, CI approved), D33=F6, D34=L1, D35=GAP-14 awarded"). First decision number is D21 (D20 taken by Migga via PR #4, D20–D32; verified free on main: decisions.md holds D1–D15 only, D16–D19 reserved for Milo M3).
- CLAIM MIE-1 | plan: real-MacBook clone-and-go (fresh clone → ./install.sh → ./verify.sh → Brief-1 probe) | files: install.sh, verify.sh, skills/frontend-kit/** (probe only) | board-hash: aa93e75 | at: 2026-11-13 01:08 UTC | status: BLOCKED — the MacBook has not been opened by its owner yet, so SSH cannot reach it. NOT a Tailscale fault (owner-confirmed via coordinator, 2026-11-13); no Tailscale check needed. Waits for the owner to open the machine.
- CLAIM MIE-2 | plan: verify the macOS CI failures live, council-decide the fix (D21), implement on fork branch, QC + red team, prove with a CI run on the branch (macOS jobs green), open a PR to upstream main | files: install.sh, verify.sh, skills/frontend-kit/scripts/gate/** | board-hash: aa93e75 | at: 2026-11-13 01:08 UTC | status: IN PROGRESS — council of 3 experts done; CI-log verification done (see milestone below).
- CLAIM MIE-3 | plan: MacBook TOOLS inventory (BUFFET-MODE.md §2) + MODELS block (FLEET-MODE.md §2) | files: coord/mie.md (inventory section) | board-hash: aa93e75 | at: 2026-11-13 01:08 UTC | status: BLOCKED — same as MIE-1: waits for the owner to open the MacBook.
- 2026-11-13 01:08 UTC — MILESTONE: fork ready. Fork: https://github.com/ashley8127/frontend-agent-kit (parent phamTuan207/frontend-agent-kit). Branch: mie/mie-2-macos, from aa93e75. gh authenticated on the VM as ashley8127 (device flow, owner-approved). Commit identity configured repo-local: phamTuan207 <232407559+phamTuan207@users.noreply.github.com>.
- 2026-11-13 01:08 UTC — MILESTONE: MIE-2 council verdict (D21, one decision, both halves, with a severability clause — see the D21 entry in the PR). Council (3 independent experts, reports in the coordinator's workspace): (A) install.sh forensics — install.sh itself is unchanged since 1464fbb (green then); the Install step fails at its fatal tail (install.sh:2137 runs ./verify.sh, default mode, and exits 1 on failure), so the embedded verify.sh is the failing code. (B) §5c sed audit — the sed hypothesis is CONFIRMED for both site classes by the FreeBSD sed man page + source: `sed -i -e …` (4 fill-helper sites) dies on `lstat("-e")`, leaving the PENDING skeleton line; bare `sed -i 's/…/…/'` (10 sites) dies on `invalid command code`, file unchanged; the three `\x..` sites need real UTF-8 bytes (`$'\xe2\x80\x8b'`, `$'\xd0\xb0'`) because BSD sed has no `\x` escape; a second blocker in the same section is 18 bare `sha256sum` uses with no `shasum` fallback. Recommended fix: one OS-dispatched `sedi` helper + one `sha256_file` helper + the byte variables; `sed -i ''` unconditionally is disproved on GNU (rc=2). (C) scope — D21 is free; one decision covering both halves; the "19 §5c cases" figure was unverified from files alone; the §5c region sits inside Milo's §5 fixture, so the PR states the owner's "macOS is yours" authorisation and requests Milo/Muse review.
- 2026-11-13 01:08 UTC — MILESTONE: CI-log verification (run 43315591520, main HEAD, fetched with authenticated gh). PROVEN on the log: exactly 19 FAIL lines per macOS job (19 macos-15 + 19 macos-26), all `judge-artifact (D15)` §5c cases downstream of the fill failure — the "19 §5c cases" figure is now confirmed on main, not a PR #3 snapshot. The log shows 22× `sed: -e: No such file or directory` and 4× `invalid command code`, matching the council's two predicted failure modes. The §3b hypothesis (H1, `sha256sum` with no `shasum` fallback) is REFUTED on the CI runners: the log shows `OK: vendored-allowlist.txt matches the vendored taste tree hash-for-hash (27 entries, pin v2.5.1 f6b76575f949707b4e3c37cd86cb44b0b98643e8)` — the runner image provides `sha256sum` (Homebrew on the image). H1 stays a real defect for a stock MacBook only (no `sha256sum` there); the §5c `sha256_file` fix is included in D21 for the MacBook target, not for CI green. Next: implement D21 on this branch.
- 2026-11-13 — NOTE (user instruction, 2026-11-13, relayed by the coordinator): milestones are ALSO reported to the Optimus group as human-facing reports, posted by the main agent as relay; the repo remains the coordination record. The "Mie never posts in the Optimus group" lines in the Role section above are superseded for milestone reporting by this instruction. The @mie reply rule also applies in the group and in the 1-to-1 DM thread: when called, Mie answers there.
- 2026-11-13 01:16 UTC — MILESTONE: D21 implemented (commit 76c7042, pushed to fork branch mie/mie-2-macos; identity verified). verify.sh: OS-dispatched `sedi` helper + `sha256_file` helper + `zwsp`/`cyr_a` byte variables; §3b hash loop uses the helper; all 14 `sed -i` sites → `sedi` (three `\x..` sites use the byte variables); all 18 bare `sha256sum` uses in §5c → `sha256_file`; loud-fill adjunct on the four fill sites. decisions.md: D21 entry appended after D15. Verification: `bash -n` passes on all five CI scripts; CI lint grep clean; local `./verify.sh --strict` on Linux: §5b 103 OK / 0 FAIL, §5c 126 OK / 0 FAIL — exactly the M2 baseline (overall exit 1 from 198 environmental failures outside §5b/§5c: no installed kit copy, no Chrome, no playwright-cli on the bare VM). One §5c UNVERIFIED: case (104)'s gitleaks half (no gitleaks on the VM). Two deliberate deviations recorded as residuals in D21: (1) the 3181 loud-fill message names the file path explicitly (`$1` is unset at top level under `set -u`); (2) `sha256_file` accepts a no-argument stdin form, used only by the two `printf`-piped sites. Independent QC + dedicated red team launched (separate agents); macOS proof (fork CI macos-15/macos-26 green) still owed before the PR.
- 2026-11-13 01:23 UTC — MILESTONE: red-team verdict FAIL (report in the coordinator's workspace). SEVERE S-1: `jr_prep` aborts on bash 3.2 at the first expert kind — CI log (run 43315591520, both macOS jobs): `verify.sh: line 2959: grader_args[@]: unbound variable`, right after case (29)'s OK line; verify.sh dies with no summary, cases (30)–(106) never ran on macOS. Cause: `grader_args=()` for expert kinds + `"${grader_args[@]}"` under `set -u` throws on bash ≤4.3 (fixed upstream in 4.4); first expert call is `jr_prep 6 expert-motion`. D21 as implemented does not fix this — macOS would still abort at the same point. Also M-1/M-2 (D21 entry overclaims CI proof for the 8 unreached bare-sed sites and the §5c sha256sum sites), M-3 (gate.sh:1120–1121 bare `sha256sum` — follow-up, out of D21 scope), 5 MINORs (per-job vs whole-log sed counts, +20 line shift, `sedi` `--` guard, loud-fill double-reporting, 3-file range note). What survived: diff scope, Darwin multi-`-e` form, all 18 `sha256sum` replacements, `sha256_file` correctness, `\x` bytes exact, lint/`bash -n` clean, §5c counts re-verified (103/126). Next: fix round (`jr_prep` + D21 entry corrections) after the independent QC verdict lands; then re-QC + re-red-team the fix. QC still running at this entry.
- 2026-11-13 01:24 UTC — MILESTONE: independent QC verdict FAIL (report in the coordinator's workspace), confirming the red team independently. The implementation code PASSED every QC check: scope exactly 2 files; all 14 sed + 18 sha256sum sites complete; helper unit checks run by QC; `bash -n` + exact lint grep clean; `./verify.sh --strict` run TWICE by QC: §5b 103 OK / 0 FAIL, §5c 126 OK / 0 FAIL / 1 UNVERIFIED (case 104 gitleaks half); CI-log claims verified (19 FAILs/job, 22×/4× sed errors as cross-job totals, §3b OK, 0 `cannot hash`); hygiene verified (identity, linear history, fork-only). FAIL reasons (same as the red team, found independently): SEVERE-1 — omitted fatal bash-3.2 abort (`jr_prep`, line 584 in each per-job log; lines 584 and 2238 in the combined run log); SEVERE-2 — Defect 3 "these pass on the CI runners" is unobserved (cases (51)+ never ran); MEDIUM-1 — "ten bare sites fail compilation" presented as CI-proven (only the case-(27) pair observed); MINOR-1 — residual (c) calls `$1` "(unset)" without qualifying "when invoked with no arguments". Fix round dispatched (separate agent): `jr_prep` branch-on-kind fix + D21 entry corrections + GAP-15 proposal (gate.sh:1120–1121, M-3 follow-up, awaiting award — not implemented); then re-QC + re-red-team on the fix.
- 2026-11-13 01:29 UTC — MILESTONE: D21 fix round done (commit 2687d70, pushed to fork branch mie/mie-2-macos; identity verified). `jr_prep` fix (verify.sh:2975–2991): the `grader_args` array is gone entirely (grep confirms zero hits); branch on kind — expert branch calls node without `--grader judge-subagent`, non-expert branch with it; no empty array is ever expanded under `set -u` on any path; covers both `jr_prep 6 expert-motion` and `jr_prep 9 expert-ux`; `fail` message and log redirect byte-identical. D21 entry corrections: Defect 4 added (`jr_prep`, line 584 in each per-job log; lines 584 and 2238 in the combined run log, base `verify.sh:2959`, cases (30)–(106) unexecuted); Defect 3 corrected to EXPECTED-to-pass / UNOBSERVED; Defect 2 corrected to per-job figures (11×/2× per job) with the eight unexecuted bare sites (cases 34, 35, 42, 66, 68, 69, 70, 72) marked as mechanism predictions; residual (c) qualified; new residuals (f) line shifts (+20/+8), (g) loud-fill double-reporting measurement note, (h) `sedi` `--` guard NOT added (BSD form unverified, no current call site affected). coord/mie.md: PROPOSED GAP-15 line (gate.sh:1120–1121, verified free; gate.sh NOT touched). Verification: `bash -n` passes on all five CI scripts; exact CI lint grep clean; local `./verify.sh --strict`: §5b 103 OK / 0 FAIL, §5c 126 OK / 0 FAIL / 1 UNVERIFIED — identical to baseline, no regression. Fresh re-QC + re-red-team launched (new agents, round 2); macOS proof (fork CI) still owed after they pass.
- 2026-11-13 01:37 UTC — MILESTONE: re-QC round 2 verdict PASS on the code, no code findings (report in the coordinator's workspace). The docs citations in this milestone were wrong — corrected in the verifier-fix commit on this branch, with a focused re-read of the corrected lines only (see the verifier-fix milestone below). Verified independently from primary sources on fix commit 2687d70 (exactly 3 files vs 6ffbe67): `jr_prep` fix — `grader_args` gone (grep: 0 hits), no array declared in the helper, branch predicate identical to base, both expert calls covered, token comparison proves expert line = base minus the grader token and non-expert line = base with the token in the same position, `fail` message + log redirect byte-identical (source lines sit 2 spaces deeper from nesting — Observation 1), bash-3.2-safe, ≤4.3 mechanism re-verified from upstream bash CHANGES 4.4-rc2 §3a and COMPAT item 54. D21 entry — Defect 4 citations read directly from the log (case-(29) OK at 583 in each per-job log (583 and 2237 in the combined run log) immediately before the abort, zero `RESULT:` lines, zero OK lines after), Defect 3 reworded (EXPECTED/UNOBSERVED, §3b OK at 412 in each per-job log (412, 1014, 1353, 2066 in the combined run log), 0 `cannot hash`), Defect 2 per-job figures re-counted (11×/2× per job, 19 FAILs/job), eight bare sites each mapped to cases 34, 35, 42, 66, 68, 69, 70, 72; residuals (c) qualified, (f) shifts verified (+20, +8, +28 total), (g) consistent with the 4 adjuncts, (h) no `--` guard added and all 14 call sites pass absolute paths. GAP-15 free on main; gate.sh and coord/BOARD.md untouched. Independent re-run: `./verify.sh --strict` exit 1, §5b 103 OK / 0 FAIL, §5c 126 OK / 0 FAIL / 1 UNVERIFIED (case 104 gitleaks half); all 198 failures outside §5b/§5c explained. Regression spot-check: helpers intact (`sedi` 16 hits, `sed -i` only at :96/:98; `sha256_file` 20 hits). Hygiene verified (identity, linear history, fork-only). Darwin/bash-3.2 execution remains CHƯA ĐỌC — the fork CI macOS run is still owed. Re-red-team round 2 still running at this entry; no PR until it lands.
- 2026-11-13 01:40 UTC — MILESTONE: re-red-team round 2 verdict PASS — no SEVERE, no MEDIUM (report in the coordinator's workspace). Sibling hunt (highest value): `jr_prep` was the only empty-array abort — every `[@]`/`[*]` expansion in verify.sh swept and classified (length checks on declared arrays, `EXPECTED` exit-1 guard, `HOSTS` forced non-empty, `UNI` seeded, `self_grade_dirs[*]` inside a `-gt 0` guard, literal non-empty lists); §5c has no array expansion except the fix's comment; `rp_prep`/`r3_prep` use a literal `--grader`; `"$@"` empty is proven safe on 3.2 by the CI run itself; the two `regrade --grader other-model` calls take the non-expert branch, preserving the original argv exactly. D21 corrections all verified (Defect 4 mechanism from upstream bash COMPAT item 54, per-job sed figures re-counted 11/2, eight bare sites verified, line shifts +20/+8 verified at seven anchors, residual (h) verified across all 14 `sedi` sites and all 97 `jr_fill_*` `$1` args). Round-1 fix intact; own `./verify.sh --strict` re-run: §5b 103 OK, §5c 126 OK / 1 UNVERIFIED, OK lines byte-identical to the fix log, counting ranges exactly full. GAP-15 verified free; gate.sh:1120–1121 read verbatim with the D9 fall-through confirmed; gate.sh untouched. Overclaim hunt: no macOS execution proof is claimed anywhere. Findings: 3 MINORs only — m-1 (Defect 3 "(51) onward" imprecise; earliest consuming case is (53)), m-2 (fix report's GAP-15 line `:143` now `:144` at HEAD — workspace citation only), m-3 ("byte-identical in behaviour" wording nit). Post-verdict wording corrections applied by the coordinator to the D21 entry per m-1/m-3 (m-1 confirmed by reading the (50)–(60) block setup: the five sites at 3539–3543 serve that block, earliest consuming case (53); m-3 reworded to "text-identical"); m-2 needs no repo change. Both round-2 verdicts are now PASS — next: open the PR to upstream main, whose CI run is the macOS proof (macos-15/macos-26 jobs must go green).
- 2026-11-13 01:42 UTC — MILESTONE: PR opened — https://github.com/phamTuan207/frontend-agent-kit/pull/5 ("D21: macOS portability for verify.sh — sedi + sha256_file helpers, jr_prep bash-3.2 fix (MIE-2)"), from fork branch mie/mie-2-macos to upstream main. Body carries the decision + QC + red-team verdicts + proof + the §5-fixture boundary wording + the Milo/Muse review request. CI run 43346473308 (pull_request) is `action_required` — fork PRs need maintainer approval before Actions run; the macOS proof (macos-15/macos-26 green, past `jr_prep 6 expert-motion`, §5c cases (30)–(106) executing) is pending that approval. Do not merge until the macOS jobs are green. MIE-2 implementation phase complete pending CI proof + Muse review.
- PROPOSED GAP-15 | gate.sh:1120–1121 bare sha256sum with no shasum fallback (D9 vendored exemption never applies on a sha256sum-less Mac) | evidence: red-team d21-redteam.md M-3 | status: proposed, awaiting coordinator award — do not implement before award.
- 2026-11-13 03:01 UTC — MILESTONE: PR #5 verifier docs fix (coordinator verification comment, 2026-11-13 02:42 UTC). Docs-only: corrected the four wrong CI-log citations (abort at line 584 in each per-job log, 584/2238 combined; case-(29) OK at 583, 583/2237 combined; §3b OK at 412, 412/1014/1353/2066 combined — all re-checked against run 43315591520's log); corrected the §3b quote to carry its `, pin v2.5.1 f6b76575f949707b4e3c37cd86cb44b0b98643e8` suffix; qualified the re-QC round-2 banner (PASS on the code; docs citations corrected with a focused re-read of the corrected lines only); Defect 3 reworded to (§3); residual (a) reworded — fork CI green proves the sed/bash/bytes thirds, the sha256sum-absence third remains owed to a stock-MacBook run; Boundary (1) reworded — 4 new FAIL assertions from the loud-fill adjunct. Same corrections applied to the PR body. No code change; no decision substance changed.
- MIE-6 DONE 2026-11-13 | branch `mie/mie-6-q3` | commit `18a7a12d1ab31dbf58493b84cd5ddbf6e45bac38` (base `907aeaa`) | files: `skills/frontend-kit/scripts/gate/gate.sh`, `verify.sh`, `skills/frontend-kit/SKILL.md`, `skills/frontend-kit/references/workflow.md`, `skills/frontend-kit/references/decisions.md` (D37) | fix: bare-relative `--target` (design/demo.html, design/v0.html, design/variants) no longer breaks the taste lock — `$target` is canonicalised to an absolute path (logical pwd), defence-in-depth strip arms, §3 hint for bare `tokens.css` from a root page, root tokens.css copies deleted, §5a regression test added | proof: pre-fix repro failed with `design/tokens.css is missing under design`, post-fix bare-relative passes the lock (demo note, lint clean); full `./verify.sh` on this VM exit 1 with 197 FAILs all environmental (no install/engine/Chrome/playwright/gitleaks) and §5a 9 OK / 0 FAIL; leg-2 static halves clean on the real §5 fixture page, full green needs CI (no Chrome here) | one deviation from the brief, recorded in D37: the negative control asserts `missing under $pf`, not `$pf/design` — the §1 message prints `$project_dir`, which for the demo target is the fixture root | no PR opened; pushed to fork for QC + red team.
- **MIE-5 (Q2, D36) DONE 2026-11-13** — lock-time template-integrity check. Branch `mie/mie-5-q2` (implementation commit `95229be`, rebased onto main `0d92f91` after PR #4 merged; D36 entry + this note follow in a second commit on the same branch). `lock` now runs `validateTemplateIntegrity()` before appending: demo.html byte-equal to the template, token-name set enforced (measured 70 distinct names / 83 occurrences from `templates/design/tokens.css`, method in D36), four design docs anchor-preserved with the three-signal stub refusal, `--allow-dropped-tokens` exact-set value flag recorded in lock notes + PLAN.md Amendments. verify.sh §5e (cases 107–128) green: full `./verify.sh` 278 ok / 0 fail in both default and `--strict` modes (1 warning: no system Chrome; 1 pending: Impeccable hook not wired). No PR opened yet — QC + red team next, per coordinator sequencing (MIE-5 lands after MIE-6).
- MIE-7 DONE 2026-11-13 02:53 UTC — branch mie/mie-7-q4, D38 round-budget enforcement in record + prepare. Files: skills/frontend-kit/scripts/judge-report.mjs (shared checkRoundBudget + roundBudgetStatus, ROUND_BUDGET_PER_DIRECTION=3 / TOTAL=9), skills/frontend-kit/scripts/run-log.mjs (record check-first), verify.sh (§5f, cases (129)–(142) after the rebase renumbering — was (107)–(120) before the MIE-5 merge occupied (107)–(128)), skills/frontend-kit/references/decisions.md (D38 entry). Counting per the council synthesis (corrects the board's literal wording): per-direction = distinct round numbers after the latest VERIFIED taste-lock; total = distinct (epoch, round) pairs. --grader none consumes budget; no --allow-4th-round flag; fake lock lines do not reset the count; corrupt log lines refuse in both entry points. Proof: §5f standalone 14 ok / 0 fail (4th distinct refuses in record + prepare; 10th total refuses in record + prepare after lock v4; re-record + prepare-for-recorded pass; round 3 / round-1-after-re-pick / 9th round exit 0; runlog-check passes; best crowns round 2). Regression: §5b+§5c standalone 229 ok / 0 fail / 1 unverified, identical to the pristine-HEAD baseline (1 unverified = case (104) gitleaks half, pre-existing); the first branch run showed 48 genuine budget refusals against §5c's fixtures, fixed per the D15 adjudication pattern by adding taste-locks v1/v2/v3 to jr_proj, moving cases (43)–(46) to a new jr2_proj, and locking rp_proj before case (60) — no case renumbered, no assertion changed, no rule weakened. NOTE: the `## Mie handoff` heading was absent at base 907aeaa — added here with this entry; the coordinator's working copy already carries the heading with MIE-4–MIE-10 entries, so the merge may need a one-line reconciliation. Full ./verify.sh (2026-11-13, fresh install from this branch, scratch HOME): 259 ok / 3 fail / 2 unverified — all 3 fails are the gate's fail-closed secret scan (no gitleaks on this machine); §5b/§5c/§5f zero fails in the full run. Rebased onto main 0d92f91 (PR #4 merged); decisions.md conflict resolved by keeping main's D20–D32 then D38. CI green still the merge gate; QC + red team next per the brief — no PR opened.
MIE-8 DONE (implementer, 2026-11-13) — PROVEN NEGATIVE, no install.sh fix.
Branch `mie/mie-8-d39`, pushed to fork (no PR yet — QC + red team next, coordinator orders).
Proof re-run by the implementer: VM fresh install (main-disk scratch HOME
`~/workspace/mie-track/mie-8/scratch/vm/home` — /tmp is a 512MB tmpfs, see
D39 caveat 1) + MacBook fresh install (scratch HOME `/tmp/mie8-mac/home`).
diff -r IDENTICAL on both machines (VM: 2 copies; MacBook: 9 copies); 16/16
files sha256 + modes MATCH per copy; moments probe installed ENOENT / repo
ENOENT / taste tree 18 moments + 25 effects; installed taste data 1,645
files, zero sha256 mismatches, moments index
db86d14cfb013db307ce95c0a42467987b52e5004c56d40ac41e69a8ac8170fd on both
machines. install.sh: 0 occurrences of `scripts/gate`. Full D39 entry in
decisions.md; verify.sh gains §2g (byte-identity + moments-index absence
in both trees). Embedded verify exits 1 on both machines for reasons
outside MIE-8 (VM: §1.1 no-scanner fail-closed, gitleaks extraction failed
on this fs; MacBook: node not on PATH in non-interactive SSH, 109x, plus
BSD sed + bash-3.2 unbound-variable abort — no summary line). D15 §5b/§5c
FAIL question NOT chased (open item for coordinator; implementer's VM run
showed 0 FAILs there). MIE-10 constraint recorded in D39: probe build must
avoid dealing taste moments or accept the false FAIL honestly.

GAP-16 CANDIDATE (proposed for the coordinator to award — NOT implemented
in MIE-8): the moments/effects gap is real and verdict-affecting
(consistency.mjs momentFits() always false with both reads ENOENT, so a
correctly-dealt moment FAILs the `moment` check). Fix options for the
council to decide: (a) vendor the moments/effects data into the skill
tree, or (b) pass the taste path via a flag. Interim position (c) adopted
in D39: accept silent-empty as designed until GAP-16 is decided.

MIE-8 FIX ROUND (2026-11-13, red-team PASS 03:07 UTC + QC FAIL 03:16 UTC
closures) — all fixes in ONE commit on branch `mie/mie-8-d39`, no PR yet
(coordinator opens it after QC round 2 + red team round 2). No install.sh
change; verdict still PROVEN NEGATIVE.
- M1: MacBook 9-copy diff/sha proof RE-RUN with output saved
  (`scratch/mac-probe-fix.log`, 734 lines): fresh install from scratch
  HOME `~/mie-8-fix-20261113/home`, clone HEAD 907aeaa recorded by
  `git rev-parse`; 9x `diff -r` IDENTICAL, 144/144 per-file sha256+mode
  MATCH (16 files x 9 copies, 0 mismatches); installed taste 1,645 files,
  moments index hash db86d14c...fd. install.sh exit 1 on the embedded
  verify (copy phase OK). One hung leg-2 fixture gate.mjs killed to let
  the run proceed (macOS verify/gate hang, MIE-2 territory). D39 Proof 1
  cites the log.
- M2: probe.sh taste row corrected (`scripts/gate`, nonexistent, ->
  `scripts/`); re-run on the VM (`scratch/vm/probe-fix.log`): taste row
  now present (18 moments) / present (25 meta.json). D39 table unchanged.
- m1: install_dir range corrected 400-426 -> 400-430 (brace at 430).
- m2: §2g comment in verify.sh notes modes are NOT asserted there
  (diff -r is content-only); gate.sh exec bit covered by §2e.
- m3: D39 records the VM cp -R fallback (35 WARNING lines in
  vm/install.log + 35 entries in copy-fallbacks.log).
- m4: "29Gi free" sourced to the MIE-3 inventory (commit 4b425ec,
  "28-29Gi free"); original clone HEAD noted as unlogged in
  mac-install.log (0 occurrences of 907aeaa).
- m5: `scratch/verify-negative-setup.md` records the tamper (1-line drift
  in the .agents copy's gate.sh; moments index planted in the .codex
  copy) + expected exactly-2-FAILs result, both observed in
  vm/verify-negative.log (exactly 2 `^FAIL:` lines).
- QC item 14: GAP-16 proposal (coord/mie.md:154-160) compared line-by-line
  against the council (a)/(b) synthesis text (coordinator's record,
  "MIE-8 COUNCIL SYNTHESIS — (a)/(b) FIX OPTIONS"); operative (a)/(b)
  wording matches, differences are elided explanatory detail only —
  proposal left unchanged; comparison recorded in D39.
- QC (a): grader_args line cited with tree (2959 on the 907aeaa base,
  2997 on this branch's HEAD). QC (b): D39 Proof 3 tightened — 1,645
  installed files, zero mismatches over the common files; the remaining
  19 vendor/taste files deliberately not installed per install.sh:528-531.
- verify.sh re-run on the branch follows this commit; exit code +
  failure/unverified counts are in the fix report to the coordinator
  (full exit 0 not expected on the VM: no Chrome; gitleaks workaround
  may be needed, as before).
- MIE-4 RENUMBER (coordinator, 2026-11-14): D22 → D72 — D22 was taken by Migga O2 on main (decisions.md:461), so the MIE-4 rule is now D72 in all three shipped files (SKILL.md:885, workflow.md:429, probe-briefs.md:44). Entries below were written when the number was D22; kept verbatim (append-only correction, never rewrite). The NOTE FOR MUSE below is superseded in its D22 half: D22 IS Migga's; the board fix is D20, D22–D32 (only D21 is Mie's) — applied to BOARD.md:123.
- MIE-4 IMPLEMENTED 2026-11-13 02:40 UTC — D22 rule (step-3-scoped, council-reconciled) implemented on branch mie/mie-4-q1 (base 907aeaa, no rebase needed — upstream main is an ancestor). Files changed: skills/frontend-kit/SKILL.md (after line 839, before `## Step 3a` at 841), skills/frontend-kit/references/workflow.md (after the taste-reference paragraph, before `## 3b` at 411), tests/clean-env/probe-briefs.md (after line 42, outside the Brief 1 quote block), coord/mie.md (this entry). No decisions.md entry (board DoD "nothing else changed"; Experts A and C agree). Grep proof — `grep -n "D22 — Do not yield mid-gate, and do not poll in-turn" skills/frontend-kit/SKILL.md skills/frontend-kit/references/workflow.md tests/clean-env/probe-briefs.md` → SKILL.md:841, workflow.md:411, probe-briefs.md:44 (Line A verbatim in all three); `grep -n "^Carve-out:"` on the same three files → SKILL.md:843, workflow.md:413, probe-briefs.md:46; `grep -n "^Definitions:"` → SKILL.md:845, workflow.md:415, probe-briefs.md: 0 (definitions paragraph in SKILL.md + workflow.md only, per council). `git diff --stat`: 3 files, 16 insertions, 0 deletions (+ this coord/mie.md entry). CI status: local ./verify.sh exits 1 with 197 FAILs — PRE-EXISTING environment state, NOT caused by this change: the kit was never installed on this VM (all FAILs are "missing skill: <host>: ~/.<host>/skills/..." plus missing playwright-cli / system Chrome / host configs); baseline run on the stashed tree gives the identical 197-FAIL set and identical OK count (diff of sorted FAIL lines is empty). CI green on the pushed branch is still to be confirmed — QC + red team next, no PR opened yet.
- D22 DECISION RECORD (MIE-4, for the PR body) — Scope adopted: step-3-scoped (mid-gate), per Experts B and C (2 of 3). Reasoning: the rule binds the step-3 gate run itself — once the gate starts it must run to its printed PASS or FAIL in the same turn, with no mid-gate yield and no in-turn re-checking; the loop's own yields (step-1.7 plan approval, step-2a variant pick, v0 nod, step-6 human gate) and the between-turn buffet polling cadence are carved out, and legitimate waits (human gates, step-3a SEVERE input-required handoff, degraded rung, escalate) are NOT forbidden. Dissent recorded (Expert A): A wanted mid-loop scope instead of step-3-scoped — recorded here, NOT implemented. COUNCIL-DRAFTED — probe4-fix-research §Q1 CHƯA ĐỌC — rule text drafted by council from the board row + repo context; coordinator to verify against the research at review. Shipped files do NOT cite probe4-fix-research.
- NOTE FOR MUSE (do NOT edit BOARD.md — this is a proposal only): BOARD.md:123 range notation is internally inconsistent — "D20–D32 = Migga PR #4" nominally contains D21 (Mie PR #5) and D22 (Mie MIE-4). Proposed one-line board fix: read the range as D20, D23–D32 (i.e. D21 and D22 are Mie's, not Migga's). Please also check the PR #4 branch for any D22 claim before merging.
- D22 DECISION RECORD AMENDMENT (red-team fix, 2026-11-13 03:11 UTC) — Two coordinator decisions, both for Muse to confirm at review: (1) M2 BOUND — "After 3 failed re-runs in one turn, end the turn with the FAIL and its findings." The number 3 is a COORDINATOR / FIX-AGENT CHOICE: it matches the 3-rounds-per-direction cap (SKILL.md stop rules) and is NOT council-drafted and NOT from probe4-fix-research §Q1 (still CHƯA ĐỌC). (2) m3 OVERRIDE — the Definitions paragraph is now added to tests/clean-env/probe-briefs.md as a verbatim mirror of SKILL.md/workflow.md, so the full rule block (Line A + Carve-out + Definitions) is character-for-character identical across all three files. This OVERRIDES the council's "Definitions in SKILL.md + workflow.md only" spec. No decisions.md entry (board DoD "nothing else changed" still holds — the record lives here, as before).
- MIE-4 RED-TEAM FIX CORRECTION (m5, coordinator-owned, append-only) — the MIE-4 IMPLEMENTED entry's "git diff --stat: 3 files, 16 insertions" misattributes the count: the implementer commit 76d7bc6's own --stat is 4 files, 19 insertions (16 is shipped files only; the 4th file is coord/mie.md, +3). The PR description must use the 19-insertion commit figure with that qualifier, or the 76-insertion branch figure.
- MIE-4 RED-TEAM FIX IMPLEMENTED 2026-11-13 03:31 UTC — NEW commit on top of 76d7bc6 (not amended), branch mie/mie-4-q1, own clone ~/workspace/mie-track/mie-4-fix/. All 3 MEDIUMs + all 6 MINORs applied, every claim re-verified against the files first: M1 — Definitions polling sentence re-scoped to mid-gate and taxonomy rewritten (sleep/retry loops + spawned-subagent status checks, without an intervening fix; buffet polling is the between-turn BUFFET-MODE.md §5 cadence, 15-min pull / 30-min merge, and is not this rule; D5 miscite removed — D5 only forbids a second cadence, decisions.md:37-40); M2 — bound added to Line A ("After 3 failed re-runs in one turn, end the turn with the FAIL and its findings" — coordinator/fix-agent choice, see D22 amendment above); M3 — "Legitimate waits" reworded to "After the gate's printed result, the following are legitimate: human gates and the step-3a SEVERE input-required handoff", with escalate + degraded rung stated explicitly as not waits and not mid-gate exits; m1 — printed result now "(leg 1 PASS/FAIL, leg 2 GREEN/FAIL)" (verified: gate.sh:1402-1403 GATE RESULT: PASS/FAIL; gate.mjs:377 gate verdict: GREEN/FAIL); m2 — "without an intervening fix" added to the polling ban in Line A and Definitions (preserves the skill-mandated exit-2 re-run); m3 — Definitions added to probe-briefs.md as a verbatim mirror (coordinator override of the council spec, see D22 amendment); m4 — Carve-out now "are not forbidden by this rule"; m5 — corrected in the entry above (implementer commit = 4 files, 19 insertions); m6 — Line A names the start ("invoking leg 1, gate.sh"). VERBATIM MIRROR: rule block (Line A + Carve-out + Definitions) character-for-character identical across all three files — sha256 2285bd37e2bada1756a9b6f55a183dc90e1a07ea38ad0bc2859cef1be8202523 for SKILL.md:841-845, workflow.md:411-415, probe-briefs.md:44-48. NEW LINE NUMBERS: Line A SKILL.md:841, workflow.md:411, probe-briefs.md:44; Carve-out :843/:413/:46; Definitions :845/:415/:48. PLACEMENT (unchanged): SKILL.md block before ## Step 3a at :847; workflow.md before ## 3b. at :417; probe-briefs D22 lines 44-48 outside the Brief 1 quote block (quote ends :42), ## Brief 2 at :50. NO LEAKAGE: grep probe4|forbid-yield over the three shipped files = 0 hits (the only CHƯA hits are pre-existing generic vocabulary at SKILL.md:1258, workflow.md:5); no decisions.md entry. VERIFY.SH: exit 1, 12 failures on the fixed tree AND on the stashed baseline (72dfbd7) — sorted ^FAIL sets IDENTICAL modulo /tmp temp-dir names; summary identical (12 failures, 1 unverified, 1 warning, 1 pending); all 12 are pre-existing environment state (no gitleaks/trufflehog secret scanner; installed-gate fixture failures; 9 judge-artifact D15 round-7 fixture build failures). NOTE: the QC-era "197 FAILs" figure is NOT reproduced on this VM now (fixed tree: 240 OK lines; baseline: 243 — the 3-line delta is host "skills present" OKs present in the baseline run only, an environment flake, not a failure); the comparison that matters — FAIL set + summary — is identical. COUNCIL-DRAFTED — probe4-fix-research §Q1 CHƯA ĐỌC — rule text drafted by council from the board row + repo context, red-team-fixed by the fix agent; coordinator to verify against the research at review. No PR opened.

- MIE-9 (D40, GAP-9/10 residuals) — branch `mie/mie-9-gap910`, 2026-11-13. Implemented, pushed, awaiting QC + red team. (b) NOT A GAP: recount re-verified (44 tree sink files / 27 listed / 17 unlisted; letters-assemble in neither set) — no fix, not added to the allowlist. (c) WRONG EXPECTATION: no verify.mjs anywhere; strings only in BOARD.md:137 — struck, no fix. (d) WRONG FILENAME: marquee-row holds moment.css/moment.js, never style.css — no install.sh change; fix is two §2c anchors in verify.sh. (e) CONFIRMED FALSE on re-verification (zero judge reports; .tmp-probe4-projects not shipped, proof project wiped) — docs corrected only (judge-calibration.md:70-71, grader-rubric.md:233, frontend-judge/SKILL.md:142), no reports fabricated. D40 entry added to decisions.md. FLAG for the PR body: the three (e) files sit outside the board row's file list. Proof: local ./verify.sh exit 1 on pre-existing missing-install failures only (kit never installed on this VM: 197 fails, all "missing skill" / "no installed copy" for hosts never installed here — identical failure classes with and without this change); §2c anchors exercised via a scratch-HOME installed wrapper: OK "taste-reference wrapper paths resolve (all cited anchors present)", and a negative control omitting moment.js fails naming exactly that anchor; §3b NOTE lists the same 17 files; no false judge-report claim remains in the operative docs; letters-assemble absent from the allowlist AND the §3b unlisted-sink NOTE. Full exit 0 is left to CI.
