#!/usr/bin/env node
// run-log.mjs — the frontend-kit run log.
//
// Appends one JSON record per grading round to <project>/design/run-log.jsonl
// and prints the log as a score table. The log is the memory that stops
// rejected directions from being re-proposed: scores per round, grader
// identity + independence basis per round, gate result, and every
// feedback -> token change -> new score.
//
// GRADER RULE (user direction, 2026-11-10, non-negotiable): the builder NEVER
// grades its own work. A builder self-grade is FORBIDDEN. This script REJECTS
// any log entry whose grader is the builder (exit 2, nothing written).
// Allowed graders: judge-subagent | muse-manager | other-model.
// A round with no independent judge is logged with --grader none
// --scores none (fixed 2026-11-10, probe G-4: the old code rejected every
// no-grade record because the grader check ran before the scores check,
// so the ladder's rung-3 "gate green, vision not available" round could
// not be recorded at all). A no-grade record stores grader: null and a
// gate-reflecting grade label — "gate green, vision not available" when
// --gate pass, "gate red, no grade" when --gate fail (W-LOOP fix
// 2026-11-11: the old code wrote the green label regardless of --gate,
// so a gate-red round read as green in the grade field) — with NO invented
// grader label and NO independence basis. --grader none WITH scores is
// still REJECTED: a score IS a grade and needs an independent judge.
//
// INDEPENDENCE BASIS (coordinator decision 2026-11-10, recorded in the repo
// AGENTS.md, superseding the old rubric exception): `muse-manager` — a
// DIFFERENT agent instance from the builder, with no production history of
// the build — IS a valid independent grader. What is forbidden is the SAME
// agent instance/context grading its own work, in any guise. The basis must
// establish BOTH halves of independence: (1) fresh/separate context (or a
// different agent instance) AND (2) no production history of the build.
// "Fresh context" alone is NOT enough (rubric A1: fresh context alone does
// not change the weights — a fresh context shown the builder's reasoning is
// not independent). A basis stating only one half is REJECTED (exit 2).
// Accepted phrasings include "fresh context, no production history",
// "a different agent from the builder, no production history of this build",
// "trained separately as a design critic, with no production history".
//
// TASTE LOCK: `lock` records the step-1 taste lock — the "commit" of the
// locked tokens + chosen references BEFORE any HTML (see frontend-kit
// SKILL.md step 1.5). "Commit" = files saved under design/ in the project
// AND this lock entry in the run log; git commit only if the project is a
// git repo.
//
// P7 RUN STATE (no separate run.json file — council decision, 2026-11-10):
// the machine-readable run state lives IN this append-only log, not in a
// mutable JSON file (a mutable file is the overwrite hazard the
// long-running-harness lesson warns against). Schema, per record kind:
//   taste-lock: { kind, lockVersion, tokens, tokensHash, references,
//     purpose, approvedBy, notes, at }. lockVersion auto-increments (1, 2, …);
//     --version N records an explicit version (a re-pick creates a NEW
//     version; re-using an existing version is REJECTED, exit 2).
//     tokensHash is the sha256 of the tokens file when it resolves on
//     disk, else null. approvedBy carries the step-1.7 approval basis for
//     human-less runs ("converge-check + round-1 grade (no human
//     present)"); solo runs record human approval in PLAN.md instead.
//     purpose is the PLAN.md "Purpose + primary user task" section,
//     recorded with the lock (UX-B council decision 2026-11-10); null
//     when the lock was recorded without --purpose.
//   purpose-fail: { kind, action, purpose, notes, at }. action is
//     re-plan (re-derive the section inventory from the revised
//     purpose) or re-pick (record a NEW taste-lock version via `lock`);
//     purpose is the revised purpose from the re-derived plan.
//   crosscheck: { kind, slice, round, severe, warning, waived, verdict,
//     report, checker, independenceBasis, notes, at }. verdict is DERIVED
//     (clear iff severe == 0 and warning == waived), never asserted. The
//     checker must be independent of the builder AND the judge for the
//     slice: basis states BOTH fresh/separate context AND no production
//     history (same two-half rule as a grader basis). report is the
//     cross-check report file (coord/crosscheck/<slice-id>-<n>.md in
//     buffet mode). A blocked verdict is recorded, not rejected — the
//     land is what a blocked verdict stops. (D15: the report path is
//     validated like other artifacts — project-relative, resolving
//     inside design/, a real non-symlink non-empty file; existence and
//     containment only, no content grammar in this wave. Before D15
//     the path was never stat'ed, so a verdict could cite a report
//     that does not exist.)
//   land: { kind, slice, round, gate, gateLeg1, gateLeg2, gateLeg1Sha,
//     gateLeg2Sha, page, crosscheckReport, notes, at }.
//     Recorded only when --gate pass AND the LATEST crosscheck verdict
//     for the same slice/round is clear; otherwise REJECTED (exit 2,
//     nothing written). crosscheckReport is copied from that verdict.
//     --gate pass ALSO requires the two gate-leg artifacts (see the
//     --gate-leg1/--gate-leg2 rule below); a land asserting a pass with
//     no artifacts is rejected the same way.
//   round: { kind, round, grader, independenceBasis, scores, grade,
//     evidence, gate, gateLeg1, gateLeg2, gateLeg1Sha, gateLeg2Sha,
//     gateFindings, variant, tokensHash, fixClass,
//     outcome, page, trigger, pairwise, pairwiseAgrees, jury, juryMode,
//     juryVotes, notRegraded, expertMotion, expertMotionEvidence,
//     expertUx, expertUxEvidence, judgeReport, judgeReportSha, pageSha,
//     pairwiseReports, pairwiseReportShas,
//     juryReportShas, expertMotionReport, expertMotionReportSha,
//     expertUxReport, expertUxReportSha, notes, at }. (D15 fields are
//     documented at the JUDGE ARTIFACTS block below; pairwiseReportSha /
//     juryReportShas / expertMotionReportSha / expertUxReportSha are
//     `;`-joined sha256 strings under *Sha keys, pairwiseReports is the
//     `;`-joined report paths.) variant is the PICKED variant.
//     tokensHash is --tokens-hash, or the sha256 of
//     <project>/design/tokens.css when present, else null. fixClass is a
//     free-form fix class (e.g. "tokens:colour"); outcome is one of
//     kept | discarded | re-pick | stopped | escalated | pending
//     (default pending). gateFindings is the gate output for the round
//     (;-separated). page is the built HTML file the round graded.
//     trigger (P6) records why the direction ended on this round:
//     flat-line | round-1-repick; stagnation is a RETIRED value for the
//     deleted trigger (c) — accepted so old logs still parse, never
//     emitted by the new rules. pairwise (P11) is the pairwise
//     keep/discard verdict vs the incumbent (keep-incumbent |
//     keep-challenger | tie); pairwiseAgrees is whether that verdict
//     agrees with the absolute-score comparison (true/false). jury (P14)
//     is the stop-round jury median per axis {type,layout,colour,space};
//     juryMode is disjoint-3 | single-family | single; juryVotes is the
//     three per-judge votes (each {type,layout,colour,space}), and when
//     both jury and juryVotes are given the jury MUST be the per-axis
//     median of the votes (otherwise the record is REJECTED).
//     notRegraded (P13, W-LOOP fix 2026-11-11) is the list of section ids
//     the round did NOT re-score because they were unchanged since an
//     earlier round (e.g. ["#hero", "#footer"]) — SECTIONS, not axes:
//     the cheap grade still produces fresh per-axis scores for the whole
//     page; only unchanged sections are not re-scored. Recorded via the
//     --not-regraded flag; --scores always carries four fresh integers
//     or "none" (a "not re-measured" value in --scores is REJECTED —
//     parseScores only accepts integers 1-5). The rubric's score table
//     marks such sections `not re-graded (unchanged since round N)`.
//     expertMotion / expertUx (Wave 6) are the Motion and UX expert
//     second-opinion scores (rubric Motion:/UX: lines — `Motion: <1-5>
//     (motion-expert) — <one-line evidence>`, `UX: <1-5> (ux-expert) —
//     <one-line evidence>`), each an integer 1-5 with one line of
//     observable evidence (expertMotionEvidence / expertUxEvidence).
//     Recorded via --expert-motion / --expert-ux +
//     --expert-motion-evidence / --expert-ux-evidence on ANY round
//     record, graded or no-grade (experts can be consulted even when no
//     independent judge grade exists). ADVISORY to the judge — the judge
//     keeps the final 4-axis scores; expert scores never change a score,
//     never trigger the stop rule, and are never a grade.
//   feedback: { kind, round, from, tokenChange, scoreAfter, grader,
//     independenceBasis, evidence, fixClass, judgeReport, judgeReportSha,
//     pageSha, at }. judgeReport / judgeReportSha / pageSha are the D15
//     regrade-artifact fields (null when no --score-after was recorded).
// The round-brief generator (skills/frontend-kit/scripts/round-brief.mjs)
// reads ONLY this log + the locked files; no round ever reads the full
// log as context. `brief` below delegates to it.
//
// Node, no dependencies. Usage:
//   node run-log.mjs --project <dir> record --round N --grader <label>
//     --basis "<why this judge counts as independent>"
//     --scores <type,layout,colour,space | none>
//     --judge-report <design/judge/round-N.md>   # REQUIRED for a graded
//       round (D15, below); the record's evidence is DERIVED from the
//       artifact's evidence cells — record no longer accepts --evidence
//       on a graded round
//     --gate <pass|fail> [--variant <name>] [--notes "..."]
//     [--gate-leg1 <path> --gate-leg2 <path>]  # REQUIRED with --gate pass (D13, below)
//     [--tokens-hash <sha256 hex>] [--fix-class "<class>"]
//     [--outcome <kept|discarded|re-pick|stopped|escalated|pending>]
//     [--gate-findings "<gate output, ;-separated>"] [--page <built.html>]
//     [--trigger <flat-line|round-1-repick|stagnation>]
//     [--pairwise <keep-incumbent|keep-challenger|tie>]
//     [--pairwise-agrees <yes|no>]
//     [--jury "<type,layout,colour,space median>"]
//     [--jury-mode <disjoint-3|single-family|single>]
//     [--jury-votes "<t,l,c,s; t,l,c,s; t,l,c,s>"]
//     [--not-regraded "<#section,#section>"]   # sections not re-scored
//       (unchanged since an earlier round); --scores stays four fresh
//       integers or "none" — never "not re-measured"
//     [--expert-motion <1-5>] [--expert-motion-evidence "<observable>"]
//     [--expert-ux <1-5>] [--expert-ux-evidence "<observable>"]
//       # Motion/UX expert second opinions (advisory only); allowed on
//       graded and no-grade records alike
//   --tokens-hash defaults to the sha256 of <project>/design/tokens.css
//   when that file exists; --page is the built HTML the round graded
//   (the round-brief generator needs it to find the best HTML).
//   GATE ARTIFACTS (D13, GAP-11 — REQUIRED with --gate pass, on `record`
//   AND `land`): a pass is recorded only with the two leg outputs on
//   disk — leg 1: `design/gate-leg1.log` (gate.sh output, redirected);
//   leg 2: `design/gate-leg2.log` (gate.mjs output, redirected). Pass
//   `--gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log`
//   (paths relative to the project, inside design/ — absolute paths and
//   `..` escapes are rejected). Each file must exist, be non-empty, and
//   contain its leg's PASS marker (`GATE RESULT: PASS` / `===== gate
//   verdict: GREEN =====`) as the verdict line itself, and contain no
//   FAIL verdict for their leg; and be at least as new as the page
//   (`--page`, when given) or `design/tokens.css` (when not). `--page`
//   itself must be the built page — an `.html` file inside
//   `design/` (or `design/tokens.css` itself), a real file, never an
//   absolute outside path, never a symlink, never one of the artifact
//   files — and at least as new as `design/tokens.css` (the enforced
//   chain is tokens <= page <= artifacts); it is stored as the
//   canonical project-relative path. Any failure is REJECTED (exit 2,
//   nothing written). `--gate fail` needs no artifact: a bad `--page`
//   there only warns and is recorded as `page: null`. Degraded rungs
//   record `--gate fail` + notes, never a pass. The record stores the
//   relative paths (`gateLeg1`/`gateLeg2`)
//   plus their sha256 (`gateLeg1Sha`/`gateLeg2Sha` — the `*Sha` suffix
//   is mandatory: runlog-check.mjs rule 3 fails bare 64-hex under any
//   other key).
//   --trigger records the P6 trigger that ended the direction on this
//   round (flat-line | round-1-repick); stagnation is RETIRED (deleted
//   trigger (c)) — accepted so old logs still parse, never emitted by
//   the new rules. --pairwise / --pairwise-agrees record the P11
//   pairwise keep/discard verdict and whether it agrees with the
//   absolute-score comparison. --jury / --jury-mode / --jury-votes
//   record the P14 stop-round jury: the per-axis median, the jury mode,
//   and the three per-judge votes; when --jury and --jury-votes are
//   both given, --jury must equal the per-axis median of the votes.
//   Pairwise and jury fields need a graded round: they are REJECTED on
//   a --grader none record (a no-grade round has no scores to compare
//   or to take a median of); --trigger is accepted on any record.
//   record enforces the same evidence bar as feedback --score-after:
//   --evidence, when given, must be 10+ characters naming an observable
//   element (same evidenceNamesObservable rule); a bare --evidence "x"
//   with a score is REJECTED (exit 2, nothing written). A score IS a
//   grade, whichever command records it.
//   No-grade record (ladder rung 3 — "gate green, vision not available"
//   on --gate pass, "gate red, no grade" on --gate fail):
//   node run-log.mjs --project <dir> record --round N --grader none
//     --scores none --gate <pass|fail> [--variant <name>] [--notes "..."]
//     [--gate-leg1 <path> --gate-leg2 <path>]  # REQUIRED with --gate pass (D13)
//     [--expert-motion <1-5>] [--expert-motion-evidence "<observable>"]
//     [--expert-ux <1-5>] [--expert-ux-evidence "<observable>"]
//   --grader none is accepted ONLY with --scores none (and no --evidence
//   score). It records grader: null, grade: "gate green, vision not
//   available". --grader none with scores is REJECTED (a score needs an
//   independent judge); omitting --grader entirely is still a usage error.
//   Expert scores ARE allowed on a no-grade record: an expert second
//   opinion is not a grade, and experts can be consulted even when no
//   independent judge grade exists.
//   node run-log.mjs --project <dir> feedback --from "<human words>"
//     --change "<token diff>" --round N [--score-after <t,l,c,s>
//     --grader <judge-subagent|muse-manager|other-model>
//     --basis "<why this judge counts as independent, 10+ chars>"
//     --judge-report <design/judge/round-N-regrade.md>]
//   --score-after REQUIRES --grader + --basis + a regrade judge artifact
//   (D15; exit 2, nothing written, otherwise): a post-feedback score IS
//   a grade, and only an independent judge may grade. --basis must not
//   merely restate the grader name; the recorded evidence is DERIVED
//   from the artifact's evidence cells — feedback no longer accepts
//   --evidence with --score-after.
//   node run-log.mjs --project <dir> lock --tokens <tokens.css path>
//     --refs "<chosen DESIGN.md + reference screenshots>"
//     [--version N] [--approved-by "<approval basis>"]
//     [--purpose "<PLAN.md Purpose + primary user task section>"]
//   lock records the step-1 taste lock (the "commit" of tokens + chosen
//   references BEFORE any HTML). It appends {kind:'taste-lock'} to the run
//   log; --tokens is required, --refs is required (name the locked
//   direction — a lock with no references is not a lock). --version
//   defaults to (existing lock count + 1); a re-pick records a NEW
//   version. --approved-by records the human-less approval basis
//   (step 1.7); omit it on solo runs (approval lives in PLAN.md).
//   --purpose records the PLAN.md "Purpose + primary user task"
//   section with the lock (UX-B council decision 2026-11-10): the
//   purpose is a lock field, not a plan note. It is optional so
//   existing lock invocations keep working; omit it only when the plan
//   has no Purpose section yet, and record it on the next lock.
//   node run-log.mjs --project <dir> replan --action <re-plan|re-pick>
//     --purpose "<revised purpose from PLAN.md>" [--notes "..."]
//   node run-log.mjs --project <dir> crosscheck --slice <id> [--round N]
//     --severe N --warning N [--waived N] --report <path>
//     --checker <security-expert|crosscheck-subagent|crosscheck-team>
//     --basis "<why this checker counts as independent>"
//   crosscheck records a security/compliance cross-check verdict
//   (BUFFET-MODE.md §14, SKILL.md step 3a). The verdict is DERIVED:
//   clear iff severe == 0 and every warning is fixed-or-waived
//   (warning == waived). The checker must be independent of the builder
//   AND the judge for the slice (same two-half basis as a grader).
//   node run-log.mjs --project <dir> land --slice <id> [--round N]
//     --gate pass [--gate-leg1 <path> --gate-leg2 <path>] [--page <built.html>] [--notes "..."]
//   land records a land/ship decision. It is REJECTED (exit 2, nothing
//   written) unless --gate pass AND the LATEST crosscheck verdict for
//   the same slice/round is clear. A land without a cross-check verdict
//   is never recorded — landing without a cross-check is forbidden,
//   exactly as landing without a gate is (F32).
//   replan records a purpose failure's resolution: re-plan re-derives
//   the section inventory from the revised purpose; re-pick records a
//   NEW taste-lock version (via `lock`). The decision is recorded in
//   the run log; a purpose failure is never resolved by an unenforced
//   plan note, and the inventory is never patched in place to fit a
//   changed purpose.
//   node run-log.mjs --project <dir> brief [--round N] [--out <file>]
//   brief assembles the minimal round brief for round N (default: the
//   next round) from this log + the locked files, via round-brief.mjs —
//   locked tokens + best HTML + gate findings + grader evidence lines +
//   run state, never the full run log. Prints to stdout, or writes
//   --out when given.
//   node run-log.mjs --project <dir> show
//   node run-log.mjs --project <dir> best
//
// JUDGE ARTIFACTS (D15, GAP-13 — REQUIRED for every score, on `record`
//   AND `feedback`): a grade is a CLAIM about a judge run, and a claim
//   with no artifact behind it is a self-assertion — the exact escape
//   three Claude probes used (fabricated scores, an invented grader, a
//   self-grade recorded as a judge grade), because the grader checks
//   above verified only the SPELLING of independence (a label + two
//   stock basis phrases), never its existence. A graded record now
//   refuses unless `--judge-report <path>` cites the judge's own report
//   file (default shape `design/judge/round-<n>.md`, written by the
//   judge into the skeleton `judge-report.mjs prepare` stamps before
//   the spawn — see that file's header for the producer split and the
//   format grammar, which run-log.mjs imports from it: one parser, two
//   readers). validateJudgeArtifact (below) checks, ALL failing closed
//   (exit 2, nothing written): the file is project-relative, resolves
//   inside <project>/design/, is a non-symlink non-empty regular file,
//   and is a distinct file (device+inode) from the page, tokens.css,
//   both gate legs, and every other judge artifact cited in the same
//   command; line 1 is the magic line (after stripInvisible); no line
//   is a judge refusal/void line or a leftover PENDING skeleton line;
//   the header grammar is strict (fixed keys, fixed order); the header
//   round / kind / grader / basis EQUAL the record flags (and the basis
//   passes the same two-half independence check on the artifact's own
//   text); the gate / cross-check bits are green / clear; the header's
//   page-sha256 and tokens-sha256 EQUAL the hashes of the files on disk
//   now (so an artifact copied from an earlier round or build, or a
//   page edited after judging, is refused); every screenshot hash in
//   the header EQUALS the current file's hash; the parsed score table
//   EQUALS --scores axis-by-axis; and the artifact is fresh in the
//   chain tokens <= page <= artifact. The recorded evidence is DERIVED
//   from the artifact's evidence cells (joined with '; ' into the same
//   `evidence` field round-brief.mjs reads — the transcription is
//   verified, not trusted). SINGLE-USE: a judge artifact's sha256 may
//   back exactly ONE grade event in a log; citing the same bytes again
//   (a second round, a feedback regrade, a jury vote) is refused.
//   Scope, all refused: scores with --gate fail (a judge is spawned
//   only on a green gate); an allowed grader with --scores none (use
//   --grader none); a no-grade record citing any judge artifact;
//   --pairwise without BOTH --pairwise-reports (each a kind-pairwise
//   artifact; the recorded verdict must EQUAL the verdict derived from
//   the two artifacts' keep lines and the A/B shot-hash mapping, and
//   the two artifacts' shot sets must be exact swaps of each other);
//   --jury / --jury-votes without --judge-reports (three kind-jury
//   artifacts whose parsed scores, as a set, equal --jury-votes; the
//   family rule applies: disjoint-3 = three distinct header families,
//   single-family = one shared family; --jury-mode single forbids
//   --jury / --jury-votes entirely — the single grade is --scores);
//   --expert-motion / --expert-ux without their kind-expert-motion /
//   kind-expert-ux artifacts (parsed score + evidence must equal the
//   flags), on graded AND no-grade records alike. `land` additionally
//   refuses when the log holds NO round record for the land's round
//   (graded or explicit no-grade) — a land after zero grading is the
//   loop closing unseen. `best` excludes gate-fail rounds and graded
//   rounds lacking a judge artifact.
//   RED-TEAM ROUND 2 (2026-11-12): the READ paths now distrust hand-
//   appended lines in shapes the writer never produces. feedback's
//   regrade page anchor is chosen ONLY from round lines that are
//   genuinely graded AND whose citation verifies on disk right now
//   (isVerifiedGradedRound) — a hand-appended scoreless line carrying
//   a pageSha (NA4, SEVERE: the writer couples pageSha to a grade, so
//   a no-grade line always stores it null) never anchors; with no
//   verified graded record the pre-D15 --page fallback applies, and
//   with no round record at all the pre-existing behaviour stands
//   (NA20). land's precondition counts only verified graded records
//   and genuine no-grade records (isGenuineNoGradeRound: the writer's
//   full no-grade field set — a hand-written minimal line in the
//   no-grade colours, NA19, never counts). `best` crowns only rounds
//   whose gate is exactly "pass" (NA3), whose grader is an allowed
//   label, whose citation verifies AND parses as the line's own
//   report (header round + score table, C3), and — for jury rounds —
//   whose three juror artifacts verify at their conventional paths
//   against juryReportShas (NA1/NA2).
//   RED-TEAM ROUND 3 (2026-11-12): the round-2 hardening was applied
//   unevenly across call sites, and round 3 proved the drift — the
//   fix is architectural, not another patch per call site. ONE
//   shared verifier now serves every read path: verifyGradedLine
//   performs the FULL record-grade verification on read (citation
//   exists, is not a symlink, resolves inside design/, hashes to
//   judgeReportSha, parses; header round / kind / grader /
//   page-sha256 / basis cross-checked against the line — closing B1
//   the pageSha-swapped anchor copy, B5 the grader misattribution,
//   B6 the stale-page pageSha edit, B7 the symlink asymmetry), and
//   verifyJuryLine verifies a jury line AS A JURY (juror artifacts
//   at their conventional paths, parsed votes == the line's
//   juryVotes as a set, parsed median == the line's jury, the family
//   rule from the headers — closing B2, the trusted recorded
//   median). isVerifiedGradedRound = the writer's graded shape +
//   verifyGradedLine (+ verifyJuryLine for jury lines), and it is
//   the ONLY graded test feedback's anchor, land's precondition and
//   `best` consult. land's no-grade half gained its missing on-disk
//   half too (B3): a genuine no-grade line's cited gate legs must
//   verify against the stored shas with the verdict matching the
//   line's gate value — a full-shape line citing legs that never
//   existed no longer counts; a line citing no legs never counts.
//   RED-TEAM ROUND 4 (2026-11-12): round 3 unified the verifier
//   inside THIS file but left gate/runlog-check.mjs holding private
//   re-implementations of it, and round 4 proved the copies had
//   drifted (F1–F7 — all read-path drift, no SEVERE): the checker's
//   parse half never applied the independence-basis check or the
//   body-Round-line agreement (F1), neither copy verified juror
//   device+inode distinctness (F2) or juror bases (F3), the checker
//   verified a jury only when jury/juryVotes were present (F4),
//   the line's own independenceBasis / tokensHash transcription
//   fields were compared by nobody (F5), citation containment
//   differed (project root in the checker, design/ here — F6), and
//   expert citations were verified by no read path at all (F7).
//   The fix is a relocation, not another patch: the verifiers and
//   the independence-basis check now live in judge-report.mjs (the
//   import-safe sibling, next to the parser), this file imports
//   them (thin fail-closed wrappers where its call sites sit), and
//   runlog-check.mjs calls the SAME functions and deletes its
//   copies. The shared verifier also gained the missing halves:
//   juror distinctness against the record-time set, juror basis
//   checks, the F5 transcription equalities, expert-citation
//   verification, and ONE jury-line definition (any of jury /
//   juryVotes / juryReportShas present and non-null). Record-time
//   validation (validateJudgeArtifact and everything it checks) is
//   unchanged; only the read paths moved.
//   RED-TEAM ROUND 5 (2026-11-12): no new mechanism and no drift —
//   round 5 proved FIELD GAPS inside the one shared verifier:
//   stored line fields it never compared. The graded shape did not
//   require gate exactly "pass" (N1 — only `best` filtered it
//   locally, so a genuine line flipped to gate "fail" still
//   anchored feedback and satisfied land); the line's evidence
//   transcription was unchecked (N2); juror artifacts were not
//   bound to the round's page on read (N3 — record time binds
//   them); expert evidence transcriptions were unchecked beside
//   expert scores (N6); and the pairwise transcription had NO
//   read verification at all (N5 — paths, hashes, swap proof and
//   the derived verdict are now re-derived by verifyPairwiseLine
//   inside verifyGradedLine, and runlog-check gained the
//   line-local pairwiseReportShas shape rule, N5b). All fixes are
//   in judge-report.mjs's shared verifier (plus the N5b shape
//   rule in runlog-check.mjs), so every consumer inherits them.
//   (N4, a juror artifact naming a different grader than the
//   line, was observed and is NOT a break: record time does not
//   compare a juror's grader either — write/read parity.)
//   Recorded fields: judgeReport /
//   judgeReportSha, pageSha (validator-computed, never a CLI flag),
//   pairwiseReports / pairwiseReportShas, juryReportShas,
//   expertMotionReport / expertMotionReportSha, expertUxReport /
//   expertUxReportSha — every hash under a *Sha key (runlog-check.mjs
//   rule 3). Residual, stated openly: deliberate fabrication of a
//   judge-shaped artifact is still possible (the builder can author
//   one from scratch; muse-manager independence remains
//   attestation-based; a judge spawned on curated inputs produces a
//   genuine artifact for a rigged grade). The mechanism converts the
//   escape from invisible to deliberate-and-auditable: the artifact is
//   on disk, hash-bound to the exact build, and a QC re-grade
//   contradicts it. Signing judge output is out of scope.
//
// Exit codes: 0 ok, 1 usage error (including a brief that fails its schema
//   check — lock, best HTML, gate findings, or evidence lines missing),
//   2 rejected entry (grader == builder, scores without a named
//   independent grader, a duplicate lock version, a checker without a
//   two-half independence basis, a land without a clear cross-check
//   verdict, a --gate pass without both gate-leg artifacts, or a score
//   without a valid judge artifact (D15)).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ALLOWED_GRADERS = ['judge-subagent', 'muse-manager', 'other-model'];
const ALLOWED_CHECKERS = ['security-expert', 'crosscheck-subagent', 'crosscheck-team'];
const FORBIDDEN_GRADERS = ['builder', 'self', 'self-grade', 'builder-grade'];

// Feedback --score-after validation: a post-feedback score is a grade, so
// it needs the same independent-judge proof as a round grade. --basis must
// carry substance beyond the grader label itself; --evidence must name an
// observable element (a digit/measurement, or a named page element), not a
// generic impression such as "looks good".
const OBSERVABLE_WORDS = [
  'hero', 'header', 'footer', 'nav', 'button', 'card', 'section',
  'heading', 'h1', 'h2', 'h3', 'text', 'image', 'icon', 'link', 'menu',
  'form', 'input', 'margin', 'padding', 'gap', 'contrast', 'font', 'size',
  'grid', 'alignment', 'whitespace', 'spacing', 'breakpoint', 'viewport',
  'screenshot', 'layout', 'colour', 'color', 'space', 'type', 'tokens',
  'background', 'border', 'radius', 'shadow', 'width', 'height',
];
const GENERIC_EVIDENCE = new Set([
  'looks good', 'looks better', 'looks great', 'looks nice', 'looks good now',
  'much better', 'better now', 'feels good', 'feels premium', 'nice',
  'good', 'fixed', 'fixed it', 'done', 'improved', 'looks fine', 'fine now',
]);

function reject(msg) {
  console.error(`run-log: REJECTED — ${msg} No entry written.`);
  process.exit(2);
}

// M2 (D13 edge cases, 2026-11-12): a cited CLI path is a SPELLING, not
// just a resolution. path.resolve() lexically collapses "." and ".."
// segments before any containment check sees the input, so a ".." that
// cancels out (design/../design/x.html, design/sub/../x.html) was
// invisible to every check and the stored path came out canonicalised,
// leaving no trace — while the error text still claimed "'..' escapes
// are rejected". A cited path must therefore spell a plain
// project-relative path: no "." or ".." segment anywhere in the raw
// string, checked BEFORE resolve. Trailing slashes stay allowed (pinned
// by §5b case (32)); the existing realpath/inside checks still catch
// symlinks and mounts. Callers pass their own fail function: reject()
// on the pass path, pageFail() for --page (warn-only on --gate fail).
function hasDotSegment(given) {
  return String(given).split(/[\\/]/).some((s) => s === '.' || s === '..');
}

// Independence basis must establish BOTH halves (see header): (1) fresh /
// separate context, or a different agent instance; AND (2) no production
// history of the build. Either half alone is rejected — "fresh context"
// alone does not change the weights (rubric A1), and "no production
// history" alone does not help if the judge shares the builder's context.
// The CHECK itself (red-team round 4) lives in judge-report.mjs —
// independenceBasisProblem / checkIndependenceBasis there — shared with
// the read paths, which apply its non-exiting halves to artifact
// headers. This wrapper is only the exiting form: it passes this file's
// reject (print + exit 2, nothing written) as the check's fail, so the
// record-time messages, exit code and nothing-written invariant are
// byte-identical to the in-file implementation it replaces. When
// judge-report.mjs cannot be imported (a partial install), the check
// cannot run, so the wrapper refuses with the missing-parser message —
// the same fail-closed stance validateJudgeArtifact takes for graded
// records, and the stance B4 set for runlog-check: a partial copy
// refuses rather than recording on an unverifiable basis.
function checkIndependenceBasis(basis, grader) {
  if (!judgeReportMod) reject('the judge-report parser (judge-report.mjs, next to run-log.mjs) is missing — the independence basis cannot be checked, so this cannot be recorded. Re-run ./install.sh.');
  judgeReportMod.checkIndependenceBasis(basis, grader, reject);
}

function evidenceNamesObservable(evidence) {
  const ev = evidence.trim();
  if (ev.length < 10) return false;
  const flat = ev.toLowerCase().replace(/[^a-z0-9 ]+/g, '').replace(/\s+/g, ' ').trim();
  if (GENERIC_EVIDENCE.has(flat)) return false;
  if (/\d/.test(ev)) return true;
  const words = ev.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  return words.some((w) => OBSERVABLE_WORDS.includes(w));
}

function usage(msg) {
  if (msg) console.error(`run-log: ${msg}`);
  console.error(`usage:
  node run-log.mjs --project <dir> record --round N --grader <label> --basis "<why independent>" --scores <t,l,c,s> --judge-report <design/judge/round-N.md> --gate pass [--gate-leg1 <path> --gate-leg2 <path>] [--variant <name>] [--notes "..."] [--tokens-hash <hex>] [--fix-class "<class>"] [--outcome <kept|discarded|re-pick|stopped|escalated|pending>] [--gate-findings "<...>"] [--page <built.html>] [--trigger <flat-line|round-1-repick|stagnation>] [--pairwise <keep-incumbent|keep-challenger|tie> --pairwise-reports <p1,p2>] [--pairwise-agrees <yes|no>] [--jury "<t,l,c,s median>" --jury-mode <disjoint-3|single-family> --jury-votes "<v1;v2;v3>" --judge-reports <j1,j2,j3>] [--not-regraded "<#section,#section>"] [--expert-motion <1-5> --expert-motion-evidence "<observable>" --expert-motion-report <path>] [--expert-ux <1-5> --expert-ux-evidence "<observable>" --expert-ux-report <path>]  (D15: a graded round requires --judge-report; the evidence is derived from the artifact, --evidence is not accepted)
  node run-log.mjs --project <dir> record --round N --grader none --scores none --gate <pass|fail> [--gate-leg1 <path> --gate-leg2 <path>] [--variant <name>] [--notes "..."] [--expert-motion <1-5> --expert-motion-evidence "<observable>" --expert-motion-report <path>] [--expert-ux <1-5> --expert-ux-evidence "<observable>" --expert-ux-report <path>]  (no-grade round: grade is "gate green, vision not available" when --gate pass, "gate red, no grade" when --gate fail; expert scores allowed, each with its expert artifact; no judge artifact may be cited)
  node run-log.mjs --project <dir> feedback --from "<human words>" --change "<token diff>" --round N [--score-after <t,l,c,s> --grader <label> --basis "<why independent>" --judge-report <design/judge/round-N-regrade.md> [--page <built.html>]] [--fix-class "<class>"]
  node run-log.mjs --project <dir> lock --tokens <path> --refs "<locked direction>" [--version N] [--approved-by "<approval basis>"] [--purpose "<purpose from PLAN.md>"]
  node run-log.mjs --project <dir> replan --action <re-plan|re-pick> --purpose "<revised purpose from PLAN.md>" [--notes "..."]
  node run-log.mjs --project <dir> crosscheck --slice <id> [--round N] --severe N --warning N [--waived N] --report <path> --checker <security-expert|crosscheck-subagent|crosscheck-team> --basis "<why independent>"
  node run-log.mjs --project <dir> land --slice <id> [--round N] --gate pass [--gate-leg1 <path> --gate-leg2 <path>] [--page <built.html>] [--notes "..."]
  node run-log.mjs --project <dir> brief [--round N] [--out <file>]
  node run-log.mjs --project <dir> show
  node run-log.mjs --project <dir> best`);
  process.exit(1);
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      // Boolean flags take no value (currently only --allow-missing on
      // `brief`); every other --flag consumes the next token.
      if (key === 'allow-missing') { out[key] = true; continue; }
      // Value flags consume the next token unconditionally: a value may
      // legitimately start with '--' (e.g. a token diff "--color-accent: ...").
      const val = argv[i + 1];
      if (val === undefined) usage(`--${key} needs a value`);
      out[key] = val;
      i++;
    } else out._.push(a);
  }
  return out;
}

function logPath(project) {
  return path.join(project, 'design', 'run-log.jsonl');
}

function readLog(project) {
  const p = logPath(project);
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

function appendLog(project, rec) {
  const dir = path.dirname(logPath(project));
  fs.mkdirSync(dir, { recursive: true });
  fs.appendFileSync(logPath(project), JSON.stringify(rec) + '\n');
}

function parseScores(s) {
  if (s === 'none') return null;
  const parts = s.split(',').map((v) => Number(v.trim()));
  if (parts.length !== 4 || parts.some((v) => !Number.isInteger(v) || v < 1 || v > 5)) {
    usage('--scores must be four integers 1-5 (type,layout,colour,space) or "none"');
  }
  return { type: parts[0], layout: parts[1], colour: parts[2], space: parts[3] };
}

// P7: sha256 of a file's bytes, or null when the path does not resolve.
// The hash is what ties a round back to the exact locked tokens — a
// round whose tokensHash differs from the lock's ran against different
// tokens, and the round-brief generator says so instead of assuming.
function sha256File(file) {
  try {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  } catch {
    return null;
  }
}

function resolveTokensPath(project, tokensArg) {
  if (!tokensArg) return path.join(project, 'design', 'tokens.css');
  return path.isAbsolute(tokensArg) ? tokensArg : path.join(project, tokensArg);
}

// P7: explicit --tokens-hash wins; otherwise hash the project's locked
// tokens.css when it exists; otherwise null (never invent a hash).
function resolveTokensHash(project, tokensArg, explicitHash) {
  if (explicitHash !== undefined) {
    if (!/^[0-9a-f]{64}$/i.test(explicitHash)) usage('--tokens-hash must be a 64-character lowercase hex sha256');
    return explicitHash.toLowerCase();
  }
  return sha256File(resolveTokensPath(project, tokensArg));
}

// D13 (GAP-11): a --gate pass is a CLAIM about two gate runs, and a claim
// with no artifact behind it is a self-assertion — the exact defect the
// installed skill could not close (the gate scripts were not in the
// installed copy, so no artifact could exist). `record` and `land` refuse
// --gate pass unless BOTH leg artifacts are cited and check out:
//   --gate-leg1 <path> --gate-leg2 <path>, each a path relative to the
//     project, resolving inside <project>/design/ (absolute paths and
//     `..` escapes are rejected);
//   each file exists, is a non-empty real file (symlinks rejected —
//     F2), and contains its leg's PASS marker as its verdict line —
//     leg 1: `GATE RESULT: PASS` (gate.sh prints it only on its exit-0
//     path); leg 2: `===== gate verdict: GREEN =====` (gate.mjs prints
//     it only when worst === 0) — and no FAIL verdict for its leg (F5:
//     a comment mentioning PASS, or an appended old PASS above a new
//     FAIL, is not a pass; R4: the FAIL check is per-line with a word
//     boundary, so FAILURE/FAILED do not match); the two legs must be
//     two distinct files, by resolved path and by device+inode (F4 —
//     a hardlink pair is one file, not two legs); `design/` itself
//     must resolve inside the project (R1 — a symlinked `design/`
//     pointing outside the project is rejected; pointing inside is
//     accepted); `--page`, when given, must be the built page — an
//     `.html` file inside `design/` (or `design/tokens.css` itself),
//     a real file, never an artifact file (R2 — compared by
//     device+inode as well as realpath, so a hardlink to a leg is
//     caught), and at least as new as `design/tokens.css` (R3 — the
//     enforced chain is tokens <= page <= artifacts; the fallback
//     `design/tokens.css` must itself be a non-symlink regular file),
//     and is stored canonically project-relative, never verbatim;
//   freshness: each artifact's mtime must be >= the built page's mtime
//     when --page is given, else >= design/tokens.css's mtime (equal
//     mtimes allowed — same-second writes). A stale artifact is a claim
//     about a different build.
// On any failed check: REJECTED (exit 2, nothing written). --gate fail
// needs no artifact — and a bad --page on the fail path only warns
// (R5): the fail is recorded with page: null instead of refused.
// The recorded paths are project-relative; the sha256
// pins the bytes. The `*Sha` suffix is MANDATORY: runlog-check.mjs rule 3
// fails a bare >=32-hex value under any other key, so `gateLeg1Hash`
// would make the NEXT gate run fail §6 1.1 on the run log itself.
// Residual, stated openly: deliberate fabrication of the artifact files
// is still possible. The mechanism converts the defect from
// accidental-and-invisible to deliberate-and-auditable (the artifact is
// on disk; QC re-running the gate reproduces or contradicts it).
// Signing gate output is out of scope.
const GATE_LEG_MARKERS = {
  leg1: 'GATE RESULT: PASS',
  leg2: '===== gate verdict: GREEN =====',
};
// A leg artifact that also carries its leg's FAIL verdict is not a pass,
// however the PASS string got in there (a comment, an appended old run).
// Checked per line with a word boundary (R4): a trimmed line matches
// the FAIL marker only when FAIL is NOT followed by a letter, so
// FAILURE/FAILED do not match but `FAIL (...)`, `FAIL (exit 1)` and
// bare FAIL do.
const GATE_LEG_FAIL_MARKERS = {
  leg1: 'GATE RESULT: FAIL',
  leg2: 'gate verdict: FAIL',
};
// Fix round 5 (F2/F3/F4) + fix round 6 (F7/F9): verdict lines are
// canonicalised before comparison by stripInvisible(), which first
// NFD-normalises the line (canonical decomposition: a precomposed
// letter becomes base letter + combining mark) and then deletes
// every invisible character, comparing what remains. The strip set:
//   \s  — all Unicode White_Space (U+0009–U+000D, U+0020, U+00A0,
//         U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F,
//         U+3000, U+FEFF)
//   \p{C} — all controls, formats, surrogates, private-use and
//         unassigned (Cc, Cf, Cs, Co, Cn) — this is the whole
//         zero-width set, the whole Cf set (U+2060, U+200E/U+200F,
//         bidi controls, U+00AD, U+2061–U+2064), U+180E, and U+FEFF
//   \p{M} — all marks (Mn, Mc, Me) — this is the variation selectors
//         (U+FE00–U+FE0F, U+E0100–U+E01EF) and every combining mark
//   U+FFFD — REPLACEMENT CHARACTER: the footprint of a byte that did
//         not survive copying, where it was INSERTED as extra noise
//         between letters. It does NOT recover a byte that REPLACED
//         a letter — the letter is gone (F8 residual, below).
//   F7 denylist — blank-rendering characters in the Lo/So classes,
//         which no property class above covers: U+115F HANGUL
//         CHOSEONG FILLER, U+1160 HANGUL JUNGSEONG FILLER, U+3164
//         HANGUL FILLER, U+FFA0 HALFWIDTH HANGUL FILLER, U+2800
//         BRAILLE PATTERN BLANK, U+303F IDEOGRAPHIC HALF FILL SPACE,
//         U+13441 EGYPTIAN HIEROGLYPH FULL BLANK, U+13442 EGYPTIAN
//         HIEROGLYPH HALF BLANK. Found by a sweep of all Lo/So code
//         points (Python unicodedata, names containing FILLER or
//         BLANK, plus supplementary probes for SPACE, EMPTY, NULL,
//         INVISIBLE and ZERO WIDTH, with U+303F found by the SPACE
//         probe); the sweep found no other blank-rendering Lo/So
//         code point except U+2422 BLANK SYMBOL, which renders
//         visibly (a control picture) and is deliberately NOT stripped.
// One canonicalisation replaces the round-4 two-variant design
// (strip vs map-to-space): mapping an invisible character to a space
// splits words (an exotic space inside FAIL hid the FAIL verdict;
// a ZWSP inside FAILURE made the R4 boundary match), while stripping
// alone missed a character substituting for a space. Deleting every
// invisible character subsumes both variants — `GATE RESULT: PASS`
// strips to `GATERESULT:PASS` on both sides of the comparison, and
// so does every line either variant accepted — and strictly more.
// Visible characters are NEVER stripped: a line differing from the
// marker by a visible character still rejects, and a comment line
// still cannot match the marker (the `#` survives stripping).
// What this does NOT cover (honest boundary, fix round 6):
//   — Substitution (F8): stripping recovers INSERTED noise only.
//     When a stripped character REPLACES a letter (F<FFFD>IL, or a
//     real invalid byte 0xFF in place of the A), the word is a
//     different, shorter word and no normaliser can recover it —
//     such a line records as a pass. Known limitation, pinned by
//     §5b cases (80)–(81); do NOT attempt fuzzy/near-miss matching.
//   — Blank Lo/So outside the denylist: none known after the sweep
//     above, but the denylist is a list, not a property — a future
//     blank-rendering character in an uncovered class would escape
//     it. This is NOT a closed set: round 5 claimed no future
//     invisible code point could escape \s, \p{C} or \p{M}, and
//     the F7 Lo/So characters disproved it.
//   — Homoglyphs (visible letters, e.g. Cyrillic A in FAIL): by
//     design — a visible character difference is not invisible
//     unicode, and no invisible-character normaliser folds it.
//   — NFD is canonical decomposition only (NOT NFKD): it does not
//     fold ligatures or fullwidth letters, which stay visible and
//     still reject.
// The line AND the marker go through the same canonicalisation
// (the marker is data too): the FAIL check strips the marker the
// same way as the line, or the check is dead code that still passes
// the PASS side. The regex itself is ASCII property escapes plus
// backslash-u escapes (four-digit and braced forms); no literal
// invisible characters in source.
const stripInvisible = (line) => line.normalize('NFD').replace(/[\s\p{C}\p{M}\uFFFD\u115F\u1160\u2800\u303F\u3164\uFFA0\u{13441}\u{13442}]/gu, '');

function validateGateArtifacts(project, args) {
  // Returns { gateLeg1, gateLeg2, gateLeg1Sha, gateLeg2Sha, page } when
  // --gate is pass; when --gate is fail the gate fields are null (no
  // artifact required, none recorded) but `page` is still the validated,
  // canonicalised --page (or null when --page is absent — or when it
  // fails validation, R5, with a stderr warning) — so a stored page
  // is never an absolute outside path on either path. Rejects
  // (exit 2, nothing written) on any failed check on the pass path.
  //
  // Rules (fix round 1, red-team F2–F5):
  //   F2 — no symlinks, no realpath escape: each leg is lstat-checked
  //     (a symlink is rejected outright, matching gate.sh's own stance)
  //     and its realpath must lie inside the realpath of <project>/design/.
  //     Lexical containment alone is not containment.
  //   F3 — --page, when given, must be a regular file (not a symlink)
  //     resolving inside the project (realpath), must not be either leg
  //     artifact file, and is stored as the canonical project-relative
  //     path — never verbatim, never absolute-outside. The freshness
  //     reference is that validated page; without --page it is
  //     design/tokens.css, which must likewise resolve inside design/.
  //     (Fix round 2, re-red-team R2/R3/R5: the artifact check also
  //     compares device+inode, so a hardlink to a leg is caught; the
  //     page must be the built page — an .html file inside design/,
  //     or tokens.css itself — and at least as new as tokens.css, so
  //     the chain tokens <= page <= artifacts holds; on --gate fail a
  //     bad --page only warns and is recorded as page: null.)
  //   F4 — the two legs must be two files: the resolved paths must
  //     differ AND the device+inode pairs must differ (a hardlink pair
  //     shares one inode and is rejected too).
  //   F5 — the PASS marker must be the verdict line itself (a line whose
  //     trimmed content equals the marker exactly — a comment mentioning
  //     the string does not count), and a file containing its leg's FAIL
  //     marker is rejected even if a PASS string also appears in it
  //     (an appended re-run concatenating an old PASS and a new FAIL
  //     is a FAIL, not a pass). (Fix round 2, R4: the FAIL check is
  //     per-line with a word boundary — FAILURE/FAILED do not match.)
  //     (Fix round 5, F2/F3/F4 + fix round 6, F7/F9: both verdict
  //     lines are canonicalised first — stripInvisible() NFD-normalises
  //     then deletes every invisible character (\s White_Space,
  //     \p{C} controls/formats, \p{M} marks, U+FFFD, the F7 Lo/So
  //     denylist) and the comparison runs on what remains, so invisible
  //     unicode in a copied verdict line neither false-rejects a PASS
  //     nor hides a FAIL, in any position. The R4 word boundary is
  //     evaluated on the stripped string. S2: --page needs a non-empty
  //     basename before `.html`. S1: the --page anchor below also
  //     requires tokens.css to be a regular file, mirroring the
  //     fallback.)
  //   R1 (fix round 2) — design/ itself must resolve inside the
  //     project: a symlinked design/ pointing outside the project is
  //     rejected; pointing inside is accepted (containment, not
  //     outright rejection). Checked on the --gate pass path, on both
  //     `record` and `land` (the validator is shared).
  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  const designDir = path.resolve(project, 'design');
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { designReal = path.join(projectReal, 'design'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  // Canonical leg-artifact locations, for the --page must-not-be-an-artifact
  // rule (applies on both gate values, even when no legs are cited).
  const canonicalLegReals = ['gate-leg1.log', 'gate-leg2.log'].map((n) => {
    try { return fs.realpathSync(path.join(designDir, n)); } catch { return path.join(designReal, n); }
  });
  const legs = {};
  if (args.gate === 'pass') {
    // R1: design/ itself must resolve inside the project — a symlinked
    // design/ pointing outside would make every "inside design/" check
    // pass for outside files. A symlinked design/ pointing INSIDE the
    // project is accepted (containment, not outright rejection).
    if (!inside(designReal, projectReal)) reject(`<project>/design/ resolves outside the project (real path ${designReal}) — a design/ directory outside the project cannot hold gate artifacts.`);
    for (const [leg, flag, marker, failMarker] of [
      ['leg1', 'gate-leg1', GATE_LEG_MARKERS.leg1, GATE_LEG_FAIL_MARKERS.leg1],
      ['leg2', 'gate-leg2', GATE_LEG_MARKERS.leg2, GATE_LEG_FAIL_MARKERS.leg2],
    ]) {
      const legName = leg === 'leg1' ? 'gate.sh' : 'gate.mjs';
      const given = args[flag];
      if (!given) reject(`--gate pass needs --${flag} <path> (the ${legName} output file under design/). A gate pass with no artifact is a self-assertion, not a record.`);
      if (path.isAbsolute(given)) reject(`--${flag} must be a path relative to the project, inside design/ — absolute paths are rejected (got "${given}").`);
      if (hasDotSegment(given)) reject(`--${flag} must be a plain project-relative path inside design/ — "." and ".." segments are rejected (got "${given}").`);
      const resolved = path.resolve(project, given);
      if (resolved !== designDir && !resolved.startsWith(designDir + path.sep)) reject(`--${flag} must resolve inside <project>/design/ (got "${given}" — '..' escapes are rejected).`);
      let lstat;
      try { lstat = fs.lstatSync(resolved); } catch { reject(`--${flag} file does not exist: ${given} (run the ${legName} leg first and save its output there).`); }
      if (lstat.isSymbolicLink()) reject(`--${flag} file ${given} is a symlink — gate artifacts must be real files inside <project>/design/, not links to files elsewhere.`);
      let stat;
      try { stat = fs.statSync(resolved); } catch { reject(`--${flag} file does not exist: ${given} (run the ${legName} leg first and save its output there).`); }
      if (!stat.isFile() || stat.size === 0) reject(`--${flag} file is empty or not a file: ${given}.`);
      let real;
      try { real = fs.realpathSync(resolved); } catch { reject(`--${flag} file cannot be resolved: ${given}.`); }
      if (!inside(real, designReal)) reject(`--${flag} file ${given} resolves outside <project>/design/ (real path ${real}) — a link or mount escaping design/ is rejected.`);
      const text = fs.readFileSync(resolved, 'utf8');
      // R4: per-line FAIL check with a word boundary — a stripped line
      // matches the stripped FAIL marker only when FAIL is NOT followed
      // by a letter, so FAILURE/FAILED do not match but `FAIL (...)`,
      // `FAIL (exit 1)` and bare FAIL do. (Fix round 5, F2/F3/F4 + fix
      // round 6, F7/F9: line and marker are NFD-normalised and stripped
      // first — every invisible character deleted — so a FAIL verdict
      // copied with invisible unicode still rejects, and the boundary
      // is evaluated on the stripped string, so a split FAILURE does
      // not match.)
      const hasFailVerdict = text.split('\n').some((line) => {
        const stripped = stripInvisible(line);
        const strippedMarker = stripInvisible(failMarker);
        let idx = stripped.indexOf(strippedMarker);
        while (idx !== -1) {
          const next = stripped[idx + strippedMarker.length];
          if (next === undefined || !/[A-Za-z]/.test(next)) return true;
          idx = stripped.indexOf(strippedMarker, idx + 1);
        }
        return false;
      });
      if (hasFailVerdict) reject(`--${flag} file ${given} contains its leg's FAIL verdict ("${failMarker}") — the gate leg did not pass on this build, even if a PASS string also appears in the file.`);
      // (Fix round 5, F2/F3/F4 + fix round 6, F7/F9: the PASS line is
      // NFD-normalised and stripped the same way as the FAIL check
      // above and compared by exact equality, so invisible unicode in
      // a copied verdict line does not false-reject a real pass, in
      // any position.)
      const verdictLine = text.split('\n').some((line) => stripInvisible(line) === stripInvisible(marker));
      if (!verdictLine) reject(`--${flag} file ${given} does not contain its leg's PASS marker ("${marker}") as the verdict line — the gate leg did not pass on this build.`);
      const field = leg === 'leg1' ? 'Leg1' : 'Leg2';
      legs[leg] = {
        resolved, real, stat,
        rel: path.relative(project, resolved),
        sha: crypto.createHash('sha256').update(fs.readFileSync(resolved)).digest('hex'),
        field,
      };
    }
    // F4: two legs, two files — same resolved path, or same device+inode
    // (a hardlink pair), is one file cited twice, not two legs.
    if (legs.leg1.resolved === legs.leg2.resolved) reject('--gate-leg1 and --gate-leg2 cite the same file — the two legs must be two separate artifact files.');
    if (legs.leg1.stat.dev === legs.leg2.stat.dev && legs.leg1.stat.ino === legs.leg2.stat.ino) reject('--gate-leg1 and --gate-leg2 are the same file (same device+inode — a hardlink pair) — the two legs must be two separate artifact files.');
  }
  // F3 (fix round 1) + R2/R3/R5 (fix round 2): --page validation —
  // runs on both gate values, whenever --page is given, so the stored
  // page is always a canonical in-project path. On --gate pass a failed
  // check REJECTS (exit 2, nothing written). On --gate fail a failed
  // check only warns (R5): the fail is recorded with page: null,
  // because a fail record needs no artifact at all and refusing it
  // would lose the record of the failure itself.
  let pageRel = null;
  let refStat = null;
  let refLabel = 'design/tokens.css';
  // tokens.css identity, best-effort (for the --page == tokens.css
  // exception in the shape rule, and for the R3 anchor / fallback on
  // the pass path — a missing tokens.css is rejected there, below).
  const tokensPath = path.join(designDir, 'tokens.css');
  let tokensReal = null;
  let tokensStat = null;
  let tokensLstat = null;
  try { tokensReal = fs.realpathSync(tokensPath); } catch { /* missing: pass path rejects below */ }
  try { tokensStat = fs.statSync(tokensPath); } catch { /* missing: pass path rejects below */ }
  try { tokensLstat = fs.lstatSync(tokensPath); } catch { /* missing: pass path rejects below */ }
  if (args.page) {
    // pageFail: hard reject on the pass path; throw (caught below, warn
    // + drop the page) on the fail path. reject() exits, so the throw
    // only ever happens on the fail path.
    const pageFail = (msg) => { if (args.gate === 'fail') throw new Error(msg); reject(msg); };
    try {
      const given = args.page;
      // M2 (D13 edge case 3): a ".." that cancels out
      // (design/../design/x.html) is invisible after resolve — reject
      // "." / ".." segments in the raw spelling, before resolve.
      if (hasDotSegment(given)) pageFail(`--page ${given} must be a plain project-relative path inside <project>/design/ — "." and ".." segments are rejected.`);
      const resolved = path.resolve(project, given);
      let lstat;
      try { lstat = fs.lstatSync(resolved); } catch { pageFail(`--page file does not exist: ${given} (the built page of this project).`); }
      if (lstat.isSymbolicLink()) pageFail(`--page file ${given} is a symlink — the built page must be a real file inside the project, not a link to a file elsewhere.`);
      let real;
      try { real = fs.realpathSync(resolved); } catch { pageFail(`--page file cannot be resolved: ${given}.`); }
      if (!inside(real, projectReal)) pageFail(`--page must resolve inside the project (got "${given}" — an outside file cannot be the freshness reference for this build).`);
      let stat;
      try { stat = fs.statSync(real); } catch { pageFail(`--page file does not exist: ${given}.`); }
      if (!stat.isFile()) pageFail(`--page must be a regular file (got "${given}").`);
      // R2: an artifact cannot be its own freshness reference — compare
      // by device+inode as well as realpath string (a hardlink shares
      // the inode but has a different realpath).
      const sameFile = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino;
      let isArtifact = canonicalLegReals.includes(real)
        || (legs.leg1 && legs.leg1.real === real) || (legs.leg2 && legs.leg2.real === real)
        || (legs.leg1 && sameFile(stat, legs.leg1.stat)) || (legs.leg2 && sameFile(stat, legs.leg2.stat));
      if (!isArtifact) {
        for (const legReal of canonicalLegReals) {
          try { const legStat = fs.statSync(legReal); if (sameFile(stat, legStat)) { isArtifact = true; break; } } catch { /* canonical leg file absent */ }
        }
      }
      if (isArtifact) pageFail(`--page ${given} is one of the gate artifact files — an artifact cannot be its own freshness reference.`);
      // R3 shape: --page must be the built page — an .html file inside
      // <project>/design/. The one exception is design/tokens.css
      // itself (by path, realpath, or device+inode — including a
      // hardlink to it): it IS the no---page fallback reference, so
      // citing it is citing the reference, not an attacker-chosen one.
      const isTokensRef = resolved === tokensPath || real === tokensReal || sameFile(stat, tokensStat);
      if (!isTokensRef) {
        if (!inside(real, designReal)) pageFail(`--page ${given} must resolve inside <project>/design/ — the freshness reference is the built page (got "${given}").`);
        // Fix round 3 (S2) + M2 (D13 edge cases 1–2): the basename
        // needs a REAL stem before a SINGLE `.html` suffix. The old
        // length-only check (`basename.length > 5`) let through
        // `..html` (stem ".", no name at all) and `x.html.html`
        // (stem "x.html", a double extension). The stem must contain
        // at least one non-dot character and must not itself end in
        // `.html`. The extension stays case-insensitive (uppercase
        // `.HTML` is HTML and still passes).
        const pageBase = path.basename(real);
        const pageStem = pageBase.slice(0, -5);
        if (!pageBase.toLowerCase().endsWith('.html') || !/[^.]/.test(pageStem) || pageStem.toLowerCase().endsWith('.html')) pageFail(`--page ${given} must be an .html file inside <project>/design/ — the freshness reference is the built page (got "${given}").`);
      }
      // R3 anchor (pass path only): the reference must be at least as
      // new as tokens.css — the enforced chain is
      // tokens <= page <= artifacts. tokens.css is written at
      // taste-lock time, before the build, so any genuine built page
      // is at least as fresh as the tokens it was built from. A
      // missing/unreadable or symlinked tokens.css cannot anchor:
      // fail closed. (The anchor check also runs when the page IS
      // tokens.css, where it holds trivially — same mtime.)
      if (args.gate === 'pass') {
        if (!tokensStat) pageFail(`--page freshness cannot be anchored: design/tokens.css does not exist or cannot be read.`);
        if (tokensLstat && tokensLstat.isSymbolicLink()) pageFail(`design/tokens.css is a symlink — the freshness anchor must be the real tokens file, not a link.`);
        // Fix round 3 (S1): the anchor must be a regular file, mirroring
        // the no---page fallback below — a directory named tokens.css
        // is not the tokens file, even with a fresh-looking mtime.
        if (!tokensStat || !tokensStat.isFile()) pageFail(`design/tokens.css is not a regular file — the freshness anchor must be the real tokens file, not a directory.`);
        if (tokensStat && stat.mtimeMs < tokensStat.mtimeMs) pageFail(`--page ${given} is older than design/tokens.css — a page older than the locked tokens is a claim about a different build. Rebuild and re-gate.`);
      }
      pageRel = path.relative(projectReal, real);
      refStat = stat;
      refLabel = `--page ${pageRel}`;
    } catch (e) {
      // R5: on --gate fail, a bad --page only warns and is dropped.
      if (args.gate === 'fail') {
        console.error(`run-log: WARNING — --page "${args.page}" ignored: ${e.message} Recording the fail with page: null.`);
        pageRel = null;
        refStat = null;
      } else {
        throw e;
      }
    }
  }
  if (args.gate !== 'pass') {
    return { gateLeg1: null, gateLeg2: null, gateLeg1Sha: null, gateLeg2Sha: null, page: pageRel };
  }
  // Freshness: each artifact must be at least as new as the build it
  // claims to cover — the validated page when --page is given, else
  // design/tokens.css (which must itself resolve inside design/).
  if (!refStat) {
    // R3 fallback: the reference IS design/tokens.css — it must be a
    // non-symlink regular file inside design/ (a symlinked tokens.css
    // pointing at an old in-design file is not the tokens file). The
    // anchor rule is trivially satisfied on this path (the reference
    // IS tokens.css), so the lstat rejection is what closes A8b.
    if (tokensLstat && tokensLstat.isSymbolicLink()) reject(`design/tokens.css is a symlink — the freshness reference must be the real tokens file, not a link.`);
    if (!tokensStat || !tokensStat.isFile()) reject(`--gate-leg1 freshness cannot be checked: design/tokens.css does not exist or is not a regular file.`);
    if (!tokensReal || !inside(tokensReal, designReal)) reject(`design/tokens.css resolves outside <project>/design/ — it cannot be the freshness reference.`);
    refStat = tokensStat;
  }
  for (const leg of ['leg1', 'leg2']) {
    const legName = leg === 'leg1' ? 'gate.sh' : 'gate.mjs';
    const flag = leg === 'leg1' ? 'gate-leg1' : 'gate-leg2';
    if (legs[leg].stat.mtimeMs < refStat.mtimeMs) reject(`--${flag} file ${legs[leg].rel} is older than ${refLabel} — a stale artifact is a claim about a different build. Re-run the ${legName} leg.`);
  }
  return {
    gateLeg1: legs.leg1.rel, gateLeg2: legs.leg2.rel,
    gateLeg1Sha: legs.leg1.sha, gateLeg2Sha: legs.leg2.sha,
    page: pageRel,
  };
}

// D15 (GAP-13): judge artifacts — the judge-side mirror of the D13 gate
// artifacts above. The grammar parser lives in judge-report.mjs (the
// producer) and is imported here so the format has ONE definition with
// two readers; if the module is missing (a partial install), graded
// records fail closed below rather than falling back to self-assertion.
let judgeReportMod = null;
try { judgeReportMod = await import('./judge-report.mjs'); } catch { judgeReportMod = null; }

// Every judge-artifact sha already cited by a grade event in this log:
// judgeReportSha (round + feedback records), the `;`-joined
// pairwiseReportShas / juryReportShas, and the expert report shas.
// Single-use is per BYTE content (the sha), not per path — copying a
// report to a second path does not make it a second judge call.
function collectUsedJudgeShas(rows) {
  const used = new Set();
  for (const r of rows) {
    if (r.judgeReportSha) used.add(r.judgeReportSha);
    for (const field of ['pairwiseReportShas', 'juryReportShas']) {
      if (r[field]) for (const sha of String(r[field]).split(';')) if (sha) used.add(sha);
    }
    if (r.expertMotionReportSha) used.add(r.expertMotionReportSha);
    if (r.expertUxReportSha) used.add(r.expertUxReportSha);
  }
  return used;
}

// The gate-leg paths CITED on this command (--gate-leg1 / --gate-leg2),
// when given. A judge artifact must be a different file from the legs
// the record actually cites, not only from the two canonical leg files
// (red-team round N4b: a non-canonical cited leg hardlinked to the
// judge artifact slipped past a canonical-only distinctness set).
function citedLegsOf(a) {
  const out = [];
  for (const flag of ['gate-leg1', 'gate-leg2']) {
    if (a[flag] !== undefined) out.push({ flag, given: a[flag] });
  }
  return out;
}

// ---------------------------------------------------------------------
// READ-PATH VERIFICATION (red-team round 3; round 4: SHARED, not
// mirrored): the verifiers themselves — verifyGradedLine,
// verifyJuryLine, verifyExpertCitations, verifyCrosscheckLine,
// isVerifiedGradedRound, isGenuineNoGradeRound — live in
// judge-report.mjs, next to the
// parser, and are imported from there (judgeReportMod, above).
// judge-report.mjs is import-safe; this file is not (its CLI runs
// at top level), which is why the shared home is there and not
// here. gate/runlog-check.mjs imports the SAME functions — round 4
// proved that the checker's private re-implementations of the
// round-3 verifier had drifted from it (F1–F7: the checker accepted
// a self-confessed basis and a body/header grader mismatch, and no
// copy verified juror distinctness, juror bases, expert citations,
// or the line's independenceBasis / tokensHash transcription
// fields), so there is now exactly one implementation and every
// read consumer routes through it. The two wrappers below keep
// this file's call sites (best, land's precondition, feedback's
// anchor) unchanged and fail closed when judge-report.mjs cannot
// be loaded (a partial install): no line verifies, so best crowns
// nothing, land's precondition counts nothing, and feedback's
// anchor search finds no verified graded record — the consumers'
// existing no-verified-record behaviour, never a weaker check.
// ---------------------------------------------------------------------

function isVerifiedGradedRound(project, r) {
  return judgeReportMod ? judgeReportMod.isVerifiedGradedRound(project, r) : false;
}

function isGenuineNoGradeRound(project, r) {
  return judgeReportMod ? judgeReportMod.isGenuineNoGradeRound(project, r) : false;
}

// Round 8 (C4 — the epoch rule): leg CURRENCY (a line's cited gate
// legs still matching the files on disk) is required only by the
// live-epoch consumers — feedback's anchor below and land's round
// precondition — on top of the artifact verification. It is NOT
// part of isVerifiedGradedRound / `best`: the canonical leg files
// rotate with every gate run, so a historical graded round
// verifies through its judge artifact alone. Fail closed like the
// wrappers above when judge-report.mjs cannot be loaded.
function verifyLegCitationsCurrent(project, r) {
  return judgeReportMod
    ? judgeReportMod.verifyLegCitationsCurrent(project, r)
    : { ok: false, reasons: ['judge-report parser unavailable'] };
}

// Round 6 (X1): the stored-crosscheck verifier land consults — the
// same shared verifyCrosscheckLine judge-report.mjs's prepare and
// gate/runlog-check.mjs use. Fail-closed like the wrappers above:
// with no judge-report module, no stored crosscheck verdict
// verifies, so land refuses rather than trusting the line.
function verifyCrosscheckLine(project, r) {
  return judgeReportMod
    ? judgeReportMod.verifyCrosscheckLine(project, r)
    : { ok: false, reasons: ['the judge-report parser (judge-report.mjs, next to run-log.mjs) is unavailable — a stored cross-check verdict cannot be verified without it'] };
}

// Round 7 (F1): the stored taste-lock verifier the lock command's
// version-occupation check consults — the same shared verifyLockLine
// round-brief and gate/runlog-check.mjs use. Fail-closed like the
// wrappers above: with no judge-report module, no stored lock line
// verifies, so no stored line occupies its version through this
// wrapper (the lock command's remaining semantics are unchanged).
function verifyLockLine(project, r) {
  return judgeReportMod
    ? judgeReportMod.verifyLockLine(project, r)
    : { ok: false, reasons: ['the judge-report parser (judge-report.mjs, next to run-log.mjs) is unavailable — a stored taste lock cannot be verified without it'] };
}

// Validate one cited judge artifact. `expect`:
//   flag           — the CLI flag name, for messages
//   kinds          — allowed header kinds
//   round          — the round the artifact must be bound to
//   grader / basis — when non-null, the header must EQUAL them (the main
//                    and regrade artifacts); when null (pairwise / jury /
//                    expert artifacts — separate invocations with no
//                    record flag to transcribe), the header basis is
//                    still independence-checked on its own text
//   pageRel        — when non-null, the canonical --page the header must
//                    name; when null, the header's own page is the binding
//   tokensHash     — when non-null, the record's tokens hash, which the
//                    header must equal as well as the on-disk hash
//   notRegraded    — when an array (possibly empty), the header's
//                    not-regraded set must equal it; null = do not check
//   usedShas       — the single-use set; this artifact's sha is checked
//                    against it and added to it
//   citedLegs      — [{ flag, given }] gate-leg paths cited on this
//                    command; they join the distinctness set (N4b)
//   others         — [{ real, stat, rel }] artifacts already validated in
//                    this command (device+inode distinctness)
// Returns { rel, sha, header, parsed, stat, real, pageSha, pageStat,
// shots, shotsA, shotsB }. Rejects (exit 2, nothing written) on any
// failed check.
function validateJudgeArtifact(project, given, expect) {
  const flag = `--${expect.flag}`;
  if (!judgeReportMod) reject(`${flag}: the judge-report parser (judge-report.mjs, next to run-log.mjs) is missing — a graded record cannot be validated, so it cannot be recorded. Re-run ./install.sh.`);
  if (!given) reject(`${flag} is required (D15): a score with no judge artifact is a self-assertion, not a record. Run judge-report.mjs prepare, spawn the independent judge to fill the report, then record with ${flag} citing it.`);
  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  const designDir = path.resolve(project, 'design');
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { designReal = path.join(projectReal, 'design'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  if (!inside(designReal, projectReal)) reject(`<project>/design/ resolves outside the project (real path ${designReal}) — a design/ directory outside the project cannot hold judge artifacts.`);
  if (path.isAbsolute(given)) reject(`${flag} must be a path relative to the project, inside design/ — absolute paths are rejected (got "${given}").`);
  if (hasDotSegment(given)) reject(`${flag} must be a plain project-relative path inside design/ — "." and ".." segments are rejected (got "${given}").`);
  const resolved = path.resolve(project, given);
  if (resolved !== designDir && !resolved.startsWith(designDir + path.sep)) reject(`${flag} must resolve inside <project>/design/ (got "${given}" — '..' escapes are rejected).`);
  let lstat;
  try { lstat = fs.lstatSync(resolved); } catch { reject(`${flag} file does not exist: ${given} (run judge-report.mjs prepare and have the judge fill the report first).`); }
  if (lstat.isSymbolicLink()) reject(`${flag} file ${given} is a symlink — judge artifacts must be real files inside <project>/design/, not links to files elsewhere.`);
  let stat;
  try { stat = fs.statSync(resolved); } catch { reject(`${flag} file does not exist: ${given}.`); }
  if (!stat.isFile() || stat.size === 0) reject(`${flag} file is empty or not a file: ${given}.`);
  let real;
  try { real = fs.realpathSync(resolved); } catch { reject(`${flag} file cannot be resolved: ${given}.`); }
  if (!inside(real, designReal)) reject(`${flag} file ${given} resolves outside <project>/design/ (real path ${real}) — a link or mount escaping design/ is rejected.`);
  const rel = path.relative(project, resolved);
  const bytes = fs.readFileSync(resolved);
  const sha = crypto.createHash('sha256').update(bytes).digest('hex');
  // Distinctness: the artifact must be its own file — not the page, not
  // tokens.css, not a gate leg, not another judge artifact in this
  // command (device+inode, so a hardlink is caught like D13's F4).
  const sameFile = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino;
  const distinctFrom = [];
  const tokensPath = path.join(designDir, 'tokens.css');
  for (const [p, label] of [[tokensPath, 'design/tokens.css'], [path.join(designDir, 'gate-leg1.log'), 'the leg-1 gate artifact'], [path.join(designDir, 'gate-leg2.log'), 'the leg-2 gate artifact']]) {
    try { distinctFrom.push({ real: fs.realpathSync(p), stat: fs.statSync(p), rel: label }); } catch { /* absent: nothing to be distinct from */ }
  }
  // Red-team round (N4b): the legs CITED on this command join the set
  // too — a record may cite non-canonical leg paths (--gate-leg1 /
  // --gate-leg2 anywhere inside design/), and a judge artifact that IS
  // one of those cited files (same realpath, or same device+inode — a
  // hardlink) is one file cited as two artifacts, exactly as with the
  // canonical pair.
  for (const cited of expect.citedLegs || []) {
    const p = path.resolve(project, cited.given);
    try { distinctFrom.push({ real: fs.realpathSync(p), stat: fs.statSync(p), rel: `the cited --${cited.flag} artifact (${cited.given})` }); } catch { /* absent: nothing to be distinct from */ }
  }
  for (const o of expect.others || []) distinctFrom.push(o);
  for (const o of distinctFrom) {
    if (real === o.real || sameFile(stat, o.stat)) reject(`${flag} file ${given} is the same file as ${o.rel} — a judge artifact must be its own file, not another artifact or the tokens file.`);
  }
  // Single-use: one judge artifact's bytes back exactly one grade event.
  if (expect.usedShas.has(sha)) reject(`${flag} file ${given} has already been cited by an earlier grade event in this run log (sha256 ${sha.slice(0, 12)}…) — one judge artifact backs exactly one grade; a new grade needs a new judge call and a new report.`);
  // Grammar: the shared parser (magic line, void/PENDING lines, strict
  // header, per-kind body grammar).
  const parsed = judgeReportMod.parseJudgeReport(bytes.toString('utf8'));
  if (parsed.problems.length) reject(`${flag} file ${given} is not a well-formed judge report: ${parsed.problems.join('; ')}.`);
  const header = parsed.header;
  // Cross-field equality: the flags become a verified transcription.
  if (Number(header.round) !== expect.round) reject(`${flag} file ${given} is a report for round ${header.round}, not round ${expect.round} — an artifact from another round cannot back this record.`);
  if (!expect.kinds.includes(header.kind)) reject(`${flag} file ${given} is a ${header.kind} report; this citation needs ${expect.kinds.join(' | ')}.`);
  if (expect.grader !== null && expect.grader !== undefined && header.grader !== expect.grader) reject(`${flag} file ${given} names grader "${header.grader}", not "${expect.grader}" — the recorded grader must be the artifact's grader.`);
  if (expect.basis !== null && expect.basis !== undefined && header.basis !== expect.basis.trim()) reject(`${flag} file ${given} carries a different independence basis than --basis — the recorded basis must be the artifact's basis, word for word.`);
  checkIndependenceBasis(header.basis, header.grader);
  if (parsed.bodyGrader !== undefined && (parsed.bodyGrader !== header.grader || parsed.bodyBasis !== header.basis || parsed.bodyRound !== expect.round)) {
    reject(`${flag} file ${given}: the body's Round line (round ${parsed.bodyRound}, grader ${parsed.bodyGrader}) does not match its header — the header and the judge's own output must agree.`);
  }
  // Page binding: the header's page must be the record's page (when the
  // record has one), and its sha256 must equal the file on disk NOW —
  // a page edited after judging no longer matches its report.
  if (expect.pageRel && header.page !== expect.pageRel) reject(`${flag} file ${given} grades page "${header.page}", not the recorded page "${expect.pageRel}" — the artifact must bind to the page being recorded.`);
  const pageResolved = path.resolve(project, header.page);
  let pageStat;
  try { pageStat = fs.statSync(pageResolved); } catch { reject(`${flag} file ${given} names page "${header.page}", which does not exist on disk.`); }
  if (sameFile(stat, pageStat)) reject(`${flag} file ${given} is the same file as its page — a judge artifact must be its own file.`);
  const pageSha = sha256File(pageResolved);
  if (pageSha !== header['page-sha256']) reject(`${flag} file ${given} binds to page-sha256 ${header['page-sha256'].slice(0, 12)}… but ${header.page} now hashes to ${(pageSha || 'unreadable').slice(0, 12)}… — the page changed after judging (or the artifact belongs to another build). Re-grade the current page.`);
  // Tokens binding: the header's tokens hash must equal the tokens file
  // on disk now, and the record's own tokens hash when one is asserted.
  const tokensShaNow = sha256File(tokensPath);
  if (!tokensShaNow) reject(`${flag}: design/tokens.css does not exist or cannot be read — the artifact's tokens binding cannot be checked.`);
  if (tokensShaNow !== header['tokens-sha256']) reject(`${flag} file ${given} binds to tokens-sha256 ${header['tokens-sha256'].slice(0, 12)}… but design/tokens.css now hashes to ${tokensShaNow.slice(0, 12)}… — the tokens changed after judging. Re-grade against the locked tokens.`);
  if (expect.tokensHash && expect.tokensHash !== header['tokens-sha256']) reject(`${flag} file ${given} binds to tokens-sha256 ${header['tokens-sha256'].slice(0, 12)}… but this record asserts --tokens-hash ${expect.tokensHash.slice(0, 12)}… — the two must agree.`);
  // Screenshot binding: every listed shot must exist with its listed
  // hash — the artifact certifies the pixels it names, no others.
  // QC round (F3): existence is not enough — each shot path gets the
  // page rules too: no symlink as the final component, and the real
  // path must resolve inside the project, so a header cannot bind the
  // artifact to pixels outside the project (or behind a link) even
  // when the hash matches a file placed there.
  const checkShots = (list, field) => {
    for (const shot of list) {
      const shotResolved = path.resolve(project, shot.path);
      let shotLstat;
      try { shotLstat = fs.lstatSync(shotResolved); } catch { reject(`${flag} file ${given}: header ${field} names screenshot "${shot.path}", which does not exist on disk.`); }
      if (shotLstat.isSymbolicLink()) reject(`${flag} file ${given}: header ${field} names screenshot "${shot.path}", which is a symlink — screenshots must be real files inside the project, not links to files elsewhere.`);
      let shotReal;
      try { shotReal = fs.realpathSync(shotResolved); } catch { reject(`${flag} file ${given}: header ${field} names screenshot "${shot.path}", which cannot be resolved.`); }
      if (!inside(shotReal, projectReal)) reject(`${flag} file ${given}: header ${field} names screenshot "${shot.path}", which resolves outside the project (real path ${shotReal}) — a judge artifact binds only to this project's screenshots.`);
      const shotSha = sha256File(shotResolved);
      if (!shotSha) reject(`${flag} file ${given}: header ${field} names screenshot "${shot.path}", which does not exist on disk.`);
      if (shotSha !== shot.sha256) reject(`${flag} file ${given}: header ${field} binds screenshot "${shot.path}" to sha256 ${shot.sha256.slice(0, 12)}… but the file now hashes to ${shotSha.slice(0, 12)}… — the screenshots changed after judging. Re-grade.`);
    }
    return list;
  };
  const shots = checkShots(judgeReportMod.parseShotList(header.screenshots) || [], 'screenshots');
  const shotsA = checkShots(judgeReportMod.parseShotList(header['shots-a']) || [], 'shots-a');
  const shotsB = checkShots(judgeReportMod.parseShotList(header['shots-b']) || [], 'shots-b');
  if (header.kind === 'pairwise') {
    if (!shotsA.length || !shotsB.length) reject(`${flag} file ${given} is a pairwise report with an empty shots-a / shots-b set — a pairwise verdict must bind to both versions' screenshots.`);
  } else if (!shots.length) {
    reject(`${flag} file ${given} binds to no screenshots — a judge report must name the screenshot set it graded.`);
  }
  // not-regraded binding (cheap grades): the header's set must equal
  // the record's --not-regraded set.
  if (expect.notRegraded !== null && expect.notRegraded !== undefined) {
    const headerSet = header['not-regraded'] === '-' ? [] : header['not-regraded'].split(',').map((s) => s.trim()).filter(Boolean);
    const want = [...expect.notRegraded].sort();
    const got = [...headerSet].sort();
    if (JSON.stringify(want) !== JSON.stringify(got)) reject(`${flag} file ${given} carries not-regraded "${header['not-regraded']}" but the record carries "${expect.notRegraded.join(',') || '(none)'}" — the two must agree.`);
  }
  // Freshness: tokens <= page <= artifact (mtime; equal allowed — the
  // D13 chain; the hash binding above is the load-bearing check, this
  // is the tripwire — F6 inheritance, stated in the header).
  let tokensStat;
  try { tokensStat = fs.statSync(tokensPath); } catch { tokensStat = null; }
  if (tokensStat && stat.mtimeMs < tokensStat.mtimeMs) reject(`${flag} file ${given} is older than design/tokens.css — a stale artifact is a claim about a different build.`);
  if (stat.mtimeMs < pageStat.mtimeMs) reject(`${flag} file ${given} is older than ${header.page} — the report predates the page it claims to grade. Re-grade.`);
  expect.usedShas.add(sha);
  return { rel, sha, header, parsed, stat, real, pageSha, pageStat, shots, shotsA, shotsB };
}

// D15: the crosscheck --report path gets the same existence/containment
// validation as other artifacts (existence/containment only — no
// content grammar in this wave). Returns the path unchanged: the stored
// form stays the caller's project-relative path, as before D15.
function validateCrosscheckReport(project, given) {
  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  const designDir = path.resolve(project, 'design');
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { designReal = path.join(projectReal, 'design'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  if (!inside(designReal, projectReal)) reject(`<project>/design/ resolves outside the project (real path ${designReal}) — a design/ directory outside the project cannot hold a cross-check report.`);
  if (path.isAbsolute(given)) reject(`--report must be a path relative to the project, inside design/ — absolute paths are rejected (got "${given}").`);
  if (hasDotSegment(given)) reject(`--report must be a plain project-relative path inside design/ — "." and ".." segments are rejected (got "${given}").`);
  const resolved = path.resolve(project, given);
  if (resolved !== designDir && !resolved.startsWith(designDir + path.sep)) reject(`--report must resolve inside <project>/design/ (got "${given}" — '..' escapes are rejected).`);
  let lstat;
  try { lstat = fs.lstatSync(resolved); } catch { reject(`--report file does not exist: ${given} (the cross-check report must be written before its verdict is recorded — D15).`); }
  if (lstat.isSymbolicLink()) reject(`--report file ${given} is a symlink — cross-check reports must be real files inside <project>/design/, not links to files elsewhere.`);
  let stat;
  try { stat = fs.statSync(resolved); } catch { reject(`--report file does not exist: ${given}.`); }
  if (!stat.isFile() || stat.size === 0) reject(`--report file is empty or not a file: ${given}.`);
  let real;
  try { real = fs.realpathSync(resolved); } catch { reject(`--report file cannot be resolved: ${given}.`); }
  if (!inside(real, designReal)) reject(`--report file ${given} resolves outside <project>/design/ (real path ${real}).`);
}

const OUTCOMES = ['kept', 'discarded', 're-pick', 'stopped', 'escalated', 'pending'];

function parseOutcome(s) {
  if (s === undefined) return 'pending';
  if (!OUTCOMES.includes(s)) usage(`--outcome must be one of ${OUTCOMES.join(' | ')}`);
  return s;
}

// P6 trigger (stop-rules.md): which trigger ended the direction on this
// round. `stagnation` is the RETIRED value for the deleted trigger (c) —
// accepted so old logs still parse, never emitted by the new rules.
const TRIGGERS = ['flat-line', 'round-1-repick', 'stagnation'];

function parseTrigger(s) {
  if (s === undefined) return null;
  if (!TRIGGERS.includes(s)) usage(`--trigger must be one of ${TRIGGERS.join(' | ')} (stagnation is retired — accepted for old logs only, never emitted by the new rules)`);
  return s;
}

// P11 pairwise verdict vs the incumbent (best-version-kept is decided by
// this verdict when pairwise runs, by absolute scores otherwise).
const PAIRWISE_VERDICTS = ['keep-incumbent', 'keep-challenger', 'tie'];

function parsePairwise(s) {
  if (s === undefined) return null;
  if (!PAIRWISE_VERDICTS.includes(s)) usage(`--pairwise must be one of ${PAIRWISE_VERDICTS.join(' | ')}`);
  return s;
}

function parsePairwiseAgrees(s) {
  if (s === undefined) return null;
  if (s === 'yes') return true;
  if (s === 'no') return false;
  usage('--pairwise-agrees must be yes or no');
  return null;
}

// P14 stop-round jury: a "t,l,c,s" score set (same 1–5 shape as --scores).
function parseJuryScores(s, flag) {
  const parts = s.split(',').map((v) => Number(v.trim()));
  if (parts.length !== 4 || parts.some((v) => !Number.isInteger(v) || v < 1 || v > 5)) {
    usage(`${flag} must be four integers 1-5 (type,layout,colour,space)`);
  }
  return { type: parts[0], layout: parts[1], colour: parts[2], space: parts[3] };
}

function parseJury(s) {
  if (s === undefined) return null;
  return parseJuryScores(s, '--jury');
}

const JURY_MODES = ['disjoint-3', 'single-family', 'single'];

function parseJuryMode(s) {
  if (s === undefined) return null;
  if (!JURY_MODES.includes(s)) usage(`--jury-mode must be one of ${JURY_MODES.join(' | ')}`);
  return s;
}

function parseJuryVotes(s) {
  if (s === undefined) return null;
  const votes = s.split(';').map((v) => v.trim()).filter(Boolean);
  if (votes.length !== 3) usage('--jury-votes must be three votes, ";"-separated, each four integers 1-5 (type,layout,colour,space)');
  return votes.map((v) => parseJuryScores(v, '--jury-votes'));
}

// P13 --not-regraded (W-LOOP fix 2026-11-11): comma-separated SECTION ids
// the round did not re-score because they were unchanged since an earlier
// round (e.g. "#hero,#footer"). Sections, not axes — the cheap grade still
// produces fresh per-axis scores for the whole page. --scores always
// carries four fresh integers or "none"; a "not re-measured" value in
// --scores is rejected by parseScores.
function parseNotRegraded(s) {
  if (s === undefined) return null;
  const ids = s.split(',').map((v) => v.trim()).filter(Boolean);
  if (!ids.length) usage('--not-regraded needs at least one section id, e.g. "#hero,#footer"');
  for (const id of ids) {
    if (!/^#[A-Za-z][\w-]*$/.test(id)) usage(`--not-regraded section ids must look like "#hero" (got "${id}")`);
  }
  return [...new Set(ids)];
}

// Wave 6 — expert second-opinion scores (Motion/UX, rubric Motion:/UX:
// lines). One integer 1-5 each; a score without its one-line evidence is
// a usage error, and evidence without its score is too. Same observable
// bar as --evidence (evidenceNamesObservable), checked by the caller.
function parseExpertScore(s, flag) {
  if (s === undefined) return null;
  const v = Number(s);
  if (!Number.isInteger(v) || v < 1 || v > 5) usage(`${flag} must be an integer 1-5`);
  return v;
}

function parseExpert(s, evidence, flag, evidenceFlag) {
  const score = parseExpertScore(s, flag);
  if (score === null && evidence !== undefined) usage(`${evidenceFlag} needs its ${flag} score`);
  if (score !== null && evidence === undefined) usage(`${flag} needs its ${evidenceFlag} (one line naming an observable element)`);
  if (score !== null && !evidenceNamesObservable(evidence)) {
    console.error(`run-log: REJECTED — ${evidenceFlag} (10+ characters) must name an observable element, e.g. a named element or a measurement — not a generic impression like "x" or "looks good". No entry written.`);
    process.exit(2);
  }
  return { score, evidence: evidence === undefined ? null : evidence.trim() };
}

function median3(a, b, c) {
  return [a, b, c].sort((x, y) => x - y)[1];
}

// The jury median is definitional (P14: median per axis): a --jury that is
// not the per-axis median of --jury-votes is an inconsistent record.
function checkJuryMedian(jury, juryVotes) {
  if (!jury || !juryVotes) return;
  for (const axis of ['type', 'layout', 'colour', 'space']) {
    const median = median3(juryVotes[0][axis], juryVotes[1][axis], juryVotes[2][axis]);
    if (jury[axis] !== median) {
      reject(`--jury ${axis} is ${jury[axis]} but the per-axis median of --jury-votes is ${median}. The jury median is definitional (P14) — record the median, not a different number.`);
    }
  }
}

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0];
if (!args.project) usage('--project <dir> is required');

if (cmd === 'record') {
  const round = Number(args.round);
  if (!Number.isInteger(round) || round < 1) usage('--round must be a positive integer');
  const grader = (args.grader || '').trim();
  if (FORBIDDEN_GRADERS.includes(grader.toLowerCase())) {
    console.error(`run-log: REJECTED — grader "${grader}" is the builder. The builder NEVER grades its own work (user direction 2026-11-10). No entry written.`);
    process.exit(2);
  }
  // No-grade record (probe G-4): --grader none is accepted ONLY with
  // --scores none. It records grader: null and a gate-reflecting grade
  // label — "gate green, vision not available" on --gate pass, "gate red,
  // no grade" on --gate fail — no invented grader label, no basis. A score
  // with grader none is a grade without a judge: REJECTED.
  const scores = parseScores(args.scores || 'none');
  const noGrade = grader.toLowerCase() === 'none';
  // P6/P11/P14 record fields. Pairwise and jury need a graded round (a
  // no-grade round has no scores to compare or to take a median of);
  // --trigger is accepted on any record. --not-regraded likewise needs
  // a graded round: a no-grade round scored nothing, so "sections not
  // re-scored" is meaningless on it.
  const trigger = parseTrigger(args.trigger);
  const pairwise = parsePairwise(args.pairwise);
  const pairwiseAgrees = parsePairwiseAgrees(args['pairwise-agrees']);
  const jury = parseJury(args.jury);
  const juryMode = parseJuryMode(args['jury-mode']);
  const juryVotes = parseJuryVotes(args['jury-votes']);
  const notRegraded = parseNotRegraded(args['not-regraded']);
  checkJuryMedian(jury, juryVotes);
  // Wave 6 — expert second opinions (Motion/UX). Allowed on any record,
  // graded or no-grade: an expert opinion is not a grade, and experts can
  // be consulted even when no independent judge grade exists. NOT added
  // to the no-grade rejection below.
  const expertMotion = parseExpert(args['expert-motion'], args['expert-motion-evidence'], '--expert-motion', '--expert-motion-evidence');
  const expertUx = parseExpert(args['expert-ux'], args['expert-ux-evidence'], '--expert-ux', '--expert-ux-evidence');
  if (noGrade && (pairwise || pairwiseAgrees !== null || jury || juryMode || juryVotes || notRegraded)) {
    console.error('run-log: REJECTED — --pairwise / --pairwise-agrees / --jury / --jury-mode / --jury-votes / --not-regraded need a graded round. A --grader none record has no scores to compare, to take a median of, or to mark sections not re-scored on. No entry written.');
    process.exit(2);
  }
  // D15: single-use set + the expert-artifact validator, shared by the
  // graded and no-grade branches (expert scores need their artifacts on
  // both). The set is seeded from the log and grows with every artifact
  // validated in this command, so two citations of one file in a single
  // record are also refused.
  const usedJudgeShas = collectUsedJudgeShas(readLog(args.project));
  const validatedJudgeArtifacts = [];
  const validateExpert = (expert, reportFlag, kind, pageRel) => {
    if (expert.score === null) {
      if (args[reportFlag] !== undefined) reject(`--${reportFlag} is cited without its expert score — an expert artifact backs an expert score, not a bare record.`);
      return null;
    }
    if (args[reportFlag] === undefined) reject(`--${reportFlag} is required (D15): an expert score with no expert artifact is a self-assertion, not a second opinion. Run judge-report.mjs prepare --kind ${kind} and have the expert fill the report.`);
    // QC round (F1): the expert artifact binds to the RECORD's page —
    // its header page must equal the page this record grades and its
    // page-sha256 must equal that page's current hash, exactly as the
    // jury artifacts already bind. (pageRel is null only when the
    // record itself carries no validated page — a --gate fail record
    // with no --page — in which case the header's own page, hash-checked
    // against disk by the validator, is the binding, as for pairwise.)
    const art = validateJudgeArtifact(args.project, args[reportFlag], {
      flag: reportFlag, kinds: [kind], round, grader: null, basis: null,
      pageRel, tokensHash: null, notRegraded: null,
      usedShas: usedJudgeShas, others: validatedJudgeArtifacts,
      citedLegs: citedLegsOf(args),
    });
    if (art.parsed.expertScore !== expert.score || art.parsed.expertEvidence !== expert.evidence) {
      reject(`--${reportFlag} file ${args[reportFlag]} records ${kind === 'expert-motion' ? 'Motion' : 'UX'} ${art.parsed.expertScore} — "${art.parsed.expertEvidence}", not the cited ${expert.score} — "${expert.evidence}". The record must transcribe the expert artifact, not assert over it.`);
    }
    validatedJudgeArtifacts.push(art);
    return art;
  };
  if (noGrade) {
    if (scores) {
      console.error('run-log: REJECTED — --grader none goes with --scores none only. A score IS a grade and needs an independent judge (judge-subagent | muse-manager | other-model). No entry written.');
      process.exit(2);
    }
    if (args.grade !== undefined && args.grade !== 'none') usage('--grader none goes with --scores none and no grade; use a graded record for scores');
    if (!['pass', 'fail'].includes(args.gate)) usage('--gate must be pass or fail');
    // D15: a no-grade record cites NO judge artifact — a judge report
    // on a no-grade round would be a grade wearing a no-grade label.
    // (Expert artifacts are separate: they back expert scores, which
    // ARE allowed here, and are validated below.)
    if (args['judge-report'] !== undefined || args['pairwise-reports'] !== undefined || args['judge-reports'] !== undefined) {
      console.error('run-log: REJECTED — a --grader none record cites no judge artifact (--judge-report / --pairwise-reports / --judge-reports). A no-grade round has no judge; if a judge graded, record it as a graded round with the artifact. No entry written.');
      process.exit(2);
    }
    // D13: a --gate pass without both leg artifacts is refused (exit 2).
    const gateArtifacts = validateGateArtifacts(args.project, args);
    // D15: expert scores on a no-grade record need their artifacts too.
    const ngExpertMotionArt = validateExpert(expertMotion, 'expert-motion-report', 'expert-motion', gateArtifacts.page);
    const ngExpertUxArt = validateExpert(expertUx, 'expert-ux-report', 'expert-ux', gateArtifacts.page);
    const rec = {
      kind: 'round', round, grader: null, independenceBasis: null,
      scores: null, grade: args.gate === 'fail' ? 'gate red, no grade' : 'gate green, vision not available',
      evidence: null, gate: args.gate,
      gateLeg1: gateArtifacts ? gateArtifacts.gateLeg1 : null,
      gateLeg2: gateArtifacts ? gateArtifacts.gateLeg2 : null,
      gateLeg1Sha: gateArtifacts ? gateArtifacts.gateLeg1Sha : null,
      gateLeg2Sha: gateArtifacts ? gateArtifacts.gateLeg2Sha : null,
      gateFindings: args['gate-findings'] || null,
      variant: args.variant || null,
      tokensHash: resolveTokensHash(args.project, undefined, args['tokens-hash']),
      fixClass: args['fix-class'] || null,
      outcome: parseOutcome(args.outcome),
      page: gateArtifacts ? gateArtifacts.page : null,
      trigger,
      pairwise: null, pairwiseAgrees: null, jury: null, juryMode: null, juryVotes: null,
      notRegraded: null,
      expertMotion: expertMotion.score, expertMotionEvidence: expertMotion.evidence,
      expertUx: expertUx.score, expertUxEvidence: expertUx.evidence,
      judgeReport: null, judgeReportSha: null, pageSha: null,
      pairwiseReports: null, pairwiseReportShas: null, juryReportShas: null,
      expertMotionReport: ngExpertMotionArt ? ngExpertMotionArt.rel : null,
      expertMotionReportSha: ngExpertMotionArt ? ngExpertMotionArt.sha : null,
      expertUxReport: ngExpertUxArt ? ngExpertUxArt.rel : null,
      expertUxReportSha: ngExpertUxArt ? ngExpertUxArt.sha : null,
      notes: args.notes || null,
      at: new Date().toISOString(),
    };
    appendLog(args.project, rec);
    console.log(`run-log: recorded round ${round} (grader: none; grade: ${rec.grade}; gate: ${args.gate})`);
    process.exit(0);
  }
  if (!ALLOWED_GRADERS.includes(grader)) {
    console.error(`run-log: REJECTED — grader "${grader}" is not an allowed independent judge (allowed: ${ALLOWED_GRADERS.join(', ')}; use --grader none with --scores none for a no-grade round). No entry written.`);
    process.exit(2);
  }
  // The basis must establish BOTH halves of independence (fresh/separate
  // context AND no production history) — "fresh context" alone is NOT
  // enough (rubric A1). muse-manager is accepted here exactly when its
  // basis proves it is a DIFFERENT instance with no production history.
  checkIndependenceBasis(args.basis, grader);
  if (!['pass', 'fail'].includes(args.gate)) usage('--gate must be pass or fail');
  // D15 scope rules, before any artifact work:
  //  (a) an allowed grader with --scores none is a contradiction — a
  //      grader label IS a grade claim; the no-grade path is --grader
  //      none. (Before D15 this fell through and recorded a no-grade
  //      label under an invented grader.)
  if (!scores) reject(`--grader ${grader} goes with --scores <t,l,c,s>. An allowed grader with --scores none is not a recordable state — use --grader none --scores none for a no-grade round.`);
  //  (b) scores on a failed gate: the judge is spawned only on a green
  //      gate (D8 pre-filter), so a graded record on --gate fail has no
  //      judge behind it by construction.
  if (args.gate === 'fail') reject('a graded record requires --gate pass. A judge is spawned only on a green gate, so scores on a failed gate cannot come from a judge — record the round with --grader none --scores none, or fix the gate first.');
  //  (c) the evidence is DERIVED from the judge artifact (below); a
  //      caller-asserted --evidence on a graded round is the old
  //      self-assertion channel and is refused, not ignored.
  if (args.evidence !== undefined) reject('--evidence is not accepted on a graded record (D15): the recorded evidence is derived from the judge artifact\'s evidence cells, so the record transcribes the judge\'s own words instead of asserting over them.');
  // D13: a --gate pass without both leg artifacts is refused (exit 2).
  const gateArtifacts = validateGateArtifacts(args.project, args);
  const tokensHash = resolveTokensHash(args.project, undefined, args['tokens-hash']);
  // D15: the main judge artifact. The record's scores and evidence are
  // a verified transcription of this file — nothing else.
  const judgeArt = validateJudgeArtifact(args.project, args['judge-report'], {
    flag: 'judge-report', kinds: ['absolute', 'cheap'], round, grader, basis: args.basis,
    pageRel: gateArtifacts.page, tokensHash, notRegraded: notRegraded || [],
    usedShas: usedJudgeShas, others: validatedJudgeArtifacts,
    citedLegs: citedLegsOf(args),
  });
  validatedJudgeArtifacts.push(judgeArt);
  const artScores = judgeArt.parsed.scores;
  for (const axis of ['type', 'layout', 'colour', 'space']) {
    if (artScores[axis] !== scores[axis]) reject(`--scores ${axis} is ${scores[axis]} but the judge artifact records ${artScores[axis]} — the record must transcribe the artifact's score table, not assert over it.`);
  }
  // The derived evidence keeps the old bar per cell (10+ chars naming
  // an observable element) and the old stored shape: the four cells
  // joined with '; ' in the same `evidence` field round-brief.mjs reads.
  for (const cell of judgeArt.parsed.evidenceCells) {
    if (!evidenceNamesObservable(cell)) reject(`the judge artifact's evidence cell "${cell}" does not name an observable element (10+ characters, a named element or a measurement) — evidence that names nothing is not evidence.`);
  }
  const derivedEvidence = judgeArt.parsed.evidenceCells.join('; ');
  // D15: pairwise (P11) — two kind-pairwise artifacts, or no pairwise
  // verdict. The recorded verdict must EQUAL the derived one.
  let pairwiseArtShas = null;
  let pairwiseArtPaths = null;
  if (args['pairwise-reports'] !== undefined && !pairwise) reject('--pairwise-reports is cited without --pairwise — the reports back a verdict, they are not a verdict on their own.');
  if (pairwiseAgrees !== null && !pairwise) reject('--pairwise-agrees needs --pairwise (and its --pairwise-reports) — it qualifies a verdict, it is not one.');
  if (pairwise) {
    const cited = (args['pairwise-reports'] || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (cited.length !== 2) reject('--pairwise requires --pairwise-reports <report-1,report-2> (D15): one report per pairwise judge call, both orders. A pairwise verdict with no artifacts is a self-assertion.');
    const pArts = cited.map((p) => {
      const art = validateJudgeArtifact(args.project, p, {
        flag: 'pairwise-reports', kinds: ['pairwise'], round, grader: null, basis: null,
        pageRel: null, tokensHash, notRegraded: null,
        usedShas: usedJudgeShas, others: validatedJudgeArtifacts,
        citedLegs: citedLegsOf(args),
      });
      validatedJudgeArtifacts.push(art);
      return art;
    });
    // Swap proof: the second call's A/B sets are the first call's B/A
    // sets (by screenshot hash multiset) — the two calls graded the
    // same two versions in swapped order, or they did not run.
    const hashSet = (list) => list.map((s) => s.sha256).sort().join(';');
    if (hashSet(pArts[0].shotsA) !== hashSet(pArts[1].shotsB) || hashSet(pArts[0].shotsB) !== hashSet(pArts[1].shotsA)) {
      reject('--pairwise-reports are not a swapped pair: report 2\'s shots-a / shots-b must be report 1\'s shots-b / shots-a (the same two versions, order swapped). Two reports of the same order are one call cited twice.');
    }
    // Derivation: the version whose shot-hash set equals the current
    // page's set (the main artifact's screenshots) is the challenger;
    // the other is the incumbent. Each report's keep line then derives
    // a verdict; the two must agree, and the flag must equal them.
    const challenger = new Set(judgeArt.shots.map((s) => s.sha256));
    const derivedList = pArts.map((art) => {
      const isChallenger = (list) => list.length === challenger.size && list.every((s) => challenger.has(s.sha256));
      const aIs = isChallenger(art.shotsA);
      const bIs = isChallenger(art.shotsB);
      if (aIs === bIs) reject(`--pairwise-reports file ${art.rel}: exactly one of shots-a / shots-b must be the current page's screenshot set (the challenger) — neither or both matched, so the A/B mapping cannot be derived.`);
      const kept = art.parsed.pairwiseKeep === 'A' ? aIs : bIs;
      return kept ? 'keep-challenger' : 'keep-incumbent';
    });
    // Red-team round (PW-tie): two derivations that DISAGREE derive
    // the verdict `tie` (the P11 rule D15 (5d) states) — recording
    // --pairwise tie for exactly that pair is the transcription, not
    // a contradiction; an AGREEING pair cited as a tie, or a
    // disagreeing pair cited as a keep, is the mismatch.
    const derived = derivedList[0] === derivedList[1] ? derivedList[0] : 'tie';
    if (derived === 'tie' && pairwise !== 'tie') reject(`--pairwise-reports disagree after A/B derivation (${derivedList[0]} vs ${derivedList[1]}) — the pair disagrees, so the derived verdict is a tie by the P11 rule; record --pairwise tie, not ${pairwise}.`);
    if (derived !== 'tie' && pairwise !== derived) reject(`--pairwise is ${pairwise} but the pairwise artifacts derive ${derived} — the record must transcribe the artifacts' verdict.`);
    pairwiseArtShas = pArts.map((a) => a.sha).join(';');
    pairwiseArtPaths = pArts.map((a) => a.rel).join(';');
  }
  // D15: jury (P14) — three kind-jury artifacts behind --jury /
  // --jury-votes, or no jury fields. --jury-mode single forbids the
  // jury fields entirely (the single grade is --scores).
  let juryArtShas = null;
  if (args['judge-reports'] !== undefined && !(jury || juryVotes)) reject('--judge-reports is cited without --jury / --jury-votes — the reports back jury votes, they are not votes on their own.');
  if (juryMode === 'single' && (jury || juryVotes)) reject('--jury-mode single forbids --jury / --jury-votes (D15): a single-judge stop round records its grade as --scores with the absolute judge artifact; there are no jury votes to transcribe.');
  if (jury || juryVotes) {
    if (!jury || !juryVotes || !juryMode || juryMode === 'single') reject('--jury / --jury-votes need --jury-mode <disjoint-3|single-family> and --judge-reports <j1,j2,j3> (D15): three jury artifacts behind the votes, transcribed.');
    const cited = (args['judge-reports'] || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (cited.length !== 3) reject('--jury requires --judge-reports <report-1,report-2,report-3> (D15): one report per juror. Jury votes with no artifacts are self-asserted.');
    const jArts = cited.map((p) => {
      const art = validateJudgeArtifact(args.project, p, {
        flag: 'judge-reports', kinds: ['jury'], round, grader: null, basis: null,
        pageRel: gateArtifacts.page, tokensHash, notRegraded: null,
        usedShas: usedJudgeShas, others: validatedJudgeArtifacts,
        citedLegs: citedLegsOf(args),
      });
      validatedJudgeArtifacts.push(art);
      return art;
    });
    const canonScores = (s) => `${s.type},${s.layout},${s.colour},${s.space}`;
    const artVoteSet = jArts.map((a) => canonScores(a.parsed.scores)).sort();
    const flagVoteSet = juryVotes.map(canonScores).sort();
    if (JSON.stringify(artVoteSet) !== JSON.stringify(flagVoteSet)) reject(`--jury-votes (${flagVoteSet.join(' | ')}) do not match the jury artifacts' score tables (${artVoteSet.join(' | ')}) as a set — the record must transcribe the jurors' reports.`);
    const families = jArts.map((a) => a.header.family);
    if (families.some((f) => !f || f === '-')) reject('--judge-reports: every jury artifact must name its model family in the header (family:) — the jury mode is checked against the families the jurors declared.');
    if (juryMode === 'disjoint-3' && new Set(families).size !== 3) reject(`--jury-mode disjoint-3 needs three DISTINCT juror families; the artifacts declare: ${families.join(', ')}.`);
    if (juryMode === 'single-family' && new Set(families).size !== 1) reject(`--jury-mode single-family needs ONE shared juror family; the artifacts declare: ${families.join(', ')}.`);
    juryArtShas = jArts.map((a) => a.sha).join(';');
  } else if (juryMode && juryMode !== 'single') {
    reject(`--jury-mode ${juryMode} without --jury / --jury-votes records a jury that never voted — cite the votes and their three artifacts, or drop the mode.`);
  }
  // D15: expert scores need their expert artifacts (graded records too).
  const gExpertMotionArt = validateExpert(expertMotion, 'expert-motion-report', 'expert-motion', gateArtifacts.page);
  const gExpertUxArt = validateExpert(expertUx, 'expert-ux-report', 'expert-ux', gateArtifacts.page);
  const rec = {
    kind: 'round', round, grader, independenceBasis: args.basis.trim(),
    scores, grade: 'graded',
    evidence: derivedEvidence, gate: args.gate,
    gateLeg1: gateArtifacts ? gateArtifacts.gateLeg1 : null,
    gateLeg2: gateArtifacts ? gateArtifacts.gateLeg2 : null,
    gateLeg1Sha: gateArtifacts ? gateArtifacts.gateLeg1Sha : null,
    gateLeg2Sha: gateArtifacts ? gateArtifacts.gateLeg2Sha : null,
    gateFindings: args['gate-findings'] || null,
    variant: args.variant || null,
    tokensHash,
    fixClass: args['fix-class'] || null,
    outcome: parseOutcome(args.outcome),
    page: gateArtifacts ? gateArtifacts.page : null,
    trigger, pairwise, pairwiseAgrees, jury, juryMode, juryVotes,
    notRegraded,
    expertMotion: expertMotion.score, expertMotionEvidence: expertMotion.evidence,
    expertUx: expertUx.score, expertUxEvidence: expertUx.evidence,
    judgeReport: judgeArt.rel, judgeReportSha: judgeArt.sha, pageSha: judgeArt.pageSha,
    pairwiseReports: pairwiseArtPaths, pairwiseReportShas: pairwiseArtShas,
    juryReportShas: juryArtShas,
    expertMotionReport: gExpertMotionArt ? gExpertMotionArt.rel : null,
    expertMotionReportSha: gExpertMotionArt ? gExpertMotionArt.sha : null,
    expertUxReport: gExpertUxArt ? gExpertUxArt.rel : null,
    expertUxReportSha: gExpertUxArt ? gExpertUxArt.sha : null,
    notes: args.notes || null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: recorded round ${round} (grader: ${grader}; grade: ${rec.grade}; gate: ${args.gate})`);
} else if (cmd === 'feedback') {
  const round = Number(args.round);
  if (!Number.isInteger(round) || round < 1) usage('--round must be a positive integer');
  if (!args.from || !args.change) usage('feedback needs --from "<human words>" and --change "<token diff>"');
  let scoreAfter = null;
  let grader = null;
  let feedbackJudgeArt = null;
  let feedbackEvidence = null;
  if (args['score-after']) {
    // A post-feedback score IS a grade: only an independent judge may give it.
    grader = (args.grader || '').trim();
    if (FORBIDDEN_GRADERS.includes(grader.toLowerCase())) {
      reject(`--score-after needs an independent grader, not "${grader}". The builder NEVER grades its own work (user direction 2026-11-10).`);
    }
    if (!ALLOWED_GRADERS.includes(grader)) {
      reject(`--score-after requires --grader <${ALLOWED_GRADERS.join('|')}>, got "${grader || '(none)'}".`);
    }
    // Same two-half bar as record: fresh/separate context AND no
    // production history; either half alone is rejected.
    checkIndependenceBasis(args.basis, grader);
    scoreAfter = parseScores(args['score-after']);
    // D15: the regrade needs its own judge artifact (kind regrade) —
    // the round's artifact cannot be re-cited (single-use), and a
    // caller-asserted --evidence is the old self-assertion channel.
    if (args.evidence !== undefined) reject('--evidence is not accepted with --score-after (D15): the recorded evidence is derived from the regrade artifact\'s evidence cells.');
    // Page binding (red-team round N12 — SEVERE): the regrade must
    // grade THE PAGE THE ROUND GRADED, and the round record itself is
    // the authority for which page that was. A graded round record
    // always carries pageSha — the hash of the page actually graded —
    // even when it was recorded without --page (page: null). The old
    // code fell back to whatever page the regrade artifact named in
    // exactly that case, so a regrade of a DIFFERENT page recorded
    // cleanly. The rules now:
    //   - the round's graded record has a pageSha: the artifact's
    //     page-sha256 MUST equal it (checked after validation below),
    //     and a --page passed to feedback must hash to it too;
    //   - the round record also names a page: the artifact must name
    //     that page (the pageRel check, as before);
    //   - the round has a record but NO pageSha (a pre-D15 log line):
    //     --page is REQUIRED and the artifact binds to that page
    //     (path + its current hash, via the validator);
    //   - no round record at all: the pre-existing behaviour (the
    //     artifact's own page, hash-checked against disk).
    // Red-team round 2 (NA4 — SEVERE, anchor poisoning): the anchor
    // record is chosen ONLY from round lines that are genuinely
    // graded AND whose citation verifies on disk right now
    // (isVerifiedGradedRound). The round-1 code anchored on ANY later
    // round line carrying a pageSha — so a hand-appended scoreless
    // line (grader null, scores null, but a pageSha pointing at a
    // DIFFERENT page: a shape the writer never produces, because a
    // no-grade record stores pageSha null) became the anchor, and a
    // regrade of that other page recorded cleanly against the round.
    // Scoreless lines, grader-less lines, and lines whose citation
    // does not verify NEVER anchor. When round records exist but none
    // is a verified graded record, the pre-D15 fallback applies:
    // --page is REQUIRED and the artifact binds to it by path +
    // current hash. When there is no round record at all (NA20), the
    // pre-existing behaviour is retained unchanged: --page anchors
    // when given, else the artifact's own page binds.
    // Red-team round 8 (C4 — the epoch rule): the anchor candidate
    // must ALSO pass leg currency (verifyLegCitationsCurrent). A
    // regrade is a LIVE operation standing on the round's gate
    // evidence now; the canonical leg files rotate with every later
    // gate run, so a graded record whose cited legs no longer match
    // the files on disk has had its gate evidence rotated away, and
    // regrading it refuses — the operator records a fresh round
    // instead. (The grade itself stays verified history through its
    // judge artifact: `best` still crowns the round.) And when a
    // graded-SHAPED record exists for the round (scores + an allowed
    // grader + a pageSha — the writer's graded field shape) but none
    // verifies as an anchor, feedback refuses outright, with or
    // without --page: the --page fallback below exists for rounds
    // with no graded-shaped record at all (pre-D15 lines, scoreless
    // logs), not as a way around a failed verification.
    const fbRows = readLog(args.project);
    const fbRoundRecs = fbRows.filter((r) => r.kind === 'round' && r.round === round);
    const fbGradedRec = [...fbRoundRecs].reverse().find((r) => isVerifiedGradedRound(args.project, r) && verifyLegCitationsCurrent(args.project, r).ok) || null;
    const fbGradedShaped = fbRoundRecs.filter((r) => r.scores && typeof r.scores === 'object'
      && ALLOWED_GRADERS.includes(r.grader)
      && typeof r.pageSha === 'string' && /^[0-9a-f]{64}$/i.test(r.pageSha));
    let feedbackPage = args.page || null;
    if (fbGradedRec && !feedbackPage && fbGradedRec.page) feedbackPage = fbGradedRec.page;
    if (fbGradedRec) {
      if (args.page) {
        const givenSha = sha256File(path.resolve(args.project, args.page));
        if (!givenSha) reject(`--page file does not exist or cannot be read: ${args.page} — the feedback regrade must bind to the page round ${round} graded.`);
        if (givenSha !== fbGradedRec.pageSha) reject(`--page ${args.page} hashes to ${givenSha.slice(0, 12)}… but round ${round}'s record graded a page with page-sha256 ${fbGradedRec.pageSha.slice(0, 12)}…${fbGradedRec.page ? ` (${fbGradedRec.page})` : ''} — the page whose hash differs is ${args.page}; the regrade must grade the page the round graded, not a different page.`);
      }
    } else if (fbGradedShaped.length) {
      reject(`round ${round} has a graded record, but it does not verify as a regrade anchor NOW — its judge citation fails verification, or its cited gate legs no longer match the leg files on disk (a later round rotated the canonical gate legs) — so it never anchors a regrade, with or without --page. Record a fresh round for the page as it now stands, then regrade that round.`);
    } else if (fbRoundRecs.length && !args.page) {
      reject(`round ${round} has round record(s) but none is a graded record whose judge citation verifies on disk (a scoreless line, a grader-less line, or a line whose citation does not verify never anchors a regrade), so the page it graded cannot be anchored from the log — pass --page <the page round ${round} graded> so the regrade artifact can be bound to it by path + current hash.`);
    }
    feedbackJudgeArt = validateJudgeArtifact(args.project, args['judge-report'], {
      flag: 'judge-report', kinds: ['regrade'], round, grader, basis: args.basis,
      pageRel: feedbackPage, tokensHash: resolveTokensHash(args.project, undefined, args['tokens-hash']),
      notRegraded: null,
      usedShas: collectUsedJudgeShas(fbRows), others: [],
      citedLegs: citedLegsOf(args),
    });
    if (fbGradedRec && feedbackJudgeArt.pageSha !== fbGradedRec.pageSha) {
      reject(`--judge-report file ${args['judge-report']} binds to page "${feedbackJudgeArt.header.page}" (page-sha256 ${feedbackJudgeArt.pageSha.slice(0, 12)}…) but round ${round}'s record graded ${fbGradedRec.page ? `page "${fbGradedRec.page}"` : 'a page recorded without --page'} with page-sha256 ${fbGradedRec.pageSha.slice(0, 12)}… — the page whose hash differs is "${feedbackJudgeArt.header.page}"; the regrade artifact must grade the page the round graded, not a different page. Re-prepare the regrade for that page.`);
    }
    for (const axis of ['type', 'layout', 'colour', 'space']) {
      if (feedbackJudgeArt.parsed.scores[axis] !== scoreAfter[axis]) reject(`--score-after ${axis} is ${scoreAfter[axis]} but the regrade artifact records ${feedbackJudgeArt.parsed.scores[axis]} — the record must transcribe the artifact's score table.`);
    }
    for (const cell of feedbackJudgeArt.parsed.evidenceCells) {
      if (!evidenceNamesObservable(cell)) reject(`the regrade artifact's evidence cell "${cell}" does not name an observable element (10+ characters, a named element or a measurement).`);
    }
    feedbackEvidence = feedbackJudgeArt.parsed.evidenceCells.join('; ');
  } else if (args['judge-report'] !== undefined) {
    reject('--judge-report is cited without --score-after — a regrade artifact backs a regrade score, not a bare feedback record.');
  }
  const rec = {
    kind: 'feedback', round, from: args.from, tokenChange: args.change,
    scoreAfter,
    grader: scoreAfter ? grader : null,
    independenceBasis: scoreAfter ? args.basis.trim() : null,
    evidence: scoreAfter ? feedbackEvidence : null,
    fixClass: args['fix-class'] || null,
    judgeReport: feedbackJudgeArt ? feedbackJudgeArt.rel : null,
    judgeReportSha: feedbackJudgeArt ? feedbackJudgeArt.sha : null,
    pageSha: feedbackJudgeArt ? feedbackJudgeArt.pageSha : null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: recorded feedback for round ${round}: "${args.from}" -> ${args.change}${scoreAfter ? ` (re-graded by ${grader}: T${scoreAfter.type}/L${scoreAfter.layout}/C${scoreAfter.colour}/S${scoreAfter.space})` : ''}`);
} else if (cmd === 'lock') {
  // Taste lock (step 1 "commit"): files saved under design/ AND this entry
  // in the run log. Git commit is separate (only if the project is a git
  // repo) — this command is the run-log half of the commit, and it is
  // required even in a git repo (a git commit without this entry is not a
  // taste lock by the workflow's definition).
  if (!args.tokens || !args.refs) usage('lock needs --tokens <path> and --refs "<locked direction>"');
  // P7 lock version (LOOP-1 follow-up — SKILL.md step 1.8 used to say
  // "record the version number in the run log's notes by hand"): the
  // version is a script field now. Default is (existing lock count + 1);
  // --version N records an explicit version. A re-pick creates a NEW
  // version; re-using an existing version is REJECTED (exit 2) — two
  // locks with one version would make the round brief ambiguous about
  // which lock it restates. (Round 7, F1: "existing" is a stored line
  // that VERIFIES — the occupation check below; an unverifiable or
  // stale stored line does not hold its version.)
  const existingLocks = readLog(args.project).filter((r) => r.kind === 'taste-lock');
  // Round 7 (F1): a stored lock line OCCUPIES its version only if
  // it verifies (shared verifyLockLine: the tokens file it names is
  // on disk inside design/, not a symlink, and still hashes to the
  // stored tokensHash). Before round 7 the existence check counted
  // every stored line, so one hand-appended line could squat a
  // version forever — and a genuine lock whose tokens had since
  // moved (the stale line no longer matches its file) blocked its
  // own version against the re-lock that supersedes it. A line
  // that cannot verify does not occupy its version; the check's
  // other semantics (explicit --version only, rejection exit 2,
  // the default of existing-lock-count + 1) are unchanged.
  const occupiedLocks = existingLocks.filter((r) => verifyLockLine(args.project, r).ok);
  let lockVersion;
  if (args.version !== undefined) {
    lockVersion = Number(args.version);
    if (!Number.isInteger(lockVersion) || lockVersion < 1) usage('--version must be a positive integer');
    if (occupiedLocks.some((r) => r.lockVersion === lockVersion)) {
      console.error(`run-log: REJECTED — lock version ${lockVersion} already exists in the run log. A re-pick creates a NEW version (next: ${existingLocks.length + 1}). No entry written.`);
      process.exit(2);
    }
  } else {
    lockVersion = existingLocks.length + 1;
  }
  const rec = {
    kind: 'taste-lock', lockVersion,
    tokens: args.tokens,
    tokensHash: resolveTokensHash(args.project, args.tokens, undefined),
    references: args.refs,
    purpose: args.purpose || null,
    approvedBy: args['approved-by'] || null,
    notes: args.notes || null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: taste locked (version ${lockVersion}) — tokens: ${args.tokens}${rec.tokensHash ? ` (sha256 ${rec.tokensHash.slice(0, 12)}…)` : ' (tokens file not on disk — no hash recorded)'}; refs: ${args.refs}${rec.purpose ? `; purpose: ${rec.purpose}` : ''}${rec.approvedBy ? `; approved-by: ${rec.approvedBy}` : ''}`);
} else if (cmd === 'replan') {
  // Purpose-fail execution path (UX-B council decision 2026-11-10): a
  // purpose failure (grade-time P1–P5 check, or a purpose change
  // mid-loop) is resolved by re-planning the inventory from the
  // revised purpose or re-picking the direction — never by patching
  // the inventory in place, and never by an unenforced plan note. The
  // decision is recorded here in the run log; a re-pick records a NEW
  // taste-lock version via `lock` (this command records the decision
  // only, it does not lock).
  const action = args.action;
  if (!['re-plan', 're-pick'].includes(action)) usage('replan needs --action <re-plan|re-pick>');
  if (!args.purpose || !args.purpose.trim()) usage('replan needs --purpose "<revised purpose from PLAN.md>"');
  const rec = {
    kind: 'purpose-fail', action, purpose: args.purpose.trim(),
    notes: args.notes || null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: purpose fail recorded — action: ${action}; revised purpose: ${rec.purpose}`);
} else if (cmd === 'crosscheck') {
  // Security/compliance cross-check verdict (BUFFET-MODE.md §14,
  // SKILL.md step 3a). The coordinator transcribes the checker's verdict
  // here BEFORE any land is recorded; `land` below refuses to record
  // without a prior clear verdict for the same slice/round.
  // Verdict is DERIVED, never asserted: clear iff severe == 0 AND every
  // warning is fixed-or-waived (warning == waived). A blocked verdict is
  // still recorded — it is the record of the block, and the next
  // cross-check after the fix supersedes it (land reads the LATEST
  // verdict for the slice/round).
  const slice = (args.slice || '').trim();
  const round = args.round !== undefined ? Number(args.round) : null;
  if (!slice && (round === null || !Number.isInteger(round) || round < 1)) usage('crosscheck needs --slice <id> and/or --round N');
  if (round !== null && (!Number.isInteger(round) || round < 1)) usage('--round must be a positive integer');
  const severe = Number(args.severe);
  const warning = Number(args.warning);
  const waived = args.waived !== undefined ? Number(args.waived) : 0;
  if (!Number.isInteger(severe) || severe < 0) usage('--severe must be a non-negative integer');
  if (!Number.isInteger(warning) || warning < 0) usage('--warning must be a non-negative integer');
  if (!Number.isInteger(waived) || waived < 0 || waived > warning) usage('--waived must be a non-negative integer no greater than --warning');
  if (!args.report || !args.report.trim()) usage('crosscheck needs --report <path to the cross-check report>');
  const checker = (args.checker || '').trim();
  if (!ALLOWED_CHECKERS.includes(checker)) {
    console.error(`run-log: REJECTED — checker "${checker}" is not an allowed independent cross-checker (allowed: ${ALLOWED_CHECKERS.join(', ')}). The checker must be independent of the builder AND of the judge for that slice. No entry written.`);
    process.exit(2);
  }
  // Same two-half independence bar as a grader basis (fresh/separate
  // context AND no production history) — a checker that shares the
  // builder's context or history is not independent (synthesis §2 C5:
  // the generator cannot be the validator).
  checkIndependenceBasis(args.basis, checker);
  // D15: the report must exist — before D15 the path was never stat'ed,
  // so a clear verdict could cite a report that was never written.
  validateCrosscheckReport(args.project, args.report.trim());
  const verdict = (severe === 0 && warning === waived) ? 'clear' : 'blocked';
  const rec = {
    kind: 'crosscheck', slice: slice || null, round,
    severe, warning, waived, verdict,
    report: args.report.trim(), checker, independenceBasis: args.basis.trim(),
    notes: args.notes || null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: cross-check recorded for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} — verdict: ${verdict} (SEVERE ${severe}, WARNING ${warning}, waived ${waived}); report: ${rec.report}`);
} else if (cmd === 'land') {
  // Land / ship decision (coordination design §3 / BUFFET-MODE.md §14, SKILL.md step 3a):
  // requires gate green AND a clear cross-check verdict already in the
  // log. A land without a prior clear verdict is REJECTED (exit 2,
  // nothing written) — landing without a cross-check is forbidden,
  // exactly as landing without a gate is (F32). The verdict read is the
  // LATEST cross-check for the slice/round: a blocked verdict after a
  // clear one supersedes it (fix → fresh re-check).
  const slice = (args.slice || '').trim();
  const round = args.round !== undefined ? Number(args.round) : null;
  if (!slice && (round === null || !Number.isInteger(round) || round < 1)) usage('land needs --slice <id> and/or --round N');
  if (round !== null && (!Number.isInteger(round) || round < 1)) usage('--round must be a positive integer');
  if (args.gate !== 'pass') {
    console.error('run-log: REJECTED — land requires --gate pass. A land on a red gate is forbidden (the gate is the first half of the land rule; the cross-check is the second). No entry written.');
    process.exit(2);
  }
  // D13: a --gate pass without both leg artifacts is refused (exit 2) —
  // the land path must not be the bypass around the record refusal.
  const gateArtifacts = validateGateArtifacts(args.project, args);
  const checks = readLog(args.project).filter((r) => r.kind === 'crosscheck'
    && (slice ? r.slice === slice : true)
    && (round !== null ? r.round === round : true));
  const latest = checks[checks.length - 1];
  if (!latest) {
    console.error(`run-log: REJECTED — land for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} has no cross-check verdict in the log. Record it first (run-log.mjs crosscheck ...), then land. No entry written.`);
    process.exit(2);
  }
  // Round 6 (X1): the latest verdict must also VERIFY as a record
  // run-log.mjs could have written (verifyCrosscheckLine: verdict
  // re-derived from the line's own counts, checker on the allowlist,
  // independence basis, cited report existing inside design/). Before
  // round 6 land trusted the stored verdict, so one hand-appended
  // "clear" line over a genuine blocked verdict landed the slice.
  // There is no fallback to an earlier line: the latest line is the
  // verdict of record, and an unverifiable one refuses the land.
  const ccVerify = verifyCrosscheckLine(args.project, latest);
  if (!ccVerify.ok) {
    console.error(`run-log: REJECTED — the latest cross-check record for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} does not verify: ${ccVerify.reasons.join('; ')}. Land acts only on a cross-check record that verifies as written. No entry written.`);
    process.exit(2);
  }
  if (latest.verdict !== 'clear') {
    console.error(`run-log: REJECTED — the latest cross-check verdict for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} is ${latest.verdict.toUpperCase()} (SEVERE ${latest.severe}, WARNING ${latest.warning}, waived ${latest.waived}; report: ${latest.report}). A SEVERE finding blocks the land like a gate FAIL; fix and re-check first. No entry written.`);
    process.exit(2);
  }
  // D15: a land also needs at least one ROUND record for the land's
  // round — graded (artifact-backed, enforced at record time) or an
  // explicit no-grade record (the human-gate path, labelled as such).
  // Before D15, land checked only the gate + cross-check and closed
  // the loop over a build no round had ever recorded. (Slice-binding
  // of round records is a schema gap left open in D15: round records
  // carry no slice field, so the precondition is on the round number,
  // or on any round record when --round is omitted.)
  // Red-team round 2 (NA19): existence is not enough — a round line
  // counts toward the precondition only if it is (a) a verified
  // graded record (isVerifiedGradedRound: scores + allowed grader +
  // pageSha + the shared full verification on disk now), or (b) a
  // genuine no-grade record (isGenuineNoGradeRound: the writer's
  // no-grade field set — grader null, scores null, no grade-coupled
  // fields, a timestamp — AND, since red-team round 3 (B3), both
  // cited gate legs verifying on disk against the stored shas with
  // the verdict matching the line's gate value; a full-shape line
  // citing legs that never existed counted under the round-2 shape
  // check alone). A hand-written minimal line in the no-grade
  // colours (grader null, scores null, nothing else) satisfied the
  // old existence check and must never count.
  // Red-team round 8 (C4 — the epoch rule): a graded record counts
  // only with leg CURRENCY on top of its artifact verification
  // (verifyLegCitationsCurrent) — land is a live operation standing
  // on the round's gate evidence now, and a later round's gate run
  // rotates the canonical leg files, retiring earlier rounds'
  // evidence. (The no-grade half needs no addition: leg currency
  // has been inside isGenuineNoGradeRound since round 3. `best`
  // deliberately does NOT require currency — historical grades
  // verify through their judge artifacts.)
  const roundRecs = readLog(args.project).filter((r) => r.kind === 'round'
    && (round !== null ? r.round === round : true)
    && ((isVerifiedGradedRound(args.project, r) && verifyLegCitationsCurrent(args.project, r).ok) || isGenuineNoGradeRound(args.project, r)));
  if (!roundRecs.length) {
    console.error(`run-log: REJECTED — land for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} has no round record in the log that counts — no verified graded record (judge citation verifying on disk, with its cited gate legs still matching the leg files on disk) and no genuine no-grade record for it. Record the round first (graded with its judge artifact, or an explicit --grader none no-grade record), then land. No entry written.`);
    process.exit(2);
  }
  const rec = {
    kind: 'land', slice: slice || null, round,
    gate: 'pass',
    gateLeg1: gateArtifacts.gateLeg1, gateLeg2: gateArtifacts.gateLeg2,
    gateLeg1Sha: gateArtifacts.gateLeg1Sha, gateLeg2Sha: gateArtifacts.gateLeg2Sha,
    page: gateArtifacts.page,
    crosscheckReport: latest.report,
    notes: args.notes || null,
    at: new Date().toISOString(),
  };
  appendLog(args.project, rec);
  console.log(`run-log: LAND recorded for slice ${slice || '(no slice)'}${round !== null ? ` (round ${round})` : ''} (gate: pass; cross-check: clear; report: ${latest.report})${rec.page ? `; page: ${rec.page}` : ''}`);
} else if (cmd === 'show') {
  const rows = readLog(args.project);
  if (!rows.length) { console.log('run-log: no entries yet.'); process.exit(0); }
  for (const r of rows) {
    if (r.kind === 'round') {
      const s = r.scores ? `T${r.scores.type}/L${r.scores.layout}/C${r.scores.colour}/S${r.scores.space}` : 'no grade';
      const g = r.grader ? `grader: ${r.grader} (${r.independenceBasis})` : `grader: none (${r.grade})`;
      const j = r.jury ? ` | jury: T${r.jury.type}/L${r.jury.layout}/C${r.jury.colour}/S${r.jury.space} (${r.juryMode || 'mode not recorded'})` : '';
      const p = r.pairwise ? ` | pairwise: ${r.pairwise}${r.pairwiseAgrees !== null && r.pairwiseAgrees !== undefined ? ` (agrees with absolute: ${r.pairwiseAgrees ? 'yes' : 'no'})` : ''}` : '';
      const nr = r.notRegraded && r.notRegraded.length ? ` | not re-graded: ${r.notRegraded.join(', ')}` : '';
      const ga = r.gateLeg1 ? ` | gate artifacts: ${r.gateLeg1}${r.gateLeg1Sha ? ` (${r.gateLeg1Sha.slice(0, 12)}…)` : ''}, ${r.gateLeg2 || '?'}${r.gateLeg2Sha ? ` (${r.gateLeg2Sha.slice(0, 12)}…)` : ''}` : '';
      const ja = r.judgeReport ? ` | judge artifact: ${r.judgeReport}${r.judgeReportSha ? ` (${r.judgeReportSha.slice(0, 12)}…)` : ''}` : '';
      const jr = r.juryReportShas ? ` | jury artifacts (sha): ${r.juryReportShas.split(';').map((x) => `${x.slice(0, 12)}…`).join(', ')}` : '';
      const pr = r.pairwiseReportShas ? ` | pairwise artifacts (sha): ${r.pairwiseReportShas.split(';').map((x) => `${x.slice(0, 12)}…`).join(', ')}` : '';
      console.log(`round ${r.round} | ${g} | ${s} | grade: ${r.grade} | gate: ${r.gate}${ga}${ja}${jr}${pr}${r.variant ? ` | variant: ${r.variant}` : ''}${r.tokensHash ? ` | tokens: ${r.tokensHash.slice(0, 12)}…` : ''}${r.fixClass ? ` | fix-class: ${r.fixClass}` : ''}${r.outcome ? ` | outcome: ${r.outcome}` : ''}${r.trigger ? ` | trigger: ${r.trigger}` : ''}${p}${j}${nr}${r.page ? ` | page: ${r.page}` : ''}${r.notes ? ` | ${r.notes}` : ''}`);
      if (r.gateFindings) console.log(`  gate findings: ${r.gateFindings}`);
      if (r.evidence) console.log(`  evidence: ${r.evidence}`);
      if (r.expertMotion !== null && r.expertMotion !== undefined) console.log(`  Motion: ${r.expertMotion} (motion-expert) — ${r.expertMotionEvidence || ''}${r.expertMotionReport ? ` [artifact: ${r.expertMotionReport}${r.expertMotionReportSha ? ` (${r.expertMotionReportSha.slice(0, 12)}…)` : ''}]` : ''}`);
      if (r.expertUx !== null && r.expertUx !== undefined) console.log(`  UX: ${r.expertUx} (ux-expert) — ${r.expertUxEvidence || ''}${r.expertUxReport ? ` [artifact: ${r.expertUxReport}${r.expertUxReportSha ? ` (${r.expertUxReportSha.slice(0, 12)}…)` : ''}]` : ''}`);
    } else if (r.kind === 'feedback') {
      console.log(`feedback (round ${r.round}): "${r.from}" -> ${r.tokenChange}${r.scoreAfter ? ` | after: T${r.scoreAfter.type}/L${r.scoreAfter.layout}/C${r.scoreAfter.colour}/S${r.scoreAfter.space} (grader: ${r.grader || 'MISSING'})` : ''}${r.judgeReport ? ` | judge artifact: ${r.judgeReport}${r.judgeReportSha ? ` (${r.judgeReportSha.slice(0, 12)}…)` : ''}` : ''}`);
      if (r.scoreAfter && r.evidence) console.log(`  evidence: ${r.evidence}`);
    } else if (r.kind === 'variant-pick') {
      console.log(`variant pick: "${r.variant}"${r.note ? ` — ${r.note}` : ''}`);
    } else if (r.kind === 'taste-lock') {
      console.log(`taste lock v${r.lockVersion ?? '?'}: tokens: ${r.tokens}${r.tokensHash ? ` (sha256 ${r.tokensHash.slice(0, 12)}…)` : ''}; refs: ${r.references}${r.purpose ? `; purpose: ${r.purpose}` : ''}${r.approvedBy ? `; approved-by: ${r.approvedBy}` : ''}${r.notes ? `; notes: ${r.notes}` : ''} (${r.at})`);
    } else if (r.kind === 'purpose-fail') {
      console.log(`purpose fail: action: ${r.action}; revised purpose: ${r.purpose}${r.notes ? `; notes: ${r.notes}` : ''} (${r.at})`);
    } else if (r.kind === 'crosscheck') {
      console.log(`cross-check (slice ${r.slice || '—'}${r.round !== null && r.round !== undefined ? `, round ${r.round}` : ''}): verdict: ${r.verdict} (SEVERE ${r.severe}, WARNING ${r.warning}, waived ${r.waived}) | checker: ${r.checker} (${r.independenceBasis}) | report: ${r.report} (${r.at})`);
    } else if (r.kind === 'land') {
      const ga = r.gateLeg1 ? ` | gate artifacts: ${r.gateLeg1}${r.gateLeg1Sha ? ` (${r.gateLeg1Sha.slice(0, 12)}…)` : ''}, ${r.gateLeg2 || '?'}${r.gateLeg2Sha ? ` (${r.gateLeg2Sha.slice(0, 12)}…)` : ''}` : '';
      console.log(`LAND (slice ${r.slice || '—'}${r.round !== null && r.round !== undefined ? `, round ${r.round}` : ''}): gate: ${r.gate}${ga} | cross-check: clear | report: ${r.crosscheckReport}${r.page ? ` | page: ${r.page}` : ''} (${r.at})`);
    } else if (r.kind === 'dictionary-overwrite') {
      console.log(`dictionary overwrite: "${r.word}" — was: ${r.previousChange} — now: ${r.newChange} (${r.at})`);
    } else {
      console.log(JSON.stringify(r));
    }
  }
} else if (cmd === 'brief') {
  // P7 (council-C form): the brief command assembles the minimal round
  // brief from this log + the locked files, via round-brief.mjs. The
  // generator is the authority; this command is the single entry point
  // the skill cites, so the orchestrator never has to remember which
  // script builds the brief.
  const { buildBrief } = await import('./round-brief.mjs');
  const round = args.round !== undefined ? Number(args.round) : undefined;
  if (round !== undefined && (!Number.isInteger(round) || round < 1)) usage('--round must be a positive integer');
  let brief;
  try {
    brief = buildBrief(args.project, {
      round,
      page: args.page,
      allowMissing: args['allow-missing'] === true,
    });
  } catch (e) {
    console.error(`run-log: brief failed — ${e.message}`);
    process.exit(1);
  }
  if (args.out) {
    fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
    fs.writeFileSync(args.out, brief + '\n');
    console.log(`run-log: round brief written to ${args.out}`);
  } else {
    console.log(brief);
  }
} else if (cmd === 'best') {
  // Effective scores: the stop-round jury median, when recorded, is the
  // round's score for keep/discard purposes (P14 replaces the single
  // grade on the stop round); otherwise the absolute scores.
  // D15: best-version-kept must not crown a fabrication — a round on a
  // failed gate, and a graded round with no judge artifact behind it
  // (a pre-D15 self-asserted record, or a hand-appended log line), are
  // excluded. A jury round's artifact proof is its juryReportShas; an
  // absolute round's is its judgeReportSha.
  // Red-team round (C3/C4 + the fake-citation case): presence is not
  // proof on the READ path either. A crownable round must carry a
  // non-null grader, and its judgeReport citation must VERIFY the
  // same way record verified it: the cited file exists inside the
  // project and hashes to the stored judgeReportSha. A scored line
  // with grader null/absent, or citing a nonexistent file or an
  // invented hash, is skipped like an artifact-less one.
  // Red-team round 2 (C3/NA1/NA2/NA3): hash equality is not proof
  // either — the cited artifact must also PARSE as the line's own
  // report (well-formed, header round == the line's round, kind
  // absolute/cheap, parsed score table == the line's scores), so a
  // line citing ANOTHER round's real artifact (C3) is skipped. The
  // gate must be exactly "pass" — a line with NO gate key (NA3)
  // passed the old !== 'fail' test. A jury round must additionally
  // produce its three juror artifacts at the conventional paths,
  // each hashing to the corresponding juryReportShas entry (which
  // must be exactly three 64-hex values) and parsing with the line's
  // round — a jury round whose juror files were deleted (NA1) or
  // whose shas are not hashes (NA2) is skipped, never crowned. Any
  // failure skips the line; nothing here may throw.
  // Red-team round 3: best no longer keeps its own weaker copies of
  // those checks — the round-2 jury check that lived here verified
  // juror hashes and header rounds but never the votes, the median,
  // or the families (B2: an edited line was crowned on edited jury
  // numbers), and its hash check followed symlinks (B7). Crowning
  // now routes through the ONE shared verifier every read path uses:
  // isVerifiedGradedRound (verifyGradedLine + verifyJuryLine).
  const effScores = (r) => r.jury || r.scores;
  const rounds = readLog(args.project).filter((r) => r.kind === 'round' && ALLOWED_GRADERS.includes(r.grader) && effScores(r) && r.gate === 'pass' && isVerifiedGradedRound(args.project, r));
  if (!rounds.length) { console.log('run-log: no graded rounds yet.'); process.exit(0); }
  const total = (s) => s.type + s.layout + s.colour + s.space;
  const best = rounds.reduce((a, b) => (total(effScores(b)) > total(effScores(a)) ? b : a));
  const bs = effScores(best);
  console.log(`best: round ${best.round} (grader: ${best.grader}) — T${bs.type}/L${bs.layout}/C${bs.colour}/S${bs.space}, total ${total(bs)}/20, gate: ${best.gate}${best.jury ? ' (jury median)' : ''}`);
} else {
  usage(`unknown command "${cmd || ''}" (record | feedback | lock | replan | crosscheck | land | brief | show | best)`);
}
