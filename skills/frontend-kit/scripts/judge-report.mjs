#!/usr/bin/env node
// judge-report.mjs — the judge-artifact producer for the frontend-kit loop
// (D15, GAP-13 — the self-grading escape hardening).
//
// THE DEFECT THIS CLOSES: before D15, `run-log.mjs record` accepted a
// graded round on the caller's mere claim — `--grader judge-subagent
// --basis "fresh context, no production history" --scores 4,4,4,4
// --evidence "..."` — with NO artifact proving a judge ever ran. Three
// Claude probes escaped grading exactly this way (fabricated scores, an
// invented grader, a self-grade recorded as a judge grade). D13 closed
// the same hole for gate passes with required leg artifacts; D15 closes
// it for grades with a required JUDGE ARTIFACT: a report file the judge
// writes into the project, at `design/judge/round-<n>*.md`, whose scores,
// evidence, grader, basis and build binding `run-log.mjs` PARSES and
// cross-checks before it records anything (see validateJudgeArtifact in
// run-log.mjs). A score with no artifact is a self-assertion, not a
// record — refused, exit 2, nothing written.
//
// PRODUCER SPLIT (who writes what — the authorship rule is the point):
//   1. The ORCHESTRATOR runs this script's `prepare` BEFORE spawning the
//      judge. prepare computes everything the judge must not assert:
//      the sha256 of the built page, of design/tokens.css, and of the
//      round's screenshot set; it DERIVES the `gate: green` bit by
//      re-validating the two canonical gate-leg artifacts against the
//      page (the same marker + freshness checks run-log.mjs applies at
//      record time) and the `cross-check: clear` bit from the latest
//      crosscheck record for the round in design/run-log.jsonl; and it
//      REFUSES (exit 2, no file written) when either bit cannot be
//      verified. It writes a SKELETON report: the stamped header (with
//      `basis:` empty) and a body whose first line is a PENDING marker
//      and whose score cells are `?`. prepare REFUSES to overwrite an
//      existing report file — one report file is one judge call.
//   2. The JUDGE (a fresh frontend-judge sub-agent, or an expert for the
//      expert kinds) fills ONLY its own fields, in the file itself: the
//      `basis:` header line, the four evidence cells, the four score
//      cells, the Fix order line, and the optional Pairwise / Motion /
//      UX blocks its kind calls for — and returns the same body as its
//      reply text. Transcribing a judge's chat reply into the file is
//      FORBIDDEN: the file is the judge's own writing, or there is no
//      grade. A judge that cannot write files in its host returns the
//      frontend-judge no-grade refusal line and gives no scores.
//   3. `run-log.mjs record / feedback` validates the filled report
//      (containment, header grammar, hash binding to the page / tokens /
//      screenshots on disk NOW, parsed-score transcription, freshness,
//      single-use) and only then records the grade.
//
// There is deliberately NO `seal` subcommand: a seal step run by the
// orchestrator after the judge writes would be an orchestrator stamp on
// judge content — the split above keeps every byte of the body the
// judge's.
//
// THE FORMAT (parsed by parseJudgeReport below; run-log.mjs imports the
// same parser — one grammar, two readers, no duplicate):
//   line 1: exactly `frontend-judge-report v1`
//   then a strict header between `---` fences: fixed keys in fixed
//   order, each exactly once — round, kind, grader, basis, family,
//   gate, cross-check, brief-type, mode, page, page-sha256,
//   tokens-sha256, screenshots, shots-a, shots-b, locked-refs,
//   not-regraded, stamped. `-` is the empty value for the optional keys
//   (family, shots-a, shots-b, locked-refs, not-regraded). screenshots
//   is a comma-separated `path=sha256:<hex>` list (pairwise reports use
//   shots-a / shots-b for the two versions instead, screenshots `-`).
//   then the body: the frontend-judge skill's output verbatim — the
//   `Round N — grader: <label> (<basis>)` line, the score table in axis
//   order Type/Layout/Colour/Space (evidence cells contain no `|` and
//   no newline), `Gate: green`, `Cross-check: clear`, the Fix order
//   line, and the kind's blocks. Pairwise bodies carry NO score table
//   (defect lists + one `Pairwise: keep <A|B> — <evidence>` line);
//   expert bodies carry one `Motion: <1-5> (motion-expert) — <evidence>`
//   or `UX: <1-5> (ux-expert) — <evidence>` line.
//
// RESIDUAL, stated openly (D13 style): a builder can still AUTHOR a
// judge-shaped artifact from scratch — nothing in a dependency-free
// Node script on the builder's own machine can prove which agent
// instance wrote a file. The mechanism's standard is narrower and is
// met: self-grading must require deliberate, on-disk,
// internally-consistent forgery — bound by hash to the exact page,
// tokens and screenshots graded, single-use in the log — that a QC
// re-grade or an artifact audit can contradict. Signing judge output
// is out of scope, exactly as signing gate output was under D13.
//
// READ-PATH VERIFICATION LIVES HERE TOO (D15 red-team round 4): this
// module also hosts the ONE implementation of the read-path grade
// verifiers (verifyGradedLine / verifyJuryLine / verifyFeedbackLine /
// verifyExpertCitations / verifyPairwiseLine / verifyCrosscheckLine /
// isVerifiedGradedRound / isGenuineNoGradeRound / isJuryRoundLine) and of the independence-
// basis check (checkIndependenceBasis). It is the shared home because
// it is import-safe (the CLI below runs only when invoked directly);
// run-log.mjs is not (its CLI runs at top level), so run-log.mjs
// imports these functions for its read paths (best, land's
// precondition, feedback's anchor) and for the record-time basis
// check, and gate/runlog-check.mjs imports the SAME functions for
// its with-project-root citation verification. Round 3 unified the
// verifier inside run-log.mjs but left runlog-check.mjs holding
// private re-implementations of it, and round 4 proved the copies
// had drifted (F1–F7): the checker accepted lines the verifier
// refuses, and neither copy checked juror distinctness, juror bases,
// expert citations, or the line's own independenceBasis /
// tokensHash transcription fields. There is now exactly one
// verifier: a check that is not in this file does not exist on any
// read path, and a check that is in this file applies on all of
// them. See the READ-PATH VERIFICATION banner below.
//
// Usage:
//   node judge-report.mjs --project <dir> prepare --round N
//     --kind <absolute|cheap|pairwise|jury|regrade|expert-motion|expert-ux>
//     --grader <judge-subagent|muse-manager|other-model>
//     [--index <1|2|3>]            # pairwise (1|2) and jury (1|2|3)
//     [--family <model family>]    # jury kind: the juror's model family
//     --brief-type <landing|dashboard/app|redesign>
//     --mode <full|cheap>
//     --page <built.html>          # project-relative, inside design/
//     [--manifest <crop manifest.json>]   # cheap mode: shot set source
//     [--shots <a.png,b.png,...>]         # explicit shot set (either mode)
//     [--shots-a <...>] [--shots-b <...>] # pairwise: the two versions
//     [--locked-refs "<ref list>"] [--not-regraded "<#section,...>"]
//     [--out <path>]               # default: the kind's canonical path
//
// Exit codes: 0 = skeleton written; 1 = usage error; 2 = refused
// (nothing written) — the page, the gate bits, the cross-check bit, a
// screenshot, or the no-overwrite rule failed verification.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const JUDGE_REPORT_MAGIC = 'frontend-judge-report v1';
export const JUDGE_KINDS = ['absolute', 'cheap', 'pairwise', 'jury', 'regrade', 'expert-motion', 'expert-ux'];
export const JUDGE_HEADER_KEYS = [
  'round', 'kind', 'grader', 'basis', 'family', 'gate', 'cross-check',
  'brief-type', 'mode', 'page', 'page-sha256', 'tokens-sha256',
  'screenshots', 'shots-a', 'shots-b', 'locked-refs', 'not-regraded',
  'stamped',
];
export const JUDGE_AXES = ['Type', 'Layout', 'Colour', 'Space'];
// The grader labels a grade may carry (the writer's allowlist —
// run-log.mjs keeps its own copy for its record-time messages; this
// one serves prepare below and the read-path verifiers).
export const ALLOWED_GRADERS = ['judge-subagent', 'muse-manager', 'other-model'];
// The checker labels a crosscheck record may carry (the writer's
// allowlist — run-log.mjs keeps its own copy for its record-time
// messages, the same arrangement as ALLOWED_GRADERS above; this one
// serves the read-path crosscheck verifier, verifyCrosscheckLine).
export const ALLOWED_CHECKERS = ['security-expert', 'crosscheck-subagent', 'crosscheck-team'];
// The judge skill's two no-grade refusal lines (frontend-judge SKILL.md,
// "Output format"): a report carrying either is a refusal, not a grade.
// Compared after stripInvisible, like every verdict line in this kit.
export const JUDGE_VOID_LINES = [
  'Not an independent judge in this context; grade is gate green, vision not available.',
  'No green-gate bit received; not spawned on a green gate — no grade.',
];

// stripInvisible: the same canonicalisation run-log.mjs applies to gate
// verdict lines (fix rounds 5–6) — NFD-normalise, then delete every
// invisible character (\s White_Space, \p{C} controls/formats, \p{M}
// marks, U+FFFD, the F7 blank Lo/So denylist). A copy lives here
// because this file must run standalone; the two copies must change
// together (the same maintenance hazard runlog-check.mjs documents for
// its duplicated secret pattern). Substitution (a stripped character
// REPLACING a letter) is NOT recovered — the F8 boundary, inherited.
export const stripInvisible = (line) => line.normalize('NFD').replace(/[\s\p{C}\p{M}\uFFFD\u115F\u1160\u2800\u303F\u3164\uFFA0\u{13441}\u{13442}]/gu, '');

const sha256Bytes = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
export const sha256File = (file) => {
  try { return sha256Bytes(fs.readFileSync(file)); } catch { return null; }
};

// Parse a `path=sha256:<hex>` comma-separated shot list. Returns
// [{ path, sha256 }] or null when the value is malformed.
export function parseShotList(value) {
  if (!value || value === '-') return [];
  const out = [];
  for (const entry of value.split(',')) {
    const m = entry.trim().match(/^(.+)=sha256:([0-9a-f]{64})$/);
    if (!m) return null;
    out.push({ path: m[1].trim(), sha256: m[2] });
  }
  return out;
}

// Parse a judge report's text into { header, scores, evidence, fixOrder,
// pairwiseKeep, pairwiseEvidence, expertScore, expertEvidence, problems }.
// `problems` is a list of grammar violations (empty = well-formed); the
// caller (run-log.mjs) turns any problem into a rejection, and also
// checks the cross-field equalities this parser cannot (hashes on disk,
// flag equality, single-use). Body score cells of `?` (an unfilled
// skeleton) are a problem here, so a skeleton can never record.
export function parseJudgeReport(text) {
  const problems = [];
  const lines = text.split('\n');
  if (!lines.length || stripInvisible(lines[0]) !== stripInvisible(JUDGE_REPORT_MAGIC)) {
    problems.push(`line 1 is not the magic line "${JUDGE_REPORT_MAGIC}"`);
    return { header: null, problems };
  }
  // Void / refusal lines anywhere: a refusal is not a grade, however the
  // rest of the file is shaped.
  for (const line of lines) {
    const stripped = stripInvisible(line);
    for (const voidLine of JUDGE_VOID_LINES) {
      if (stripped === stripInvisible(voidLine)) problems.push(`the report carries a judge refusal line ("${voidLine}") — a refusal is not a grade`);
    }
    if (stripped.startsWith('PENDING')) problems.push('the report still carries its PENDING skeleton line — the judge has not filled it in');
  }
  // Strict header: `---` fence, fixed keys in fixed order, each once.
  if (lines[1] !== '---') {
    problems.push('line 2 is not the header opening fence "---"');
    return { header: null, problems };
  }
  const header = {};
  let i = 2;
  for (const key of JUDGE_HEADER_KEYS) {
    const line = lines[i];
    if (line === undefined || !line.startsWith(`${key}:`)) {
      problems.push(`header key "${key}" is missing or out of order (fixed key order is part of the format)`);
      return { header: null, problems };
    }
    header[key] = line.slice(key.length + 1).trim();
    i++;
  }
  if (lines[i] !== '---') {
    problems.push('the header closing fence "---" is missing after the last header key');
    return { header: null, problems };
  }
  const body = lines.slice(i + 1).join('\n');
  const bodyLines = body.split('\n');
  const out = { header, body, problems };

  // Header field shapes.
  if (!/^\d+$/.test(header.round)) problems.push(`header round "${header.round}" is not an integer`);
  if (!JUDGE_KINDS.includes(header.kind)) problems.push(`header kind "${header.kind}" is not one of ${JUDGE_KINDS.join(' | ')}`);
  if (header.gate !== 'green') problems.push(`header gate is "${header.gate}", not "green" — a judge is only spawned on a green gate`);
  if (header['cross-check'] !== 'clear') problems.push(`header cross-check is "${header['cross-check']}", not "clear" — a judge is only spawned on a clear cross-check`);
  if (!/^[0-9a-f]{64}$/.test(header['page-sha256'])) problems.push('header page-sha256 is not a 64-hex sha256');
  if (!/^[0-9a-f]{64}$/.test(header['tokens-sha256'])) problems.push('header tokens-sha256 is not a 64-hex sha256');
  for (const field of ['screenshots', 'shots-a', 'shots-b']) {
    if (parseShotList(header[field]) === null) problems.push(`header ${field} is not a well-formed path=sha256:<hex> list`);
  }

  const scored = ['absolute', 'cheap', 'jury', 'regrade'].includes(header.kind);
  if (scored) {
    // The judge skill's first body line: `Round N — grader: <label> (<basis>)`.
    // Found on the raw line; the grader TOKEN is compared after
    // stripInvisible (a token carries no spaces, so the verdict-line
    // canonicalisation is safe on it) — an invisible character inserted
    // inside the token does not split the judge's identity.
    const roundLine = bodyLines.find((l) => l.startsWith('Round '));
    if (!roundLine) {
      problems.push('the body has no "Round N — grader: ..." line (the judge output format)');
    } else {
      const m = roundLine.match(/^Round (\d+) — grader: (\S+) \((.*)\)\s*$/);
      if (!m) problems.push(`the body's Round line is malformed: "${roundLine}"`);
      else {
        out.bodyRound = Number(m[1]);
        out.bodyGrader = stripInvisible(m[2]);
        out.bodyBasis = m[3];
      }
    }
    // Score table: one row per axis, in axis order, `| Axis | evidence | score |`.
    const rows = [];
    for (const line of bodyLines) {
      const t = line.trim();
      if (!t.startsWith('|')) continue;
      const cells = t.split('|').slice(1, -1).map((c) => c.trim());
      if (cells.length !== 3) continue;
      if (JUDGE_AXES.includes(cells[0])) rows.push({ axis: cells[0], evidence: cells[1], score: cells[2] });
    }
    if (rows.length !== 4 || rows.some((r, idx) => r.axis !== JUDGE_AXES[idx])) {
      problems.push('the score table does not carry exactly the four axes in order (Type, Layout, Colour, Space)');
    } else {
      const scores = {};
      const evidence = [];
      for (const r of rows) {
        if (!/^[1-5]$/.test(r.score)) problems.push(`the ${r.axis} score cell is "${r.score}", not an integer 1-5 (an unfilled "?" cell is not a score)`);
        else scores[r.axis.toLowerCase()] = Number(r.score);
        if (!r.evidence || r.evidence === '?') problems.push(`the ${r.axis} evidence cell is empty or unfilled`);
        evidence.push(r.evidence);
      }
      if (Object.keys(scores).length === 4) out.scores = scores;
      out.evidenceCells = evidence;
    }
    if (!bodyLines.some((l) => stripInvisible(l) === stripInvisible('Gate: green'))) problems.push('the body has no "Gate: green" line');
    if (!bodyLines.some((l) => stripInvisible(l) === stripInvisible('Cross-check: clear'))) problems.push('the body has no "Cross-check: clear" line');
    const fix = bodyLines.find((l) => l.startsWith('Fix order:'));
    if (!fix || !fix.slice('Fix order:'.length).trim() || fix.slice('Fix order:'.length).trim() === '?') problems.push('the body has no filled "Fix order:" line');
    else out.fixOrder = fix.slice('Fix order:'.length).trim();
  }
  if (header.kind === 'pairwise') {
    if (bodyLines.some((l) => l.trim().startsWith('|') && JUDGE_AXES.includes(l.trim().split('|')[1]?.trim()))) {
      problems.push('a pairwise report carries no score table (P11: the verdict feeds keep/discard only)');
    }
    const keep = bodyLines.map((l) => l.match(/^Pairwise: keep (A|B) — (.+)$/)).find(Boolean);
    if (!keep) problems.push('the body has no "Pairwise: keep <A|B> — <evidence>" verdict line');
    else { out.pairwiseKeep = keep[1]; out.pairwiseEvidence = keep[2].trim(); }
    if (!bodyLines.some((l) => stripInvisible(l) === stripInvisible('Gate: green'))) problems.push('the body has no "Gate: green" line');
    if (!bodyLines.some((l) => stripInvisible(l) === stripInvisible('Cross-check: clear'))) problems.push('the body has no "Cross-check: clear" line');
  }
  if (header.kind === 'expert-motion' || header.kind === 'expert-ux') {
    const domain = header.kind === 'expert-motion' ? 'Motion' : 'UX';
    const label = header.kind === 'expert-motion' ? 'motion-expert' : 'ux-expert';
    const re = new RegExp(`^${domain}: ([1-5]) \\(${label}\\) — (.+)$`);
    const hit = bodyLines.map((l) => l.match(re)).find(Boolean);
    if (!hit) problems.push(`the body has no "${domain}: <1-5> (${label}) — <evidence>" line`);
    else { out.expertScore = Number(hit[1]); out.expertEvidence = hit[2].trim(); }
  }
  return out;
}

// ---------------------------------------------------------------------
// READ-PATH VERIFICATION (shared — D15 red-team round 4)
//
// Everything from here to the prepare CLI is the ONE implementation
// of read-path grade verification, imported by run-log.mjs (best,
// land's precondition, feedback's anchor) and by
// gate/runlog-check.mjs (its with-project-root citation rule).
// Rounds 1–2 hardened the read paths call-site by call-site; round 3
// unified them inside run-log.mjs but left runlog-check.mjs with
// private re-implementations (citationParseProblem /
// juryParseProblem); round 4 proved the drift between the copies
// (F1–F7) — the checker accepted a self-confessed basis artifact and
// a body Round line naming a different grader, and NEITHER copy
// verified juror file distinctness, juror independence bases, expert
// citations, or the line's own independenceBasis / tokensHash
// transcription fields. The fix is the relocation itself: the
// verifiers live here, with the parser, because this module is
// import-safe and run-log.mjs is not. runlog-check.mjs deletes its
// copies and calls these. No consumer keeps a weaker private check.
// Round 6 closes the channel the earlier field coverage never
// opened: the CROSSCHECK line itself. A stored crosscheck verdict
// was trusted by every consumer of it (land, prepare's cross-check
// bit, and — by omission — runlog-check, which never looked at
// crosscheck lines at all), so one hand-appended "clear" line
// overrode a genuine blocked verdict everywhere.
// verifyCrosscheckLine below is the one verifier for that channel,
// called by all three consumers. The same round binds the fields
// the field coverage still missed: a graded line's own cited gate
// legs verify on disk (X2 — round 8 moved that leg-currency check
// OUT of the universal grade verification into
// verifyLegCitationsCurrent, required only by the live-operation
// consumers; see its comment), juror and
// expert artifacts bind the line's tokensHash (X3/X4), and a
// graded line's notRegraded transcribes its artifact's
// not-regraded header set (X5).
// Every function below is total: it returns { ok, reasons } (or a
// boolean), never throws, never exits.
// ---------------------------------------------------------------------

// The independence basis, shared by the record-time check and the
// read paths. The basis must establish BOTH halves: (1) fresh /
// separate context, or a different agent instance; AND (2) no
// production history of the build. Either half alone is not
// independence — "fresh context" alone does not change the weights
// (rubric A1), and "no production history" alone does not help if
// the judge shares the builder's context. The basis also must not
// merely restate the grader label.
export function basisRestatesGrader(basis, grader) {
  const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '');
  if (norm(basis) === norm(grader)) return true;
  // Remove every occurrence of the grader label (any separator spelling)
  // and require >= 10 characters of other substance to remain.
  const labelPattern = grader.replace(/-/g, '[-_ ]?');
  const stripped = basis
    .replace(new RegExp(labelPattern, 'gi'), '')
    .replace(/[^A-Za-z0-9]+/g, ' ')
    .trim();
  return stripped.length < 10;
}

const FRESH_SIGNALS = [
  /fresh context/,
  /separate context/,
  /new context/,
  /fresh sub-?agent/,
  /no shared context/,
  /different agent/,
  /different model/,
  /separate agent/,
  /independent agent/,
  /different instance/,
  /separate instance/,
  /trained separately/,
  /separately trained/,
];
const NO_HISTORY_SIGNALS = [
  /no production history/,
  /no history of (this|the) build/,
  /never (shown|seen).*?(draft|build)/,
  /not involved in.*build/,
  /no prior involvement/,
];

export function basisEstablishesIndependence(basis) {
  const b = basis.toLowerCase();
  const fresh = FRESH_SIGNALS.some((re) => re.test(b));
  const noHistory = NO_HISTORY_SIGNALS.some((re) => re.test(b));
  return { fresh, noHistory, ok: fresh && noHistory };
}

// The pure basis check: returns the refusal message, or null when
// the basis establishes independence. checkIndependenceBasis is the
// exiting form — the CALLER supplies its own fail (run-log.mjs
// passes its reject, which prints "run-log: REJECTED — ..." and
// exits 2), so the record-time messages stay byte-identical while
// the check itself lives exactly once, here. The read paths use the
// non-exiting halves directly (basisEstablishesIndependence +
// basisRestatesGrader): a read path must not exit the process.
export function independenceBasisProblem(basis, grader) {
  if (!basis || typeof basis !== 'string' || basis.trim().length < 10) {
    return '--basis must state why this judge counts as independent (10+ characters).';
  }
  if (basisRestatesGrader(basis.trim(), grader)) {
    return '--basis must not merely restate the grader name: state the independence basis (e.g. "fresh context, no production history").';
  }
  const { fresh, noHistory } = basisEstablishesIndependence(basis.trim());
  if (!fresh || !noHistory) {
    const missing = [!fresh ? 'fresh/separate context (or a different agent instance)' : null, !noHistory ? 'no production history of the build' : null].filter(Boolean).join(' AND ');
    return `--basis must establish BOTH halves of independence — missing: ${missing}. "Fresh context" alone is NOT enough (rubric A1). Example: "fresh context, no production history".`;
  }
  return null;
}

export function checkIndependenceBasis(basis, grader, fail) {
  const problem = independenceBasisProblem(basis, grader);
  if (problem) fail(problem);
}

// The non-exiting basis test the read paths apply to an artifact's
// own header basis (the halves of independenceBasisProblem that do
// not need the caller's flags): a stored basis long enough not to be
// a restatement, establishing BOTH halves.
function headerBasisEstablishesIndependence(header) {
  const basisText = typeof header.basis === 'string' ? header.basis.trim() : '';
  return Boolean(basisText) && basisText.length >= 10
    && !basisRestatesGrader(basisText, header.grader)
    && basisEstablishesIndependence(basisText).ok;
}

const designContext = (project) => {
  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  const designDir = path.resolve(project, 'design');
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { designReal = path.join(projectReal, 'design'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  return { projectReal, designDir, designReal, inside };
};

// One cited artifact file, verified on read: project-relative (an
// absolute path is not a citation), not a symlink (lstat), a
// non-empty regular file, resolving inside <project>/design/, and
// hashing to the stored sha. Appends reasons; returns the real path
// when the file is present and contained (hash mismatch still
// returns it — the caller decides), or null when there is nothing
// sound to read.
function verifyCitedFile(project, ctx, rel, storedSha, label) {
  const reasons = [];
  if (path.isAbsolute(rel)) {
    reasons.push(`the cited ${label} ${rel} is an absolute path — citations are project-relative, inside design/`);
    return { reasons, real: null };
  }
  const resolved = path.resolve(project, rel);
  let lstat = null;
  try { lstat = fs.lstatSync(resolved); } catch { reasons.push(`the cited ${label} ${rel} does not exist or cannot be read`); }
  if (!lstat) return { reasons, real: null };
  if (lstat.isSymbolicLink()) {
    reasons.push(`the cited ${label} ${rel} is a symlink — a citation must name a real file, not a link`);
    return { reasons, real: null };
  }
  let stat = null;
  try { stat = fs.statSync(resolved); } catch { stat = null; }
  if (!stat || !stat.isFile() || stat.size === 0) {
    reasons.push(`the cited ${label} ${rel} is empty or not a file`);
    return { reasons, real: null };
  }
  let real = null;
  try { real = fs.realpathSync(resolved); } catch { reasons.push(`the cited ${label} ${rel} cannot be resolved`); }
  if (!real) return { reasons, real: null };
  if (!ctx.inside(real, ctx.designReal)) {
    reasons.push(`the cited ${label} ${rel} resolves outside <project>/design/ (real path ${real})`);
    return { reasons, real: null };
  }
  const sha = sha256File(real);
  if (sha !== storedSha.toLowerCase()) {
    reasons.push(`the cited ${label} ${rel} hashes to ${(sha || 'unreadable').slice(0, 12)}…, not the stored sha ${storedSha.slice(0, 12)}…`);
  }
  return { reasons, real };
}

// The FULL record-grade verification of a line's main judge
// citation, on read: everything record itself cross-checked,
// re-derived from the artifact on disk NOW. `wantKinds` /
// `lineScores` / `kindExpectation` adapt the one core to the two
// citation shapes (a round line's absolute/cheap report vs a
// feedback line's regrade report). Checks: the citation exists and
// is a non-empty string with a 64-hex sha; the cited file verifies
// (verifyCitedFile: relative, non-symlink, inside design/, hash);
// the file PARSES with no problems; header round == the line's
// round; the kind matches the citation's role; header grader ==
// the line's grader (a line whose grader field was edited to a
// different label no longer verifies against the artifact's own
// grader); header page-sha256 == the line's pageSha (a copied line
// whose pageSha was swapped to another page, or edited to a newer
// page version the artifact never bound, fails here); the parsed
// score table == the line's scores; the line's evidence EQUALS the
// artifact's evidence cells joined with '; ' (round 5, N2: the
// record DERIVES its evidence field from those cells, so a line
// whose stored evidence was edited — or which carries none — does
// not transcribe its artifact; the writer always stores the derived
// evidence behind a scored citation, on a round record and on a
// feedback regrade alike, so there is no genuine scored shape with
// a missing evidence field); the line's OWN transcription
// fields match the header they claim to transcribe — its
// independenceBasis, when carried, EQUALS the header basis, and its
// tokensHash, when carried, EQUALS the header tokens-sha256 (round
// 4, F5: round 3 compared the artifact against the disk and the
// score table, but a line whose stored basis was edited to confess
// self-grading — the artifact untouched — still verified, because
// nothing compared those two stored fields against the header);
// the header basis passes the independence check on the artifact's
// own text (round 4, F1: the checker's old parse half never applied
// it, so a report whose basis confesses self-grading passed the
// checker while every run-log read path refused it); and the body's
// Round line agrees with the header (round 4, F1: the same drift
// hid a body Round line naming a different grader than the header).
function verifyGradeCitation(project, r, wantKinds, lineScores, kindExpectation) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  if (typeof r.judgeReport !== 'string' || !r.judgeReport) fail('the line cites no judgeReport');
  if (typeof r.judgeReportSha !== 'string' || !/^[0-9a-f]{64}$/i.test(r.judgeReportSha)) fail('the line carries no valid judgeReportSha (exactly 64 hex)');
  if (reasons.length) return { ok: false, reasons };
  const ctx = designContext(project);
  const cited = verifyCitedFile(project, ctx, r.judgeReport, r.judgeReportSha, 'judge artifact');
  reasons.push(...cited.reasons);
  if (!cited.real || cited.reasons.length) return { ok: false, reasons };
  let parsed = null;
  try { parsed = parseJudgeReport(fs.readFileSync(cited.real, 'utf8')); } catch { parsed = null; }
  if (!parsed || !parsed.header || parsed.problems.length) {
    fail(`the cited file does not parse as a well-formed judge report${parsed && parsed.problems.length ? ` (${parsed.problems[0]})` : ''}`);
    return { ok: false, reasons, parsed: null };
  }
  const header = parsed.header;
  if (Number(header.round) !== r.round) fail(`the cited file is a report for round ${header.round}, not round ${r.round}`);
  if (!wantKinds.includes(header.kind)) fail(`the cited file is a ${header.kind} report — ${kindExpectation}`);
  if (header.grader !== r.grader) fail(`the cited report names grader "${header.grader}", not the line's grader "${r.grader}" — the line misattributes the grade`);
  const linePageSha = typeof r.pageSha === 'string' ? r.pageSha.toLowerCase() : null;
  if (header['page-sha256'] !== linePageSha) fail(`the cited report binds page-sha256 ${String(header['page-sha256']).slice(0, 12)}…, not the line's pageSha ${String(r.pageSha).slice(0, 12)}… — the line claims a grade bound to a page version the report does not bind`);
  if (!parsed.scores || !lineScores || typeof lineScores !== 'object'
    || parsed.scores.type !== lineScores.type || parsed.scores.layout !== lineScores.layout
    || parsed.scores.colour !== lineScores.colour || parsed.scores.space !== lineScores.space) {
    fail('the cited report records different scores than the line');
  }
  // Round 5 (N2): the evidence transcription. The writer DERIVES a
  // scored line's evidence from the cited artifact's evidence cells
  // (joined with '; ') — it is not a caller-asserted field — so the
  // stored value must equal that derivation exactly. A line whose
  // evidence was edited after the fact, or which carries no
  // evidence at all, does not transcribe its artifact.
  if (Array.isArray(parsed.evidenceCells)) {
    const derivedEvidence = parsed.evidenceCells.join('; ');
    if (r.evidence !== derivedEvidence) {
      fail(`the line's evidence ${typeof r.evidence === 'string' ? `"${r.evidence}"` : '(none)'} is not the cited report's evidence cells joined ("${derivedEvidence}") — the record's evidence is derived from the artifact, so the line does not transcribe it`);
    }
  }
  if (typeof r.independenceBasis === 'string' && r.independenceBasis !== header.basis) {
    fail(`the line's independenceBasis "${r.independenceBasis}" is not the cited report's basis "${header.basis}" — the line does not transcribe its artifact`);
  }
  if (typeof r.tokensHash === 'string' && r.tokensHash && header['tokens-sha256'] !== r.tokensHash.toLowerCase()) {
    fail(`the cited report binds tokens-sha256 ${String(header['tokens-sha256']).slice(0, 12)}…, not the line's tokensHash ${String(r.tokensHash).slice(0, 12)}… — the line claims a grade bound to a tokens version the cited report does not bind`);
  }
  if (!headerBasisEstablishesIndependence(header)) {
    fail('the cited report carries no independence basis establishing BOTH fresh/separate context AND no production history');
  }
  if (parsed.bodyRound !== undefined && (parsed.bodyRound !== r.round || parsed.bodyGrader !== header.grader || parsed.bodyBasis !== header.basis)) {
    fail('the cited report body Round line disagrees with its header');
  }
  // `parsed` rides along for the callers' kind-specific
  // transcription checks (round 6, X5: verifyGradedLine compares
  // the line's notRegraded against this header's not-regraded set).
  return { ok: reasons.length === 0, reasons, parsed };
}

// A round line carries PAIRWISE fields when any of pairwise /
// pairwiseReports / pairwiseReportShas is present and non-null —
// the writer couples the three (a verdict is recorded only with
// its two artifacts), so any one of them present means the
// pairwise transcription must verify too (verifyPairwiseLine,
// round 5, N5 — the same one-definition rule isJuryRoundLine
// established for jury fields in round 4, F4).
export function isPairwiseRoundLine(r) {
  return (r.pairwise !== null && r.pairwise !== undefined)
    || (r.pairwiseReports !== null && r.pairwiseReports !== undefined)
    || (r.pairwiseReportShas !== null && r.pairwiseReportShas !== undefined);
}

// A round line's grade verification: the main citation
// (verifyGradeCitation, kinds absolute/cheap) PLUS its expert
// citations (round 4, F7 — below) PLUS its pairwise transcription
// when it carries pairwise fields (round 5, N5 — below). Round 5
// (N1): the line's gate must be exactly "pass" — the writer never
// writes scores behind a failed gate (record refuses them), so a
// scored line flipped to gate "fail" after the fact is a shape no
// genuine record has; best filtered it locally before, but land,
// feedback's anchor and the checker trusted the line through this
// function, so the requirement lives here, in the shared core,
// where every consumer inherits it. Round 6 added (X5) the
// not-regraded transcription — record validates the main
// artifact's header not-regraded set against the record's
// --not-regraded set (for BOTH kinds: the writer stores the parsed
// flag, null when absent, and validates the header against
// `flag || []`), but no read path compared the stored field
// against the header it transcribes.
export function verifyGradedLine(project, r) {
  const reasons = [];
  if (r.gate !== 'pass') {
    reasons.push(`the line carries scores behind gate "${r.gate === undefined ? '(absent)' : r.gate}", not "pass" — run-log.mjs never writes a graded record on a failed gate, so this line was hand-appended or edited`);
  }
  const core = verifyGradeCitation(project, r, ['absolute', 'cheap'], r.scores, "a round line's main citation is absolute | cheap");
  const experts = verifyExpertCitations(project, r);
  reasons.push(...core.reasons, ...experts.reasons);
  // NOTE (round 8, C4): the line's cited gate legs are NOT verified
  // here. Round 6 (X2) verified them inside this function; round 8
  // moved leg currency OUT of the universal grade verification —
  // see verifyLegCitationsCurrent below for the epoch rule and the
  // consumers that require it.
  // Round 6 (X5): the not-regraded transcription. Record time
  // defines it as exact set equality — the header value split on
  // ',', trimmed, empties dropped ('-' is the empty set), sorted,
  // against the record's set — and applies it to the main artifact
  // of either kind, so the read check mirrors it for either kind:
  // the line's stored notRegraded (null when the flag was absent,
  // which is the empty set) must equal the cited header's set.
  if (core.parsed && core.parsed.header) {
    const headerValue = core.parsed.header['not-regraded'];
    const headerSet = (headerValue === '-' || headerValue === undefined
      ? []
      : String(headerValue).split(',').map((s) => s.trim()).filter(Boolean)).sort();
    const lineSet = (Array.isArray(r.notRegraded) ? [...r.notRegraded] : []).sort();
    if (JSON.stringify(headerSet) !== JSON.stringify(lineSet)) {
      reasons.push(`the line's notRegraded ${JSON.stringify(r.notRegraded === undefined ? null : r.notRegraded)} does not transcribe the cited report's not-regraded set "${headerValue}" — record derives the field from the record's --not-regraded set and validates the header against it, so an edited field is not a transcription`);
    }
  }
  if (isPairwiseRoundLine(r)) reasons.push(...verifyPairwiseLine(project, r).reasons);
  return { ok: reasons.length === 0, reasons };
}

// A line's own cited gate legs, verified for CURRENCY on read
// (round 6, X2; round 8, C4 — the EPOCH rule). The check itself is
// round 6's X2, unchanged: the same on-disk verification the
// no-grade path has applied since round 3 (verifyCitedLegOnRead —
// the cited file exists inside design/, is not a symlink, hashes
// to the stored gateLeg<N>Sha, and carries the verdict matching
// the line's gate value), plus the two legs being two distinct
// files. WHAT CHANGED in round 8 is WHO requires it. Round 6 ran
// it inside verifyGradedLine, so every read consumer held EVERY
// graded line to leg currency — but the two canonical leg files
// (design/gate-leg1.log / gate-leg2.log) are ephemeral by design:
// the next round's gate run overwrites them, so a genuine second
// round rotated the evidence out from under the genuine first
// round's line, and the checker failed a fully genuine log while
// `best` forgot a genuinely graded round (C4, a fail-CLOSED false
// positive). The epoch principle — round 7's lock ruling
// generalised: currency checks (stored sha == current file) bind
// the LIVE EPOCH, the records a live operation anchors on;
// rotated history is checked for shape + artifact binding, not
// leg currency, because the judge artifact (which carries the
// stamped gate bit) is the durable evidence of a past round's
// grade. Consumers therefore split:
//   - feedback's anchor and land's round precondition (a graded
//     record counts only with leg currency too — live operations
//     standing on the line NOW), and isGenuineNoGradeRound
//     (unchanged since round 3);
//   - verifyLandLine's CURRENT reading (its round half follows
//     land's rule) — kept for callers that omit the flag; the one
//     production caller, runlog-check, no longer uses it (the
//     deadlock, below);
//   - NOT verifyGradedLine / `best`: a historical grade verifies
//     through its judge artifact alone;
//   - NOT runlog-check, for ANY stored line (live-proof round 2 —
//     the deadlock adjudication): round 8 left the checker a
//     latest-round-line currency check, but gate.sh §1.1 folds
//     the checker's output into leg 1's verdict and every gate
//     run rotates the canonical legs, so the still-latest round
//     line failed currency inside the very gate run meant to
//     supersede it — leg 1 failed, prepare refused, and no later
//     round could ever record. Currency is a property of live
//     operations, not of the log's standing state; the checker
//     holds stored lines to shape + artifact binding only.
export function verifyLegCitationsCurrent(project, r) {
  const reasons = [];
  const leg1 = verifyCitedLegOnRead(project, r, 'leg1');
  const leg2 = verifyCitedLegOnRead(project, r, 'leg2');
  if (!leg1) reasons.push(`the line's cited gate leg 1 (${typeof r.gateLeg1 === 'string' ? r.gateLeg1 : '(none)'}) does not verify on disk against its stored gateLeg1Sha with the verdict its gate value requires — a graded record's legs are part of the record, and an edited leg sha is not a transcription`);
  if (!leg2) reasons.push(`the line's cited gate leg 2 (${typeof r.gateLeg2 === 'string' ? r.gateLeg2 : '(none)'}) does not verify on disk against its stored gateLeg2Sha with the verdict its gate value requires — a graded record's legs are part of the record, and an edited leg sha is not a transcription`);
  if (leg1 && leg2 && (leg1.real === leg2.real || (leg1.stat.dev === leg2.stat.dev && leg1.stat.ino === leg2.stat.ino))) {
    reasons.push('the line\'s two cited gate legs are the same file (same device+inode — a hardlink pair) — the two gate legs must be two separate artifact files');
  }
  return { ok: reasons.length === 0, reasons };
}

// A feedback line's regrade verification: the same core, with the
// regrade kind and the line's scoreAfter as the score table.
export function verifyFeedbackLine(project, r) {
  return verifyGradeCitation(project, r, ['regrade'], r.scoreAfter, "a feedback line's judge citation is a regrade report");
}

// Expert citations on a round line (round 4, F7): an expert score
// IS a score, but before round 4 NO read path opened its citation
// at all — a line carrying expertMotion 5 / expertUx 5 with report
// paths naming files that do not exist and invented shas verified
// everywhere its main citation did. For each expert domain the
// line carries a score in, the stored citation must verify the
// same way the main citation does: the file exists inside design/
// (non-symlink, hash-equal to the stored *Sha), parses as the
// matching expert kind for the line's round, binds the line's page
// (header page-sha256 == the line's pageSha; on a no-grade line,
// which stores pageSha null, header page == the line's recorded
// page and that page's current hash), its parsed expert score
// EQUALS the line's expert score, and its parsed expert EVIDENCE
// equals the line's stored expert evidence (round 5, N6: record
// time equality-checks the caller's --expert-*-evidence flag
// against the artifact before storing it, so a genuine line's
// expertMotionEvidence / expertUxEvidence IS the artifact's
// evidence text — an edited or missing field does not transcribe
// the expert report).
export function verifyExpertCitations(project, r) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  const ctx = designContext(project);
  for (const [scoreField, reportField, shaField, evidenceField, kind, label] of [
    ['expertMotion', 'expertMotionReport', 'expertMotionReportSha', 'expertMotionEvidence', 'expert-motion', 'Motion'],
    ['expertUx', 'expertUxReport', 'expertUxReportSha', 'expertUxEvidence', 'expert-ux', 'UX'],
  ]) {
    const score = r[scoreField];
    if (score === null || score === undefined) continue;
    const rel = r[reportField];
    const sha = r[shaField];
    if (typeof rel !== 'string' || !rel) { fail(`the line carries a ${label} expert score (${score}) but no ${reportField} citation — an expert score with no artifact is a self-assertion`); continue; }
    if (typeof sha !== 'string' || !/^[0-9a-f]{64}$/i.test(sha)) { fail(`the line carries a ${label} expert score (${score}) but no valid ${shaField} (exactly 64 hex)`); continue; }
    const cited = verifyCitedFile(project, ctx, rel, sha, `${label} expert artifact`);
    reasons.push(...cited.reasons);
    if (!cited.real || cited.reasons.length) continue;
    let parsed = null;
    try { parsed = parseJudgeReport(fs.readFileSync(cited.real, 'utf8')); } catch { parsed = null; }
    if (!parsed || !parsed.header || parsed.problems.length) { fail(`the cited ${label} expert artifact ${rel} does not parse as a well-formed judge report`); continue; }
    if (parsed.header.kind !== kind) { fail(`the cited ${label} expert artifact ${rel} is a ${parsed.header.kind} report, not ${kind}`); continue; }
    if (Number(parsed.header.round) !== r.round) { fail(`the cited ${label} expert artifact ${rel} is a report for round ${parsed.header.round}, not round ${r.round}`); continue; }
    if (typeof r.pageSha === 'string' && r.pageSha) {
      if (parsed.header['page-sha256'] !== r.pageSha.toLowerCase()) fail(`the cited ${label} expert artifact ${rel} binds page-sha256 ${String(parsed.header['page-sha256']).slice(0, 12)}…, not the line's pageSha ${r.pageSha.slice(0, 12)}… — the expert graded a different page version than the round's judge`);
    } else if (typeof r.page === 'string' && r.page) {
      if (parsed.header.page !== r.page) fail(`the cited ${label} expert artifact ${rel} grades page "${parsed.header.page}", not the line's recorded page "${r.page}"`);
      else {
        const pageShaNow = sha256File(path.resolve(project, r.page));
        if (!pageShaNow || parsed.header['page-sha256'] !== pageShaNow) fail(`the cited ${label} expert artifact ${rel} binds page-sha256 ${String(parsed.header['page-sha256']).slice(0, 12)}…, not the current hash of the line's page ${r.page} (${(pageShaNow || 'unreadable').slice(0, 12)}…)`);
      }
    }
    // Round 6 (X4): the expert artifact must bind the LINE'S tokens
    // version, the way the pairwise artifacts already did — record
    // time validates expert artifacts with no tokens expectation,
    // so before round 6 a genuine expert artifact prepared against
    // a DIFFERENT tokens.css (its score re-cited in the line)
    // verified everywhere. Genuine prepare+fill artifacts from the
    // same build carry the build's tokens hash, so a genuine line
    // still verifies; the check applies only when the line carries
    // a tokensHash (graded lines always store one — the sha of the
    // tokens file record resolved; a no-grade line stores null).
    if (typeof r.tokensHash === 'string' && r.tokensHash && parsed.header['tokens-sha256'] !== r.tokensHash.toLowerCase()) fail(`the cited ${label} expert artifact ${rel} binds tokens-sha256 ${String(parsed.header['tokens-sha256']).slice(0, 12)}…, not the line's tokensHash ${r.tokensHash.slice(0, 12)}… — the expert graded a different tokens version than the round`);
    if (parsed.expertScore !== score) fail(`the cited ${label} expert artifact ${rel} records ${label} ${parsed.expertScore}, not the line's ${scoreField} ${score} — the line does not transcribe the expert report`);
    if (parsed.expertEvidence !== r[evidenceField]) fail(`the cited ${label} expert artifact ${rel} records evidence "${parsed.expertEvidence}", not the line's ${evidenceField} ${typeof r[evidenceField] === 'string' ? `"${r[evidenceField]}"` : '(none)'} — the line does not transcribe the expert report`);
  }
  return { ok: reasons.length === 0, reasons };
}

// Boolean jury-median test: the per-axis median of three votes.
function median3(a, b, c) {
  return [a, b, c].sort((x, y) => x - y)[1];
}

export function juryMedianMatches(jury, votes) {
  if (!jury || typeof jury !== 'object' || !Array.isArray(votes) || votes.length !== 3) return false;
  for (const axis of ['type', 'layout', 'colour', 'space']) {
    if (jury[axis] !== median3(votes[0][axis], votes[1][axis], votes[2][axis])) return false;
  }
  return true;
}

// The jury half of the shared verifier (red-team round 3, B2): a
// jury line's recorded median was trusted on read as long as its
// ABSOLUTE citation verified — an attacker who edited only the log
// line's jury/juryVotes fields raised the crowned median while the
// juror artifacts stood untouched. A jury line verifies only when
// its three juror artifacts verify AS A JURY: juryReportShas is
// exactly three 64-hex values; the conventional files
// design/judge/round-<n>-jury-<1|2|3>.md exist, are not symlinks,
// resolve inside design/, and hash to the corresponding entry; each
// parses (kind jury, header round == the line's round); the
// multiset of the PARSED juror score-vectors equals the line's
// juryVotes (the same set comparison record uses); the per-axis
// median of the PARSED vectors equals the line's jury; and the
// family rule is re-checked from the headers (disjoint-3: three
// distinct families; single-family: one shared family). Round 4
// adds the two halves record time always had and read time lacked:
// (F2) DISTINCTNESS — the juror files are pairwise distinct files
// (device+inode, so a hardlink is caught) and distinct from the
// line's absolute judge artifact, the page that artifact binds,
// and design/tokens.css (the record-time distinctness set): one
// opinion hardlinked into two juror slots was two votes; and (F3)
// each juror's header basis passes the independence check on its
// own text — a juror whose basis confesses self-grading does not
// count toward a median.
export function verifyJuryLine(project, r) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  const shas = typeof r.juryReportShas === 'string' ? r.juryReportShas.split(';') : [];
  if (shas.length !== 3 || shas.some((s) => !/^[0-9a-f]{64}$/i.test(s))) {
    fail('juryReportShas is not exactly three 64-hex sha256 values joined with ";"');
    return { ok: false, reasons };
  }
  const votesOk = Array.isArray(r.juryVotes) && r.juryVotes.length === 3
    && r.juryVotes.every((v) => v && ['type', 'layout', 'colour', 'space'].every((a) => Number.isInteger(v[a])));
  if (!votesOk) fail('the line carries no juryVotes of three recorded votes');
  if (!r.jury || typeof r.jury !== 'object') fail('the line carries no jury median');
  const ctx = designContext(project);
  const { designDir, designReal, inside } = ctx;
  const sameFile = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino;
  const statOrNull = (p) => { try { return fs.statSync(p); } catch { return null; } };
  const realOrNull = (p) => { try { return fs.realpathSync(p); } catch { return null; } };
  // F2: the record-time distinctness set, assembled on read — the
  // line's absolute artifact, the page it binds (from its header),
  // and tokens.css. A member that cannot be stat'ed is skipped (the
  // graded half reports the underlying problem itself).
  const others = [];
  const addOther = (resolved, label) => {
    const st = statOrNull(resolved);
    if (st) others.push({ stat: st, real: realOrNull(resolved), label });
  };
  if (typeof r.judgeReport === 'string' && r.judgeReport && !path.isAbsolute(r.judgeReport)) {
    const absResolved = path.resolve(project, r.judgeReport);
    addOther(absResolved, "the line's absolute judge artifact");
    try {
      const absParsed = parseJudgeReport(fs.readFileSync(absResolved, 'utf8'));
      if (absParsed && absParsed.header && absParsed.header.page) addOther(path.resolve(project, absParsed.header.page), "the page the line's judge artifact binds");
    } catch { /* missing/unreadable: verifyGradedLine reports it */ }
  }
  addOther(path.join(designDir, 'tokens.css'), 'design/tokens.css');
  const parsedVotes = [];
  const families = [];
  const jurorFiles = [];
  for (let k = 0; k < 3; k++) {
    const rel = `design/judge/round-${r.round}-jury-${k + 1}.md`;
    const resolved = path.resolve(project, rel);
    let lstat = null;
    try { lstat = fs.lstatSync(resolved); } catch { fail(`juror artifact ${rel} does not exist`); }
    if (!lstat) continue;
    if (lstat.isSymbolicLink()) { fail(`juror artifact ${rel} is a symlink — a citation must name a real file, not a link`); continue; }
    let real = null;
    try { real = fs.realpathSync(resolved); } catch { fail(`juror artifact ${rel} cannot be resolved`); }
    if (!real) continue;
    if (!inside(real, designReal)) { fail(`juror artifact ${rel} resolves outside <project>/design/`); continue; }
    const stat = statOrNull(resolved);
    for (const o of others) {
      if (real === o.real || sameFile(stat, o.stat)) fail(`juror artifact ${rel} is the same file as ${o.label} — one file cannot back two judge calls`);
    }
    for (const o of jurorFiles) {
      if (real === o.real || sameFile(stat, o.stat)) fail(`juror artifacts ${o.rel} and ${rel} are the same file (same device+inode — a hardlink pair) — one opinion cannot be counted as two jurors`);
    }
    jurorFiles.push({ rel, real, stat });
    if (sha256File(real) !== shas[k].toLowerCase()) { fail(`juror artifact ${rel} does not hash to juryReportShas entry ${k + 1}`); continue; }
    let parsed = null;
    try { parsed = parseJudgeReport(fs.readFileSync(real, 'utf8')); } catch { parsed = null; }
    if (!parsed || !parsed.header || parsed.problems.length || !parsed.scores) { fail(`juror artifact ${rel} does not parse as a well-formed jury report`); continue; }
    if (Number(parsed.header.round) !== r.round) { fail(`juror artifact ${rel} is a report for round ${parsed.header.round}, not round ${r.round}`); continue; }
    if (parsed.header.kind !== 'jury') { fail(`juror artifact ${rel} is a ${parsed.header.kind} report, not a jury report`); continue; }
    // Round 5 (N3): the juror must bind the ROUND'S page, exactly
    // as record time binds it (validateJudgeArtifact with the
    // record's page: header page == the recorded page, and its
    // page-sha256 == the graded page's hash). Before round 5 the
    // read path checked a juror's round, kind, basis, family and
    // scores — but never its page binding, so three genuine juror
    // artifacts of ANOTHER page version (their shas re-cited in the
    // line) verified as this round's jury.
    if (typeof r.pageSha === 'string' && r.pageSha && parsed.header['page-sha256'] !== r.pageSha.toLowerCase()) { fail(`juror artifact ${rel} binds page-sha256 ${String(parsed.header['page-sha256']).slice(0, 12)}…, not the line's pageSha ${r.pageSha.slice(0, 12)}… — the juror graded a different page version than the round's judge`); continue; }
    if (typeof r.page === 'string' && r.page && parsed.header.page !== r.page) { fail(`juror artifact ${rel} grades page "${parsed.header.page}", not the recorded page "${r.page}"`); continue; }
    // Round 6 (X3): the juror must also bind the LINE'S tokens
    // version. Record time validates juror artifacts against the
    // record's tokensHash (validateJudgeArtifact with the record's
    // tokensHash), but the read path never compared it, so three
    // genuine juror artifacts prepared against a DIFFERENT
    // tokens.css — their shas, votes and median re-cited in the
    // line consistently — derived a median for a build the round
    // never graded. The check applies when the line carries a
    // tokensHash (graded lines always store one).
    if (typeof r.tokensHash === 'string' && r.tokensHash && parsed.header['tokens-sha256'] !== r.tokensHash.toLowerCase()) { fail(`juror artifact ${rel} binds tokens-sha256 ${String(parsed.header['tokens-sha256']).slice(0, 12)}…, not the line's tokensHash ${r.tokensHash.slice(0, 12)}… — the juror graded a different tokens version than the round`); continue; }
    if (!headerBasisEstablishesIndependence(parsed.header)) { fail(`juror artifact ${rel} carries no independence basis establishing BOTH fresh/separate context AND no production history`); continue; }
    parsedVotes.push(parsed.scores);
    families.push(parsed.header.family);
  }
  if (parsedVotes.length === 3) {
    if (votesOk) {
      const canon = (s) => `${s.type},${s.layout},${s.colour},${s.space}`;
      if (JSON.stringify(parsedVotes.map(canon).sort()) !== JSON.stringify(r.juryVotes.map(canon).sort())) {
        fail('the juror artifacts record different votes than the line juryVotes (as a set)');
      }
    }
    if (r.jury && typeof r.jury === 'object' && !juryMedianMatches(r.jury, parsedVotes)) {
      fail('the line jury median is not the per-axis median of the juror artifacts scores');
    }
    if (families.some((f) => !f || f === '-')) fail('a juror artifact names no model family in its header');
    else if (r.juryMode === 'disjoint-3' && new Set(families).size !== 3) fail('juryMode disjoint-3 but the juror artifacts do not declare three distinct families');
    else if (r.juryMode === 'single-family' && new Set(families).size !== 1) fail('juryMode single-family but the juror artifacts do not share one family');
    else if (r.juryMode !== 'disjoint-3' && r.juryMode !== 'single-family') fail(`juryMode "${r.juryMode}" cannot carry a verified jury (votes need disjoint-3 | single-family)`);
  }
  return { ok: reasons.length === 0, reasons };
}

// The pairwise half of the shared verifier (round 5, N5): before
// round 5 NO read path opened a line's pairwise transcription at
// all — the verdict, its two artifacts and its shas were trusted
// from the line, so a line carrying invented pairwise fields (or a
// verdict flipped against genuine artifacts) verified everywhere
// its absolute citation did, and `show` printed the fake verdict
// as the round's P11 result. A pairwise-carrying line verifies
// only when the transcription re-derives, exactly as record time
// derives it: pairwiseReportShas is exactly two 64-hex values and
// pairwiseReports names the two artifacts; each cited file
// verifies (verifyCitedFile: relative, non-symlink, inside
// design/, hash-equal to its stored sha), parses as a kind-pairwise
// report for the line's round, carries an independence basis, and
// binds the round's page and tokens the way record time binds
// them (header page-sha256 == the line's pageSha, header page ==
// the line's recorded page when it names one, header
// tokens-sha256 == the line's tokensHash when it carries one); the
// two files are two distinct files, and distinct from the line's
// main judge artifact (the record-time distinctness set, as for
// jurors); the A/B swap proof holds (report 2's shots-a / shots-b
// are report 1's shots-b / shots-a, by screenshot-hash multiset);
// and the verdict re-derives from the two keep lines against the
// MAIN artifact's screenshot set — the version whose shot set
// equals that set is the challenger, each report's keep line
// derives keep-challenger / keep-incumbent, two derivations that
// agree ARE the verdict, two that disagree derive `tie` (the P11
// rule) — and the derived verdict EQUALS the line's pairwise.
// pairwiseAgrees is shape-checked only (a boolean or null): at
// record time the flag is the caller's recorded observation of
// whether the verdict agreed with the absolute-score keep/discard,
// a comparison against the INCUMBENT round's scores — data that
// lives on other log lines, which no per-line verifier receives —
// and record time itself never derives or cross-checks the value,
// so there is no per-line derivation to mirror; what read CAN and
// does enforce is that the verdict the flag qualifies is itself
// verified, above.
export function verifyPairwiseLine(project, r) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  if (!['keep-incumbent', 'keep-challenger', 'tie'].includes(r.pairwise)) {
    fail(`the line's pairwise "${r.pairwise === undefined ? '(absent)' : r.pairwise}" is not one of keep-incumbent | keep-challenger | tie — the only verdicts run-log.mjs writes`);
    return { ok: false, reasons };
  }
  const shas = typeof r.pairwiseReportShas === 'string' ? r.pairwiseReportShas.split(';') : [];
  if (shas.length !== 2 || shas.some((s) => !/^[0-9a-f]{64}$/i.test(s))) {
    fail('pairwiseReportShas is not exactly two 64-hex sha256 values joined with ";"');
    return { ok: false, reasons };
  }
  const rels = typeof r.pairwiseReports === 'string' ? r.pairwiseReports.split(';') : [];
  if (rels.length !== 2 || rels.some((s) => !s)) {
    fail('pairwiseReports does not name exactly two pairwise artifacts (";"-joined, as run-log.mjs writes them)');
    return { ok: false, reasons };
  }
  if (r.pairwiseAgrees !== null && r.pairwiseAgrees !== undefined && typeof r.pairwiseAgrees !== 'boolean') {
    fail(`the line's pairwiseAgrees is ${JSON.stringify(r.pairwiseAgrees)}, not a boolean — run-log.mjs stores --pairwise-agrees yes/no as true/false`);
  }
  const ctx = designContext(project);
  // The challenger set comes from the line's MAIN artifact (the
  // record-time derivation reads judgeArt.shots): the main report
  // must itself be readable and parse — verifyGradedLine has
  // already verified its citation; a failure here is reported in
  // its own words rather than re-derived.
  let mainParsed = null;
  let mainReal = null;
  if (typeof r.judgeReport === 'string' && r.judgeReport
    && typeof r.judgeReportSha === 'string' && /^[0-9a-f]{64}$/i.test(r.judgeReportSha)) {
    const mainCited = verifyCitedFile(project, ctx, r.judgeReport, r.judgeReportSha, 'judge artifact');
    if (mainCited.real && !mainCited.reasons.length) {
      mainReal = mainCited.real;
      try { mainParsed = parseJudgeReport(fs.readFileSync(mainReal, 'utf8')); } catch { mainParsed = null; }
    }
  }
  if (!mainParsed || !mainParsed.header || mainParsed.problems.length) {
    fail('the line\'s main judge artifact cannot be read and parsed, so the pairwise challenger set (its screenshot set) cannot be derived');
    return { ok: false, reasons };
  }
  const challenger = new Set((parseShotList(mainParsed.header.screenshots) || []).map((s) => s.sha256));
  if (!challenger.size) {
    fail('the line\'s main judge artifact binds no screenshots, so no pairwise A/B mapping can be derived from it');
    return { ok: false, reasons };
  }
  const arts = [];
  const seenReals = new Map();
  if (mainReal) seenReals.set(mainReal, "the line's main judge artifact");
  for (let k = 0; k < 2; k++) {
    const rel = rels[k];
    const cited = verifyCitedFile(project, ctx, rel, shas[k], `pairwise artifact ${k + 1}`);
    reasons.push(...cited.reasons);
    if (!cited.real || cited.reasons.length) continue;
    if (seenReals.has(cited.real)) { fail(`pairwise artifact ${rel} is the same file as ${seenReals.get(cited.real)} — one file cannot back two judge calls`); continue; }
    seenReals.set(cited.real, `pairwise artifact ${rel}`);
    let parsed = null;
    try { parsed = parseJudgeReport(fs.readFileSync(cited.real, 'utf8')); } catch { parsed = null; }
    if (!parsed || !parsed.header || parsed.problems.length) { fail(`the cited pairwise artifact ${rel} does not parse as a well-formed judge report`); continue; }
    if (parsed.header.kind !== 'pairwise') { fail(`the cited pairwise artifact ${rel} is a ${parsed.header.kind} report, not a pairwise report`); continue; }
    if (Number(parsed.header.round) !== r.round) { fail(`the cited pairwise artifact ${rel} is a report for round ${parsed.header.round}, not round ${r.round}`); continue; }
    if (!headerBasisEstablishesIndependence(parsed.header)) { fail(`the cited pairwise artifact ${rel} carries no independence basis establishing BOTH fresh/separate context AND no production history`); continue; }
    if (typeof r.pageSha === 'string' && r.pageSha && parsed.header['page-sha256'] !== r.pageSha.toLowerCase()) { fail(`the cited pairwise artifact ${rel} binds page-sha256 ${String(parsed.header['page-sha256']).slice(0, 12)}…, not the line's pageSha ${r.pageSha.slice(0, 12)}… — the pairwise calls graded a different page version than the round's judge`); continue; }
    if (typeof r.page === 'string' && r.page && parsed.header.page !== r.page) { fail(`the cited pairwise artifact ${rel} grades page "${parsed.header.page}", not the line's recorded page "${r.page}"`); continue; }
    if (typeof r.tokensHash === 'string' && r.tokensHash && parsed.header['tokens-sha256'] !== r.tokensHash.toLowerCase()) { fail(`the cited pairwise artifact ${rel} binds tokens-sha256 ${String(parsed.header['tokens-sha256']).slice(0, 12)}…, not the line's tokensHash ${r.tokensHash.slice(0, 12)}…`); continue; }
    const shotsA = parseShotList(parsed.header['shots-a']) || [];
    const shotsB = parseShotList(parsed.header['shots-b']) || [];
    if (!shotsA.length || !shotsB.length) { fail(`the cited pairwise artifact ${rel} binds an empty shots-a / shots-b set — a pairwise verdict must bind to both versions' screenshots`); continue; }
    arts.push({ rel, parsed, shotsA, shotsB });
  }
  if (arts.length === 2) {
    const hashSet = (list) => list.map((s) => s.sha256).sort().join(';');
    if (hashSet(arts[0].shotsA) !== hashSet(arts[1].shotsB) || hashSet(arts[0].shotsB) !== hashSet(arts[1].shotsA)) {
      fail('the cited pairwise artifacts are not a swapped pair: report 2\'s shots-a / shots-b are not report 1\'s shots-b / shots-a (the same two versions, order swapped) — two reports of the same order are one call cited twice');
    } else {
      const derivedList = [];
      let derivable = true;
      for (const art of arts) {
        const isChallenger = (list) => list.length === challenger.size && list.every((s) => challenger.has(s.sha256));
        const aIs = isChallenger(art.shotsA);
        const bIs = isChallenger(art.shotsB);
        if (aIs === bIs) {
          fail(`pairwise artifact ${art.rel}: exactly one of shots-a / shots-b must be the current page's screenshot set (the challenger) — neither or both matched, so the A/B mapping cannot be derived`);
          derivable = false;
          break;
        }
        const kept = art.parsed.pairwiseKeep === 'A' ? aIs : bIs;
        derivedList.push(kept ? 'keep-challenger' : 'keep-incumbent');
      }
      if (derivable) {
        const derived = derivedList[0] === derivedList[1] ? derivedList[0] : 'tie';
        if (derived !== r.pairwise) {
          fail(`the pairwise artifacts derive ${derived}, not the line's pairwise "${r.pairwise}" — the line does not transcribe the pairwise verdict`);
        }
      }
    }
  }
  return { ok: reasons.length === 0, reasons };
}

// A round line counts as a JURY line on read when it carries ANY
// jury field — the writer couples jury / juryVotes /
// juryReportShas, so any one of them present and non-null means
// the jury half must verify too. ONE definition for every consumer
// (round 4, F4): round 3's runlog-check triggered its jury
// verification only on jury/juryVotes, so a line carrying
// juryReportShas alone — well-formed shas, no juror files — passed
// the checker while run-log.mjs's consumers refused it.
export function isJuryRoundLine(r) {
  return (r.jury !== null && r.jury !== undefined)
    || (r.juryVotes !== null && r.juryVotes !== undefined)
    || (r.juryReportShas !== null && r.juryReportShas !== undefined);
}

// A round line is GENUINELY GRADED (red-team round 2, NA4/NA19;
// round 3: the full shared verification) only in the shape the
// writer produces: scores + an allowed grader + pageSha, AND a
// citation that passes verifyGradedLine on disk right now — and,
// for a jury line, verifyJuryLine too (a jury line must not anchor
// feedback or satisfy land on its absolute citation alone when its
// jury does not verify). Hand-appended lines fail at least one
// half: a scoreless line carrying a pageSha (the NA4 poison) has no
// scores and no grader; a scored line citing an invented hash does
// not verify; a scored copy of a genuine line whose pageSha was
// swapped to another page (round 3, B1) verifies its hash but not
// its page binding. Read paths that anchor on a round's record
// (feedback's page anchor, land's precondition, best) consult ONLY
// lines passing this test.
export function isVerifiedGradedRound(project, r) {
  if (!r || r.kind !== 'round') return false;
  if (!r.scores || typeof r.scores !== 'object') return false;
  if (!ALLOWED_GRADERS.includes(r.grader)) return false;
  if (typeof r.pageSha !== 'string' || !/^[0-9a-f]{64}$/i.test(r.pageSha)) return false;
  // Round 5 (N1): the gate half of the shape. A graded record is
  // written only on --gate pass (record refuses scores on a failed
  // gate), so a scored line whose gate is not exactly "pass" is a
  // shape the writer never produces — before round 5 this
  // predicate (the anchor/precondition test land and feedback
  // share) did not check it, and only `best` filtered it locally,
  // so a genuine line flipped to gate "fail" after the fact still
  // anchored feedback and satisfied land. verifyGradedLine carries
  // the same requirement for the checker's path; it is stated here
  // too so the predicate is self-contained.
  if (r.gate !== 'pass') return false;
  if (!verifyGradedLine(project, r).ok) return false;
  if (isJuryRoundLine(r) && !verifyJuryLine(project, r).ok) return false;
  return true;
}

// One cited gate leg, verified ON READ (red-team round 3, B3): the
// file the no-grade line cites must exist inside <project>/design/,
// must not be a symlink, must hash to the line's stored leg sha, and
// must carry the verdict matching the line's gate value — the PASS
// verdict line and no FAIL verdict for a pass line, the FAIL
// verdict and no PASS verdict line for a fail line (the same marker
// semantics validateGateArtifacts applies at write time, R4 word
// boundary on the FAIL scan included). Returns { real, stat } or
// null on any failure.
function verifyCitedLegOnRead(project, r, leg) {
  const rel = leg === 'leg1' ? r.gateLeg1 : r.gateLeg2;
  const sha = leg === 'leg1' ? r.gateLeg1Sha : r.gateLeg2Sha;
  if (typeof rel !== 'string' || !rel || path.isAbsolute(rel)) return null;
  if (typeof sha !== 'string' || !/^[0-9a-f]{64}$/i.test(sha)) return null;
  const { designReal, inside } = designContext(project);
  const resolved = path.resolve(project, rel);
  let lstat;
  try { lstat = fs.lstatSync(resolved); } catch { return null; }
  if (lstat.isSymbolicLink()) return null;
  let stat;
  try { stat = fs.statSync(resolved); } catch { return null; }
  if (!stat.isFile() || stat.size === 0) return null;
  let real;
  try { real = fs.realpathSync(resolved); } catch { return null; }
  if (!inside(real, designReal)) return null;
  if (sha256File(real) !== sha.toLowerCase()) return null;
  const text = fs.readFileSync(real, 'utf8');
  const marker = GATE_LEG_MARKERS[leg];
  const failMarker = GATE_LEG_FAIL_MARKERS[leg];
  const hasPassVerdict = text.split('\n').some((line) => stripInvisible(line) === stripInvisible(marker));
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
  if (r.gate === 'pass' && (!hasPassVerdict || hasFailVerdict)) return null;
  if (r.gate === 'fail' && (!hasFailVerdict || hasPassVerdict)) return null;
  return { real, stat };
}

// A round line is a GENUINE NO-GRADE record (the writer's no-grade
// shape) only when it carries the no-grade field set: grader null
// (a no-grade record stores grader: null — the CLI's --grader none
// is not a stored label), scores null, and NO grade-coupled fields
// — judgeReport / judgeReportSha / pageSha are all null, because
// the writer couples them to a grade. It must also carry the
// writer's timestamp. Red-team round 2 (NA19) stopped at the field
// shape; a hand-written line can carry the full shape with INVENTED
// leg citations (round 3, B3: leg paths that never existed, sha
// values invented) — so round 3 adds the on-disk half: the line
// counts only when BOTH cited legs verify on disk against the
// stored shas, with the verdict matching the line's gate value, and
// the two legs are two distinct files. A line citing no legs at all
// does not count (on either gate value): land re-validates its own
// legs anyway, and the precondition's job — a round genuinely ran
// behind artifacts — is exactly what an uncited or unverifiable
// line cannot show. (The writer's no-grade FAIL lines cite no legs,
// so they never satisfy the precondition; the no-grade rung that
// lands is the gate-pass one, whose legs the writer always cites.)
// Round 4 (F7 parity): expert scores ARE allowed on a no-grade
// record, but they are scores — a no-grade line carrying expert
// scores whose citations do not verify (verifyExpertCitations)
// does not count either.
// The no-grade SHAPE alone (the field-set half of
// isGenuineNoGradeRound, without the on-disk leg half): factored
// out in round 8 because verifyLandLine's OLDER-land round half
// accepts a genuine-SHAPED no-grade line — under the epoch rule a
// historical land's no-grade round is not held to leg currency
// either (its legs rotated with the same gate runs).
function isNoGradeShape(r) {
  if (!r || r.kind !== 'round') return false;
  if (r.grader !== null && r.grader !== undefined) return false;
  if (r.scores !== null && r.scores !== undefined) return false;
  if (r.judgeReport || r.judgeReportSha || r.pageSha) return false;
  if (typeof r.at !== 'string' || !r.at) return false;
  if (r.gate !== 'pass' && r.gate !== 'fail') return false;
  if (!r.gateLeg1 || !r.gateLeg2) return false;
  return true;
}

export function isGenuineNoGradeRound(project, r) {
  if (!isNoGradeShape(r)) return false;
  // The on-disk leg half is the shared leg-currency check
  // (verifyLegCitationsCurrent — the same helper land's graded
  // half and the checker's latest-line check use, round 8): both
  // cited legs verify against the stored shas with the verdict
  // matching the line's gate value, as two distinct files.
  if (!verifyLegCitationsCurrent(project, r).ok) return false;
  if ((r.expertMotion !== null && r.expertMotion !== undefined)
    || (r.expertUx !== null && r.expertUx !== undefined)) {
    if (!verifyExpertCitations(project, r).ok) return false;
  }
  return true;
}

// A stored CROSSCHECK line, verified on read (round 6, X1 — the
// round's SEVERE). Before round 6 the crosscheck channel was the
// one grade-coupled channel NO read path verified: record derives
// the verdict from the counts, restricts the checker to an
// allowlist, requires the two-half independence basis, and (D15)
// validates the cited report — but land trusted the LATEST stored
// verdict, prepare derived its cross-check bit from the latest
// stored verdict, and runlog-check never looked at crosscheck
// lines at all. One hand-appended line — verdict "clear" over
// counts that derive "blocked", an unlisted checker, a report path
// naming nothing — therefore overrode a genuine blocked verdict in
// all three consumers at once. This verifier mirrors the record
// path exactly:
//   - the counts are the writer's shape (non-negative integers,
//     waived no greater than warning) and the stored verdict
//     EQUALS the verdict derived from them — clear iff severe == 0
//     AND warning == waived, blocked otherwise; those are the only
//     two verdict values the writer stores;
//   - the checker is on the record-time allowlist
//     (ALLOWED_CHECKERS) and the stored independenceBasis passes
//     the same two-half independence check record applies
//     (independenceBasisProblem against the checker label);
//   - with a project root, the cited report verifies the way
//     record's validateCrosscheckReport accepts it: <project>/
//     design/ itself resolves inside the project, the path is
//     project-relative and resolves lexically inside design/, the
//     file exists, is not a symlink, is a non-empty regular file,
//     and its real path resolves inside the real design/. (A
//     crosscheck line stores no report sha — there is no stored
//     hash to compare, so existence/containment/shape is the whole
//     on-disk half, exactly as at record time.)
// `project` may be null (runlog-check's line-local mode): the
// verdict derivation and the shape halves still apply; only the
// report half is skipped, because there is no project to resolve
// it against. Consumers keep their own SELECTION semantics (land:
// latest for the slice/round; prepare: latest for the round) —
// this function verifies the selected line, and a selected line
// that does not verify is refused, never skipped for an earlier
// one: falling back would let a genuine blocked verdict be buried
// under a later fake clear, which is the attack.
export function verifyCrosscheckLine(project, r) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  if (!r || r.kind !== 'crosscheck') {
    fail('the line is not a crosscheck line');
    return { ok: false, reasons };
  }
  // Round 7 (A7): the selection keys' TYPES are part of the writer's
  // shape too. run-log.mjs writes slice as a non-empty string or null
  // (a round-only record stores slice: null) and round as a positive
  // integer or null (a slice-only record stores round: null) — both
  // keys always present. Consumers select the verdict of record with
  // strict === (land: latest for the slice/round; prepare: latest
  // for the round), so a string-typed round ("1") is never SELECTED
  // — but before round 7 it passed this verifier and the checker,
  // leaving a line no consumer would act on standing as a clean
  // verdict. Anything outside the writer's two shapes per key is
  // not a line run-log.mjs writes.
  if (r.slice !== null && (typeof r.slice !== 'string' || !r.slice.trim())) {
    fail(`the crosscheck line's slice ${JSON.stringify(r.slice)} is not a non-empty string or null — run-log.mjs writes the slice id, or null for a round-only record`);
  }
  if (r.round !== null && (!Number.isInteger(r.round) || r.round < 1)) {
    fail(`the crosscheck line's round ${JSON.stringify(r.round)} is not a positive integer or null — run-log.mjs writes the round number, or null for a slice-only record, and consumers select on it with strict equality`);
  }
  const countsOk = [r.severe, r.warning, r.waived].every((n) => Number.isInteger(n) && n >= 0);
  if (!countsOk) {
    fail(`the crosscheck line's counts (severe ${JSON.stringify(r.severe)}, warning ${JSON.stringify(r.warning)}, waived ${JSON.stringify(r.waived)}) are not the non-negative integers run-log.mjs writes`);
  } else if (r.waived > r.warning) {
    fail(`the crosscheck line waives ${r.waived} of ${r.warning} warnings — run-log.mjs never writes waived greater than warning`);
  }
  if (r.verdict !== 'clear' && r.verdict !== 'blocked') {
    fail(`the crosscheck line's verdict ${JSON.stringify(r.verdict)} is not one of clear | blocked — the only verdicts run-log.mjs derives`);
  } else if (countsOk && r.waived <= r.warning) {
    const derived = (r.severe === 0 && r.warning === r.waived) ? 'clear' : 'blocked';
    if (r.verdict !== derived) {
      fail(`the crosscheck line's verdict "${r.verdict}" contradicts its own counts (SEVERE ${r.severe}, WARNING ${r.warning}, waived ${r.waived}) — run-log.mjs derives the verdict from the counts (clear iff severe == 0 and every warning is waived), which derives "${derived}" here, so this line was hand-appended or edited`);
    }
  }
  if (typeof r.checker !== 'string' || !ALLOWED_CHECKERS.includes(r.checker)) {
    fail(`the crosscheck line's checker ${JSON.stringify(r.checker)} is not an allowed independent cross-checker (${ALLOWED_CHECKERS.join(', ')}) — run-log.mjs records no other checker`);
  } else {
    const basisProblem = independenceBasisProblem(r.independenceBasis, r.checker);
    if (basisProblem) fail(`the crosscheck line's independence basis does not verify: ${basisProblem}`);
  }
  if (project) {
    const ctx = designContext(project);
    if (!ctx.inside(ctx.designReal, ctx.projectReal)) {
      fail(`<project>/design/ resolves outside the project (real path ${ctx.designReal}) — a design/ directory outside the project cannot hold a cross-check report`);
    } else if (typeof r.report !== 'string' || !r.report) {
      fail('the crosscheck line cites no report — run-log.mjs records a cross-check only behind a written report');
    } else if (path.isAbsolute(r.report)) {
      fail(`the crosscheck line's report ${r.report} is an absolute path — citations are project-relative, inside design/`);
    } else {
      const resolved = path.resolve(project, r.report);
      if (resolved !== ctx.designDir && !resolved.startsWith(ctx.designDir + path.sep)) {
        fail(`the crosscheck line's report ${r.report} resolves outside <project>/design/ ('..' escapes are rejected)`);
      } else {
        let lstat = null;
        try { lstat = fs.lstatSync(resolved); } catch { fail(`the crosscheck line's report ${r.report} does not exist — the cross-check report must be written before its verdict is recorded`); }
        if (lstat) {
          if (lstat.isSymbolicLink()) {
            fail(`the crosscheck line's report ${r.report} is a symlink — cross-check reports must be real files inside <project>/design/, not links to files elsewhere`);
          } else {
            let stat = null;
            try { stat = fs.statSync(resolved); } catch { stat = null; }
            if (!stat || !stat.isFile() || stat.size === 0) {
              fail(`the crosscheck line's report ${r.report} is empty or not a file`);
            } else {
              let real = null;
              try { real = fs.realpathSync(resolved); } catch { fail(`the crosscheck line's report ${r.report} cannot be resolved`); }
              if (real && !ctx.inside(real, ctx.designReal)) {
                fail(`the crosscheck line's report ${r.report} resolves outside <project>/design/ (real path ${real})`);
              }
            }
          }
        }
      }
    }
  }
  return { ok: reasons.length === 0, reasons };
}

// A stored TASTE-LOCK line, verified on read (round 7, F1). Before
// round 7 no read path verified a lock line at all: round-brief
// restated whichever stored line carried the highest lockVersion
// (references, tokens path and version adopted verbatim — a
// hand-appended line at version 99, its tokensHash copied from the
// real tokens.css so the brief's own mismatch warning stayed
// silent, became the lock every round brief restated), and the
// `lock` command's version-exists check counted every stored line,
// so one appended line could squat a version number forever. The
// on-disk half a lock line CAN carry is exactly one file — the
// tokens file it names — so verification is: lockVersion is a
// positive integer (the writer's shape); the tokens path is
// project-relative and resolves inside <project>/design/ to an
// existing, non-symlink regular file; and the file's sha256 NOW
// equals the stored tokensHash. Currency is the correct test for
// the lock of record (the LATEST lock line — the consumer-side
// selection in round-brief, the lock command's occupation check
// and runlog-check all consult this one function): a lock whose
// tokens file has since changed is stale by definition — the lock
// no longer matches the file it locked — while OLDER lock lines
// are history and are not held to currency (a re-lock legitimately
// supersedes them; their files may since have moved on). What this
// cannot distinguish — stated in D15 as an explicit extension of
// the authorship residual — is a hand-appended line that DOES
// verify: one naming the real tokens file (or another real file
// the writer of the line placed inside design/) with its true
// current hash. A lock has no second artifact to bind to, so such
// a line is internally consistent in exactly the way a genuine
// lock line is; the residual is the lock channel's instance of
// the from-scratch forgery the D15 entry already names.
export function verifyLockLine(project, r) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  if (!r || r.kind !== 'taste-lock') {
    fail('the line is not a taste-lock line');
    return { ok: false, reasons };
  }
  if (!Number.isInteger(r.lockVersion) || r.lockVersion < 1) {
    fail(`the lock line's lockVersion ${JSON.stringify(r.lockVersion)} is not a positive integer — run-log.mjs writes lock versions as positive integers`);
  }
  if (typeof r.tokens !== 'string' || !r.tokens) {
    fail('the lock line names no tokens file — run-log.mjs records a lock only behind a --tokens path');
  } else if (path.isAbsolute(r.tokens)) {
    fail(`the lock line's tokens path ${r.tokens} is an absolute path — lock tokens are project-relative, inside design/`);
  } else if (typeof r.tokensHash !== 'string' || !/^[0-9a-f]{64}$/i.test(r.tokensHash)) {
    fail('the lock line carries no valid tokensHash (exactly 64 hex) — without the tokens file\'s stored hash there is nothing to verify the lock against');
  } else {
    const ctx = designContext(project);
    const resolved = path.resolve(project, r.tokens);
    let lstat = null;
    try { lstat = fs.lstatSync(resolved); } catch { fail(`the lock line's tokens file ${r.tokens} does not exist — the locked tokens must be on disk for the lock to verify`); }
    if (lstat) {
      if (lstat.isSymbolicLink()) {
        fail(`the lock line's tokens file ${r.tokens} is a symlink — locked tokens must be a real file inside <project>/design/, not a link`);
      } else {
        let stat = null;
        try { stat = fs.statSync(resolved); } catch { stat = null; }
        if (!stat || !stat.isFile()) {
          fail(`the lock line's tokens file ${r.tokens} is not a file`);
        } else {
          let real = null;
          try { real = fs.realpathSync(resolved); } catch { fail(`the lock line's tokens file ${r.tokens} cannot be resolved`); }
          if (real) {
            if (!ctx.inside(real, ctx.designReal)) {
              fail(`the lock line's tokens file ${r.tokens} resolves outside <project>/design/ (real path ${real})`);
            } else {
              const sha = sha256File(real);
              if (sha !== r.tokensHash.toLowerCase()) {
                fail(`the locked tokens file ${r.tokens} now hashes to ${(sha || 'unreadable').slice(0, 12)}…, not the lock's stored tokensHash ${r.tokensHash.slice(0, 12)}… — the tokens moved after this lock was recorded, so the lock is stale`);
              }
            }
          }
        }
      }
    }
  }
  return { ok: reasons.length === 0, reasons };
}

// One cited report file's existence/containment half, in the shape
// verifyCrosscheckLine's report half accepts at record time
// (lexical containment inside <project>/design/, exists, not a
// symlink, a non-empty regular file, real path inside the real
// design/). Returns a reason string, or null when the file stands.
// `label` names the citing field in messages.
function citedReportProblem(project, ctx, rel, label) {
  if (path.isAbsolute(rel)) {
    return `the ${label} ${rel} is an absolute path — citations are project-relative, inside design/`;
  }
  const resolved = path.resolve(project, rel);
  if (resolved !== ctx.designDir && !resolved.startsWith(ctx.designDir + path.sep)) {
    return `the ${label} ${rel} resolves outside <project>/design/ ('..' escapes are rejected)`;
  }
  let lstat = null;
  try { lstat = fs.lstatSync(resolved); } catch { return `the ${label} ${rel} does not exist — the report must be written before it is cited`; }
  if (lstat.isSymbolicLink()) {
    return `the ${label} ${rel} is a symlink — reports must be real files inside <project>/design/, not links to files elsewhere`;
  }
  let stat = null;
  try { stat = fs.statSync(resolved); } catch { stat = null; }
  if (!stat || !stat.isFile() || stat.size === 0) {
    return `the ${label} ${rel} is empty or not a file`;
  }
  let real = null;
  try { real = fs.realpathSync(resolved); } catch { return `the ${label} ${rel} cannot be resolved`; }
  if (real && !ctx.inside(real, ctx.designReal)) {
    return `the ${label} ${rel} resolves outside <project>/design/ (real path ${real})`;
  }
  return null;
}

// One cited gate leg's EXISTENCE + SHAPE on read, for a HISTORICAL
// line (round 8, C4): the citation is a non-empty project-relative
// path resolving lexically inside <project>/design/, the stored
// sha is exactly 64 hex, and the file exists as a regular file.
// No currency (no sha comparison, no verdict markers, no symlink
// rule): the canonical leg files rotate with every gate run, so a
// rotated historical citation cannot be held to the bytes it
// named. Returns a reason string, or null when the citation
// stands as shape.
function citedLegShapeProblem(project, ctx, r, leg) {
  const rel = leg === 'leg1' ? r.gateLeg1 : r.gateLeg2;
  const sha = leg === 'leg1' ? r.gateLeg1Sha : r.gateLeg2Sha;
  const n = leg === 'leg1' ? '1' : '2';
  if (typeof rel !== 'string' || !rel) return `the line cites no gate leg ${n} — run-log.mjs records a land only behind both leg artifacts`;
  if (typeof sha !== 'string' || !/^[0-9a-f]{64}$/i.test(sha)) return `the line's gate leg ${n} sha is not exactly 64 hex — not a sha run-log.mjs stores`;
  if (path.isAbsolute(rel)) return `the line's gate leg ${n} citation ${rel} is an absolute path — citations are project-relative, inside design/`;
  const resolved = path.resolve(project, rel);
  if (resolved !== ctx.designDir && !resolved.startsWith(ctx.designDir + path.sep)) return `the line's gate leg ${n} citation ${rel} resolves outside <project>/design/ ('..' escapes are rejected)`;
  let stat = null;
  try { stat = fs.statSync(resolved); } catch { return `the line's gate leg ${n} citation ${rel} does not exist`; }
  if (!stat.isFile()) return `the line's gate leg ${n} citation ${rel} is not a file`;
  return null;
}

// A stored LAND line, verified on read (round 7, F2; round 8, C4 —
// the EPOCH split). Before round 7 no consumer verified a stored
// land line: `show` printed it as fact ("LAND (slice ghost,
// round 7): gate: pass … cross-check: clear") and the checker
// never looked at one, so a hand-appended land line stood as a
// shipment that never happened. (The `land` command itself never
// trusted stored land lines — it re-derives its preconditions
// before writing a new one — so this verifier's consumer is
// runlog-check, the tripwire.) A land line verifies only when its
// preconditions verify, checked with the same shared halves land
// itself applies before recording: the gate is "pass" (the only
// value the writer stores); the cited cross-check report exists
// inside design/ (citedReportProblem — the same acceptance
// verifyCrosscheckLine applies to a crosscheck line's report);
// and a round record for the land's round exists IN THE SAME LOG
// that counts toward land's own precondition; a land line with no
// round recorded (a null round) accepts any round record in the
// log, mirroring the land command's precondition when --round is
// omitted. `rows` is the log's parsed lines; the land line itself
// may be among them (it is not a round line, so it never counts
// toward its own precondition).
//
// Round 8 (C4) split WHICH leg standard applies by epoch,
// selected by the caller's { current } flag (the checker then
// passed current: true only for the LATEST land line in the
// log). The CURRENT reading: the line's cited gate legs verify
// on disk against their stored shas with a PASS verdict
// (verifyCitedLegOnRead) as two distinct files, and its round
// half follows the land command's live precondition — a graded
// record counting only with leg currency
// (isVerifiedGradedRound + verifyLegCitationsCurrent) or a
// genuine no-grade record (isGenuineNoGradeRound). The
// NON-CURRENT reading treats the line as rotated history: its
// legs are checked for existence + shape only
// (citedLegShapeProblem — its stored shas named bytes the next
// gate run legitimately overwrote), and its round half accepts
// a graded record verifying through its judge ARTIFACT
// (isVerifiedGradedRound) or a genuine-SHAPED no-grade line
// (isNoGradeShape) — no leg currency anywhere.
// LIVE PROOF ROUND 2 (the deadlock adjudication): the checker
// now passes current: false for EVERY land line — currency
// belongs to the live operations (the land command enforces it
// in its own precondition in run-log.mjs and never calls this
// verifier), and a checker holding the still-latest land line
// to currency deadlocks the loop through gate.sh §1.1's fold-in
// of the checker (see the verifyLegCitationsCurrent comment).
// The current reading remains the default for callers that omit
// the flag — fail closed on an unknown epoch.
export function verifyLandLine(project, rows, r, opts) {
  const reasons = [];
  const fail = (m) => { reasons.push(m); };
  if (!r || r.kind !== 'land') {
    fail('the line is not a land line');
    return { ok: false, reasons };
  }
  const current = !opts || opts.current !== false;
  if (r.gate !== 'pass') {
    fail(`the land line's gate is ${JSON.stringify(r.gate)}, not "pass" — run-log.mjs records a land only on --gate pass`);
  }
  if (current) {
    const leg1 = verifyCitedLegOnRead(project, r, 'leg1');
    const leg2 = verifyCitedLegOnRead(project, r, 'leg2');
    if (!leg1) fail(`the land line's gate leg 1 citation (${typeof r.gateLeg1 === 'string' ? r.gateLeg1 : 'none recorded'}) does not verify on disk against its stored sha with a PASS verdict`);
    if (!leg2) fail(`the land line's gate leg 2 citation (${typeof r.gateLeg2 === 'string' ? r.gateLeg2 : 'none recorded'}) does not verify on disk against its stored sha with a PASS verdict`);
    if (leg1 && leg2 && (leg1.real === leg2.real || (leg1.stat.dev === leg2.stat.dev && leg1.stat.ino === leg2.stat.ino))) {
      fail('the land line\'s two cited gate legs are the same file — a gate pass stands behind two distinct leg artifacts');
    }
  } else {
    const ctx = designContext(project);
    const p1 = citedLegShapeProblem(project, ctx, r, 'leg1');
    const p2 = citedLegShapeProblem(project, ctx, r, 'leg2');
    if (p1) fail(p1);
    if (p2) fail(p2);
    if (!p1 && !p2 && path.resolve(project, r.gateLeg1) === path.resolve(project, r.gateLeg2)) {
      fail('the land line\'s two cited gate legs are the same path — a gate pass stands behind two distinct leg artifacts');
    }
  }
  if (typeof r.crosscheckReport !== 'string' || !r.crosscheckReport) {
    fail('the land line cites no cross-check report — run-log.mjs records a land only behind the cross-check verdict\'s report');
  } else {
    const ctx = designContext(project);
    if (!ctx.inside(ctx.designReal, ctx.projectReal)) {
      fail(`<project>/design/ resolves outside the project (real path ${ctx.designReal}) — a design/ directory outside the project cannot hold a cross-check report`);
    } else {
      const problem = citedReportProblem(project, ctx, r.crosscheckReport, 'land line\'s cross-check report');
      if (problem) fail(problem);
    }
  }
  const roundCounts = current
    ? (x) => (isVerifiedGradedRound(project, x) && verifyLegCitationsCurrent(project, x).ok) || isGenuineNoGradeRound(project, x)
    : (x) => isVerifiedGradedRound(project, x) || isNoGradeShape(x);
  const roundRecs = (Array.isArray(rows) ? rows : []).filter((x) => x && x.kind === 'round'
    && (r.round === null || r.round === undefined ? true : x.round === r.round)
    && roundCounts(x));
  if (!roundRecs.length) {
    fail(`no verified graded or genuine no-grade round record${r.round === null || r.round === undefined ? '' : ` for round ${JSON.stringify(r.round)}`} exists in the same log — the land's round precondition does not verify`);
  }
  return { ok: reasons.length === 0, reasons };
}

// ---------------------------------------------------------------------
// prepare (the CLI — everything below runs only when invoked directly)
// ---------------------------------------------------------------------

function usage(msg) {
  if (msg) console.error(`judge-report: ${msg}`);
  console.error('usage: node judge-report.mjs --project <dir> prepare --round N --kind <absolute|cheap|pairwise|jury|regrade|expert-motion|expert-ux> --grader <judge-subagent|muse-manager|other-model> [--index <1|2|3>] [--family <name>] --brief-type <landing|dashboard/app|redesign> --mode <full|cheap> --page <built.html> [--manifest <crop manifest.json>] [--shots <a,b,...>] [--shots-a <...>] [--shots-b <...>] [--locked-refs "<refs>"] [--not-regraded "<#a,#b>"] [--out <path>]');
  process.exit(1);
}

function refuse(msg) {
  console.error(`judge-report: REFUSED — ${msg} No file written.`);
  process.exit(2);
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const val = argv[i + 1];
      if (val === undefined) usage(`--${key} needs a value`);
      out[key] = val;
      i++;
    } else out._.push(a);
  }
  return out;
}

const GATE_LEG_MARKERS = { leg1: 'GATE RESULT: PASS', leg2: '===== gate verdict: GREEN =====' };
const GATE_LEG_FAIL_MARKERS = { leg1: 'GATE RESULT: FAIL', leg2: 'gate verdict: FAIL' };

// The gate bit, derived — never asserted: both canonical leg artifacts
// must exist under design/, carry their PASS verdict line (and no FAIL
// verdict, per-line with the R4 word boundary, canonicalised by
// stripInvisible — the same checks validateGateArtifacts applies), and
// be at least as new as the page they claim to cover.
//
// QC round (F2): prepare applies the SAME leg checks record-time
// validateGateArtifacts applies, as far as they are checkable here —
// a skeleton must never be stamped for legs a record would refuse:
// symlink rejection (lstat), realpath containment inside design/,
// regular non-empty files, device+inode distinctness (legs against
// each other, the page and tokens.css — a hardlink pair is one file
// cited twice), and the freshness chain tokens <= legs as well as
// page <= legs. The checks are COPIED, not imported: run-log.mjs runs
// its CLI at top level and itself imports this module, so importing it
// from here would be circular and would execute the CLI. The one
// record-time check family with no prepare-time analogue is the
// validation of CALLER-CITED leg paths (record accepts --gate-leg1 /
// --gate-leg2 pointing anywhere inside design/; prepare derives the
// bit from the two canonical files only) — record still re-validates
// whichever artifacts the record actually cites, so nothing stamped
// here bypasses that.
function deriveGateGreen(project, binding) {
  const { pageStat, pageReal, tokensStat, tokensReal } = binding;
  const designDir = path.join(project, 'design');
  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { designReal = path.join(projectReal, 'design'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  const sameFile = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino;
  const legStats = [];
  for (const [leg, file, marker, failMarker] of [
    ['leg1', 'gate-leg1.log', GATE_LEG_MARKERS.leg1, GATE_LEG_FAIL_MARKERS.leg1],
    ['leg2', 'gate-leg2.log', GATE_LEG_MARKERS.leg2, GATE_LEG_FAIL_MARKERS.leg2],
  ]) {
    const p = path.join(designDir, file);
    let lstat;
    try { lstat = fs.lstatSync(p); } catch { return `design/${file} does not exist — the gate leg has not run (or its output was not saved); a judge is spawned only on a green gate`; }
    if (lstat.isSymbolicLink()) return `design/${file} is a symlink — gate artifacts must be real files inside design/, not links to files elsewhere; the gate bit cannot be derived`;
    let stat;
    try { stat = fs.statSync(p); } catch { return `design/${file} does not exist — the gate bit cannot be derived`; }
    if (!stat.isFile() || stat.size === 0) return `design/${file} is empty or not a file — the gate bit cannot be derived`;
    let real;
    try { real = fs.realpathSync(p); } catch { return `design/${file} cannot be resolved — the gate bit cannot be derived`; }
    if (!inside(real, designReal)) return `design/${file} resolves outside design/ (real path ${real}) — a link or mount escaping design/ cannot back the gate bit`;
    // Distinctness (D13 F4 pattern): a leg that IS the page, the tokens
    // file, or the other leg (same realpath, or same device+inode — a
    // hardlink) is one file cited as two, not a gate artifact.
    if (real === pageReal || sameFile(stat, pageStat)) return `design/${file} is the same file as the page it claims to cover — a gate artifact cannot be its own subject`;
    if (real === tokensReal || sameFile(stat, tokensStat)) return `design/${file} is the same file as design/tokens.css — a gate artifact must be its own file`;
    for (const other of legStats) {
      if (real === other.real || sameFile(stat, other.stat)) return `design/${file} is the same file as design/${other.file} (same device+inode — a hardlink pair) — the two gate legs must be two separate artifact files`;
    }
    legStats.push({ real, stat, file });
    const text = fs.readFileSync(p, 'utf8');
    const hasFail = text.split('\n').some((line) => {
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
    if (hasFail) return `design/${file} carries its leg's FAIL verdict — the gate is not green on this build`;
    if (!text.split('\n').some((line) => stripInvisible(line) === stripInvisible(marker))) return `design/${file} has no PASS verdict line ("${marker}") — the gate bit cannot be derived`;
    if (stat.mtimeMs < pageStat.mtimeMs) return `design/${file} is older than the page — a stale gate artifact is a claim about a different build`;
    if (stat.mtimeMs < tokensStat.mtimeMs) return `design/${file} is older than design/tokens.css — a stale gate artifact is a claim about a different build`;
    void leg;
  }
  return null;
}

// The cross-check bit, derived from the run log: the LATEST crosscheck
// record for this round must be verdict clear (a blocked verdict after
// a clear one supersedes it — the same read `land` makes). Round 6
// (X1): the latest record must also VERIFY (verifyCrosscheckLine —
// verdict re-derived from its counts, allowed checker, independence
// basis, cited report on disk). Before round 6 this read trusted the
// stored verdict, so a hand-appended "clear" line over a genuine
// blocked record stamped skeletons `cross-check: clear`.
function deriveCrosscheckClear(project, round) {
  const logFile = path.join(project, 'design', 'run-log.jsonl');
  if (!fs.existsSync(logFile)) return 'design/run-log.jsonl does not exist — no cross-check verdict has been recorded for this round';
  let rows;
  try {
    rows = fs.readFileSync(logFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  } catch (e) {
    return `design/run-log.jsonl cannot be parsed (${e.message}) — the cross-check bit cannot be derived`;
  }
  const checks = rows.filter((r) => r.kind === 'crosscheck' && r.round === round);
  const latest = checks[checks.length - 1];
  if (!latest) return `no cross-check record for round ${round} in the run log — record it (run-log.mjs crosscheck) before preparing a judge report`;
  const ccv = verifyCrosscheckLine(project, latest);
  if (!ccv.ok) return `the latest cross-check record for round ${round} does not verify (${ccv.reasons.join('; ')}) — the cross-check bit cannot be derived from an unverifiable record`;
  if (latest.verdict !== 'clear') return `the latest cross-check verdict for round ${round} is ${String(latest.verdict).toUpperCase()} — a judge is spawned only on a clear cross-check`;
  return null;
}

function canonicalOut(round, kind, index) {
  switch (kind) {
    case 'absolute': return `design/judge/round-${round}.md`;
    case 'cheap': return `design/judge/round-${round}-cheap.md`;
    case 'pairwise': return `design/judge/round-${round}-pairwise-${index}.md`;
    case 'jury': return `design/judge/round-${round}-jury-${index}.md`;
    case 'regrade': return `design/judge/round-${round}-regrade.md`;
    case 'expert-motion': return `design/judge/round-${round}-expert-motion.md`;
    case 'expert-ux': return `design/judge/round-${round}-expert-ux.md`;
    default: return null;
  }
}

function prepare(project, args) {
  const round = Number(args.round);
  if (!Number.isInteger(round) || round < 1) usage('--round must be a positive integer');
  const kind = args.kind;
  if (!JUDGE_KINDS.includes(kind)) usage(`--kind must be one of ${JUDGE_KINDS.join(' | ')}`);
  const grader = (args.grader || '').trim();
  const expertLabel = kind === 'expert-motion' ? 'motion-expert' : kind === 'expert-ux' ? 'ux-expert' : null;
  if (expertLabel) {
    if (grader && grader !== expertLabel) usage(`--kind ${kind} is stamped by the ${expertLabel}; --grader must be ${expertLabel} or omitted`);
  } else if (!ALLOWED_GRADERS.includes(grader)) {
    usage(`--grader must be one of ${ALLOWED_GRADERS.join(' | ')}`);
  }
  const headerGrader = expertLabel || grader;
  let index = null;
  if (kind === 'pairwise' || kind === 'jury') {
    index = Number(args.index);
    const max = kind === 'pairwise' ? 2 : 3;
    if (!Number.isInteger(index) || index < 1 || index > max) usage(`--kind ${kind} needs --index <1..${max}> (one report file per judge call)`);
  } else if (args.index !== undefined) {
    usage(`--index applies only to --kind pairwise / jury`);
  }
  const briefType = args['brief-type'];
  if (!['landing', 'dashboard/app', 'redesign'].includes(briefType)) usage('--brief-type must be landing | dashboard/app | redesign');
  const mode = args.mode;
  if (!['full', 'cheap'].includes(mode)) usage('--mode must be full | cheap');
  if (!args.page) usage('--page <built.html> is required (the built page this report binds to)');

  const projectReal = (() => { try { return fs.realpathSync(project); } catch { return path.resolve(project); } })();
  const designDir = path.resolve(project, 'design');
  let designReal;
  try { designReal = fs.realpathSync(designDir); } catch { refuse('<project>/design/ does not exist — set up the project (step 0) before preparing a judge report.'); }
  const inside = (realPath, realDir) => realPath === realDir || realPath.startsWith(realDir + path.sep);
  if (!inside(designReal, projectReal)) refuse('<project>/design/ resolves outside the project — its files cannot bind a judge report.');

  // The page, under the same rules run-log.mjs applies at record time
  // (D13 F3/R2/R3): a real, non-symlink .html file inside design/ (or
  // design/tokens.css itself), at least as new as tokens.css.
  const tokensPath = path.join(designDir, 'tokens.css');
  let tokensStat; let tokensLstat;
  try { tokensStat = fs.statSync(tokensPath); tokensLstat = fs.lstatSync(tokensPath); } catch { refuse('design/tokens.css does not exist — there is no locked build to grade.'); }
  if (tokensLstat.isSymbolicLink() || !tokensStat.isFile()) refuse('design/tokens.css is a symlink or not a regular file — the binding anchor must be the real tokens file.');
  const tokensSha = sha256File(tokensPath);
  const pageGiven = args.page;
  if (path.isAbsolute(pageGiven)) refuse('--page must be a path relative to the project, inside design/ — absolute paths are rejected.');
  // M2 (D13 edge cases, same rules as run-log.mjs record time): no "."
  // or ".." segments in the raw spelling (a ".." that cancels out is
  // invisible after resolve), and the basename needs a real stem before
  // a single ".html" suffix — "..html" and "x.html.html" are refused.
  if (String(pageGiven).split(/[\\/]/).some((s) => s === '.' || s === '..')) refuse(`--page ${pageGiven} must be a plain project-relative path inside <project>/design/ — "." and ".." segments are rejected.`);
  const pageResolved = path.resolve(project, pageGiven);
  let pageLstat;
  try { pageLstat = fs.lstatSync(pageResolved); } catch { refuse(`--page file does not exist: ${pageGiven}.`); }
  if (pageLstat.isSymbolicLink()) refuse(`--page file ${pageGiven} is a symlink — the built page must be a real file inside the project.`);
  const pageReal = fs.realpathSync(pageResolved);
  if (!inside(pageReal, projectReal)) refuse(`--page must resolve inside the project (got "${pageGiven}").`);
  const pageStat = fs.statSync(pageReal);
  if (!pageStat.isFile()) refuse(`--page must be a regular file (got "${pageGiven}").`);
  const isTokensRef = pageResolved === tokensPath;
  if (!isTokensRef) {
    if (!inside(pageReal, designReal)) refuse(`--page ${pageGiven} must resolve inside <project>/design/ — the graded page lives there.`);
    const pageBase = path.basename(pageReal);
    const pageStem = pageBase.slice(0, -5);
    if (!pageBase.toLowerCase().endsWith('.html') || !/[^.]/.test(pageStem) || pageStem.toLowerCase().endsWith('.html')) refuse(`--page ${pageGiven} must be an .html file inside <project>/design/.`);
  }
  if (pageStat.mtimeMs < tokensStat.mtimeMs) refuse(`--page ${pageGiven} is older than design/tokens.css — a page older than the locked tokens is a different build. Rebuild first.`);
  const pageRel = path.relative(projectReal, pageReal);
  const pageSha = sha256File(pageReal);

  // The screenshot set this report binds to. Red-team round (prepare
  // containment): every shot — explicit --shots / --shots-a / --shots-b
  // or derived (canonical set, crop manifest) — gets the record-side
  // containment rules BEFORE it is stamped into the header: no symlink
  // as the final component, and the real path must resolve inside the
  // project. A skeleton must never be stamped binding the report to
  // pixels outside the project or behind a link.
  const hashShots = (rels, fieldLabel) => rels.map((rel) => {
    if (path.isAbsolute(rel)) refuse(`--${fieldLabel} entries must be project-relative paths (got "${rel}").`);
    const resolved = path.resolve(project, rel);
    let lst;
    try { lst = fs.lstatSync(resolved); } catch { refuse(`screenshot does not exist: ${rel} (the judge grades the screenshots on disk — capture them first).`); }
    if (lst.isSymbolicLink()) refuse(`screenshot ${rel} is a symlink — screenshots must be real files inside the project, not links to files elsewhere.`);
    let st;
    try { st = fs.statSync(resolved); } catch { refuse(`screenshot does not exist: ${rel} (the judge grades the screenshots on disk — capture them first).`); }
    if (!st.isFile() || st.size === 0) refuse(`screenshot is empty or not a file: ${rel}.`);
    const real = fs.realpathSync(resolved);
    if (!inside(real, projectReal)) refuse(`screenshot ${rel} resolves outside the project (real path ${real}) — a judge report binds only to this project's screenshots.`);
    return { path: path.relative(projectReal, real), sha256: sha256File(resolved) };
  });
  const shotListValue = (shots) => shots.map((s) => `${s.path}=sha256:${s.sha256}`).join(', ');
  let screenshotsValue = '-';
  let shotsAValue = '-';
  let shotsBValue = '-';
  if (kind === 'pairwise') {
    if (!args['shots-a'] || !args['shots-b']) usage('--kind pairwise needs --shots-a <list> and --shots-b <list> (the two versions, labelled A/B)');
    shotsAValue = shotListValue(hashShots(args['shots-a'].split(',').map((s) => s.trim()).filter(Boolean), 'shots-a'));
    shotsBValue = shotListValue(hashShots(args['shots-b'].split(',').map((s) => s.trim()).filter(Boolean), 'shots-b'));
  } else {
    let shotRels;
    if (args.shots) {
      shotRels = args.shots.split(',').map((s) => s.trim()).filter(Boolean);
    } else if (mode === 'cheap') {
      if (!args.manifest) usage('--mode cheap needs --manifest <crop manifest.json> (the crop-sections.mjs input manifest) or an explicit --shots list');
      const manifestPath = path.resolve(project, args.manifest);
      let manifest;
      try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); } catch (e) { refuse(`--manifest cannot be read/parsed: ${args.manifest} (${e.message}).`); }
      const manifestDir = path.dirname(manifestPath);
      const files = [];
      if (manifest.full390 && manifest.full390.file) files.push(path.join(manifestDir, manifest.full390.file));
      for (const c of manifest.changedSections || []) if (c.file) files.push(path.join(manifestDir, c.file));
      if (!files.length) refuse(`--manifest ${args.manifest} lists no captured shots (full390 / changedSections files) — a dry-run manifest cannot bind a judge report.`);
      shotRels = files.map((f) => path.relative(project, f));
    } else {
      shotRels = ['design/screenshots/1440.png', 'design/screenshots/768.png', 'design/screenshots/390.png'];
    }
    if (!shotRels.length) usage('the screenshot set is empty — a judge report must bind to at least one screenshot');
    screenshotsValue = shotListValue(hashShots(shotRels, 'shots'));
  }

  // The two precondition bits, derived — a prepare that cannot verify
  // them writes nothing (the judge is spawned only on a green gate AND
  // a clear cross-check; D8 pre-filter).
  const gateProblem = deriveGateGreen(project, { pageStat, pageReal, tokensStat, tokensReal: fs.realpathSync(tokensPath) });
  if (gateProblem) refuse(gateProblem);
  const ccProblem = deriveCrosscheckClear(project, round);
  if (ccProblem) refuse(ccProblem);

  // Output path: canonical for the kind, or an explicit --out (still
  // inside design/judge/). NEVER overwrite: one file, one judge call.
  const outRel = args.out || canonicalOut(round, kind, index);
  if (path.isAbsolute(outRel)) refuse('--out must be a path relative to the project, inside design/judge/.');
  const outResolved = path.resolve(project, outRel);
  const judgeDir = path.join(designDir, 'judge');
  if (outResolved !== judgeDir && !outResolved.startsWith(judgeDir + path.sep)) refuse(`--out must resolve inside <project>/design/judge/ (got "${outRel}").`);
  // Red-team round (prepare containment): the lexical check above is
  // not containment — design/judge (or a parent component of an
  // explicit --out) can be a SYMLINK pointing outside the project, in
  // which case the skeleton would be written outside while claiming a
  // design/judge/ path. Create the parent, then require its REAL path
  // to resolve inside the project before anything is written.
  fs.mkdirSync(path.dirname(outResolved), { recursive: true });
  let parentReal;
  try { parentReal = fs.realpathSync(path.dirname(outResolved)); } catch { refuse(`--out parent directory cannot be resolved: ${outRel}.`); }
  if (!inside(parentReal, projectReal)) refuse(`--out ${outRel} has a real parent directory outside the project (real path ${parentReal}) — design/judge resolving outside the project cannot hold judge reports.`);
  let outLstat = null;
  try { outLstat = fs.lstatSync(outResolved); } catch { /* absent: the normal case */ }
  if (outLstat || fs.existsSync(outResolved)) refuse(`the report file already exists: ${outRel} — one report file is one judge call; a new judge call gets a new round/kind/index, never an overwrite.`);

  const header = [
    JUDGE_REPORT_MAGIC,
    '---',
    `round: ${round}`,
    `kind: ${kind}`,
    `grader: ${headerGrader}`,
    'basis:',
    `family: ${kind === 'jury' ? (args.family || '-') : '-'}`,
    'gate: green',
    'cross-check: clear',
    `brief-type: ${briefType}`,
    `mode: ${mode}`,
    `page: ${pageRel}`,
    `page-sha256: ${pageSha}`,
    `tokens-sha256: ${tokensSha}`,
    `screenshots: ${screenshotsValue}`,
    `shots-a: ${shotsAValue}`,
    `shots-b: ${shotsBValue}`,
    `locked-refs: ${args['locked-refs'] || '-'}`,
    `not-regraded: ${args['not-regraded'] || '-'}`,
    `stamped: ${new Date().toISOString()}`,
    '---',
    '',
  ];
  let body;
  if (kind === 'pairwise') {
    body = [
      'PENDING — pairwise judge has not returned a verdict yet.',
      'Defects in A: ?',
      'Defects in B: ?',
      'Pairwise: keep ? — ?',
      'Gate: green',
      'Cross-check: clear',
      '',
    ];
  } else if (expertLabel) {
    const domain = kind === 'expert-motion' ? 'Motion' : 'UX';
    body = [
      `PENDING — ${expertLabel} has not returned a verdict yet.`,
      `${domain}: ? (${expertLabel}) — ?`,
      '',
    ];
  } else {
    body = [
      'PENDING — judge has not graded yet.',
      `Round ${round} — grader: ${headerGrader} (?)`,
      '| Axis | Evidence (one line, observable, citing the reference) | Score |',
      '|---|---|---|',
      '| Type | ? | ? |',
      '| Layout | ? | ? |',
      '| Colour | ? | ? |',
      '| Space | ? | ? |',
      'Gate: green',
      'Cross-check: clear',
      'Fix order: ?',
      '',
    ];
  }
  fs.mkdirSync(judgeDir, { recursive: true });
  fs.writeFileSync(outResolved, header.concat(body).join('\n'), { flag: 'wx' });
  console.log(`judge-report: prepared ${outRel} (kind: ${kind}; round: ${round}; grader: ${headerGrader}; page: ${pageRel} sha256 ${pageSha.slice(0, 12)}…; gate: green and cross-check: clear derived from the project's gate artifacts + run log). The judge fills basis, evidence, scores and the Fix order IN THIS FILE — an unfilled skeleton cannot be recorded.`);
}

const invokedDirectly =
  process.argv[1] != null && process.argv[1].endsWith('judge-report.mjs');
if (invokedDirectly) {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0];
  if (!args.project) usage('--project <dir> is required');
  if (cmd !== 'prepare') usage(`unknown command "${cmd || ''}" (prepare)`);
  prepare(args.project, args);
}
