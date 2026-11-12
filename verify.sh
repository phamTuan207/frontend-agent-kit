#!/usr/bin/env bash
# frontend-agent-kit — verifier v2.
#
# Verifies the LOOP, not just files (phase-1 research/SYNTHESIS.md §3.1, §6 A10/A7/A3 — workspace research note, not shipped in this repo):
#   1. every expected skill present in every installed host's skills dir,
#      with frontmatter name == directory name (catches double-nesting);
#   2. no stale ${CLAUDE_PLUGIN_ROOT} paths in installed skills (A3);
#   2b. installed Impeccable SKILL.md has no unresolved {{placeholders}}
#       and no top-level `version:` (spec-pure frontmatter — the generator
#       guarantees both; verify re-checks the installed copy);
#   2c. taste pipeline paths resolve from the installed wrapper;
#   2d. no live builder-self-grade language in installed skills
#       (prohibiting/overridden mentions allowlisted — see §2d);
#   3. Impeccable skill<->engine LOCKSTEP (A10): the installed engine's
#      reported version must equal the vendored scripts/VERSION exactly.
#      A mismatch FAILS LOUDLY — the 62-rule registry lives in the engine,
#      so a wrong engine silently applies the wrong registry;
#   3b. Vendored-allowlist manifest vs taste tree (GAP-9, D9): the
#      skills/frontend-kit/scripts/gate/vendored-allowlist.txt pin header must equal the
#      SOURCES.md taste pin, every entry's sha256 must equal the vendored
#      tree file's, and the key set must equal the tree's recomputed
#      runtime sink-file set. A mismatch FAILS LOUDLY — a stale manifest
#      must never ship as if it were current;
#   4. `impeccable detect` runs on a clean fixture;
#   5. the deterministic gate (skills/frontend-kit/scripts/gate/gate.sh) runs on the fixture;
#   6. Playwright eyes: `playwright-cli --help`, serve over http (never
#      file://), screenshot at 390px, console clean — retried up to 3x
#      with per-attempt logs kept (Q-1 redo: the old single attempt
#      failed ~1 in 3 runs with its diagnostic discarded). Skipped at
#      install (--skip-eyes, recorded in skipped-subsystems.txt) →
#      PENDING, step not run (W-FIX-SKIP 2026-11-10: a skipped eyes step
#      is not a broken loop); when NOT skipped, a missing/failing
#      browser still FAILs — the skip check changes nothing there.
#   7. Pro Max search smoke test (v1 behaviour kept).
#   8. hook / MCP presence (H5/H6): skipped subsystems recorded by
#      install.sh are reported PENDING; the host's actual config is read
#      back for the Playwright MCP and the Impeccable hook — never silent,
#      never an OK for a subsystem that is not there.
#   9. Node 22+ (single required version, H14) and system-Chrome presence
#      (warn with the degradation when absent).
#
# Exit codes: 0 = the loop is PROVEN (every step ran and passed).
# 1 = a hard check failed, OR a loop step is UNVERIFIED (engine missing,
# detect unrunnable, gate's detect step skipped, playwright missing).
# Default mode used to warn those away and print RESULT: OK — a false
# pass (F3, fixed 2026-11-10): a run that never proved the loop said OK.
# Now an unverified loop step FAILS the run with RESULT: UNVERIFIED.
# --strict is kept for compatibility (it used to be the only mode that
# failed on a missing engine/playwright); default and --strict now agree
# on loop steps. A PRESENT-but-wrong engine, a present-but-failing
# screenshot, or a missing skill is ALWAYS a hard FAIL.
# Warnings remain for non-loop items only (copilot fallback copy, stale
# paths in reference data, Pro Max smoke, console probe).
# The "4x fewer tokens, ~27k vs ~114k" Playwright figure is CLAIMED (not in
# Microsoft's README) and is never cited here.
#
# Usage: ./verify.sh [--strict] [--hosts=H1,H2] [--help]
set -uo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
user_home="${HOME:?HOME must be set}"
state_dir="$user_home/.local/share/frontend-agent-kit"
refs_dir="$user_home/.local/share/agent-design-references"

strict=0
hosts_filter=""
for arg in "$@"; do
  case "$arg" in
    --help|-h) printf 'Usage: ./verify.sh [--strict] [--hosts=H1,H2]\n  --strict  (kept for compatibility) missing engine / missing playwright-cli fails; default mode already fails on any unverified loop step.\n'; exit 0 ;;
    --strict) strict=1 ;;
    --hosts=*) hosts_filter="${arg#--hosts=}" ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

fails=0
warns=0
unverified=0
# OS note (macOS phase, D12): Linux and macOS are both supported — no hard
# OS gate here (install.sh is the gate). On macOS, report the known gaps
# up front instead of failing confusingly in a later section.
case "$(uname -s)" in
  Linux) : ;;
  Darwin)
    printf 'verify.sh: running on macOS (Darwin) — supported. Known gaps on this OS: probes run unbounded when timeout(1) is absent (stock macOS has none; CI bounds the job with timeout-minutes), and the Playwright browser cache is ~/Library/Caches/ms-playwright.\n'
    ;;
  *) printf 'WARNING: verify.sh: untested OS (%s) — Linux and macOS are the supported targets.\n' "$(uname -s)" >&2 ;;
esac
ok()   { printf 'OK: %s\n' "$1"; }
warn() { warns=$((warns+1)); printf 'WARN: %s\n' "$1"; }
fail() { fails=$((fails+1)); printf 'FAIL: %s\n' "$1"; }
fail_loud() { fails=$((fails+1)); printf 'FAIL (LOCKSTEP): %s\n' "$1"; }
# UNVERIFIED is not a warning and not a hard fail: a loop step that could
# not run, so the loop is not proven. It fails the run (exit 1) with a
# RESULT: UNVERIFIED summary — never an OK.
unverified() { unverified=$((unverified+1)); printf 'UNVERIFIED: %s\n' "$1"; }
pending=0
# PENDING is informational, never silent and never a failure: a best-effort
# subsystem (hook / MCP) that is not registered. Install exits 0 with these
# pending by design; verify must REPORT them (H5), not print OK for them
# and not fail the loop for them either.
pending_msg() { pending=$((pending+1)); printf 'PENDING: %s\n' "$1"; }

# --- which hosts to check ---------------------------------------------------
# install.sh records its hosts; otherwise check every skills dir that exists.
declare -a HOSTS=()
if [[ -n "$hosts_filter" ]]; then
  IFS=',' read -r -a HOSTS <<< "$hosts_filter"
elif [[ -f "$state_dir/installed-hosts.txt" ]]; then
  # Bash 3.2 has no line-to-array builtin (stock macOS /bin/bash is 3.2;
  # the feature arrived in bash 4) — read the file with a loop instead
  # (the house style elsewhere in this file). Blank lines are skipped.
  while IFS= read -r _h || [[ -n "$_h" ]]; do
    [[ -n "$_h" ]] && HOSTS+=("$_h")
  done < "$state_dir/installed-hosts.txt"
  # An empty/blank record means "no hosts recorded" — fall back to all
  # hosts (same as a missing file). This also keeps HOSTS non-empty:
  # expanding an empty array under `set -u` aborts bash older than 4.4.
  if [[ "${#HOSTS[@]}" -eq 0 ]]; then
    for h in claude codex opencode gemini hermes copilot muse cmd; do HOSTS+=("$h"); done
  fi
else
  for h in claude codex opencode gemini hermes copilot muse cmd; do HOSTS+=("$h"); done
fi

skills_dirs_for_host() {
  case "$1" in
    claude)   printf '%s' "$user_home/.claude/skills" ;;
    codex)    printf '%s\n%s\n' "$user_home/.agents/skills" "$user_home/.codex/skills" ;;
    opencode) printf '%s\n%s\n' "$user_home/.config/opencode/skills" "$user_home/.agents/skills" ;;
    gemini)   printf '%s\n%s\n' "$user_home/.gemini/skills" "$user_home/.agents/skills" ;;
    hermes)   printf '%s\n%s\n' "$user_home/.hermes/skills" "$user_home/.agents/skills" ;;
    copilot)  printf '%s' "$user_home/.copilot/skills" ;;
    muse)     printf '%s' "$user_home/workspace/custom-skills" ;;
    # CommandCode (cmd): native user dir first, then the shared dir —
    # see install.sh skills_dirs_for_host (same order, same reason).
    cmd)      printf '%s\n%s\n' "$user_home/.commandcode/skills" "$user_home/.agents/skills" ;;
  esac
}

# Every skills dir the kit installs to, one per line. Used by the
# taste-path check and the Impeccable SKILL.md check below.
all_skills_dirs() {
  printf '%s\n' "$user_home/.agents/skills" "$user_home/.claude/skills" \
    "$user_home/.config/opencode/skills" "$user_home/.codex/skills" \
    "$user_home/.gemini/skills" "$user_home/.hermes/skills" \
    "$user_home/.copilot/skills" "$user_home/.commandcode/skills" \
    "$user_home/workspace/custom-skills"
}

# Find the Impeccable launcher in ANY installed skills dir. The old
# 3-path list missed muse-only installs (~/workspace/custom-skills) and
# codex/gemini/hermes/copilot installs, so a correct muse-only tree
# failed with "launcher missing" (F7/6b). Keep this list in sync with
# install.sh's warm-step search.
find_launcher() {
  local cand
  for cand in "$user_home/.agents/skills/impeccable/scripts/impeccable" \
             "$user_home/.claude/skills/impeccable/scripts/impeccable" \
             "$user_home/.config/opencode/skills/impeccable/scripts/impeccable" \
             "$user_home/.codex/skills/impeccable/scripts/impeccable" \
             "$user_home/.gemini/skills/impeccable/scripts/impeccable" \
             "$user_home/.hermes/skills/impeccable/scripts/impeccable" \
             "$user_home/.copilot/skills/impeccable/scripts/impeccable" \
             "$user_home/.commandcode/skills/impeccable/scripts/impeccable" \
             "$user_home/workspace/custom-skills/impeccable/scripts/impeccable"; do
    if [[ -x "$cand" ]]; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}

# Whether install.sh installed copilot (recorded hosts). The copilot
# instructions file is a hard fail only then; on a record-less run that
# merely assumes all hosts, a missing copilot artefact is a warn.
# install.sh touches $state_dir/copilot-instructions-installed ONLY when it
# actually writes ~/.github/copilot-instructions.md. The no-host fallback
# installs to skills dirs only and must NOT write that live Copilot file
# (H18), even though installed-hosts.txt still lists copilot as a fallback
# skills-dir target — so the hosts list alone must not imply the file.
copilot_installed_by_kit=0
[[ -f "$state_dir/copilot-instructions-installed" ]] && copilot_installed_by_kit=1

# --- expected skills (discovered from the repo, same rule as install.sh) ---
declare -a EXPECTED=()
for d in "$root"/skills/*/; do [[ -f "${d}SKILL.md" ]] && EXPECTED+=("$(basename "$d")"); done
for d in "$root"/vendor/gsap/*/; do [[ -f "${d}SKILL.md" ]] && EXPECTED+=("$(basename "$d")"); done
[[ -d "$root/vendor/impeccable" ]] && EXPECTED+=("impeccable")
# A repo with no skills has a broken layout — nothing to verify. Fail
# loudly here: the loops below expand EXPECTED, and expanding an empty
# array under `set -u` aborts bash older than 4.4 (stock macOS bash 3.2)
# instead of failing cleanly. (macOS phase, D12.)
if [[ "${#EXPECTED[@]}" -eq 0 ]]; then
  printf 'ERROR: no skills found under %s/skills (or vendor/gsap, vendor/impeccable) — repo layout broken, nothing to verify.\n' "$root" >&2
  exit 1
fi
# de-duplicate, keep order
declare -a UNI=()
for n in "${EXPECTED[@]}"; do
  # Length guard: UNI starts empty, and expanding an empty array under
  # `set -u` aborts bash older than 4.4 — seed the first element
  # directly; the membership test only runs once UNI is non-empty.
  if [[ "${#UNI[@]}" -eq 0 ]]; then UNI+=("$n"); continue; fi
  case " ${UNI[*]} " in *" $n "*) ;; *) UNI+=("$n") ;; esac
done
EXPECTED=("${UNI[@]}")
printf 'Hosts checked: %s\n' "${HOSTS[*]}"
printf 'Skills expected per host: %s\n' "${EXPECTED[*]}"

# --- 1. skills present per host + name == dir ------------------------------
for host in "${HOSTS[@]}"; do
  while IFS= read -r dir || [[ -n "$dir" ]]; do
    [[ -z "$dir" ]] && continue
    # Copilot does not load SKILL.md files (GSAP README, VERIFIED): a copy
    # there is a fallback only. Check it exists, but a missing Copilot copy
    # never fails the kit. Its WORKING artefact is
    # ~/.github/copilot-instructions.md (install.sh writes it when
    # copilot is installed): missing that fails when the kit installed
    # copilot, warns otherwise.
    if [[ "$host" == copilot ]]; then
      missing=0
      for name in "${EXPECTED[@]}"; do [[ -f "$dir/$name/SKILL.md" ]] || missing=$((missing+1)); done
      if [[ "$missing" == 0 ]]; then ok "copilot fallback copy present ($dir)";
      else warn "copilot fallback copy incomplete ($missing missing in $dir) — Copilot's working artefact is .github/copilot-instructions.md per project, not SKILL.md files"; fi
      if [[ -f "$user_home/.github/copilot-instructions.md" ]]; then
        ok "copilot instructions present ($user_home/.github/copilot-instructions.md)"
      elif [[ "$copilot_installed_by_kit" == 1 ]]; then
        fail "copilot instructions missing: $user_home/.github/copilot-instructions.md — Copilot's working artefact (install.sh writes it when copilot is installed)"
      else
        warn "copilot instructions missing: $user_home/.github/copilot-instructions.md (copilot was not installed by this kit — run ./install.sh --hosts=copilot)"
      fi
      continue
    fi
    fails_before="$fails"
    for name in "${EXPECTED[@]}"; do
      f="$dir/$name/SKILL.md"
      if [[ ! -f "$f" ]]; then fail "missing skill: $host: $f"; continue; fi
      got="$(grep -m1 -E '^[[:space:]]*name:[[:space:]]*' "$f" | sed -E 's/.*name:[[:space:]]*"?([^" ]+)"?/\1/' || true)"
      if [[ -n "$got" && "$got" != "$name" ]]; then
        fail "skill name mismatch: $f declares name '$got', directory is '$name'"
      fi
    done
    # An OK line is a verdict: only print it when this dir added no
    # failures (the old unconditional OK printed after FAILs — F11).
    [[ "$fails" == "$fails_before" ]] && ok "skills present: $host ($dir)"
  done < <(skills_dirs_for_host "$host")
done

# --- 2. stale ${CLAUDE_PLUGIN_ROOT} paths (A3) -----------------------------
if grep -rInF '${CLAUDE_PLUGIN_ROOT}' \
     "$user_home/.agents/skills" "$user_home/.claude/skills" \
     "$user_home/.config/opencode/skills" "$user_home/.gemini/skills" \
     "$user_home/.hermes/skills" "$user_home/.codex/skills" \
     "$user_home/.copilot/skills" "$user_home/.commandcode/skills" \
     "$user_home/workspace/custom-skills" 2>/dev/null | head -5; then
  fail "stale \${CLAUDE_PLUGIN_ROOT} path found in an installed skill (clean-env failure A3) — see matches above"
else
  ok "no stale \${CLAUDE_PLUGIN_ROOT} in installed skills"
fi
if grep -rInF '${CLAUDE_PLUGIN_ROOT}' "$refs_dir" 2>/dev/null | head -3; then
  # The matches that fire this are upstream reference-data text, NOT the
  # installed skills (those fail hard in §2 above): the vendored taste
  # tree's hook command cites ${CLAUDE_PLUGIN_ROOT} (it only resolves
  # inside a Claude plugin install). Warn, do not fail: the kit's wrapper
  # skills use the $HOME path and never rely on the variable. The old text
  # ("known v1 vendored defect, fixed by the Pro Max re-pin") was stale on
  # both counts: the Pro Max SKILL.md refs were fixed by the KIT PATCH
  # (vendor/ui-ux-pro-max/SOURCE.txt, KIT PATCH — re-apply on re-pin), not
  # by the re-pin, and the firing match is the taste tree, which no re-pin
  # fixed. A match inside an installed SKILL.md is a different case: §2
  # fails it, and the fix is re-applying the patch, not this warn.
  warn "stale \${CLAUDE_PLUGIN_ROOT} in reference data ($refs_dir) — upstream vendored text (see matches above; taste tree hook command). Warn-only: the kit's wrapper skills use the \$HOME path, so the reference data is still usable. (Pro Max SKILL.md refs were fixed by the kit patch, not the re-pin — a match inside a SKILL.md fails in §2.)"
fi

# --- 2b. generated Impeccable SKILL.md is shippable as-is --------------------
# Check EVERY installed copy in EVERY skills dir (H11 redo 2026-11-10).
# The old code `break`ed after the first copy found, so a corrupted
# second copy (e.g. only .codex/skills/impeccable/SKILL.md tampered)
# passed verify with RESULT: OK. A failure in ANY copy fails the run.
checked_2b=0
while IFS= read -r sd || [[ -n "$sd" ]]; do
  cand="$sd/impeccable/SKILL.md"
  [[ -f "$cand" ]] || continue
  checked_2b=$((checked_2b+1))
  if grep -q '{{[a-z_]*}}' "$cand"; then
    fail "generated Impeccable SKILL.md has unresolved placeholders: $cand"
  fi
  if grep -q '^version:' "$cand"; then
    fail "generated Impeccable SKILL.md carries a top-level version: (must live in metadata): $cand"
  fi
  if grep -q '^metadata:' "$cand" && grep -A1 '^metadata:' "$cand" | grep -q 'version:'; then
    ok "Impeccable SKILL.md spec-pure (version in metadata, no placeholders): $cand"
  else
    warn "Impeccable SKILL.md has no metadata.version: $cand (older v1 variant?)"
  fi
done < <(all_skills_dirs)
[[ "$checked_2b" == 0 ]] && fail "no installed Impeccable SKILL.md found in any skills dir"

# --- 2c. taste pipeline paths resolve from the installed wrapper --------
# The taste-reference wrapper cites vendor/taste/skills/taste-skill/…
# paths. install.sh points each installed wrapper's vendor/ at the
# installed taste tree ($refs_dir/taste); every cited anchor must resolve
# from the installed skill dir, or the taste layer is dangling (F5).
taste_anchors=(
  'vendor/taste/skills/taste-skill/SKILL.md'
  'vendor/taste/skills/taste-skill/scripts/consistency.mjs'
  'vendor/taste/skills/taste-skill/scripts/gate.mjs'
  'vendor/taste/skills/taste-skill/scripts/start.mjs'
  'vendor/taste/skills/taste-skill/library/palettes.json'
  'vendor/taste/skills/taste-skill/library/type.json'
  'vendor/taste/skills/taste-skill/assets/diagrams/presets.json'
  'vendor/taste/skills/taste-skill/references/system.md'
)
taste_checked=0
taste_fails_before="$fails"
while IFS= read -r sd || [[ -n "$sd" ]]; do
  tdir="$sd/taste-reference"
  [[ -f "$tdir/SKILL.md" ]] || continue
  taste_checked=1
  for anchor in "${taste_anchors[@]}"; do
    [[ -e "$tdir/$anchor" ]] || fail "taste path dangling: $tdir/$anchor does not resolve (install.sh must point taste-reference/vendor at the installed taste tree)"
  done
done < <(all_skills_dirs)
[[ "$taste_checked" == 1 && "$fails" == "$taste_fails_before" ]] && ok "taste-reference wrapper paths resolve (all cited anchors present)"

# --- 2d. no live builder-self-grade language in installed skills --------
# The builder NEVER grades its own work (kit grader rule — the grade step
# MUST dispatch to an independent judge; see skills/frontend-kit/SKILL.md
# "Precedence" and references/grader-rubric.md). This check FAILS the
# install if any installed skill contains a LIVE instruction to self-grade,
# and distinguishes those from PROHIBITING mentions of the same words.
#
# RULE (exact, fail-closed — redo 2026-11-10, H4):
#   1. PATTERNS (case-insensitive, substring): the four original phrases
#      plus the direct phrasings — "grade your own work", "grade your own",
#      "score your own", "review your own work", "assess your own",
#      "evaluate your own", "critique your own work" (lowercase form of
#      the original "Critique your own work").
#   2. FILE TYPES: every shipped file type under the installed skills dirs,
#      not just *.md — .md, .toml, .json, .js, .mjs, .py, .sh. A live
#      instruction in a Codex .toml agent file is a live instruction.
#   3. ALLOWLIST — sentence-scoped governance. A matched line is exempt
#      ONLY if, in the SAME SENTENCE as the matched phrase (a sentence is
#      the text between . ! ? or ; boundaries on that physical line), one
#      of these prohibiting constructions occurs:
#        a negation governing the phrase: never / not / n't / cannot
#        (word-matched, so "notice" does not count);
#        a prohibition/override word: forbidden, prohibit*, overrid*;
#        a documented override citation: "which requires a",
#        "including upstream", "Those passages are upstream text",
#        "frontend-design/SKILL.md:57" (the citation form of the
#        frontend-design passage), "banner on degraded runs",
#        "must not be followed as grading".
#      A token in a DIFFERENT sentence on the same line does NOT exempt
#      the phrase (H4b: "…grade your own work and report the score.
#      NEVER grades its own work" FAILS — the NEVER is a second sentence
#      quoting the prohibition, not a negation governing the instruction).
#      ONE narrow exception to the same-sentence rule (H4 fix 2026-11-10):
#      a QUOTED mention — the phrase inside double quotes, i.e. a citation
#      of upstream text, not a bare instruction — is exempt when a
#      citation/override marker (upstream / overrid* / "must not be
#      followed" / "which requires a" / "precedence" / the
#      frontend-design citation) occurs in the same sentence, the
#      immediately following one, or the NEXT PHYSICAL LINE (the kit's
#      docs hard-wrap paragraphs, so the Precedence note's "Those
#      passages are upstream text" sits on the line after the quoted
#      phrase, and "is OVERRIDDEN" sits on the line after the quoted
#      sentence). This is what the kit's own Precedence notes need:
#      frontend-kit SKILL.md:34 cites ("Critique your own work") and
#      the next line says "Those passages are upstream text …
#      overridden"; SKILL.md:104 quotes the sentence and the next line
#      says "is OVERRIDDEN". Bare negations (never/not) do NOT qualify
#      for this exception — a quoted instruction followed by "NEVER do
#      it" still FAILS — so the H4b bypass stays caught: its phrase is
#      unquoted, so the exception never applies to it at all.
#   4. EXACT-STRING EXCEPTION (line level): the one documented overridden
#      vendored passage, Anthropic's sentence "Critique your own work as
#      you build, taking screenshots" (frontend-design SKILL.md:59 +
#      SOURCE.md:59). Any OTHER wording of a self-critique instruction
#      is not allowlisted and FAILS.
#   5. NO file-scoped exemption for upstream critique.md banner lines.
#      The generated copy must not contain "MUST be a banner" /
#      "lead the report with" lines at all; if it does, the generator
#      failed and verify FAILS (H1 class). The old file-scoped exemption
#      is deleted, not widened.
# Implemented in python3 (a hard prereq already — the fixture server
# below needs it) because sentence splitting + word matching is not
# expressible in a grep -v pipeline, and grep -v was the H4b hole.
self_grade_dirs=()
while IFS= read -r sd || [[ -n "$sd" ]]; do [[ -d "$sd" ]] && self_grade_dirs+=("$sd"); done < <(all_skills_dirs)
self_grade_hits=""
if [[ "${#self_grade_dirs[@]}" -gt 0 ]]; then
  self_grade_hits="$(SELF_GRADE_DIRS="${self_grade_dirs[*]}" python3 - "$root" <<'PYEOF2'
import os, re, sys
patterns = [
    'you are both parties', 'degraded: single-context',
    'single-context self-critique', 'critique your own work',
    'grade your own work', 'grade your own', 'score your own',
    'review your own work', 'assess your own', 'evaluate your own',
]
# Word-matched negations / prohibitions (regex, case-insensitive).
prohibiting_res = [
    r'\bnever\b', r'\bnot\b', r"n\'t\b", r'\bcannot\b',
    r'\bforbidden\b', r'\bprohibit\w*', r'\boverrid\w*',
]
# Substring citations that only occur in override notes.
prohibiting_subs = [
    'which requires a', 'including upstream',
    'those passages are upstream text', 'frontend-design/skill.md:57',
    'banner on degraded runs', 'must not be followed as grading',
]
# Citation/override markers for the QUOTED-mention exception (rule 3b):
# bare negations are deliberately NOT in this list.
citation_markers = [
    'upstream', 'overrid', 'must not be followed', 'which requires a',
    'including upstream', 'those passages are upstream text',
    'precedence', 'frontend-design/skill.md:57',
]
quoted_re = re.compile(r'"[^"]*"')
exact_exception = 'critique your own work as you build, taking screenshots'
exts = {'.md', '.toml', '.json', '.js', '.mjs', '.py', '.sh'}
sentence_split = re.compile(r'[.!?;]')
hits = []
for d in os.environ['SELF_GRADE_DIRS'].split():
    for base, _dirs, files in os.walk(d):
        for fn in files:
            if os.path.splitext(fn)[1].lower() not in exts:
                continue
            path = os.path.join(base, fn)
            try:
                with open(path, encoding='utf-8', errors='replace') as f:
                    lines = f.read().splitlines()
            except OSError:
                continue
            for n, line in enumerate(lines, 1):
                low = line.lower()
                # Next physical line (lowercased) — the kit's docs hard-wrap
                # paragraphs, so a quoted citation's governing marker can
                # sit on the line after the phrase (rule 3b only).
                next_low = lines[n].lower() if n < len(lines) else ''
                if exact_exception in low:
                    continue
                found = [pt for pt in patterns if pt in low]
                if not found:
                    continue
                live = False
                sentences = sentence_split.split(low)
                for si, sent in enumerate(sentences):
                    if not any(pt in sent for pt in found):
                        continue
                    governed = any(re.search(rx, sent) for rx in prohibiting_res) \
                        or any(sub in sent for sub in prohibiting_subs)
                    if governed:
                        continue
                    # Quoted-mention exception (rule 3b): the phrase is a
                    # citation inside double quotes, and a citation/override
                    # marker occurs in this sentence, the next one, or the
                    # next physical line. "Quoted" means inside a complete
                    # "..." span on this line, OR after an unclosed opening
                    # quote (the quote closes on the next hard-wrapped
                    # line, as in SKILL.md:104-105: "Critique your own
                    # work as / you build" … is OVERRIDDEN).
                    quoted = any(pt in q for q in quoted_re.findall(sent) for pt in found)
                    if not quoted:
                        for pt in found:
                            _pos = sent.find(pt)
                            if _pos >= 0 and sent[:_pos].count('"') % 2 == 1:
                                quoted = True
                                break
                    if quoted:
                        nxt = sentences[si + 1] if si + 1 < len(sentences) else ''
                        if any(m in sent for m in citation_markers) \
                                or any(m in nxt for m in citation_markers) \
                                or any(m in next_low for m in citation_markers):
                            continue
                    live = True
                    break
                if live:
                    hits.append(f'{path}:{n}:{line}')
print('\n'.join(hits))
PYEOF2
)"
fi
if [[ -n "$self_grade_hits" ]]; then
  fail "live builder-self-grade language in an installed skill — the builder NEVER grades its own work (kit grader rule, skills/frontend-kit/SKILL.md Precedence). Matches:"
  printf '%s\n' "$self_grade_hits"
else
  ok "no live builder-self-grade language in installed skills (sentence-scoped prohibiting mentions allowlisted — see §2d comment)"
fi

# --- 2e. installed-copy gate presence anchors (D13, GAP-11) --------------
# The gate scripts live INSIDE the skill now
# (skills/frontend-kit/scripts/gate/), so every installed frontend-kit
# copy must carry all 16 of them — a copy without the gate cannot
# complete the loop (the GAP-11 defect: the installed skill cited a
# gate that was not there). FAIL per missing file per copy, in the §2b
# every-copy pattern (a corrupted second copy must not pass because the
# first one is fine). gate.sh must be executable (-x): the cp -r
# fallback exec-bit preservation is otherwise unverified.
# F8 (fix round 1): presence alone cannot tell a current installed gate
# from a pre-D13 one, so two content anchors are checked per copy:
# gate.sh must carry the §6 1.1 gate-leg-log exclusion itself
# (`-not -path '*/design/gate-leg1.log'` on the find line — a mere
# comment mentioning the log does not count) and gate.mjs must carry
# the D13 error string (`Re-run ./install.sh`). A stale installed gate
# FAILs §2e instead of passing silently and failing the next real gate
# run on its own output.
gate_files=(
  gate.sh gate.mjs detect.mjs converge-check.mjs copy-lint.mjs
  consistency.mjs anti-cliche.mjs lint-tokens.mjs runlog-check.mjs
  json-dup-keys.mjs seed-structural.mjs dompurify-call.mjs
  vendored-allowlist.txt vendored-runtime-list.txt README.md
  .gitleaks.toml
)
checked_2e=0
fails_2e_before="$fails"
while IFS= read -r sd || [[ -n "$sd" ]]; do
  gdir="$sd/frontend-kit/scripts/gate"
  [[ -f "$sd/frontend-kit/SKILL.md" ]] || continue
  checked_2e=$((checked_2e+1))
  for gf in "${gate_files[@]}"; do
    [[ -f "$gdir/$gf" ]] || fail "installed gate file missing: $gdir/$gf (D13 — the installed skill cannot run the gate)"
  done
  [[ -x "$gdir/gate.sh" ]] || fail "installed gate.sh is not executable: $gdir/gate.sh (D13 — re-run ./install.sh)"
  grep -qF "*/design/gate-leg1.log" "$gdir/gate.sh" 2>/dev/null || fail "installed gate.sh is stale (pre-D13): missing the §6 1.1 gate-leg-log exclusion: $gdir/gate.sh (D13 — re-run ./install.sh)"
  grep -q 'Re-run \./install\.sh' "$gdir/gate.mjs" 2>/dev/null || fail "installed gate.mjs is stale (pre-D13): missing the 'Re-run ./install.sh' error string: $gdir/gate.mjs (D13 — re-run ./install.sh)"
done < <(all_skills_dirs)
[[ "$checked_2e" == 0 ]] && fail "no installed frontend-kit copy found in any skills dir (D13 §2e cannot check gate presence)"
[[ "$checked_2e" != 0 && "$fails" == "$fails_2e_before" ]] && ok "installed gate present in $checked_2e frontend-kit copy/copies (all 16 files, gate.sh executable, D13 content anchors present)"

# --- 2f. installed-copy template presence anchors (D14, GAP-12) --------------
# The design templates live INSIDE the skill now
# (skills/frontend-kit/templates/design/), so every installed frontend-kit
# copy must carry them — a copy without the templates cannot perform
# Step 0 as written (the GAP-12 defect: the installed skill cited
# templates/design/ paths that did not exist in the installed copy, and
# the probe agent wrote stubs instead — TASTE.md 587 B vs template
# 3,872 B; the stub PLAN.md had no Section inventory table, which made
# converge-check a no-op). FAIL per missing file per copy, in the §2b
# every-copy pattern. Presence alone cannot catch a stub, so two content
# anchors are checked per copy: PLAN.md must contain a
# `## Section inventory` heading, and TASTE.md must be at least 1KB
# (the demonstrated stub was 587 B; the template is 3,872 B). No hashes:
# they would churn on every legitimate template edit. The motion
# reference PNGs are checked as a non-empty directory, not by filename —
# filenames may change, the tree must not go missing.
template_files=(
  templates/design/TASTE.md templates/design/tokens.css
  templates/design/PLAN.md templates/design/DESIGN-READ.md
  templates/design/DESIGN-SYSTEM.md templates/design/demo.html
  templates/design/primitives.css
  templates/design/rounds/README.md
  templates/design/rounds/_template/proposal.md
  templates/design/rounds/_template/delta.md
  templates/design/rounds/_template/tasks.md
  templates/design/references/DESIGN.md/README.md
  templates/design/references/DESIGN.md/claude.md
  templates/design/references/DESIGN.md/linear.md
  templates/design/references/DESIGN.md/vercel.md
)
checked_2f=0
fails_2f_before="$fails"
while IFS= read -r sd || [[ -n "$sd" ]]; do
  tdir="$sd/frontend-kit/templates/design"
  [[ -f "$sd/frontend-kit/SKILL.md" ]] || continue
  checked_2f=$((checked_2f+1))
  for tf in "${template_files[@]}"; do
    [[ -f "$sd/frontend-kit/$tf" ]] || fail "installed template file missing: $sd/frontend-kit/$tf (D14 — the installed skill cannot perform Step 0)"
  done
  [[ -n "$(find "$tdir/references/motion" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null)" ]] || fail "installed template motion refs missing: no PNG under $tdir/references/motion (D14 — re-run ./install.sh)"
  grep -qF '## Section inventory' "$tdir/PLAN.md" 2>/dev/null || fail "installed PLAN.md template is a stub (pre-D14 or agent-written): missing the '## Section inventory' heading: $tdir/PLAN.md (D14 — re-run ./install.sh)"
  [[ "$(wc -c < "$tdir/TASTE.md" 2>/dev/null || echo 0)" -ge 1024 ]] || fail "installed TASTE.md template is a stub (pre-D14 or agent-written): smaller than 1KB: $tdir/TASTE.md (D14 — re-run ./install.sh)"
done < <(all_skills_dirs)
[[ "$checked_2f" == 0 ]] && fail "no installed frontend-kit copy found in any skills dir (D14 §2f cannot check template presence)"
[[ "$checked_2f" != 0 && "$fails" == "$fails_2f_before" ]] && ok "installed templates present in $checked_2f frontend-kit copy/copies (15 files + motion refs, D14 content anchors present)"
# --- 3. Impeccable engine lockstep (A10) — FAIL LOUDLY on mismatch --------
# The expected engine comes from the REPO pin, not from the installed
# tree (F4/QC F8): installed-vs-installed lockstep passes a jointly
# replaced skill+engine pair undetected. Repo pin sources, in order:
# the canonical tree's scripts/VERSION, then SOURCE.txt's engine= line.
launcher="$(find_launcher || true)"
expected_engine=""
repo_version_file="$root/vendor/impeccable/skill/scripts/VERSION"
if [[ -f "$repo_version_file" ]]; then
  expected_engine="$(tr -d '[:space:]' < "$repo_version_file")"
elif [[ -f "$root/vendor/impeccable/SOURCE.txt" ]]; then
  expected_engine="$(sed -n 's/^engine=//p' "$root/vendor/impeccable/SOURCE.txt" | head -n 1 | tr -d '[:space:]')"
fi
if [[ -z "$expected_engine" ]]; then
  fail "cannot establish the repo engine pin (vendor/impeccable/skill/scripts/VERSION and SOURCE.txt engine= both unreadable) — lockstep cannot be checked"
fi
if [[ -z "$launcher" ]]; then
  fail "impeccable launcher missing from every installed skills dir"
elif [[ -z "$expected_engine" ]]; then
  : # pin already failed above; do not probe against an unknown pin
else
  # The installed skill's own VERSION must ALSO match the repo pin — a
  # jointly-replaced installed pair (skill VERSION + engine both swapped
  # to a wrong version) is caught here even though probe-vs-installed
  # would pass.
  installed_version=""
  vf="$(dirname -- "$launcher")/VERSION"
  [[ -f "$vf" ]] && installed_version="$(tr -d '[:space:]' < "$vf")"
  if [[ -z "$installed_version" ]]; then
    fail "impeccable scripts/VERSION missing next to $launcher (cannot establish the installed skill's expected engine)"
  elif [[ "$installed_version" != "$expected_engine" ]]; then
    fail_loud "installed skill expects engine $installed_version but the repo pin is $expected_engine — the installed skill tree is not the vendored pin. Re-run ./install.sh."
  else
    probe_out="$("$launcher" engine-probe 2>&1 || true)"
    case "$probe_out" in
      impeccable-engine\ *)
        actual_engine="${probe_out#impeccable-engine }"
        actual_engine="${actual_engine%%[[:space:]]*}"
        if [[ "$actual_engine" == "$expected_engine" ]]; then
          ok "engine lockstep: repo pin $expected_engine, installed skill expects $installed_version, engine reports $actual_engine"
          # H2 (redo 2026-11-10): a version STRING is not lockstep. The
          # launcher trusts IMPECCABLE_BIN (no probe at all), the
          # unversioned ~/.impeccable/bin/impeccable and PATH `impeccable`
          # on a probe handshake alone, and verify.sh never read
          # engine-checksums.txt at all — a 6-line stub printing the
          # pinned version passed everything. So hash the engine binary
          # the launcher actually resolved against the REPO's
          # engine-checksums.txt (vendor/impeccable/skill/scripts/).
          # Resolution mirrors the launcher's candidate order
          # (IMPECCABLE_BIN, sibling bin/, unversioned home bin,
          # version-pinned cache, PATH); the first executable candidate
          # that answers the probe is the engine that ran. A hash
          # mismatch FAILS unless the operator explicitly opted into a
          # local build with IMPECCABLE_ALLOW_LOCAL_ENGINE=1 (documented
          # opt-in: that binary is trusted by the operator, not by the
          # kit — the version string is still checked above).
          engine_asset=""
          case "$(uname -s 2>/dev/null || echo unknown)-$(uname -m 2>/dev/null || echo unknown)" in
            Linux-x86_64|Linux-amd64) engine_asset="impeccable-linux-x64" ;;
            Linux-aarch64|Linux-arm64) engine_asset="impeccable-linux-arm64" ;;
            Darwin-arm64|Darwin-aarch64) engine_asset="impeccable-darwin-arm64" ;;
            Darwin-x86_64|Darwin-amd64) engine_asset="impeccable-darwin-x64" ;;
          esac
          repo_checksums="$root/vendor/impeccable/skill/scripts/engine-checksums.txt"
          expected_digest=""
          if [[ -n "$engine_asset" && -f "$repo_checksums" ]]; then
            expected_digest="$(awk -v v="$expected_engine" -v a="$engine_asset" '$1==v && $2==a {print $3; exit}' "$repo_checksums")"
          fi
          resolved_engine=""
          probe_candidate() { # <path> — 0 if it answers the engine handshake
            IMPECCABLE_LAUNCHER_PROBE=1 "$1" engine-probe 2>/dev/null | grep -q '^impeccable-engine '
          }
          _cand=""
          if [[ -n "${IMPECCABLE_BIN:-}" && -x "$IMPECCABLE_BIN" ]]; then resolved_engine="$IMPECCABLE_BIN";
          else
            _sib="$(dirname -- "$launcher")/bin/$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')-$(uname -m 2>/dev/null)/impeccable"
            case "$(uname -s 2>/dev/null)" in Darwin) _sib="$(dirname -- "$launcher")/bin/darwin-$(uname -m 2>/dev/null | sed -e 's/x86_64/x64/' -e 's/aarch64/arm64/')/impeccable" ;; Linux) _sib="$(dirname -- "$launcher")/bin/linux-$(uname -m 2>/dev/null | sed -e 's/x86_64/x64/' -e 's/aarch64/arm64/')/impeccable" ;; esac
            _home_bin="$user_home/.impeccable/bin/impeccable"
            _cache="${IMPECCABLE_HOME:-$user_home/.impeccable}/bin/$expected_engine/impeccable"
            for _cand in "$_sib" "$_home_bin" "$_cache" "$(command -v impeccable 2>/dev/null || true)"; do
              [[ -n "$_cand" && -x "$_cand" ]] || continue
              if probe_candidate "$_cand"; then resolved_engine="$_cand"; break; fi
            done
          fi
          if [[ -z "$resolved_engine" ]]; then
            fail "engine answered the probe but no engine binary could be located to hash (checked IMPECCABLE_BIN, sibling bin/, ~/.impeccable/bin/impeccable, the $expected_engine cache, PATH) — refusing probe-only trust (H2)"
          elif [[ -z "$expected_digest" ]]; then
            fail "no checksum in the repo engine-checksums.txt for engine $expected_engine ($engine_asset) — cannot hash-verify the engine binary $resolved_engine"
          else
            actual_digest=""
            if command -v sha256sum >/dev/null 2>&1; then actual_digest="$(sha256sum -- "$resolved_engine" 2>/dev/null | awk '{print $1}')";
            elif command -v shasum >/dev/null 2>&1; then actual_digest="$(shasum -a 256 -- "$resolved_engine" 2>/dev/null | awk '{print $1}')"; fi
            if [[ -z "$actual_digest" ]]; then
              fail "cannot hash the engine binary $resolved_engine (no sha256sum/shasum) — lockstep cannot be proven"
            elif [[ "$actual_digest" == "$expected_digest" ]]; then
              ok "engine binary hash-verified against repo engine-checksums.txt ($resolved_engine, $engine_asset $expected_engine)"
            elif [[ "${IMPECCABLE_ALLOW_LOCAL_ENGINE:-}" == 1 ]]; then
              warn "engine binary $resolved_engine does NOT match the repo checksum for $engine_asset $expected_engine, but IMPECCABLE_ALLOW_LOCAL_ENGINE=1 explicitly trusts this local build (operator opt-in — the kit does not vouch for it)"
            else
              fail_loud "engine binary hash MISMATCH: $resolved_engine hashes to $actual_digest but the repo engine-checksums.txt records $expected_digest for $engine_asset $expected_engine. This binary is NOT the pinned release — a probe-only stub or substituted engine passes the version string but fails the hash. Refusing it (set IMPECCABLE_ALLOW_LOCAL_ENGINE=1 only to explicitly trust a local build)."
            fi
          fi
        else
          fail_loud "engine MISMATCH: repo pin is $expected_engine but the installed engine reports $actual_engine. The 62-rule registry lives in the engine — detect would silently apply the wrong rules. Re-run ./install.sh (warm) or install the matching engine binary."
        fi
        ;;
      *)
        # No engine answered the probe. If a DIFFERENT engine version sits in
        # the version-pinned cache, that is not "not warmed yet" — it is a
        # stale engine shadowing the expected one, and the loop must not
        # proceed on a warn. (The 4.8.2 launcher additionally refuses to
        # download an engine whose checksum is not in engine-checksums.txt,
        # so a tampered VERSION cannot silently fetch a wrong binary.)
        stale=""
        if [[ -d "$user_home/.impeccable/bin" ]]; then
          for vdir in "$user_home"/.impeccable/bin/*/; do
            [[ -d "$vdir" ]] || continue
            v="$(basename "$vdir")"
            [[ "$v" != "$expected_engine" ]] && stale="$stale $v"
          done
        fi
        if [[ -n "${stale// }" ]]; then
          fail_loud "engine UNREACHABLE for expected $expected_engine, but stale engine version(s)$stale sit in ~/.impeccable/bin. Re-warm with ./install.sh (or: $launcher engine-probe) so the expected engine is installed; do not run detect against the stale one."
        else
          unverified "impeccable engine not installed/reachable (repo pin $expected_engine; engine-probe gave: ${probe_out:-<no output>}). Run ./install.sh (warm step) or: $launcher engine-probe — lockstep cannot be checked until the engine exists."
        fi
        ;;
    esac
  fi
fi

# --- 3b. Vendored-allowlist manifest vs taste tree (GAP-9, D9) — FAIL LOUDLY on mismatch --------
# Same style as the engine lockstep check (§3): the manifest
# skills/frontend-kit/scripts/gate/vendored-allowlist.txt must match the vendored taste
# assets tree for the pinned taste version, or a stale manifest ships
# as if it were current. Three checks, all FAILs:
#   (a) the manifest's pin header (tag + commit) equals the SOURCES.md
#       taste pin;
#   (b) every manifest entry's sha256 equals the vendored tree file's
#       sha256 for that asset-relative path, and every entry names a
#       file that exists in the tree;
#   (c) the manifest's key set equals the runtime INCLUSION list
#       (skills/frontend-kit/scripts/gate/vendored-runtime-list.txt) — the SAME file the
#       generator (vendor-update.sh) reads, so the two cannot drift, by
#       construction (RR-04, fix round 2: the old mirrored regex is gone;
#       the generator and this check share one source of truth, and a
#       manifest entry not in the inclusion list FAILS here).
# A missing manifest FAILS (no exemption is silently assumed). What this
# does NOT check, stated plainly: whether a fresh classification of the
# sink sites was recorded for the pin (w-gap9-analysis.md §1 method) —
# that is a re-pin process step owned by the vendor-update.sh reminder,
# not a file verify.sh can read; the manifest header records the pin so
# the classification note can be matched to it by hand.
# RT-06 (2026-11-11): §3b is self-consistency only — it cannot detect a
# tampered tree + refreshed SHA256SUMS + regenerated manifest, because
# all three inputs (manifest, tree, SOURCES.md pin) are produced by the
# same vendor-update.sh run from the same upstream clone. No cheap real
# anchor exists inside this checkout: anyone who can rewrite the tree +
# SHA256SUMS + manifest can also rewrite gate.sh / verify.sh themselves
# (same trust boundary as the manifest itself — RT-12: manifest integrity
# = repo-checkout integrity), so an in-checkout upstream check (e.g.
# resolving the tag via git ls-remote) would be theatre against that
# attack — it checks the pin label, not the tree bytes, and the attacker
# controls the checker. The tamper control is therefore the re-pin
# review itself (diff + re-classification + git-history review by a
# human), not this check; §3b's job is detecting inconsistency
# (stale/mismatched manifest), and it does that. No anchor was built
# here deliberately.
taste_allowlist="$root/skills/frontend-kit/scripts/gate/vendored-allowlist.txt"
taste_assets="$root/vendor/taste/skills/taste-skill/assets"
taste_pin="$(sed -n 's/^<!-- PIN: taste | repo=[^ |]* | tag=\([^ |]*\) | commit=\([^ >]*\).*/\1 \2/p' "$root/SOURCES.md" | head -n 1)"
if [[ ! -f "$taste_allowlist" ]]; then
  fail "vendored-allowlist.txt missing ($taste_allowlist) — gate 1.2 has no hash exemption; regenerate it with vendor-update.sh taste <tag>"
elif [[ -z "$taste_pin" ]]; then
  fail "cannot establish the SOURCES.md taste pin — vendored-allowlist lockstep cannot be checked"
elif [[ ! -d "$taste_assets" ]]; then
  fail "vendored taste assets tree missing at $taste_assets — vendored-allowlist lockstep cannot be checked"
else
  manifest_pin="$(sed -n 's/^# pin: taste | tag=\([^ |]*\) | commit=\([^ ]*\).*/\1 \2/p' "$taste_allowlist" | head -n 1)"
  if [[ "$manifest_pin" != "$taste_pin" ]]; then
    fail_loud "vendored-allowlist.txt pin header '$manifest_pin' != SOURCES.md taste pin '$taste_pin' — the manifest is stale for this pin. Re-run vendor-update.sh taste <tag> (and re-classify the sink sites first)."
  else
    ok "vendored-allowlist.txt pin header matches the SOURCES.md taste pin ($taste_pin)"
  fi
  allowlist_bad=0
  while IFS= read -r allow_line; do
    case "$allow_line" in \#*|"") continue ;; esac
    allow_hash="${allow_line%%  *}"; allow_path="${allow_line#*  }"
    tree_file="$taste_assets/${allow_path#assets/}"
    if [[ ! -f "$tree_file" ]]; then
      allowlist_bad=1; printf 'FAIL: vendored-allowlist.txt lists %s but no such file exists in the vendored taste tree\n' "$allow_path"
    elif command -v sha256sum >/dev/null 2>&1; then
      actual_hash="$(sha256sum -- "$tree_file" 2>/dev/null | awk '{print $1}')"
      if [[ "$actual_hash" != "$allow_hash" ]]; then
        allowlist_bad=1; printf 'FAIL: vendored-allowlist.txt hash mismatch for %s (manifest %s, tree %s)\n' "$allow_path" "$allow_hash" "$actual_hash"
      fi
    else
      allowlist_bad=1; printf 'FAIL: cannot hash %s (no sha256sum) — vendored-allowlist lockstep cannot be proven\n' "$tree_file"
    fi
  done < "$taste_allowlist"
  # Reverse direction: the manifest's key set must equal the runtime
  # INCLUSION list (skills/frontend-kit/scripts/gate/vendored-runtime-list.txt) — the SAME
  # file vendor-update.sh generates from (RR-04, fix round 2: single
  # source of truth, no mirrored pattern). Separately, and
  # informationally only (NOT a fail — the 17 lab/demo/catalog files are
  # unlisted by design), print the review set: sink files in the tree
  # NOT on the inclusion list, so a NEW upstream file is visible at
  # verify time and must be reviewed against the list at re-pin.
  runtime_list="$root/skills/frontend-kit/scripts/gate/vendored-runtime-list.txt"
  allow_keys="$(grep -v '^#' "$taste_allowlist" | grep -v '^$' | awk '{print $2}' | sort)"
  if [[ ! -f "$runtime_list" ]]; then
    allowlist_bad=1
    printf 'FAIL: vendored runtime inclusion list missing (%s) — the manifest cannot be checked against its source of truth\n' "$runtime_list"
  else
    # RR2-09 (fix round 3): §3b must agree with the generator about list
    # hygiene, not just the key set. The generator refuses a duplicate or
    # unsorted list (vendor-update.sh: duplicate check via sort -u count,
    # sorted check via cmp against sort) while the old set-only comparison
    # (sort -u) passed — so a re-pin was blocked while verify said OK.
    # The two checks below mirror the generator's exactly (same cleaning
    # pipeline, same plain `sort`): a duplicate or unsorted list now
    # fails §3b too.
    list_raw="$(grep -v '^[[:space:]]*#' "$runtime_list" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    list_keys="$(printf '%s\n' "$list_raw" | sort -u)"
    if [[ "$(printf '%s\n' "$list_raw" | sort -u | grep -c . || true)" != "$(printf '%s\n' "$list_raw" | grep -c . || true)" ]]; then
      allowlist_bad=1
      printf 'FAIL: vendored runtime inclusion list has duplicate entries (%s) — the generator refuses such a list; deduplicate it first\n' "$runtime_list"
    fi
    if ! cmp -s <(printf '%s\n' "$list_raw") <(printf '%s\n' "$list_raw" | sort); then
      allowlist_bad=1
      printf 'FAIL: vendored runtime inclusion list is not sorted (%s) — the generator refuses such a list; sort it first\n' "$runtime_list"
    fi
    if [[ "$allow_keys" != "$list_keys" ]]; then
      allowlist_bad=1
      printf 'FAIL: vendored-allowlist.txt key set != runtime inclusion list (%s). In manifest but not in inclusion list:\n%s\nIn inclusion list but not in manifest:\n%s\n' "$runtime_list" "$(comm -23 <(printf '%s\n' "$allow_keys") <(printf '%s\n' "$list_keys"))" "$(comm -13 <(printf '%s\n' "$allow_keys") <(printf '%s\n' "$list_keys"))"
    fi
    tree_sink_keys="$(
      grep -rlE 'dangerouslySetInnerHTML|innerHTML[[:space:]]*=|outerHTML[[:space:]]*=|document\.write[[:space:]]*\(' "$taste_assets" 2>/dev/null \
      | sed "s|^$taste_assets/|assets/|" | sort || true
    )"
    unlisted_sink="$(comm -13 <(printf '%s\n' "$list_keys") <(printf '%s\n' "$tree_sink_keys") || true)"
    if [[ -n "$unlisted_sink" ]]; then
      printf 'NOTE: %s sink file(s) in the vendored tree NOT on the inclusion list (lab/demo/catalog by classification, or NEW — review each against the inclusion list at re-pin; a new runtime file enters the manifest ONLY by being added to the list after classification):\n%s\n' "$(printf '%s\n' "$unlisted_sink" | grep -c .)" "$unlisted_sink"
    fi
  fi
  if [[ "$allowlist_bad" == 0 ]]; then
    ok "vendored-allowlist.txt matches the vendored taste tree hash-for-hash ($(printf '%s\n' "$allow_keys" | grep -c .) entries, pin $taste_pin)"
  else
    fail "vendored-allowlist.txt does not match the vendored taste tree — see lines above. Re-run vendor-update.sh taste <tag> (and re-classify the sink sites first)."
  fi
fi

# --- fixture page (served over http, never file://) -------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/index.html" <<'EOF'
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>frontend-agent-kit verify fixture</title>
<link rel="icon" href="favicon.ico">
<link rel="stylesheet" href="tokens.css">
<style>body{background:var(--bg);color:var(--ink);padding:var(--space)}</style></head>
<body><main id="main"><h1>Verify fixture</h1><p>A clean page for the loop checks.</p></main></body></html>
EOF
cat > "$work/tokens.css" <<'EOF'
:root { --bg: #ffffff; --ink: #0a0f1e; --space: 16px; }
body { background: var(--bg); color: var(--ink); margin: 0; padding: var(--space); font-family: system-ui, sans-serif; }
EOF
# The fixture is a real project by the gate's own rule (F6): the taste lock
# lives in design/tokens.css — without it gate.sh fails the fixture.
mkdir -p "$work/design"
cp "$work/tokens.css" "$work/design/tokens.css"
# D13 (GAP-11): the fixture gains a minimal design/PLAN.md so the
# converge check actually executes on the §5 gate runs (B §5e, C §4.3 —
# a PLAN-less fixture lets a missing converge-check pass silently via
# a note at gate.sh:466). One section, matching the fixture page's
# <main id="main">; no state matrix (converge-check notes that state
# evidence is unchecked, it does not fail).
cat > "$work/design/PLAN.md" <<'EOF'
## Section inventory

| id | section | notes |
| --- | --- | --- |
| main | Main | Verify fixture content |
EOF
# Q-1 redo: the fixture ships a real favicon.ico so the page logs no
# deterministic favicon 404 console error (the only anomaly on the old
# fixture page — it fired on every page load). Minimal valid 16x16 32bpp
# ICO, generated inline: no external file, no network.
python3 - "$work/favicon.ico" <<'PYEOF'
import struct, sys
w = h = 16
xor = bytes([0x1e, 0x0f, 0x0a, 0xff]) * (w * h)  # solid #0a0f1e, opaque
and_mask = bytes(32)                            # fully opaque
bih = struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, len(xor) + len(and_mask), 0, 0, 0, 0)
img = bih + xor + and_mask
hdr = struct.pack('<HHH', 0, 1, 1)
entry = struct.pack('<BBBBHHII', w, h, 0, 0, 1, 32, len(img), 6 + 16)
open(sys.argv[1], 'wb').write(hdr + entry + img)
PYEOF

# --- 4. impeccable detect runs ----------------------------------------------
if [[ -n "$launcher" && -n "$expected_engine" ]]; then
  detect_out="$("$launcher" detect "$work/index.html" 2>&1)"
  detect_code=$?
  case "$detect_code" in
    0) ok "impeccable detect runs clean on the fixture" ;;
    2) fail "impeccable detect reported findings on the clean fixture (exit 2): $detect_out" ;;
    1) fail "impeccable detect could not scan the fixture (exit 1): $detect_out" ;;
    *) unverified "impeccable detect not runnable (exit $detect_code — engine probably not warmed): $detect_out" ;;
  esac
fi

# --- 5. deterministic gate runs ---------------------------------------------
# D13 (GAP-11): the gate runs TWICE on the same fixture — once from the
# repo clone (regression: guards the move itself) and once from the
# INSTALLED copy (the loop agents actually run). Same fixture, same
# --launcher handling, same detect-skipped → UNVERIFIED / real-failure
# → FAIL distinction on each run. The installed run additionally FAILS
# if its log contains "missing from the kit install" (gate.sh degrades
# missing §3c/§5 helpers to notes, not failures — a gate that silently
# skipped its helpers is not a green gate).
run_gate_leg1() { # <path-to-gate.sh> <log-file> <label>
  local gate_sh="$1" gate_log="$2" label="$3"
  if [[ ! -x "$gate_sh" ]]; then
    fail "gate script missing: $gate_sh ($label)"
    return
  fi
  if "$gate_sh" --target "$work" ${launcher:+--launcher "$launcher"} >"$gate_log" 2>&1; then
    # A passing gate whose detect step was SKIPPED proves only the static
    # checks — the loop's detect leg is unproven (F3). That is UNVERIFIED,
    # not an OK.
    if grep -qi 'detect skipped' "$gate_log"; then
      unverified "gate ran but its impeccable-detect step was skipped (engine not reachable) — static checks alone passed; the loop's detect leg is not proven ($label)"
    else
      ok "gate scripts run ($label)"
    fi
  else
    # A gate that fails ONLY because its detect leg could not run is
    # UNVERIFIED (the loop step is unproven), not a hard FAIL — the new
    # gate.sh fails loudly on a skipped detect (F6) instead of passing on
    # static checks alone, so distinguish that from a real gate failure.
    if grep -qi 'detect skipped\|detect did not complete' "$gate_log"; then
      unverified "gate could not run its impeccable-detect leg on the fixture (engine not reachable) — static checks may have passed, but the loop's detect leg is not proven ($label)"
      cat "$gate_log" >&2 || true
    else
      fail "gate scripts failed on the fixture ($label) — see $gate_log (log removed with temp dir; re-run gate.sh --target <dir> to reproduce)"
      cat "$gate_log" >&2 || true
    fi
  fi
}

# Clone run (regression — guards the move itself).
run_gate_leg1 "$root/skills/frontend-kit/scripts/gate/gate.sh" "$work/gate.log" "repo clone gate.sh on fixture"

# Installed run: the first installed frontend-kit copy that has the gate.
installed_gate_sh=""
installed_gate_mjs=""
while IFS= read -r sd || [[ -n "$sd" ]]; do
  cand="$sd/frontend-kit/scripts/gate/gate.sh"
  if [[ -x "$cand" ]]; then installed_gate_sh="$cand"; installed_gate_mjs="$sd/frontend-kit/scripts/gate/gate.mjs"; break; fi
done < <(all_skills_dirs)
if [[ -z "$installed_gate_sh" ]]; then
  fail "no installed frontend-kit copy has frontend-kit/scripts/gate/gate.sh (D13 §2e should have caught this — the installed skill cannot run the gate)"
else
  run_gate_leg1 "$installed_gate_sh" "$work/gate-installed.log" "installed gate.sh on fixture ($installed_gate_sh)"
  # The installed run must fail if the gate degraded a missing helper to
  # a note instead of failing (gate.sh §3c/§5): a "missing from the kit
  # install" note means the installed copy is incomplete.
  if grep -qi 'missing from the kit install' "$work/gate-installed.log"; then
    fail "installed gate degraded a missing helper to a note (\"missing from the kit install\" in the installed gate log) — the installed copy is incomplete; re-run ./install.sh"
  fi
  # Installed leg 2 (gate.mjs, §5d): exit 0 = green; exit 2 with the
  # --skip-browser marker = browser leg skipped, not green (UNVERIFIED);
  # exit 1 naming the missing Chrome = the browser leg could not run in
  # this environment (UNVERIFIED, same as a skipped detect leg); any
  # other failure = FAIL. NOTE (D13, verified 2026-11-11 on a
  # Chrome-less machine): without Chrome and WITHOUT --skip-browser,
  # gate.mjs exits 1 with "No Chrome, Edge or Chromium found", NOT exit
  # 2 with the skip marker — the skip marker only appears under
  # explicit --skip-browser. The synthesis §5d "exit 2 with the skip
  # marker without [Chrome]" prediction is wrong for that invocation;
  # this section matches the observed exit codes.
  if [[ -f "$installed_gate_mjs" ]]; then
    if node "$installed_gate_mjs" "$work/index.html" >"$work/gate-installed-leg2.log" 2>&1; then
      ok "installed gate leg 2 green (gate.mjs on fixture)"
    elif grep -qi 'browser checks were SKIPPED\|consistency SKIPPED' "$work/gate-installed-leg2.log"; then
      unverified "installed gate leg 2 skipped its browser leg (--skip-browser marker) — copy-lint may have passed, but the browser leg is not proven"
    elif grep -qi 'No Chrome, Edge or Chromium found' "$work/gate-installed-leg2.log"; then
      unverified "installed gate leg 2 could not run its browser leg (no Chrome in this environment) — the loop's browser leg is not proven"
    else
      fail "installed gate leg 2 failed on the fixture — see the installed leg-2 log (log removed with temp dir; re-run gate.mjs <page> to reproduce)"
      cat "$work/gate-installed-leg2.log" >&2 || true
    fi
  else
    fail "installed gate leg 2 missing: $installed_gate_mjs"
  fi
  # Installed gate.sh --self-test (§5d): exit 0 = pass; a failure that
  # is ONLY the skipped detect leg is UNVERIFIED (same distinction as
  # the §5 runs — on an engine-less machine the self-test fixture fails
  # its detect leg by design, F6); any other failure = FAIL.
  if "$installed_gate_sh" --self-test >"$work/gate-installed-selftest.log" 2>&1; then
    ok "installed gate.sh --self-test passes"
  elif grep -qi 'detect skipped\|detect did not complete' "$work/gate-installed-selftest.log"; then
    unverified "installed gate.sh --self-test could not run its impeccable-detect leg (engine not reachable) — the self-test's detect leg is not proven"
  else
    fail "installed gate.sh --self-test failed — see the installed self-test log (log removed with temp dir)"
    cat "$work/gate-installed-selftest.log" >&2 || true
  fi
fi

# --- 5b. run-log gate-artifact refusal (D13, GAP-11) ------------------------
# A --gate pass with no artifacts (or with an artifact missing its PASS
# marker) must be REFUSED (exit 2, nothing written) on both `record`
# and `land`; with well-formed artifacts it records gateLeg1/gateLeg2
# + their sha256. Uses the installed copy's run-log.mjs when one
# exists, else the repo copy (the code under test is the same file).
rl_proj="$work/runlog-proj"
mkdir -p "$rl_proj/design"
cp "$work/tokens.css" "$rl_proj/design/tokens.css"
# D15 adjudication: the setup cross-checks below cite design/cc.md as
# their report, and the D15 crosscheck --report rule requires the cited
# report to exist (a real, non-empty file inside design/) before the
# verdict is recorded — so the shared fixture creates it once, here.
printf '# Cross-check report (verify fixture)\n\nIndependent security cross-check of slice d12-test: 0 severe, 0 warning — verdict clear.\n' > "$rl_proj/design/cc.md"
run_log_mjs=""
while IFS= read -r sd || [[ -n "$sd" ]]; do
  cand="$sd/frontend-kit/scripts/run-log.mjs"
  if [[ -f "$cand" ]]; then run_log_mjs="$cand"; break; fi
done < <(all_skills_dirs)
[[ -z "$run_log_mjs" ]] && run_log_mjs="$root/skills/frontend-kit/scripts/run-log.mjs"
rl_log="$rl_proj/design/run-log.jsonl"
rl_lines() { if [[ -f "$rl_log" ]]; then grep -c . "$rl_log" || true; else printf '0'; fi; }
# (1) record --gate pass with no artifacts → exit 2, nothing written.
if node "$run_log_mjs" --project "$rl_proj" record --round 1 --grader none --scores none --gate pass >"$work/runlog-t1.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass without artifacts exited 0 — a gate pass with no artifact must be refused (exit 2)"
elif [[ -f "$rl_log" ]]; then
  fail "run-log refusal (D13): record --gate pass without artifacts wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass without artifacts (exit 2, nothing written)"
fi
# (2) record --gate pass with an artifact missing its PASS marker → exit 2, nothing written.
printf 'GATE RESULT: FAIL (3 issue(s))\n' > "$rl_proj/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 1 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t2.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a FAIL leg-1 artifact exited 0 — an artifact without its PASS marker must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a FAIL leg-1 artifact wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with an artifact missing its PASS marker (exit 2, nothing written)"
fi
# (3) record --gate pass with well-formed artifacts → exit 0, fields recorded.
printf 'GATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
if node "$run_log_mjs" --project "$rl_proj" record --round 1 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t3.log" 2>&1; then
  if grep -q '"gateLeg1":"design/gate-leg1.log"' "$rl_log" && grep -q '"gateLeg2":"design/gate-leg2.log"' "$rl_log" && grep -q '"gateLeg1Sha":"[0-9a-f]\{64\}"' "$rl_log" && grep -q '"gateLeg2Sha":"[0-9a-f]\{64\}"' "$rl_log"; then
    ok "run-log records record --gate pass with well-formed artifacts (gateLeg1/gateLeg2 + gateLeg1Sha/gateLeg2Sha)"
  else
    fail "run-log refusal (D13): record --gate pass exited 0 but the record lacks gateLeg1/gateLeg2/gateLeg1Sha/gateLeg2Sha"
  fi
else
  fail "run-log refusal (D13): record --gate pass with well-formed artifacts failed — see $work/runlog-t3.log"
  cat "$work/runlog-t3.log" >&2 || true
fi
# (4) land --gate pass without artifacts → exit 2 (the land path must not
# be the bypass). Needs a clear cross-check first, else land refuses for
# the cross-check reason instead of the artifact reason.
if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-cc.log" 2>&1; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass >"$work/runlog-t4.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass without artifacts exited 0 — the land path must not bypass the artifact refusal (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass without artifacts wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses land --gate pass without artifacts (exit 2, nothing written)"
  fi
  # (5) land --gate pass with well-formed artifacts → exit 0.
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t5.log" 2>&1; then
    ok "run-log records land --gate pass with well-formed artifacts"
  else
    fail "run-log refusal (D13): land --gate pass with well-formed artifacts failed — see $work/runlog-t5.log"
    cat "$work/runlog-t5.log" >&2 || true
  fi
else
  fail "run-log refusal (D13): setup cross-check failed, so the land refusal could not be tested — see $work/runlog-cc.log"
  cat "$work/runlog-cc.log" >&2 || true
fi
# F7 (fix round 1): the refusal paths the red team bypassed (F2–F5) get
# their own §5b cases — each asserts exit 2 AND nothing written, so a
# future edit that re-opens any bypass fails verify.sh instead of
# passing it silently. Well-formed artifacts are reset before each case.
rl_reset_artifacts() {
  printf 'GATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
  printf '===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
}
# (6) stale artifacts (page newer than both legs) → exit 2, nothing written.
rl_reset_artifacts
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2030-01-01' "$rl_proj/design/page.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t6.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with stale artifacts exited 0 — artifacts older than --page must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with stale artifacts wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with stale artifacts (exit 2, nothing written)"
fi
touch -d '2026-11-11 12:00' "$rl_proj/design/page.html"
# (7) absolute artifact path → exit 2, nothing written.
rl_reset_artifacts
printf 'GATE RESULT: PASS\n' > "$work/outside-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 "$work/outside-leg1.log" --gate-leg2 design/gate-leg2.log >"$work/runlog-t7.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with an absolute artifact path exited 0 — absolute paths must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with an absolute artifact path wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with an absolute artifact path (exit 2, nothing written)"
fi
# (8) true `..` escape (artifact outside design/) → exit 2, nothing written.
rl_reset_artifacts
printf 'GATE RESULT: PASS\n' > "$work/escape-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 ../escape-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t8.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a '..' escape artifact exited 0 — paths resolving outside design/ must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a '..' escape artifact wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with a '..' escape artifact (exit 2, nothing written)"
fi
# (9a) leg-1 artifact with a PASS string in a comment plus its real FAIL
# verdict → exit 2, nothing written (F5).
rl_reset_artifacts
printf '# NOTE: I wish this said GATE RESULT: PASS but the gate failed\nGATE RESULT: FAIL (3 issue(s))\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t9a.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a leg-1 artifact carrying a FAIL verdict exited 0 — a FAIL verdict must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a leg-1 artifact carrying a FAIL verdict wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with a leg-1 artifact carrying a FAIL verdict (exit 2, nothing written)"
fi
# (9b) leg-2 artifact with a GREEN string in a comment plus its real FAIL
# verdict → exit 2, nothing written (F5).
rl_reset_artifacts
printf '// ===== gate verdict: GREEN ===== is what we want\n===== gate verdict: FAIL (exit 1) =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t9b.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a leg-2 artifact carrying a FAIL verdict exited 0 — a FAIL verdict must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a leg-2 artifact carrying a FAIL verdict wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with a leg-2 artifact carrying a FAIL verdict (exit 2, nothing written)"
fi
# (10) one file cited as both legs → exit 2, nothing written (F4).
rl_reset_artifacts
printf 'GATE RESULT: PASS\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/both.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/both.log --gate-leg2 design/both.log >"$work/runlog-t10.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with one file as both legs exited 0 — the two legs must be two separate files (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with one file as both legs wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with one file as both legs (exit 2, nothing written)"
fi
# (10b) hardlink pair (same inode, two names) as the two legs → exit 2.
if ln "$rl_proj/design/both.log" "$rl_proj/design/both2.log" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/both.log --gate-leg2 design/both2.log >"$work/runlog-t10b.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with a hardlink pair as both legs exited 0 — same device+inode is one file, not two legs (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with a hardlink pair as both legs wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with a hardlink pair as both legs (exit 2, nothing written)"
  fi
else
  unverified "run-log hardlink-pair refusal case skipped — this environment cannot create a hardlink"
fi
rm -f "$rl_proj/design/both.log" "$rl_proj/design/both2.log"
# (11) --page outside the project → exit 2, nothing written (F3).
rl_reset_artifacts
printf '<html>old</html>\n' > "$work/ancient-page.html"
touch -d '2019-01-01' "$work/ancient-page.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page "$work/ancient-page.html" >"$work/runlog-t11.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page outside the project exited 0 — an outside file cannot be the freshness reference (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page outside the project wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page outside the project (exit 2, nothing written)"
fi
# (11b) --page that IS one of the artifact files → exit 2, nothing written.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/gate-leg1.log >"$work/runlog-t11b.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page as its own artifact exited 0 — an artifact cannot be its own freshness reference (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page as its own artifact wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page as its own artifact (exit 2, nothing written)"
fi
# (11c) land with --page outside the project → exit 2, nothing written
# (the cross-check from case (4) is still clear, so only the --page
# refusal can reject this land).
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page "$work/ancient-page.html" >"$work/runlog-t11c.log" 2>&1; then
  fail "run-log refusal (D13): land --gate pass with --page outside the project exited 0 — the land path must not bypass the --page refusal (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): land --gate pass with --page outside the project wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses land --gate pass with --page outside the project (exit 2, nothing written)"
fi
# (12) symlink artifact (inside design/, target outside) → exit 2,
# nothing written (F2). Skipped, not failed, where the environment
# cannot create a symlink.
rl_reset_artifacts
printf 'GATE RESULT: PASS\n' > "$work/outside-evil.log"
touch -d '2030-01-01' "$work/outside-evil.log"
if mv "$rl_proj/design/gate-leg1.log" "$rl_proj/design/gate-leg1.real" && ln -s "$work/outside-evil.log" "$rl_proj/design/gate-leg1.log" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t12.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with a symlink artifact exited 0 — a symlink to a file outside the project must be refused (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with a symlink artifact wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with a symlink artifact (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/gate-leg1.log"
  mv "$rl_proj/design/gate-leg1.real" "$rl_proj/design/gate-leg1.log"
else
  if [[ -f "$rl_proj/design/gate-leg1.real" ]]; then
    rm -f "$rl_proj/design/gate-leg1.log"
    mv "$rl_proj/design/gate-leg1.real" "$rl_proj/design/gate-leg1.log"
  fi
  unverified "run-log symlink-artifact refusal case skipped — this environment cannot create a symlink"
fi
# (13) R1 (fix round 2): design/ itself symlinked to a directory outside
# the project → exit 2, nothing written. The outside dir holds
# marker-only logs + tokens.css, so the pre-fix validator passes them.
rl_reset_artifacts
mkdir -p "$work/rl-outdesign"
printf 'GATE RESULT: PASS\n' > "$work/rl-outdesign/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$work/rl-outdesign/gate-leg2.log"
printf ':root{}\n' > "$work/rl-outdesign/tokens.css"
printf '# Cross-check report (verify fixture)\n\nIndependent security cross-check of slice d12-test: 0 severe, 0 warning — verdict clear.\n' > "$work/rl-outdesign/cc.md"
touch -d '2026-11-11 12:00' "$work/rl-outdesign/tokens.css"
if mv "$rl_proj/design" "$work/rl-design-backup" && ln -s "$work/rl-outdesign" "$rl_proj/design" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t13.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with design/ symlinked outside the project exited 0 — a design/ outside the project must be refused (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with design/ symlinked outside the project wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with design/ symlinked outside the project (exit 2, nothing written)"
  fi
  # (13b) R1 on land + D15 on crosscheck: same symlinked design/. Under
  # D15 the cross-check itself is refused here — its report must resolve
  # inside the project's real design/ (the cc.md in the outside dir
  # exists, so the refusal is the containment rule, not a missing file).
  # Land needs no seeded verdict to reach its refusal: land validates
  # the gate artifacts — which refuse a design/ outside the project —
  # before it reads any cross-check verdict. Both refusals are asserted
  # (exit 2, containment message, nothing written) as this one case.
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t13b-cc.log" 2>&1; then
    fail "run-log refusal (D15): crosscheck --report design/cc.md with design/ symlinked outside the project exited 0 — a cross-check report must resolve inside the project's design/ (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D15): crosscheck with design/ symlinked outside the project wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "resolves outside the project" "$work/runlog-t13b-cc.log"; then
    fail "run-log refusal (D15): crosscheck with design/ symlinked outside the project exited 2 but not via the design/ containment message — see $work/runlog-t13b-cc.log"
    cat "$work/runlog-t13b-cc.log" >&2 || true
  elif node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t13b.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with design/ symlinked outside the project exited 0 — the land path must not bypass the design/ refusal (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with design/ symlinked outside the project wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "resolves outside the project" "$work/runlog-t13b.log"; then
    fail "run-log refusal (D13): land --gate pass with design/ symlinked outside the project exited 2 but not via the design/ containment message — see $work/runlog-t13b.log"
    cat "$work/runlog-t13b.log" >&2 || true
  else
    ok "run-log refuses crosscheck and land --gate pass with design/ symlinked outside the project (exit 2, containment message, nothing written)"
  fi
  rm -f "$rl_proj/design"
  mv "$work/rl-design-backup" "$rl_proj/design"
else
  if [[ -d "$work/rl-design-backup" && ! -e "$rl_proj/design" ]]; then
    mv "$work/rl-design-backup" "$rl_proj/design"
  fi
  unverified "run-log symlinked-design/ refusal case skipped — this environment cannot move/symlink the design directory"
fi
# (13c) R1 positive control: design/ symlinked to a directory INSIDE the
# project is accepted (containment, not outright rejection) → exit 0.
rl_reset_artifacts
if mv "$rl_proj/design" "$rl_proj/design-real" && ln -s design-real "$rl_proj/design" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t13c.log" 2>&1; then
    if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
      ok "run-log records record --gate pass with design/ symlinked inside the project (exit 0)"
    else
      fail "run-log refusal (D13): record --gate pass with design/ symlinked inside the project exited 0 but did not append exactly one line"
    fi
  else
    fail "run-log refusal (D13): record --gate pass with design/ symlinked inside the project failed — an inside-project design/ symlink must be accepted (exit 0); see $work/runlog-t13c.log"
    cat "$work/runlog-t13c.log" >&2 || true
  fi
  rm -f "$rl_proj/design"
  mv "$rl_proj/design-real" "$rl_proj/design"
else
  if [[ -d "$rl_proj/design-real" && ! -e "$rl_proj/design" ]]; then
    mv "$rl_proj/design-real" "$rl_proj/design"
  fi
  unverified "run-log inside-symlink design/ case skipped — this environment cannot move/symlink the design directory"
fi
# (14) R2 (fix round 2): --page as a hardlink to a leg artifact, with
# stale artifacts → exit 2, nothing written (the hardlink shares the
# leg's inode, so it is the artifact even though its realpath differs).
rl_reset_artifacts
touch -d '2020-01-01' "$rl_proj/design/gate-leg1.log" "$rl_proj/design/gate-leg2.log"
if ln "$rl_proj/design/gate-leg1.log" "$rl_proj/design/page-hard.html" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page-hard.html >"$work/runlog-t14.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with --page hardlinked to a leg artifact exited 0 — an artifact cannot be its own freshness reference (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with --page hardlinked to a leg artifact wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with --page hardlinked to gate-leg1.log (exit 2, nothing written)"
  fi
  # (14b) R2 on land, same hardlink (the case-(4) cross-check is still clear).
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page-hard.html >"$work/runlog-t14b.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with --page hardlinked to a leg artifact exited 0 — the land path must not bypass the hardlink---page refusal (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with --page hardlinked to a leg artifact wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses land --gate pass with --page hardlinked to gate-leg1.log (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/page-hard.html"
else
  unverified "run-log hardlink---page refusal case skipped — this environment cannot create a hardlink"
fi
# (14c) R2, leg-2 variant: --page hardlinked to gate-leg2.log → exit 2.
if ln "$rl_proj/design/gate-leg2.log" "$rl_proj/design/page-hard.html" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page-hard.html >"$work/runlog-t14c.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with --page hardlinked to gate-leg2.log exited 0 — an artifact cannot be its own freshness reference (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with --page hardlinked to gate-leg2.log wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with --page hardlinked to gate-leg2.log (exit 2, nothing written)"
  fi
  # (14d) R2 leg-2 variant on land.
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page-hard.html >"$work/runlog-t14d.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with --page hardlinked to gate-leg2.log exited 0 — the land path must not bypass the hardlink---page refusal (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with --page hardlinked to gate-leg2.log wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses land --gate pass with --page hardlinked to gate-leg2.log (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/page-hard.html"
else
  unverified "run-log hardlink---page (leg 2) refusal case skipped — this environment cannot create a hardlink"
fi
rl_reset_artifacts
# (15) R3 (fix round 2): --page an old .html inside design/ (2019), older
# than tokens.css → exit 2, nothing written (anchor: tokens <= page).
printf '<html>old</html>\n' > "$rl_proj/design/ancient.html"
touch -d '2019-01-01' "$rl_proj/design/ancient.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/ancient.html >"$work/runlog-t15.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page older than tokens.css exited 0 — a page older than the locked tokens must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page older than tokens.css wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with an ancient --page inside design/ (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/ancient.html"
# (16) R3: --page a non-HTML file outside design/ (README.md) → exit 2.
printf '# readme\n' > "$rl_proj/README.md"
touch -d '2019-01-01' "$rl_proj/README.md"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page README.md >"$work/runlog-t16.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page README.md exited 0 — the freshness reference must be the built .html page inside design/ (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page README.md wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page README.md (exit 2, nothing written)"
fi
rm -f "$rl_proj/README.md"
# (17) R3: --page a freshly created file backdated to 2019 → exit 2.
printf '<html>new-old</html>\n' > "$rl_proj/design/brand-new-old.html"
touch -d '2019-01-01' "$rl_proj/design/brand-new-old.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/brand-new-old.html >"$work/runlog-t17.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a freshly created backdated --page exited 0 — a page older than the locked tokens must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a freshly created backdated --page wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with a freshly created backdated --page (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/brand-new-old.html"
# (18) R3 fallback: design/tokens.css symlinked to an old in-design file,
# no --page → exit 2, nothing written (the fallback reference must be
# the real tokens file, not a link).
rl_reset_artifacts
printf ':root{old}\n' > "$rl_proj/design/old.css"
touch -d '2019-01-01' "$rl_proj/design/old.css"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && ln -s old.css "$rl_proj/design/tokens.css" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t18.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with a symlinked design/tokens.css fallback exited 0 — the fallback reference must be the real tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with a symlinked design/tokens.css fallback wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with a symlinked design/tokens.css fallback (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
else
  if [[ -f "$rl_proj/design/tokens.real" ]]; then
    rm -f "$rl_proj/design/tokens.css"
    mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  fi
  unverified "run-log symlinked-tokens.css fallback case skipped — this environment cannot create a symlink"
fi
rm -f "$rl_proj/design/old.css"
# (19) R4 (fix round 2): a passing log containing FAILURE/FAILED lines
# (plus a realistic green log's `0 failed checks` / `0 failures` /
# `FAILURE count: 0`) → exit 0, recorded.
rl_reset_artifacts
printf '0 failed checks\n0 failures\nFAILURE count: 0\nGATE RESULT: PASS\nGATE RESULT: FAILURE is not a verdict\nGATE RESULT: FAILED too\n' > "$rl_proj/design/gate-leg1.log"
printf '0 failed checks\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t19.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with FAILURE/FAILED lines in a passing log (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with FAILURE/FAILED lines in a passing log exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with FAILURE/FAILED lines in a passing log failed — FAILURE/FAILED are not FAIL verdicts (exit 0); see $work/runlog-t19.log"
  cat "$work/runlog-t19.log" >&2 || true
fi
# (20a) R5 (fix round 2): --gate fail with an outside --page → exit 0,
# fail recorded, stored page: null, warning on stderr.
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page "$work/ancient-page.html" >"$work/runlog-t20a.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && grep -q 'WARNING' "$work/runlog-t20a.log"; then
    ok "run-log records --gate fail with an outside --page as page: null with a warning (exit 0)"
  else
    fail "run-log refusal (D13): --gate fail with an outside --page exited 0 but did not record page: null with a warning"
  fi
else
  fail "run-log refusal (D13): --gate fail with an outside --page failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t20a.log"
  cat "$work/runlog-t20a.log" >&2 || true
fi
# (20b) R5: --gate fail with --page as an artifact → exit 0, page: null, warning.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page design/gate-leg1.log >"$work/runlog-t20b.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && grep -q 'WARNING' "$work/runlog-t20b.log"; then
    ok "run-log records --gate fail with --page as an artifact as page: null with a warning (exit 0)"
  else
    fail "run-log refusal (D13): --gate fail with --page as an artifact exited 0 but did not record page: null with a warning"
  fi
else
  fail "run-log refusal (D13): --gate fail with --page as an artifact failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t20b.log"
  cat "$work/runlog-t20b.log" >&2 || true
fi
# (20c) R5 positive: --gate fail with a valid --page → exit 0, canonical page stored.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page design/page.html >"$work/runlog-t20c.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":"design/page.html"'; then
    ok "run-log records --gate fail with a valid --page (exit 0, canonical page stored)"
  else
    fail "run-log refusal (D13): --gate fail with a valid --page exited 0 but did not store the canonical page"
  fi
else
  fail "run-log refusal (D13): --gate fail with a valid --page failed — see $work/runlog-t20c.log"
  cat "$work/runlog-t20c.log" >&2 || true
fi
# (21) R3 positive: --page a fresh .html inside design/ → exit 0.
# (Case (6) left page.html at 12:00, older than the copied tokens.css, so
# both are set to 12:00 here — equal mtimes allowed — to keep the
# tokens <= page anchor and the artifacts >= page freshness both true.)
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t21.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":"design/page.html"'; then
    ok "run-log records record --gate pass with a fresh --page inside design/ (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with a fresh --page exited 0 but did not store the canonical page"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a fresh --page failed — see $work/runlog-t21.log"
  cat "$work/runlog-t21.log" >&2 || true
fi
# (22) R3 positive: --page design/tokens.css itself → exit 0.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/tokens.css >"$work/runlog-t22.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":"design/tokens.css"'; then
    ok "run-log records record --gate pass with --page design/tokens.css (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with --page design/tokens.css exited 0 but did not store the canonical page"
  fi
else
  fail "run-log refusal (D13): record --gate pass with --page design/tokens.css failed — see $work/runlog-t22.log"
  cat "$work/runlog-t22.log" >&2 || true
fi
# (23) R3 positive: --page a hardlink to tokens.css → exit 0.
if ln "$rl_proj/design/tokens.css" "$rl_proj/design/tokens-hard.css" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/tokens-hard.css >"$work/runlog-t23.log" 2>&1; then
    if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":"design/tokens-hard.css"'; then
      ok "run-log records record --gate pass with --page hardlinked to tokens.css (exit 0)"
    else
      fail "run-log refusal (D13): record --gate pass with --page hardlinked to tokens.css exited 0 but did not store the canonical page"
    fi
  else
    fail "run-log refusal (D13): record --gate pass with --page hardlinked to tokens.css failed — see $work/runlog-t23.log"
    cat "$work/runlog-t23.log" >&2 || true
  fi
  rm -f "$rl_proj/design/tokens-hard.css"
else
  unverified "run-log hardlink-to-tokens.css --page case skipped — this environment cannot create a hardlink"
fi
# (24) S1 (fix round 3): design/tokens.css as a directory (empty, current
# mtime) + --page design/page.html → exit 2, nothing written. The anchor
# must be the real tokens file, mirroring the no---page fallback.
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && mkdir "$rl_proj/design/tokens.css" 2>/dev/null; then
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css"
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t24.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a directory exited 0 — the freshness anchor must be the real tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a directory wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with design/tokens.css as a directory (exit 2, nothing written)"
  fi
  # (24b) S1 on land: same shape, after a fresh clear cross-check.
  if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t24b-cc.log" 2>&1; then
    rl_before="$(rl_lines)"
    if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t24b.log" 2>&1; then
      fail "run-log refusal (D13): land --gate pass with design/tokens.css as a directory exited 0 — the land path must not bypass the anchor refusal (exit 2)"
    elif [[ "$(rl_lines)" != "$rl_before" ]]; then
      fail "run-log refusal (D13): land --gate pass with design/tokens.css as a directory wrote to the run log — a refused entry must write nothing"
    else
      ok "run-log refuses land --gate pass with design/tokens.css as a directory (exit 2, nothing written)"
    fi
  else
    fail "run-log refusal (D13): setup cross-check failed for the directory-tokens.css land case — see $work/runlog-t24b-cc.log"
    cat "$work/runlog-t24b-cc.log" >&2 || true
  fi
  rm -rf "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -d "$rl_proj/design/tokens.css" ]]; then rmdir "$rl_proj/design/tokens.css" 2>/dev/null || true; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the directory-tokens.css case — could not replace design/tokens.css with a directory"
fi
# (25) S2 (fix round 3): --page design/.html (empty basename) → exit 2,
# nothing written.
rl_reset_artifacts
printf '<html>dot</html>\n' > "$rl_proj/design/.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/.html >"$work/runlog-t25.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/.html exited 0 — a dotfile with an empty basename is not a built page (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/.html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/.html (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/.html"
# (26a) S3 (fix round 3): PASS line with NBSP (U+00A0, octal \302\240)
# inside the marker → exit 0, recorded. A copied verdict line with
# invisible unicode must not false-reject a real pass.
rl_reset_artifacts
printf 'GATE RESULT:\302\240PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t26a.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with NBSP inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with NBSP inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with NBSP inside the PASS line failed — invisible unicode must not false-reject a real pass (exit 0); see $work/runlog-t26a.log"
  cat "$work/runlog-t26a.log" >&2 || true
fi
# (26b) S3: PASS line with a trailing ZWSP (U+200B, octal \342\200\213)
# → exit 0, recorded.
rl_reset_artifacts
printf 'GATE RESULT: PASS\342\200\213\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t26b.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with a trailing ZWSP after the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with a trailing ZWSP after the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a trailing ZWSP after the PASS line failed — invisible unicode must not false-reject a real pass (exit 0); see $work/runlog-t26b.log"
  cat "$work/runlog-t26b.log" >&2 || true
fi
# (27) Nested-symlink design/ (design -> inner link -> OUTSIDE dir) →
# exit 2, nothing written. Only a direct symlink is tested by (13);
# realpathSync must resolve the full chain.
rl_reset_artifacts
mkdir -p "$work/rl-nested-out"
printf 'GATE RESULT: PASS\n' > "$work/rl-nested-out/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$work/rl-nested-out/gate-leg2.log"
printf ':root{}\n' > "$work/rl-nested-out/tokens.css"
touch -d '2026-11-11 12:00' "$work/rl-nested-out/tokens.css"
rm -f "$work/rl-nested-mid"
ln -s "$work/rl-nested-out" "$work/rl-nested-mid" 2>/dev/null
if mv "$rl_proj/design" "$work/rl-design-backup2" && ln -s "$work/rl-nested-mid" "$rl_proj/design" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t27.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with a nested-symlink design/ exited 0 — a design/ resolving outside the project through a symlink chain must be refused (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with a nested-symlink design/ wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with a nested-symlink design/ (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design"
  mv "$work/rl-design-backup2" "$rl_proj/design"
else
  if [[ -d "$work/rl-design-backup2" && ! -e "$rl_proj/design" ]]; then
    mv "$work/rl-design-backup2" "$rl_proj/design"
  fi
  unverified "run-log nested-symlink design/ refusal case skipped — this environment cannot move/symlink the design directory"
fi
# (28) Missing design/tokens.css + --page → exit 2, nothing written (the
# anchor cannot be computed — only old-page cases (15)/(17) tested it).
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t28.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with a missing design/tokens.css exited 0 — freshness cannot be anchored without the tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with a missing design/tokens.css wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses record --gate pass with a missing design/tokens.css plus --page (exit 2, nothing written)"
  fi
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  fail "run-log refusal (D13): setup failed for the missing-tokens.css case — could not move design/tokens.css aside"
fi
# (29a) R5: --gate fail with --page a directory → exit 0, fail recorded,
# stored page: null, warning on stderr.
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page design >"$work/runlog-t29a.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && grep -q 'WARNING' "$work/runlog-t29a.log"; then
    ok "run-log records --gate fail with --page a directory as page: null with a warning (exit 0)"
  else
    fail "run-log refusal (D13): --gate fail with --page a directory exited 0 but did not record page: null with a warning"
  fi
else
  fail "run-log refusal (D13): --gate fail with --page a directory failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t29a.log"
  cat "$work/runlog-t29a.log" >&2 || true
fi
# (29b) R5: --gate fail with --page nonexistent → exit 0, page: null, warning.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page design/nope.html >"$work/runlog-t29b.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && grep -q 'WARNING' "$work/runlog-t29b.log"; then
    ok "run-log records --gate fail with a nonexistent --page as page: null with a warning (exit 0)"
  else
    fail "run-log refusal (D13): --gate fail with a nonexistent --page exited 0 but did not record page: null with a warning"
  fi
else
  fail "run-log refusal (D13): --gate fail with a nonexistent --page failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t29b.log"
  cat "$work/runlog-t29b.log" >&2 || true
fi
# (29c) R5: --gate fail with --page "" (empty string) → exit 0, page: null,
# NO warning — an empty string is falsy, consistent with absent --page.
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page "" >"$work/runlog-t29c.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && ! grep -q 'WARNING' "$work/runlog-t29c.log"; then
    ok "run-log records --gate fail with an empty --page as page: null with no warning (exit 0)"
  else
    fail "run-log refusal (D13): --gate fail with an empty --page exited 0 but did not record page: null with no warning"
  fi
else
  fail "run-log refusal (D13): --gate fail with an empty --page failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t29c.log"
  cat "$work/runlog-t29c.log" >&2 || true
fi
# (30) B7e: --gate fail + symlinked design/ + valid --page → exit 0,
# stored page: null, WARNING; the record lands in the OUTSIDE dir's log
# (logPath joins project/design without realpath) while the project's
# real log gains no line — the stored VALUES are correct, only the log
# LOCATION follows the symlink (documented consequence, not a fix).
rl_reset_artifacts
mkdir -p "$work/rl-b7e-out"
printf '<html><body><main id="main">x</main></body></html>\n' > "$work/rl-b7e-out/page.html"
if mv "$rl_proj/design" "$work/rl-design-backup3" && ln -s "$work/rl-b7e-out" "$rl_proj/design" 2>/dev/null; then
  rl_real_before="$(grep -c . "$work/rl-design-backup3/run-log.jsonl" || true)"
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate fail --page design/page.html >"$work/runlog-t30.log" 2>&1; then
    if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":null' && grep -q 'WARNING' "$work/runlog-t30.log" && [[ "$(grep -c . "$work/rl-design-backup3/run-log.jsonl" || true)" == "$rl_real_before" ]]; then
      ok "run-log records --gate fail with a symlinked design/ and valid --page as page: null with a warning, real log unchanged (exit 0)"
    else
      fail "run-log refusal (D13): --gate fail with a symlinked design/ and valid --page exited 0 but did not record page: null with a warning and an unchanged real log"
    fi
  else
    fail "run-log refusal (D13): --gate fail with a symlinked design/ and valid --page failed — a fail record must be recorded with page: null (exit 0); see $work/runlog-t30.log"
    cat "$work/runlog-t30.log" >&2 || true
  fi
  rm -f "$rl_proj/design"
  mv "$work/rl-design-backup3" "$rl_proj/design"
else
  if [[ -d "$work/rl-design-backup3" && ! -e "$rl_proj/design" ]]; then
    mv "$work/rl-design-backup3" "$rl_proj/design"
  fi
  unverified "run-log symlinked-design/ fail case skipped — this environment cannot move/symlink the design directory"
fi
# (31) S2 shape: --page design/page.htm → exit 2, nothing written.
rl_reset_artifacts
printf '<html>htm</html>\n' > "$rl_proj/design/page.htm"
touch -d '2026-11-11 12:00' "$rl_proj/design/page.htm"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.htm >"$work/runlog-t31.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/page.htm exited 0 — the freshness reference must be an .html file (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/page.htm wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/page.htm (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/page.htm"
# (32) Trailing-slash --page design/page.html/ → exit 0, stored
# canonically as design/page.html (path.resolve normalises the slash).
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html/ >"$work/runlog-t32.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]] && tail -n 1 "$rl_log" | grep -q '"page":"design/page.html"'; then
    ok "run-log records record --gate pass with a trailing-slash --page (exit 0, canonical page stored)"
  else
    fail "run-log refusal (D13): record --gate pass with a trailing-slash --page exited 0 but did not store the canonical page"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a trailing-slash --page failed — see $work/runlog-t32.log"
  cat "$work/runlog-t32.log" >&2 || true
fi
# (33) R4 mixed-case: leg-1 log with `Gate Result: Fail` and
# `GATE RESULT: Fail` lines alongside the real PASS line → exit 0,
# recorded (the FAIL marker is the gate's uppercase verdict line).
rl_reset_artifacts
printf 'Gate Result: Fail\nGATE RESULT: Fail\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t33.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with mixed-case FAIL lines alongside a real PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with mixed-case FAIL lines alongside a real PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with mixed-case FAIL lines alongside a real PASS line failed — mixed-case FAIL is not the uppercase verdict (exit 0); see $work/runlog-t33.log"
  cat "$work/runlog-t33.log" >&2 || true
fi
# (34) T1 (fix round 4): PASS line with U+2003 EM SPACE (octal
# \342\200\203) inside the marker → exit 0, recorded. The fix-round-3
# normaliser handled only NBSP + zero-width/BOM; the round-4 fold covers
# the full Unicode White_Space class.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\203PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t34.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+2003 inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+2003 inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+2003 inside the PASS line failed — invisible unicode must not false-reject a real pass (exit 0); see $work/runlog-t34.log"
  cat "$work/runlog-t34.log" >&2 || true
fi
# (35) T1 leg 2 (fix round 4): `===== gate verdict:<U+2003>GREEN =====`
# → exit 0, recorded.
rl_reset_artifacts
printf '===== gate verdict:\342\200\203GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t35.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+2003 inside the leg-2 PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+2003 inside the leg-2 PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+2003 inside the leg-2 PASS line failed — invisible unicode must not false-reject a real pass (exit 0); see $work/runlog-t35.log"
  cat "$work/runlog-t35.log" >&2 || true
fi
# (36) T1 FAILhide leg 1 (fix round 4): `GATE RESULT:<U+2003>FAIL
# (3 issue(s))` followed by a real `GATE RESULT: PASS` → exit 2 via the
# FAIL-verdict message, nothing written. The exotic-space FAIL line must
# not hide behind the real PASS line.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\203FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t36.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t36.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t36.log"
  cat "$work/runlog-t36.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2003 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (37) T1 FAILhide leg 2 (fix round 4): `===== gate verdict:<U+2003>FAIL
# (exit 1) =====` followed by a real GREEN line → exit 2 via the
# FAIL-verdict message, nothing written.
rl_reset_artifacts
printf '===== gate verdict:\342\200\203FAIL (exit 1) =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t37.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real GREEN line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real GREEN line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t37.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line alongside a real GREEN line exited 2 but not via the FAIL-verdict message — see $work/runlog-t37.log"
  cat "$work/runlog-t37.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2003 FAIL line alongside a real GREEN line (exit 2, FAIL-verdict message, nothing written)"
fi
# (38) T2 ZWSP-substitution leg 1 (fix round 4): `GATE RESULT:<U+200B>PASS`
# (ZWSP, octal \342\200\213, REPLACING the space after the colon) →
# exit 0, recorded. The fix-round-3 strip-only normaliser read this as
# `GATE RESULT:PASS`; the round-4 map variant reads it as the verdict.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\213PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t38.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with ZWSP substituting for the space in the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with ZWSP substituting for the space in the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with ZWSP substituting for the space in the PASS line failed — a zero-width character substituting for a space must not false-reject a real pass (exit 0); see $work/runlog-t38.log"
  cat "$work/runlog-t38.log" >&2 || true
fi
# (39) T2 ZWSP-substitution leg 2 (fix round 4): `===== gate verdict:
# <U+200B>GREEN =====` → exit 0, recorded.
rl_reset_artifacts
printf '===== gate verdict:\342\200\213GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t39.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with ZWSP substituting for the space in the leg-2 PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with ZWSP substituting for the space in the leg-2 PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with ZWSP substituting for the space in the leg-2 PASS line failed — a zero-width character substituting for a space must not false-reject a real pass (exit 0); see $work/runlog-t39.log"
  cat "$work/runlog-t39.log" >&2 || true
fi
# (40) T2 ZWSP-substitution FAILhide leg 1 (fix round 4):
# `GATE RESULT:<U+200B>FAIL (3 issue(s))` + real PASS → exit 2 via the
# FAIL-verdict message, nothing written.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\213FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t40.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t40.log"; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t40.log"
  cat "$work/runlog-t40.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a ZWSP-substituted FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (41) T2 ZWSP-substitution FAILhide leg 2 (fix round 4): `===== gate
# verdict:<U+200B>FAIL (exit 1) =====` + real GREEN → exit 2 via the
# FAIL-verdict message, nothing written.
rl_reset_artifacts
printf '===== gate verdict:\342\200\213FAIL (exit 1) =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t41.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real GREEN line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real GREEN line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t41.log"; then
  fail "run-log refusal (D13): record --gate pass with a ZWSP-substituted FAIL line alongside a real GREEN line exited 2 but not via the FAIL-verdict message — see $work/runlog-t41.log"
  cat "$work/runlog-t41.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a ZWSP-substituted FAIL line alongside a real GREEN line (exit 2, FAIL-verdict message, nothing written)"
fi
# (42) U+180E leg 1 (fix round 4): `GATE RESULT:<U+180E>PASS` (Mongolian
# vowel separator, octal \341\240\216 — not Unicode White_Space, handled
# for completeness as the historical straggler) → exit 0, recorded.
rl_reset_artifacts
printf 'GATE RESULT:\341\240\216PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t42.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+180E inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+180E inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+180E inside the PASS line failed — U+180E must not false-reject a real pass (exit 0); see $work/runlog-t42.log"
  cat "$work/runlog-t42.log" >&2 || true
fi
# (43) U+180E leg 2 (fix round 4): `===== gate verdict:<U+180E>GREEN
# =====` → exit 0, recorded.
rl_reset_artifacts
printf '===== gate verdict:\341\240\216GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t43.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+180E inside the leg-2 PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+180E inside the leg-2 PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+180E inside the leg-2 PASS line failed — U+180E must not false-reject a real pass (exit 0); see $work/runlog-t43.log"
  cat "$work/runlog-t43.log" >&2 || true
fi
# (44) S1 FIFO (fix round 4): design/tokens.css as a FIFO + --page
# design/page.html → exit 2, nothing written (the S1 isFile() anchor
# check covers FIFOs exactly as it covers directories).
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && mkfifo "$rl_proj/design/tokens.css" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t44.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a FIFO exited 0 — the freshness anchor must be the real tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a FIFO wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "is not a regular file" "$work/runlog-t44.log"; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a FIFO exited 2 but not via the regular-file message — see $work/runlog-t44.log"
    cat "$work/runlog-t44.log" >&2 || true
  else
    ok "run-log refuses record --gate pass with design/tokens.css as a FIFO (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -p "$rl_proj/design/tokens.css" ]]; then rm -f "$rl_proj/design/tokens.css"; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the FIFO-tokens.css case — could not replace design/tokens.css with a FIFO"
fi
# (45) S1 Unix socket (fix round 4): design/tokens.css as a Unix-domain
# socket (python3 AF_UNIX bind; the socket file persists after the
# binder exits) + --page design/page.html → exit 2, nothing written.
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && python3 -c "import socket; s = socket.socket(socket.AF_UNIX); s.bind('$rl_proj/design/tokens.css'); s.close()" 2>/dev/null; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t45.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a Unix socket exited 0 — the freshness anchor must be the real tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a Unix socket wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "is not a regular file" "$work/runlog-t45.log"; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a Unix socket exited 2 but not via the regular-file message — see $work/runlog-t45.log"
    cat "$work/runlog-t45.log" >&2 || true
  else
    ok "run-log refuses record --gate pass with design/tokens.css as a Unix socket (exit 2, nothing written)"
  fi
  rm -f "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -S "$rl_proj/design/tokens.css" ]]; then rm -f "$rl_proj/design/tokens.css"; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the socket-tokens.css case — could not replace design/tokens.css with a Unix socket (python3 AF_UNIX bind)"
fi
# (46) S1 directory on the FALLBACK path (fix round 4): design/tokens.css
# as a directory, NO --page → exit 2, nothing written, via the unchanged
# fallback message (only the --page path was tested by (24)).
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && mkdir "$rl_proj/design/tokens.css" 2>/dev/null; then
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css"
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t46.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a directory and no --page exited 0 — the fallback anchor must be the real tokens file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a directory and no --page wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "freshness cannot be checked" "$work/runlog-t46.log"; then
    fail "run-log refusal (D13): record --gate pass with design/tokens.css as a directory and no --page exited 2 but not via the unchanged fallback message — see $work/runlog-t46.log"
    cat "$work/runlog-t46.log" >&2 || true
  else
    ok "run-log refuses record --gate pass with design/tokens.css as a directory and no --page (exit 2, fallback message, nothing written)"
  fi
  rm -rf "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -d "$rl_proj/design/tokens.css" ]]; then rmdir "$rl_proj/design/tokens.css" 2>/dev/null || true; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the directory-tokens.css fallback case — could not replace design/tokens.css with a directory"
fi
# (47) S1 directory + --page the directory itself (fix round 4):
# design/tokens.css as a directory + --page design/tokens.css → exit 2,
# nothing written, via the "--page must be a regular file" message (the
# --page regular-file check fires before the tokens.css exception).
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && mkdir "$rl_proj/design/tokens.css" 2>/dev/null; then
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css"
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/tokens.css >"$work/runlog-t47.log" 2>&1; then
    fail "run-log refusal (D13): record --gate pass with --page design/tokens.css when tokens.css is a directory exited 0 — --page must be a regular file (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): record --gate pass with --page design/tokens.css when tokens.css is a directory wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "must be a regular file" "$work/runlog-t47.log"; then
    fail "run-log refusal (D13): record --gate pass with --page design/tokens.css when tokens.css is a directory exited 2 but not via the regular-file message — see $work/runlog-t47.log"
    cat "$work/runlog-t47.log" >&2 || true
  else
    ok "run-log refuses record --gate pass with --page design/tokens.css when tokens.css is a directory (exit 2, nothing written)"
  fi
  rm -rf "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -d "$rl_proj/design/tokens.css" ]]; then rmdir "$rl_proj/design/tokens.css" 2>/dev/null || true; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the directory-tokens.css --page case — could not replace design/tokens.css with a directory"
fi
# (48) S2 --page design/..html (fix round 4 blessed it; M2 reverses
# that blessing): basename 6, but the stem before `.html` is just "."
# — not a name, so it is not a built page → exit 2, nothing written.
rl_reset_artifacts
printf '<html>dd</html>\n' > "$rl_proj/design/..html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/..html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/..html >"$work/runlog-t48.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/..html exited 0 — a dot-only stem before .html is not a built page (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/..html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/..html (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/..html"
# (49) S2 --page design/a.html plus a trailing space (fix round 4): the
# extension check sees ".html " not ".html" → exit 2, nothing written.
rl_reset_artifacts
printf '<html>ts</html>\n' > "$rl_proj/design/a.html "
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/a.html "
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page "design/a.html " >"$work/runlog-t49.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/a.html plus a trailing space exited 0 — the freshness reference must be an .html file (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/a.html plus a trailing space wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/a.html plus a trailing space (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/a.html "
# (50) S2 --page design/.HTML (fix round 4): dotfile with an uppercase
# extension — basename length 5, no stem before ".HTML" → exit 2,
# nothing written.
rl_reset_artifacts
printf '<html>du</html>\n' > "$rl_proj/design/.HTML"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/.HTML"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/.HTML >"$work/runlog-t50.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/.HTML exited 0 — a dotfile with an empty basename is not a built page (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/.HTML wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/.HTML (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/.HTML"
# (51) S2 --page design/x.html.html (fix round 4 blessed it; M2
# reverses that blessing): a double extension — the stem "x.html"
# itself ends in ".html", so it is not a single-suffix built page →
# exit 2, nothing written.
rl_reset_artifacts
printf '<html>de</html>\n' > "$rl_proj/design/x.html.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/x.html.html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/x.html.html >"$work/runlog-t51.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/x.html.html exited 0 — a double extension is not a built page (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/x.html.html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/x.html.html (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/x.html.html"
# (52) S2 --page design/html (fix round 4): a file named exactly "html",
# no dot — does not end with ".html" → exit 2, nothing written.
rl_reset_artifacts
printf '<html>nh</html>\n' > "$rl_proj/design/html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/html"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/html >"$work/runlog-t52.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/html exited 0 — a file named exactly html is not an .html file (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/html (exit 2, nothing written)"
fi
rm -f "$rl_proj/design/html"
# (53) F2 Cf FAILhide leg 1 (fix round 5): `GATE RESULT:<U+2060>FAIL
# (3 issue(s))` (word joiner, octal \342\201\240) followed by a real
# `GATE RESULT: PASS` → exit 2 via the FAIL-verdict message, nothing
# written. The round-4 normaliser had no Cf-format member, so a Cf
# character before FAIL hid the FAIL verdict; strip-all deletes it.
rl_reset_artifacts
printf 'GATE RESULT:\342\201\240FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t53.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t53.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t53.log"
  cat "$work/runlog-t53.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2060 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (54) F2 Cf FAILhide leg 2 (fix round 5): `===== gate verdict:<U+2060>FAIL
# (exit 1) =====` followed by a real GREEN line → exit 2 via the
# FAIL-verdict message, nothing written.
rl_reset_artifacts
printf '===== gate verdict:\342\201\240FAIL (exit 1) =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t54.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real GREEN line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real GREEN line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t54.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2060 FAIL line alongside a real GREEN line exited 2 but not via the FAIL-verdict message — see $work/runlog-t54.log"
  cat "$work/runlog-t54.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2060 FAIL line alongside a real GREEN line (exit 2, FAIL-verdict message, nothing written)"
fi
# (55) F2 Cf PASS-sub leg 1 (fix round 5): `GATE RESULT:<U+2060>PASS`
# → exit 0, recorded. A Cf character substituting for the space must
# not false-reject a real pass.
rl_reset_artifacts
printf 'GATE RESULT:\342\201\240PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t55.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+2060 inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+2060 inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+2060 inside the PASS line failed — a Cf-format character must not false-reject a real pass (exit 0); see $work/runlog-t55.log"
  cat "$work/runlog-t55.log" >&2 || true
fi
# (56) F3 in-word FAILhide leg 1 (fix round 5): `GATE RESULT: FA<NBSP>IL
# (3 issue(s))` (NBSP, octal \302\240, INSIDE the word FAIL) followed by
# a real `GATE RESULT: PASS` → exit 2 via the FAIL-verdict message,
# nothing written. The round-4 fold mapped the NBSP to a space and
# split the word, so the FAIL hid; strip-all deletes it.
rl_reset_artifacts
printf 'GATE RESULT: FA\302\240IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t56.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with an NBSP inside the FAIL word alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with an NBSP inside the FAIL word alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t56.log"; then
  fail "run-log refusal (D13): record --gate pass with an NBSP inside the FAIL word alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t56.log"
  cat "$work/runlog-t56.log" >&2 || true
else
  ok "run-log refuses record --gate pass with an NBSP inside the FAIL word alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (57) F3 in-word FAILhide leg 2 (fix round 5): `===== gate verdict:
# FA<U+2003>IL (exit 1) =====` (EM SPACE, octal \342\200\203, inside the
# word FAIL) followed by a real GREEN line → exit 2 via the FAIL-verdict
# message, nothing written.
rl_reset_artifacts
printf '===== gate verdict: FA\342\200\203IL (exit 1) =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t57.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 inside the FAIL word alongside a real GREEN line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 inside the FAIL word alongside a real GREEN line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t57.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 inside the FAIL word alongside a real GREEN line exited 2 but not via the FAIL-verdict message — see $work/runlog-t57.log"
  cat "$work/runlog-t57.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2003 inside the FAIL word alongside a real GREEN line (exit 2, FAIL-verdict message, nothing written)"
fi
# (58) F4 FAILURE-split leg 1 (fix round 5): `GATE RESULT: FAIL<ZWSP>URE
# (0 issues)` followed by a real `GATE RESULT: PASS` → exit 0, recorded.
# The round-4 map variant turned this into `FAIL URE` and the R4 boundary
# matched; strip-all recovers `FAILURE` and the boundary blocks it.
rl_reset_artifacts
printf 'GATE RESULT: FAIL\342\200\213URE (0 issues)\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t58.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with a ZWSP-split FAILURE line alongside a real PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with a ZWSP-split FAILURE line alongside a real PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a ZWSP-split FAILURE line alongside a real PASS line failed — a split FAILURE is not a FAIL verdict (exit 0); see $work/runlog-t58.log"
  cat "$work/runlog-t58.log" >&2 || true
fi
# (59) F4 FAILURE-split leg 2 (fix round 5): `===== gate verdict:
# FAIL<ZWSP>URE =====` followed by a real GREEN line → exit 0, recorded.
rl_reset_artifacts
printf '===== gate verdict: FAIL\342\200\213URE =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t59.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with a ZWSP-split FAILURE line alongside a real GREEN line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with a ZWSP-split FAILURE line alongside a real GREEN line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a ZWSP-split FAILURE line alongside a real GREEN line failed — a split FAILURE is not a FAIL verdict (exit 0); see $work/runlog-t59.log"
  cat "$work/runlog-t59.log" >&2 || true
fi
# (60) U+180E FAILhide leg 1 (fix round 5): `GATE RESULT:<U+180E>FAIL
# (3 issue(s))` (octal \341\240\216) followed by a real `GATE RESULT:
# PASS` → exit 2 via the FAIL-verdict message, nothing written. Only
# the PASS side of U+180E was cased before ((42)/(43)).
rl_reset_artifacts
printf 'GATE RESULT:\341\240\216FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t60.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t60.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t60.log"
  cat "$work/runlog-t60.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+180E FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (61) U+180E FAIL-alone leg 1 (fix round 5): `GATE RESULT:<U+180E>FAIL
# (3 issue(s))`, no PASS line → exit 2 via the FAIL-verdict message
# (not the missing-PASS message), nothing written.
rl_reset_artifacts
printf 'GATE RESULT:\341\240\216FAIL (3 issue(s))\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t61.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line and no PASS line exited 0 — a FAIL verdict with no PASS must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line and no PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t61.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+180E FAIL line and no PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t61.log"
  cat "$work/runlog-t61.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+180E FAIL line and no PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (62) ZWNJ-substitution PASS leg 1 (fix round 5): `GATE RESULT:<U+200C>PASS`
# (zero-width non-joiner, octal \342\200\214) → exit 0, recorded. Only
# ZWSP was cased individually before ((38)–(41)).
rl_reset_artifacts
printf 'GATE RESULT:\342\200\214PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t62.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with ZWNJ substituting for the space in the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with ZWNJ substituting for the space in the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with ZWNJ substituting for the space in the PASS line failed — a zero-width character substituting for a space must not false-reject a real pass (exit 0); see $work/runlog-t62.log"
  cat "$work/runlog-t62.log" >&2 || true
fi
# (63) ZWJ-substitution PASS leg 1 (fix round 5): `GATE RESULT:<U+200D>PASS`
# (zero-width joiner, octal \342\200\215) → exit 0, recorded.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\215PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t63.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with ZWJ substituting for the space in the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with ZWJ substituting for the space in the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with ZWJ substituting for the space in the PASS line failed — a zero-width character substituting for a space must not false-reject a real pass (exit 0); see $work/runlog-t63.log"
  cat "$work/runlog-t63.log" >&2 || true
fi
# (64) BOM-substitution PASS leg 1 (fix round 5): `GATE RESULT:<U+FEFF>PASS`
# (byte order mark, octal \357\273\277) → exit 0, recorded.
rl_reset_artifacts
printf 'GATE RESULT:\357\273\277PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t64.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with BOM substituting for the space in the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with BOM substituting for the space in the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with BOM substituting for the space in the PASS line failed — a BOM substituting for a space must not false-reject a real pass (exit 0); see $work/runlog-t64.log"
  cat "$work/runlog-t64.log" >&2 || true
fi
# (65) Extra-White_Space PASS-in leg 1 (fix round 5): `GATE RESULT:<U+1680>PASS`
# (OGHAM SPACE MARK, octal \341\232\200) → exit 0, recorded. Only U+2003
# was cased among the extra White_Space four before.
rl_reset_artifacts
printf 'GATE RESULT:\341\232\200PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t65.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+1680 inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+1680 inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+1680 inside the PASS line failed — an exotic space must not false-reject a real pass (exit 0); see $work/runlog-t65.log"
  cat "$work/runlog-t65.log" >&2 || true
fi
# (66) FAIL-alone exotic leg 1 (fix round 5): `GATE RESULT:<U+2003>FAIL
# (3 issue(s))`, no PASS line → exit 2 via the FAIL-verdict message
# (not the missing-PASS message), nothing written. No FAIL-alone case
# in an exotic space existed before.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\203FAIL (3 issue(s))\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t66.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line and no PASS line exited 0 — a FAIL verdict with no PASS must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line and no PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t66.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2003 FAIL line and no PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t66.log"
  cat "$work/runlog-t66.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2003 FAIL line and no PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (67) Land variant of (36) (fix round 5): U+2003 FAILhide leg 1 on `land`
# → exit 2, lines unchanged (cross-check line only). All round-4 cases
# were record-only, so a land-only divergence would not have been caught.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\203FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t67-cc.log" 2>&1; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t67.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with a U+2003 FAIL line alongside a real PASS line exited 0 — the land path must not bypass the FAIL refusal (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with a U+2003 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t67.log"; then
    fail "run-log refusal (D13): land --gate pass with a U+2003 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t67.log"
    cat "$work/runlog-t67.log" >&2 || true
  else
    ok "run-log refuses land --gate pass with a U+2003 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
  fi
else
  fail "run-log refusal (D13): setup cross-check failed for the U+2003 FAILhide land case — see $work/runlog-t67-cc.log"
  cat "$work/runlog-t67-cc.log" >&2 || true
fi
# (68) Land variant of (38) (fix round 5): ZWSP-substitution PASS leg 1 on
# `land` → exit 0, recorded.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\213PASS\n' > "$rl_proj/design/gate-leg1.log"
if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t68-cc.log" 2>&1; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t68.log" 2>&1; then
    if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
      ok "run-log records land --gate pass with ZWSP substituting for the space in the PASS line (exit 0)"
    else
      fail "run-log refusal (D13): land --gate pass with ZWSP substituting for the space in the PASS line exited 0 but did not append exactly one line"
    fi
  else
    fail "run-log refusal (D13): land --gate pass with ZWSP substituting for the space in the PASS line failed — see $work/runlog-t68.log"
    cat "$work/runlog-t68.log" >&2 || true
  fi
else
  fail "run-log refusal (D13): setup cross-check failed for the ZWSP-substitution PASS land case — see $work/runlog-t68-cc.log"
  cat "$work/runlog-t68-cc.log" >&2 || true
fi
# (69) Land variant of (44) (fix round 5): design/tokens.css as a FIFO +
# --page design/page.html on `land` → exit 2, nothing written.
rl_reset_artifacts
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
if mv "$rl_proj/design/tokens.css" "$rl_proj/design/tokens.real" && mkfifo "$rl_proj/design/tokens.css" 2>/dev/null; then
  if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t69-cc.log" 2>&1; then
    rl_before="$(rl_lines)"
    if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t69.log" 2>&1; then
      fail "run-log refusal (D13): land --gate pass with design/tokens.css as a FIFO exited 0 — the freshness anchor must be the real tokens file (exit 2)"
    elif [[ "$(rl_lines)" != "$rl_before" ]]; then
      fail "run-log refusal (D13): land --gate pass with design/tokens.css as a FIFO wrote to the run log — a refused entry must write nothing"
    elif ! grep -q "is not a regular file" "$work/runlog-t69.log"; then
      fail "run-log refusal (D13): land --gate pass with design/tokens.css as a FIFO exited 2 but not via the regular-file message — see $work/runlog-t69.log"
      cat "$work/runlog-t69.log" >&2 || true
    else
      ok "run-log refuses land --gate pass with design/tokens.css as a FIFO (exit 2, nothing written)"
    fi
  else
    fail "run-log refusal (D13): setup cross-check failed for the FIFO-tokens.css land case — see $work/runlog-t69-cc.log"
    cat "$work/runlog-t69-cc.log" >&2 || true
  fi
  rm -f "$rl_proj/design/tokens.css"
  mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"
  touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
else
  if [[ -p "$rl_proj/design/tokens.css" ]]; then rm -f "$rl_proj/design/tokens.css"; fi
  if [[ -f "$rl_proj/design/tokens.real" ]]; then mv "$rl_proj/design/tokens.real" "$rl_proj/design/tokens.css"; fi
  fail "run-log refusal (D13): setup failed for the FIFO-tokens.css land case — could not replace design/tokens.css with a FIFO"
fi
# (70) Land variant of (48) (fix round 5 blessed it; M2 reverses
# that blessing): --page design/..html on `land` → exit 2, nothing
# written.
rl_reset_artifacts
printf '<html>dd</html>\n' > "$rl_proj/design/..html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/..html"
if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t70-cc.log" 2>&1; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/..html >"$work/runlog-t70.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with --page design/..html exited 0 — a dot-only stem before .html is not a built page (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with --page design/..html wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses land --gate pass with --page design/..html (exit 2, nothing written)"
  fi
else
  fail "run-log refusal (D13): setup cross-check failed for the --page design/..html land case — see $work/runlog-t70-cc.log"
  cat "$work/runlog-t70-cc.log" >&2 || true
fi
rm -f "$rl_proj/design/..html"
# (71) ZWJ FAILhide leg 1 (fix round 5): `GATE RESULT:<U+200D>FAIL
# (3 issue(s))` (zero-width joiner, octal \342\200\215) followed by a real
# `GATE RESULT: PASS` → exit 2 via the FAIL-verdict message, nothing
# written. The ZWJ PASS side is cased in (63); this locks in the FAIL side.
rl_reset_artifacts
printf 'GATE RESULT:\342\200\215FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t71.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a ZWJ FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a ZWJ FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t71.log"; then
  fail "run-log refusal (D13): record --gate pass with a ZWJ FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t71.log"
  cat "$work/runlog-t71.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a ZWJ FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (72) F7 U+3164 FAILhide leg 1 (fix round 6): `GATE RESULT:<U+3164>FAIL
# (3 issue(s))` (HANGUL FILLER, octal \343\205\244) followed by a real
# `GATE RESULT: PASS` → exit 2 via the FAIL-verdict message, nothing
# written. A blank-rendering Lo character before FAIL hid the FAIL
# verdict under strip-all; the F7 denylist deletes it.
rl_reset_artifacts
printf 'GATE RESULT:\343\205\244FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t72.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t72.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t72.log"
  cat "$work/runlog-t72.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+3164 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (73) F7 U+2800 FAILhide leg 1 (fix round 6): `GATE RESULT:<U+2800>FAIL
# (3 issue(s))` (BRAILLE PATTERN BLANK, octal \342\240\200) followed by
# a real `GATE RESULT: PASS` → exit 2 via the FAIL-verdict message,
# nothing written. U+2800 is So, not covered by any strip class; the
# F7 denylist deletes it.
rl_reset_artifacts
printf 'GATE RESULT:\342\240\200FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t73.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+2800 FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+2800 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t73.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+2800 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t73.log"
  cat "$work/runlog-t73.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+2800 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (74) F7 U+3164 PASS-sub leg 1 (fix round 6): `GATE RESULT:<U+3164>PASS`
# → exit 0, recorded. A blank-rendering filler substituting for the
# space must not false-reject a real pass.
rl_reset_artifacts
printf 'GATE RESULT:\343\205\244PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t74.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with U+3164 inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with U+3164 inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with U+3164 inside the PASS line failed — a blank-rendering filler must not false-reject a real pass (exit 0); see $work/runlog-t74.log"
  cat "$work/runlog-t74.log" >&2 || true
fi
# (75) F7 U+3164 FAILhide leg 2 (fix round 6): `===== gate verdict:
# <U+3164>FAIL (exit 1) =====` followed by a real GREEN line → exit 2
# via the FAIL-verdict message, nothing written.
rl_reset_artifacts
printf '===== gate verdict:\343\205\244FAIL (exit 1) =====\n===== gate verdict: GREEN =====\n' > "$rl_proj/design/gate-leg2.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t75.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real GREEN line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real GREEN line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t75.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+3164 FAIL line alongside a real GREEN line exited 2 but not via the FAIL-verdict message — see $work/runlog-t75.log"
  cat "$work/runlog-t75.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+3164 FAIL line alongside a real GREEN line (exit 2, FAIL-verdict message, nothing written)"
fi
# (76) F9 NFC FAILhide leg 1 (fix round 6): `GATE RESULT: FÄIL
# (3 issue(s))`, Ä = U+00C4 precomposed (NFC, octal \303\204),
# followed by a real `GATE RESULT: PASS` → exit 2 via the
# FAIL-verdict message, nothing written. NFD decomposes Ä to A +
# U+0308, the mark strips, and FAIL is recovered.
rl_reset_artifacts
printf 'GATE RESULT: F\303\204IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t76.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with an NFC FÄIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with an NFC FÄIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t76.log"; then
  fail "run-log refusal (D13): record --gate pass with an NFC FÄIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t76.log"
  cat "$work/runlog-t76.log" >&2 || true
else
  ok "run-log refuses record --gate pass with an NFC FÄIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (77) F9 NFD FAILhide leg 1 (fix round 6): same shape as (76) with Ä
# decomposed (A + U+0308, octal \314\210) → exit 2 via the FAIL-verdict
# message, nothing written. Pairs with (76): the two canonically
# equivalent forms must get the same verdict. Lock-in vs round-5 AND
# round-4 (round-4 already stripped the combining mark).
rl_reset_artifacts
printf 'GATE RESULT: FA\314\210IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t77.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with an NFD FÄIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with an NFD FÄIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t77.log"; then
  fail "run-log refusal (D13): record --gate pass with an NFD FÄIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t77.log"
  cat "$work/runlog-t77.log" >&2 || true
else
  ok "run-log refuses record --gate pass with an NFD FÄIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (78) F9 NFC PASS-sub leg 1 (fix round 6): `GATE RESULT: PÀSS`,
# À = U+00C0 precomposed (NFC, octal \303\200) → exit 0, recorded.
# NFD decomposes À to A + U+0300, the mark strips, and PASS is
# recovered — the precomposed form must not false-reject a real pass.
rl_reset_artifacts
printf 'GATE RESULT: P\303\200SS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t78.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with NFC PÀSS inside the PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with NFC PÀSS inside the PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with NFC PÀSS inside the PASS line failed — a precomposed letter must not false-reject a real pass (exit 0); see $work/runlog-t78.log"
  cat "$work/runlog-t78.log" >&2 || true
fi
# (79) F8 U+FFFD-insertion FAILhide leg 1 (fix round 6): `GATE RESULT:
# FA<U+FFFD>IL (3 issue(s))` (octal \357\277\275, INSERTED between
# letters) followed by a real `GATE RESULT: PASS` → exit 2 via the
# FAIL-verdict message, nothing written. Lock-in vs round-5 (round-5
# already stripped the inserted footprint); FAILs vs round-4 (no U+FFFD
# member there). Pairs with (80): insertion is fixed, substitution is not.
rl_reset_artifacts
printf 'GATE RESULT: FA\357\277\275IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t79.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+FFFD-inserted FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+FFFD-inserted FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t79.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+FFFD-inserted FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t79.log"
  cat "$work/runlog-t79.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+FFFD-inserted FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (80) F8 U+FFFD-substitution FAILhide leg 1 (fix round 6): `GATE RESULT:
# F<U+FFFD>IL (3 issue(s))` (octal \357\277\275, SUBSTITUTING for the A)
# followed by a real `GATE RESULT: PASS` → exit 0, 1 line recorded.
# KNOWN LIMITATION (F8 residual): stripping recovers inserted noise
# only — when the stripped character replaces a letter, the letter is
# gone and no normaliser can recover it. This case pins the boundary,
# it does NOT pin a fix; do not "fix" it with fuzzy matching.
rl_reset_artifacts
printf 'GATE RESULT: F\357\277\275IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t80.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with a U+FFFD-substituted FAIL line alongside a real PASS line (exit 0, KNOWN LIMITATION (F8 residual))"
  else
    fail "run-log refusal (D13): record --gate pass with a U+FFFD-substituted FAIL line alongside a real PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a U+FFFD-substituted FAIL line alongside a real PASS line failed — substitution is a KNOWN LIMITATION (F8 residual), expected exit 0; see $work/runlog-t80.log"
  cat "$work/runlog-t80.log" >&2 || true
fi
# (81) F8 real-invalid-byte substitution FAILhide leg 1 (fix round 6):
# `GATE RESULT: F<0xFF>IL (3 issue(s))` with a REAL 0xFF byte in the
# leg file (octal \377), SUBSTITUTING for the A, followed by a real
# `GATE RESULT: PASS` → exit 0, 1 line recorded.
# KNOWN LIMITATION (F8 residual): the byte decodes to U+FFFD and
# strips to FIL — the FAIL is gone, same as (80) but with a real
# invalid byte, not an escape. This case pins the boundary; it does
# NOT pin a fix.
rl_reset_artifacts
printf 'GATE RESULT: F\377IL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t81.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with a real-0xFF-substituted FAIL line alongside a real PASS line (exit 0, KNOWN LIMITATION (F8 residual))"
  else
    fail "run-log refusal (D13): record --gate pass with a real-0xFF-substituted FAIL line alongside a real PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with a real-0xFF-substituted FAIL line alongside a real PASS line failed — substitution is a KNOWN LIMITATION (F8 residual), expected exit 0; see $work/runlog-t81.log"
  cat "$work/runlog-t81.log" >&2 || true
fi
# (82) F7 boundary flip leg 1 (fix round 6): `GATE RESULT: FAIL<U+3164>URE
# (0 issues)` (HANGUL FILLER, octal \343\205\244, inside FAILURE)
# followed by a real `GATE RESULT: PASS` → exit 0, 1 line recorded.
# The denylist is applied to the boundary side too: the filler strips
# to FAILURE and the R4 boundary blocks it — the same word the round-5
# code false-rejected (re-red-team #5 C10: exit 2 on round-5 code).
rl_reset_artifacts
printf 'GATE RESULT: FAIL\343\205\244URE (0 issues)\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t82.log" 2>&1; then
  if [[ "$(rl_lines)" == "$((rl_before + 1))" ]]; then
    ok "run-log records record --gate pass with FAIL<U+3164>URE alongside a real PASS line (exit 0)"
  else
    fail "run-log refusal (D13): record --gate pass with FAIL<U+3164>URE alongside a real PASS line exited 0 but did not append exactly one line"
  fi
else
  fail "run-log refusal (D13): record --gate pass with FAIL<U+3164>URE alongside a real PASS line failed — the denylist strips the filler to FAILURE, which the boundary must accept (exit 0); see $work/runlog-t82.log"
  cat "$work/runlog-t82.log" >&2 || true
fi
# (83) F7 sweep-extra U+13441 FAILhide leg 1 (fix round 6): `GATE RESULT:
# <U+13441>FAIL (3 issue(s))` (EGYPTIAN HIEROGLYPH FULL BLANK, octal
# \360\223\221\201) followed by a real `GATE RESULT: PASS` → exit 2 via
# the FAIL-verdict message, nothing written. The §3 sweep found U+13441
# (and U+13442) beyond the five demonstrated code points; this case
# locks in at least one sweep-extra member of the denylist.
rl_reset_artifacts
printf 'GATE RESULT:\360\223\221\201FAIL (3 issue(s))\nGATE RESULT: PASS\n' > "$rl_proj/design/gate-leg1.log"
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/runlog-t83.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with a U+13441 FAIL line alongside a real PASS line exited 0 — the FAIL verdict must be caught (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with a U+13441 FAIL line alongside a real PASS line wrote to the run log — a refused entry must write nothing"
elif ! grep -q "contains its leg's FAIL verdict" "$work/runlog-t83.log"; then
  fail "run-log refusal (D13): record --gate pass with a U+13441 FAIL line alongside a real PASS line exited 2 but not via the FAIL-verdict message — see $work/runlog-t83.log"
  cat "$work/runlog-t83.log" >&2 || true
else
  ok "run-log refuses record --gate pass with a U+13441 FAIL line alongside a real PASS line (exit 2, FAIL-verdict message, nothing written)"
fi
# (84) M2 edge case 3 — --page design/../design/page.html: a ".." that
# cancels out and resolves back inside design/ is invisible after
# path.resolve, so the raw spelling must be refused → exit 2, nothing
# written. (The stored path would have come out canonicalised, leaving
# no trace of the evasion.)
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/../design/page.html >"$work/runlog-t84.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/../design/page.html exited 0 — a '..' segment in a cited path must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/../design/page.html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/../design/page.html (exit 2, nothing written)"
fi
# (85) M2 edge case 3, mid-path variant — --page design/sub/../page.html
# (a ".." after a real segment, still resolving inside design/) → exit 2,
# nothing written.
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/sub/../page.html >"$work/runlog-t85.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/sub/../page.html exited 0 — a '..' segment in a cited path must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/sub/../page.html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/sub/../page.html (exit 2, nothing written)"
fi
# (86) M2 edge case 3, "." variant — --page design/./page.html → exit 2,
# nothing written. (A "." segment is the same non-canonical spelling
# class as ".."; the plain spelling design/page.html is the accepted form.)
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/./page.html >"$work/runlog-t86.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --page design/./page.html exited 0 — a '.' segment in a cited path must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --page design/./page.html wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --page design/./page.html (exit 2, nothing written)"
fi
# (87) M2 edge case 3 on a leg — --gate-leg1 design/../design/gate-leg1.log
# (the same ".." hole in the leg loop, not only --page) → exit 2, nothing
# written.
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_reset_artifacts
rl_before="$(rl_lines)"
if node "$run_log_mjs" --project "$rl_proj" record --round 9 --grader none --scores none --gate pass --gate-leg1 design/../design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >"$work/runlog-t87.log" 2>&1; then
  fail "run-log refusal (D13): record --gate pass with --gate-leg1 design/../design/gate-leg1.log exited 0 — a '..' segment in a cited path must be refused (exit 2)"
elif [[ "$(rl_lines)" != "$rl_before" ]]; then
  fail "run-log refusal (D13): record --gate pass with --gate-leg1 design/../design/gate-leg1.log wrote to the run log — a refused entry must write nothing"
else
  ok "run-log refuses record --gate pass with --gate-leg1 design/../design/gate-leg1.log (exit 2, nothing written)"
fi
# (88) Land variant of (84) — --page design/../design/page.html on `land`
# → exit 2, nothing written.
printf '<html><body><main id="main">x</main></body></html>\n' > "$rl_proj/design/page.html"
touch -d '2026-11-11 12:00' "$rl_proj/design/tokens.css" "$rl_proj/design/page.html"
rl_reset_artifacts
if node "$run_log_mjs" --project "$rl_proj" crosscheck --slice d12-test --severe 0 --warning 0 --report design/cc.md --checker security-expert --basis "fresh context, no production history" >"$work/runlog-t88-cc.log" 2>&1; then
  rl_before="$(rl_lines)"
  if node "$run_log_mjs" --project "$rl_proj" land --slice d12-test --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/../design/page.html >"$work/runlog-t88.log" 2>&1; then
    fail "run-log refusal (D13): land --gate pass with --page design/../design/page.html exited 0 — a '..' segment in a cited path must be refused (exit 2)"
  elif [[ "$(rl_lines)" != "$rl_before" ]]; then
    fail "run-log refusal (D13): land --gate pass with --page design/../design/page.html wrote to the run log — a refused entry must write nothing"
  else
    ok "run-log refuses land --gate pass with --page design/../design/page.html (exit 2, nothing written)"
  fi
else
  fail "run-log refusal (D13): setup cross-check failed for the --page design/../design/page.html land case — see $work/runlog-t88-cc.log"
  cat "$work/runlog-t88-cc.log" >&2 || true
fi

# --- 5c. run-log judge-artifact mechanism (D15, GAP-13) --------------------
# A graded record must TRANSCRIBE a judge artifact the orchestrator
# prepared (judge-report.mjs prepare) and an independent judge filled
# in on disk — scores, evidence, pairwise/jury verdicts and expert
# scores with no artifact, or not matching the artifact, are REFUSED
# (exit 2, nothing written). §5b above is NOT touched by this section.
# Its crosscheck cases cite design/cc.md: the §5b fixtures create that
# report file (the shared setup, and case (13)'s outside dir for its
# symlinked-design/ cases), and case (13b) asserts the D15 containment
# refusal for a crosscheck — and the D13 refusal for a land — behind a
# symlinked design/ (see the D15 entry in references/decisions.md).
# §5c uses real report files throughout.
jr_proj="$work/judge-proj"
mkdir -p "$jr_proj/design/screenshots" "$jr_proj/design/screenshots-prev" "$jr_proj/design/judge" "$jr_proj/design/crosscheck"
cp "$work/tokens.css" "$jr_proj/design/tokens.css"
cp "$jr_proj/design/tokens.css" "$work/tokens-d15-orig.css"
printf '<html><body><main id="main"><h1>Learn</h1></main></body></html>\n' > "$jr_proj/design/page.html"
cp "$jr_proj/design/page.html" "$work/page-d15-orig.html"
for v in 1440 768 390; do
  printf 'PNG-%s-A' "$v" > "$jr_proj/design/screenshots/$v.png"
  printf 'PNG-%s-B' "$v" > "$jr_proj/design/screenshots-prev/$v.png"
done
printf 'GATE RESULT: PASS\n' > "$jr_proj/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$jr_proj/design/gate-leg2.log"
for r in 1 2 3 4 5 6 7 9; do printf 'cross-check report r%s\n' "$r" > "$jr_proj/design/crosscheck/round-$r.md"; done
touch -d '2026-11-11 12:00' "$jr_proj/design/tokens.css"
touch -d '2026-11-11 12:01' "$jr_proj/design/page.html"
touch -d '2026-11-11 12:02' "$jr_proj/design/screenshots/"*.png "$jr_proj/design/screenshots-prev/"*.png "$jr_proj/design/gate-leg1.log" "$jr_proj/design/gate-leg2.log" "$jr_proj/design/crosscheck/"*.md
judge_report_mjs="$(dirname "$run_log_mjs")/judge-report.mjs"
[[ -f "$judge_report_mjs" ]] || judge_report_mjs="$root/skills/frontend-kit/scripts/judge-report.mjs"
runlog_check_mjs="$(dirname "$run_log_mjs")/gate/runlog-check.mjs"
[[ -f "$runlog_check_mjs" ]] || runlog_check_mjs="$root/skills/frontend-kit/scripts/gate/runlog-check.mjs"
jr_log="$jr_proj/design/run-log.jsonl"
jr_lines() { if [[ -f "$jr_log" ]]; then grep -c . "$jr_log" || true; else printf '0'; fi; }
jr_basis="fresh context, no production history"
jr_legs="--gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html"
# Setup: cross-check records (the gate/cross-check bits prepare derives
# from); round 9 sits on its own slice for the land case (32).
jr_cc_ok=1
for r in 1 2 3 4 5 6 7; do
  node "$run_log_mjs" --project "$jr_proj" crosscheck --slice d15 --round $r --severe 0 --warning 0 --report "design/crosscheck/round-$r.md" --checker security-expert --basis "$jr_basis" >"$work/judge-cc-$r.log" 2>&1 || jr_cc_ok=0
done
node "$run_log_mjs" --project "$jr_proj" crosscheck --slice d15-land --round 9 --severe 0 --warning 0 --report design/crosscheck/round-9.md --checker security-expert --basis "$jr_basis" >"$work/judge-cc-9.log" 2>&1 || jr_cc_ok=0
if [[ "$jr_cc_ok" != 1 ]]; then
  fail "judge-artifact (D15): setup cross-check records failed — the §5c cases below will cascade; see $work/judge-cc-*.log"
fi
# jr_reject <name> <logfile> <pattern> <cmd...>: the command must exit
# non-zero (run-log refusals are exit 2), write nothing, and refuse via
# a message containing <pattern>.
jr_reject() {
  local name="$1" logf="$2" pat="$3"; shift 3
  local before; before="$(jr_lines)"
  if "$@" >"$logf" 2>&1; then
    fail "judge-artifact (D15): $name exited 0 — must be refused (exit 2)"
  elif [[ "$(jr_lines)" != "$before" ]]; then
    fail "judge-artifact (D15): $name wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "$pat" "$logf"; then
    fail "judge-artifact (D15): $name was refused but not via the expected message (/$pat/) — see $logf"
    cat "$logf" >&2 || true
  else
    ok "run-log refuses $name (exit 2, nothing written)"
  fi
}
jr_prep() { # round kind [extra prepare args...] — expert kinds are stamped by their expert; no --grader.
  local round="$1" kind="$2"; shift 2
  local grader_args=(--grader judge-subagent)
  if [[ "$kind" == expert-* ]]; then grader_args=(); fi
  if ! node "$judge_report_mjs" --project "$jr_proj" prepare --round "$round" --kind "$kind" "${grader_args[@]}" --brief-type landing --mode full --page design/page.html "$@" >"$work/judge-prep-$round-$kind.log" 2>&1; then
    fail "judge-artifact (D15): prepare round $round kind $kind failed — dependent cases will cascade; see $work/judge-prep-$round-$kind.log"
    cat "$work/judge-prep-$round-$kind.log" >&2 || true
  fi
}
# jr_fill_scores <file> <t> <l> <c> <s>: fill a skeleton the way a judge
# would — basis in, PENDING out, evidence + scores in the table.
jr_fill_scores() {
  sed -i -e '/^PENDING/d' -e 's/^basis:$/basis: fresh context, no production history/' \
    -e 's/— grader: \([^ ]*\) (?)/— grader: \1 (fresh context, no production history)/' \
    -e "s/| Type | ? | ? |/| Type | hero heading 64px vs ref 1 | $2 |/" \
    -e "s/| Layout | ? | ? |/| Layout | section gap 96px vs ref 1 | $3 |/" \
    -e "s/| Colour | ? | ? |/| Colour | accent button contrast 4.6 vs ref 1 | $4 |/" \
    -e "s/| Space | ? | ? |/| Space | card padding 32px vs ref 1 | $5 |/" \
    -e 's/^Fix order: ?$/Fix order: Layout first, then Type./' "$1"
  touch -d '2026-11-11 12:05' "$1"
}
jr_fill_pairwise() { # file keep
  sed -i -e '/^PENDING/d' -e 's/^basis:$/basis: fresh context, no production history/' \
    -e 's/pairwise call \(.\) of 2 (?)/pairwise call \1 of 2 (fresh context, no production history)/' \
    -e 's/^Defects in A: ?$/Defects in A: hero heading clips 2px at 390px/' \
    -e 's/^Defects in B: ?$/Defects in B: section gap 12px off scale/' \
    -e "s/^Pairwise: keep ? — ?\$/Pairwise: keep $2 — hero heading fits at 390px, gap 96px on scale/" "$1"
  touch -d '2026-11-11 12:05' "$1"
}
# (1) graded record with NO --judge-report → exit 2 (the C-memo escape:
# self-asserted scores on a green gate).
jr_reject "graded record without --judge-report" "$work/judge-t1.log" "judge-report is required" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --gate pass $jr_legs
# (2) --judge-report citing a file that does not exist → exit 2.
jr_reject "record citing a missing judge artifact" "$work/judge-t2.log" "does not exist" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-42.md --gate pass $jr_legs
# (3) --judge-report as an ABSOLUTE path → exit 2 (relative-to-project only).
jr_prep 1 absolute
jr_reject "record citing an absolute-path judge artifact" "$work/judge-t3.log" "must be a path relative" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report "$jr_proj/design/judge/round-1.md" --gate pass $jr_legs
# (4) --judge-report citing a SYMLINK → exit 2.
ln -sf round-1.md "$jr_proj/design/judge/link.md"
jr_reject "record citing a symlinked judge artifact" "$work/judge-t4.log" "is a symlink" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/link.md --gate pass $jr_legs
# (5) --judge-report citing an EMPTY file → exit 2.
: > "$jr_proj/design/judge/round-8.md"
jr_reject "record citing an empty judge artifact" "$work/judge-t5.log" "is empty" \
  node "$run_log_mjs" --project "$jr_proj" record --round 8 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-8.md --gate pass $jr_legs
# (6) the UNFILLED prepare skeleton (PENDING + ? cells) → exit 2.
jr_reject "record citing the unfilled judge skeleton" "$work/judge-t6.log" "PENDING" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $jr_legs
jr_fill_scores "$jr_proj/design/judge/round-1.md" 4 4 4 4
# (7) round MISMATCH: the round-1 artifact cited for round 2 → exit 2.
jr_reject "record citing an artifact of another round" "$work/judge-t7.log" "is a report for round" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $jr_legs
# (8) HEADLINE POSITIVE: prepare -> judge fills -> record exits 0 and the
# stored line transcribes the artifact (judgeReport + judgeReportSha +
# pageSha + the derived evidence, cells joined with '; ').
# KNOWN LIMITATION, stated not hidden: this harness fills the artifact
# BY HAND — a builder-authored judge-shaped artifact that is internally
# consistent records exactly like a real judge's (D15 residual B1). The
# mechanism's bar is that self-grading now requires deliberate, on-disk,
# internally-consistent forgery that a QC re-grade or an audit of
# design/judge/ can contradict; it does not and cannot prove authorship.
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $jr_legs --outcome stopped >"$work/judge-t8.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"judgeReport":"design/judge/round-1.md"' && tail -n 1 "$jr_log" | grep -q '"judgeReportSha":"[0-9a-f]\{64\}"' && tail -n 1 "$jr_log" | grep -q '"pageSha":"[0-9a-f]\{64\}"' && tail -n 1 "$jr_log" | grep -q '"evidence":"hero heading 64px vs ref 1; section gap 96px vs ref 1; accent button contrast 4.6 vs ref 1; card padding 32px vs ref 1"'; then
    ok "run-log records a graded round from a filled judge artifact (judgeReport/judgeReportSha/pageSha stored, evidence derived from the artifact cells)"
  else
    fail "judge-artifact (D15): headline positive recorded but the stored line lacks judgeReport/judgeReportSha/pageSha or the derived evidence"
  fi
else
  fail "judge-artifact (D15): headline positive (prepare -> fill -> record) failed — see $work/judge-t8.log"
  cat "$work/judge-t8.log" >&2 || true
fi
# (9) REUSE of the same artifact for a second grade → exit 2 (single-use).
jr_reject "record reusing a judge artifact" "$work/judge-t9.log" "already been cited" \
  node "$run_log_mjs" --project "$jr_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $jr_legs
# (10) a NO-GRADE record citing a judge artifact → exit 2.
jr_reject "no-grade record citing a judge artifact" "$work/judge-t10.log" "cites no judge artifact" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader none --scores none --gate fail --judge-report design/judge/round-1.md
# (11) allowed grader + --scores none → exit 2.
jr_reject "allowed grader with --scores none" "$work/judge-t11.log" "goes with --scores" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores none --gate fail
# (12) scores on a FAILED gate → exit 2 (no judge is spawned on red).
jr_reject "scores recorded on a failed gate" "$work/judge-t12.log" "requires --gate pass" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate fail
# Round 2 artifact for the mismatch family (13)–(17).
jr_prep 2 absolute
jr_fill_scores "$jr_proj/design/judge/round-2.md" 3 3 3 3
# (13) SCORE mismatch: artifact says 3,3,3,3, flags claim 4,4,4,4 → exit 2.
jr_reject "record whose --scores differ from the artifact" "$work/judge-t13.log" "judge artifact records" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-2.md --gate pass $jr_legs
# (14) GRADER mismatch: artifact grader judge-subagent, flag other-model → exit 2.
jr_reject "record whose --grader differs from the artifact" "$work/judge-t14.log" "names grader" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader other-model --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $jr_legs
# (15) BASIS mismatch: the flag basis is not the artifact's basis → exit 2.
jr_reject "record whose --basis differs from the artifact" "$work/judge-t15.log" "different independence basis" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "different agent, no production history of this build" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $jr_legs
# (16) PAGE EDITED after judging (gate legs re-run, so only the artifact's
# page hash can catch it) → exit 2.
printf '<html><body><main id="main"><h1>EDITED</h1></main></body></html>\n' > "$jr_proj/design/page.html"
touch -d '2026-11-11 12:06' "$jr_proj/design/page.html"
touch -d '2026-11-11 12:07' "$jr_proj/design/gate-leg1.log" "$jr_proj/design/gate-leg2.log"
jr_reject "record after the page was edited post-judging" "$work/judge-t16.log" "page changed after judging" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $jr_legs
cp "$work/page-d15-orig.html" "$jr_proj/design/page.html"
touch -d '2026-11-11 12:01' "$jr_proj/design/page.html"
touch -d '2026-11-11 12:02' "$jr_proj/design/gate-leg1.log" "$jr_proj/design/gate-leg2.log"
# (17) STALE artifact: the report predates the current page → exit 2.
touch -d '2026-11-11 11:59' "$jr_proj/design/judge/round-2.md"
jr_reject "record citing a judge artifact older than the page" "$work/judge-t17.log" "is older than" \
  node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $jr_legs
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-2.md"
# Round 2 positive (the mismatches above must not have consumed it).
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $jr_legs >"$work/judge-t17b.log" 2>&1 && [[ "$(jr_lines)" == "$((jr_before + 1))" ]]; then
  ok "run-log records round 2 once the flags transcribe the artifact (3,3,3,3)"
else
  fail "judge-artifact (D15): round 2 positive record failed — see $work/judge-t17b.log"
  cat "$work/judge-t17b.log" >&2 || true
fi
# (18) TOKENS EDITED after judging: the artifact's tokens hash no longer
# matches the record's tokens hash → exit 2; restored tokens record fine.
jr_prep 3 absolute
jr_fill_scores "$jr_proj/design/judge/round-3.md" 4 4 4 4
printf ':root{--color-canvas:#000}\n' >> "$jr_proj/design/tokens.css"
touch -d '2026-11-11 12:00' "$jr_proj/design/tokens.css"
jr_reject "record after tokens.css was edited post-judging" "$work/judge-t18.log" "binds to tokens-sha256" \
  node "$run_log_mjs" --project "$jr_proj" record --round 3 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-3.md --gate pass $jr_legs
cp "$work/tokens-d15-orig.css" "$jr_proj/design/tokens.css"
touch -d '2026-11-11 12:00' "$jr_proj/design/tokens.css"
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 3 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-3.md --gate pass $jr_legs >"$work/judge-t18b.log" 2>&1 && [[ "$(jr_lines)" == "$((jr_before + 1))" ]]; then
  ok "run-log records round 3 with the tokens restored (hash binding is content, not assertion)"
else
  fail "judge-artifact (D15): round 3 positive record failed — see $work/judge-t18b.log"
  cat "$work/judge-t18b.log" >&2 || true
fi
# (19) feedback --score-after with NO regrade artifact → exit 2.
jr_reject "feedback --score-after without a regrade artifact" "$work/judge-t19.log" "judge-report is required" \
  node "$run_log_mjs" --project "$jr_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 3 --score-after 4,4,4,4 --grader other-model --basis "$jr_basis"
# (20) feedback --score-after with a caller --evidence → exit 2 (derived only).
jr_reject "feedback --score-after with caller-asserted --evidence" "$work/judge-t20.log" "not accepted with --score-after" \
  node "$run_log_mjs" --project "$jr_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 3 --score-after 4,4,4,4 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-3-regrade.md --evidence "hero heading 64px vs ref 1"
# (21) feedback WITH a filled regrade artifact → exit 0, artifact cited.
jr_prep 3 regrade --grader other-model
jr_fill_scores "$jr_proj/design/judge/round-3-regrade.md" 4 4 4 4
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 3 --score-after 4,4,4,4 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-3-regrade.md >"$work/judge-t21.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"judgeReport":"design/judge/round-3-regrade.md"' && tail -n 1 "$jr_log" | grep -q '"judgeReportSha":"[0-9a-f]\{64\}"'; then
    ok "run-log records feedback --score-after from a regrade artifact (judgeReport/judgeReportSha stored)"
  else
    fail "judge-artifact (D15): feedback positive recorded but the stored line lacks the regrade artifact citation"
  fi
else
  fail "judge-artifact (D15): feedback with a regrade artifact failed — see $work/judge-t21.log"
  cat "$work/judge-t21.log" >&2 || true
fi
# Jury on round 4: absolute + three juror artifacts (families fam1..fam3).
jr_prep 4 absolute
jr_prep 4 jury --index 1 --family fam1
jr_prep 4 jury --index 2 --family fam2
jr_prep 4 jury --index 3 --family fam3
jr_fill_scores "$jr_proj/design/judge/round-4.md" 4 4 4 4
jr_fill_scores "$jr_proj/design/judge/round-4-jury-1.md" 4 4 4 4
jr_fill_scores "$jr_proj/design/judge/round-4-jury-2.md" 4 3 4 4
jr_fill_scores "$jr_proj/design/judge/round-4-jury-3.md" 3 4 4 4
# (22) jury with only TWO --judge-reports → exit 2.
jr_reject "jury record citing only two juror artifacts" "$work/judge-t22.log" "one report per juror" \
  node "$run_log_mjs" --project "$jr_proj" record --round 4 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-4.md --gate pass $jr_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "4,4,4,4;4,3,4,4;3,4,4,4" --judge-reports design/judge/round-4-jury-1.md,design/judge/round-4-jury-2.md
# (23) jury VOTES that do not match the artifacts' tables → exit 2.
jr_reject "jury record whose votes differ from the artifacts" "$work/judge-t23.log" "do not match the jury artifacts" \
  node "$run_log_mjs" --project "$jr_proj" record --round 4 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-4.md --gate pass $jr_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "5,5,5,5;4,3,4,4;3,4,4,4" --judge-reports design/judge/round-4-jury-1.md,design/judge/round-4-jury-2.md,design/judge/round-4-jury-3.md
# (24) jury POSITIVE: votes transcribed, median derived, shas stored.
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 4 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-4.md --gate pass $jr_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "4,4,4,4;4,3,4,4;3,4,4,4" --judge-reports design/judge/round-4-jury-1.md,design/judge/round-4-jury-2.md,design/judge/round-4-jury-3.md >"$work/judge-t24.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"juryReportShas":"[0-9a-f]\{64\};[0-9a-f]\{64\};[0-9a-f]\{64\}"'; then
    ok "run-log records a jury round transcribed from three juror artifacts (juryReportShas stored)"
  else
    fail "judge-artifact (D15): jury positive recorded but the stored line lacks juryReportShas"
  fi
else
  fail "judge-artifact (D15): jury positive record failed — see $work/judge-t24.log"
  cat "$work/judge-t24.log" >&2 || true
fi
# Pairwise on round 5: absolute (current page = challenger) + two
# pairwise artifacts, the second with A/B swapped.
jr_prep 5 absolute
jr_prep 5 pairwise --index 1 --shots-a design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --shots-b design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png
jr_prep 5 pairwise --index 2 --shots-a design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png --shots-b design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png
jr_fill_scores "$jr_proj/design/judge/round-5.md" 4 4 4 4
jr_fill_pairwise "$jr_proj/design/judge/round-5-pairwise-1.md" A
jr_fill_pairwise "$jr_proj/design/judge/round-5-pairwise-2.md" B
# (25) pairwise with only ONE report → exit 2.
jr_reject "pairwise record citing only one pairwise artifact" "$work/judge-t25.log" "one report per pairwise judge call" \
  node "$run_log_mjs" --project "$jr_proj" record --round 5 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-5.md --gate pass $jr_legs --pairwise keep-challenger --pairwise-reports design/judge/round-5-pairwise-1.md
# (26) pairwise citing the SAME report twice (not a swapped pair) → exit 2.
jr_reject "pairwise record citing the same artifact twice" "$work/judge-t26.log" "is the same file as" \
  node "$run_log_mjs" --project "$jr_proj" record --round 5 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-5.md --gate pass $jr_legs --pairwise keep-challenger --pairwise-reports design/judge/round-5-pairwise-1.md,design/judge/round-5-pairwise-1.md
# (27) pairwise SPLIT: both calls keep the CURRENT page's set in their
# own A/B terms edited to disagree after derivation → exit 2 (a tie).
sed -i 's/^Pairwise: keep B —/Pairwise: keep A —/' "$jr_proj/design/judge/round-5-pairwise-2.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-5-pairwise-2.md"
jr_reject "pairwise record whose artifacts disagree after derivation" "$work/judge-t27.log" "disagree after A/B derivation" \
  node "$run_log_mjs" --project "$jr_proj" record --round 5 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-5.md --gate pass $jr_legs --pairwise keep-challenger --pairwise-reports design/judge/round-5-pairwise-1.md,design/judge/round-5-pairwise-2.md
sed -i 's/^Pairwise: keep A —/Pairwise: keep B —/' "$jr_proj/design/judge/round-5-pairwise-2.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-5-pairwise-2.md"
# (28) pairwise POSITIVE: both calls derive keep-challenger; flag agrees.
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 5 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-5.md --gate pass $jr_legs --pairwise keep-challenger --pairwise-agrees yes --pairwise-reports design/judge/round-5-pairwise-1.md,design/judge/round-5-pairwise-2.md >"$work/judge-t28.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"pairwiseReportShas":"[0-9a-f]\{64\};[0-9a-f]\{64\}"'; then
    ok "run-log records a pairwise verdict derived from two swapped pairwise artifacts (pairwiseReportShas stored)"
  else
    fail "judge-artifact (D15): pairwise positive recorded but the stored line lacks pairwiseReportShas"
  fi
else
  fail "judge-artifact (D15): pairwise positive record failed — see $work/judge-t28.log"
  cat "$work/judge-t28.log" >&2 || true
fi
# Experts on round 6 (a no-grade record: expert scores are allowed there
# WITH their artifacts).
# (29) expert score with NO expert artifact → exit 2.
jr_reject "expert score without an expert artifact" "$work/judge-t29.log" "expert-motion-report is required" \
  node "$run_log_mjs" --project "$jr_proj" record --round 6 --grader none --scores none --gate fail --expert-motion 4 --expert-motion-evidence "hero reveal travels 24px in 220ms"
jr_prep 6 expert-motion
sed -i -e '/^PENDING/d' -e 's/^basis:$/basis: fresh context, no production history/' \
  -e 's/— grader: \([^ ]*\) (?)/— grader: \1 (fresh context, no production history)/' \
  -e 's/^Motion: ? (motion-expert) — ?$/Motion: 4 (motion-expert) — hero reveal travels 24px in 220ms/' \
  "$jr_proj/design/judge/round-6-expert-motion.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-6-expert-motion.md"
# (30) expert score MISMATCH: artifact says 4, flag claims 5 → exit 2.
jr_reject "expert score differing from the expert artifact" "$work/judge-t30.log" "not the cited" \
  node "$run_log_mjs" --project "$jr_proj" record --round 6 --grader none --scores none --gate fail --expert-motion 5 --expert-motion-evidence "hero reveal travels 24px in 220ms" --expert-motion-report design/judge/round-6-expert-motion.md
# (31) expert POSITIVE on the no-grade record.
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 6 --grader none --scores none --gate fail --expert-motion 4 --expert-motion-evidence "hero reveal travels 24px in 220ms" --expert-motion-report design/judge/round-6-expert-motion.md >"$work/judge-t31.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"expertMotionReportSha":"[0-9a-f]\{64\}"'; then
    ok "run-log records an expert score transcribed from its expert artifact (expertMotionReportSha stored)"
  else
    fail "judge-artifact (D15): expert positive recorded but the stored line lacks expertMotionReportSha"
  fi
else
  fail "judge-artifact (D15): expert positive record failed — see $work/judge-t31.log"
  cat "$work/judge-t31.log" >&2 || true
fi
# (32) LAND with a clear cross-check + green gate but NO round record
# for the land's round → exit 2 (D15 land precondition).
jr_reject "land with no round record for its round" "$work/judge-t32.log" "has no round record" \
  node "$run_log_mjs" --project "$jr_proj" land --slice d15-land --round 9 --gate pass $jr_legs
# (33) a judge artifact containing a REFUSAL line is void → exit 2.
jr_prep 7 absolute
jr_fill_scores "$jr_proj/design/judge/round-7.md" 4 4 4 4
printf 'Not an independent judge in this context; grade is gate green, vision not available.\n' >> "$jr_proj/design/judge/round-7.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-7.md"
jr_reject "record citing a void (refusal-carrying) judge artifact" "$work/judge-t33.log" "refusal line" \
  node "$run_log_mjs" --project "$jr_proj" record --round 7 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-7.md --gate pass $jr_legs
# (34) the same refusal line with a ZERO-WIDTH SPACE inserted inside it
# is still a refusal line (the void check strips invisibles) → exit 2.
sed -i "s/^Not an independent judge/Not\xe2\x80\x8b an independent judge/" "$jr_proj/design/judge/round-7.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-7.md"
jr_reject "record citing a judge artifact with a ZWSP-split refusal line" "$work/judge-t34.log" "refusal line" \
  node "$run_log_mjs" --project "$jr_proj" record --round 7 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-7.md --gate pass $jr_legs
# (35) UNICODE INSERTION, lenient side: a ZWSP inside the Round line's
# grader label is stripped by the parser and the record succeeds (the
# §5b note's leniency asymmetry, mirrored for judge artifacts).
jr_prep 7 cheap
jr_fill_scores "$jr_proj/design/judge/round-7-cheap.md" 4 4 4 4
sed -i 's/— grader: judge-subagent (/— grader: judge-\xe2\x80\x8bsubagent (/' "$jr_proj/design/judge/round-7-cheap.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-7-cheap.md"
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 7 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-7-cheap.md --gate pass $jr_legs >"$work/judge-t35.log" 2>&1 && [[ "$(jr_lines)" == "$((jr_before + 1))" ]]; then
  ok "run-log records from a judge artifact with a ZWSP inserted in the Round-line grader label (invisible insertion stripped, lenient)"
else
  fail "judge-artifact (D15): ZWSP-in-Round-line positive record failed — see $work/judge-t35.log"
  cat "$work/judge-t35.log" >&2 || true
fi
# (36) crosscheck --report citing a file that does not exist → exit 2
# (before D15 the path was never stat'ed and the verdict recorded).
jr_reject "crosscheck citing a nonexistent report file" "$work/judge-t36.log" "report file does not exist" \
  node "$run_log_mjs" --project "$jr_proj" crosscheck --slice d15 --round 1 --severe 0 --warning 0 --report design/crosscheck/NEVER.md --checker security-expert --basis "$jr_basis"
# (37) runlog-check structural rule (D15): the clean §5c log passes; a
# copy with a hand-appended scored line (grader + scores, no artifact
# citation) FAILS — the downstream tripwire for the escape.
if node "$runlog_check_mjs" "$jr_log" >"$work/judge-t37a.log" 2>&1; then
  ok "runlog-check passes the artifact-backed §5c run log"
else
  fail "judge-artifact (D15): runlog-check failed the clean §5c log — see $work/judge-t37a.log"
  cat "$work/judge-t37a.log" >&2 || true
fi
cp "$jr_log" "$work/judge-fake.jsonl"
printf '%s\n' '{"kind":"round","round":99,"grader":"judge-subagent","scores":{"type":5,"layout":5,"colour":5,"space":5},"gate":"pass"}' >> "$work/judge-fake.jsonl"
if node "$runlog_check_mjs" "$work/judge-fake.jsonl" >"$work/judge-t37b.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a hand-appended scored line with no judge artifact citation — the structural tripwire is missing"
else
  ok "runlog-check fails a hand-appended scored line with no judge artifact citation (D15 structural rule)"
fi
# --- QC-round cases (38)–(42): expert page binding (F1), the
# not-swapped pairwise pair (F4a), the unicode-SUBSTITUTION boundary
# (F4b). Setup: a second built page + a round-9 cross-check record
# (round 8's judge dir already holds case (5)'s empty file, and
# prepare never overwrites, so the graded family below uses round 9).
printf '<html><body><main id="main"><h1>Other page</h1></main></body></html>\n' > "$jr_proj/design/page2.html"
touch -d '2026-11-11 12:01' "$jr_proj/design/page2.html"
printf 'cross-check report r9\n' > "$jr_proj/design/crosscheck/round-9.md"
touch -d '2026-11-11 12:02' "$jr_proj/design/crosscheck/round-9.md"
if ! node "$run_log_mjs" --project "$jr_proj" crosscheck --slice d15 --round 9 --severe 0 --warning 0 --report design/crosscheck/round-9.md --checker security-expert --basis "$jr_basis" >"$work/judge-cc-9b.log" 2>&1; then
  fail "judge-artifact (D15): QC-round setup cross-check for round 9 failed — cases (38)–(42) will cascade; see $work/judge-cc-9b.log"
  cat "$work/judge-cc-9b.log" >&2 || true
fi
jr_fill_expert() { # file domain label score evidence — fill an expert skeleton the way the expert would.
  sed -i -e '/^PENDING/d' -e 's/^basis:$/basis: fresh context, no production history/' \
    -e "s/^$2: ? ($3) — ?\$/$2: $4 ($3) — $5/" "$1"
  touch -d '2026-11-11 12:05' "$1"
}
# (38) F1 (QC A8): an expert-motion artifact prepared against page2,
# cited on a NO-GRADE record whose page is page.html → exit 2 (before
# the QC fix the expert validator took no page binding and this
# recorded). The artifact's score/evidence match the flags, so only
# the page binding can refuse it.
if ! node "$judge_report_mjs" --project "$jr_proj" prepare --round 7 --kind expert-motion --brief-type landing --mode full --page design/page2.html >"$work/judge-prep-7-expert-motion-p2.log" 2>&1; then
  fail "judge-artifact (D15): prepare of the page2 expert-motion artifact failed — case (38) will cascade; see $work/judge-prep-7-expert-motion-p2.log"
  cat "$work/judge-prep-7-expert-motion-p2.log" >&2 || true
fi
jr_fill_expert "$jr_proj/design/judge/round-7-expert-motion.md" Motion motion-expert 4 "hero reveal travels 24px in 220ms"
jr_reject "expert artifact bound to a different page on a no-grade record" "$work/judge-t38.log" "not the recorded page" \
  node "$run_log_mjs" --project "$jr_proj" record --round 7 --grader none --scores none --gate fail --page design/page.html --expert-motion 4 --expert-motion-evidence "hero reveal travels 24px in 220ms" --expert-motion-report design/judge/round-7-expert-motion.md
# Round 9 graded family for (39)–(41): absolute artifact on page.html,
# an expert-motion artifact bound to page2, a correctly-bound
# expert-ux artifact, and two pairwise artifacts.
jr_prep 9 absolute
jr_fill_scores "$jr_proj/design/judge/round-9.md" 4 4 4 4
if ! node "$judge_report_mjs" --project "$jr_proj" prepare --round 9 --kind expert-motion --brief-type landing --mode full --page design/page2.html >"$work/judge-prep-9-expert-motion-p2.log" 2>&1; then
  fail "judge-artifact (D15): prepare of the round-9 page2 expert-motion artifact failed — case (39) will cascade; see $work/judge-prep-9-expert-motion-p2.log"
  cat "$work/judge-prep-9-expert-motion-p2.log" >&2 || true
fi
jr_fill_expert "$jr_proj/design/judge/round-9-expert-motion.md" Motion motion-expert 4 "hero reveal travels 24px in 220ms"
# (39) F1, graded branch: the same wrong-page expert artifact cited on
# a GRADED record for page.html → exit 2.
jr_reject "expert artifact bound to a different page on a graded record" "$work/judge-t39.log" "not the recorded page" \
  node "$run_log_mjs" --project "$jr_proj" record --round 9 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-9.md --gate pass $jr_legs --expert-motion 4 --expert-motion-evidence "hero reveal travels 24px in 220ms" --expert-motion-report design/judge/round-9-expert-motion.md
# (40) F4a: pairwise citing two DISTINCT artifacts whose A/B sets are
# in the SAME order (call 2 repeats call 1's order instead of swapping)
# → exit 2. Distinct files, both well-formed and filled — only the
# missing swap can refuse the record (contrast (26): same file twice).
jr_prep 9 pairwise --index 1 --shots-a design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --shots-b design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png
jr_prep 9 pairwise --index 2 --shots-a design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --shots-b design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png
jr_fill_pairwise "$jr_proj/design/judge/round-9-pairwise-1.md" A
jr_fill_pairwise "$jr_proj/design/judge/round-9-pairwise-2.md" A
jr_reject "pairwise record citing two artifacts in the same A/B order (not swapped)" "$work/judge-t40.log" "not a swapped pair" \
  node "$run_log_mjs" --project "$jr_proj" record --round 9 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-9.md --gate pass $jr_legs --pairwise keep-challenger --pairwise-reports design/judge/round-9-pairwise-1.md,design/judge/round-9-pairwise-2.md
# (41) F1 positive control: an expert-ux artifact bound to the record's
# OWN page records on the graded round (the binding refuses the wrong
# page, not expert artifacts as such).
jr_prep 9 expert-ux
jr_fill_expert "$jr_proj/design/judge/round-9-expert-ux.md" UX ux-expert 4 "focus ring reaches the signup button at stop 3 of 9"
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 9 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-9.md --gate pass $jr_legs --expert-ux 4 --expert-ux-evidence "focus ring reaches the signup button at stop 3 of 9" --expert-ux-report design/judge/round-9-expert-ux.md >"$work/judge-t41.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"expertUxReportSha":"[0-9a-f]\{64\}"'; then
    ok "run-log records a graded round whose expert artifact is bound to the record's page (expertUxReportSha stored)"
  else
    fail "judge-artifact (D15): graded expert positive recorded but the stored line lacks expertUxReportSha"
  fi
else
  fail "judge-artifact (D15): graded expert positive (correct page) failed — see $work/judge-t41.log"
  cat "$work/judge-t41.log" >&2 || true
fi
# (42) F4b: UNICODE SUBSTITUTION, strict side — a Cyrillic а (U+0430,
# byte pair \xd0\xb0) REPLACES the Latin a in the Round line's grader
# token. Contrast (35): an INSERTED invisible is stripped by
# stripInvisible and the record succeeds (lenient); a substitution is
# NOT recovered — canonicalisation deletes inserted invisibles only,
# it does not fold visible look-alikes (the F8 boundary, documented at
# stripInvisible in judge-report.mjs) — so the forged token fails the
# header/body equality and the record is refused. Verified against the
# current code before this case was written: exit 2, "does not match
# its header".
jr_prep 9 cheap
jr_fill_scores "$jr_proj/design/judge/round-9-cheap.md" 4 4 4 4
sed -i 's/grader: judge-subagent (/grader: judge-sub\xd0\xb0gent (/' "$jr_proj/design/judge/round-9-cheap.md"
touch -d '2026-11-11 12:05' "$jr_proj/design/judge/round-9-cheap.md"
jr_reject "record citing a judge artifact with a substituted look-alike in the Round-line grader token" "$work/judge-t42.log" "does not match its header" \
  node "$run_log_mjs" --project "$jr_proj" record --round 9 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-9-cheap.md --gate pass $jr_legs

# --- Red-team-round cases (43)–(49): the feedback regrade page
# binding (N12, SEVERE), the pairwise-tie positive, the read-path
# fake shapes (runlog-check + best), and prepare containment.
printf 'cross-check report r10\n' > "$jr_proj/design/crosscheck/round-10.md"
printf 'cross-check report r11\n' > "$jr_proj/design/crosscheck/round-11.md"
touch -d '2026-11-11 12:02' "$jr_proj/design/crosscheck/round-10.md" "$jr_proj/design/crosscheck/round-11.md"
jr_cc2_ok=1
for r in 10 11; do
  node "$run_log_mjs" --project "$jr_proj" crosscheck --slice d15 --round $r --severe 0 --warning 0 --report "design/crosscheck/round-$r.md" --checker security-expert --basis "$jr_basis" >"$work/judge-cc-$r.log" 2>&1 || jr_cc2_ok=0
done
if [[ "$jr_cc2_ok" != 1 ]]; then
  fail "judge-artifact (D15): red-team-round setup cross-checks for rounds 10/11 failed — cases (43)–(46) will cascade; see $work/judge-cc-1*.log"
fi
jr_legs_nopage="--gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log"
# (43) N12 setup positive: a graded record WITHOUT --page stores
# page: null but DOES store pageSha (the hash of the page the judge
# artifact binds to) — the shape the N12 escape hid behind.
jr_prep 10 absolute
jr_fill_scores "$jr_proj/design/judge/round-10.md" 4 4 4 4
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 10 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-10.md --gate pass $jr_legs_nopage >"$work/judge-t43.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"page":null' && tail -n 1 "$jr_log" | grep -q '"pageSha":"[0-9a-f]\{64\}"'; then
    ok "run-log records a graded round without --page (page null, pageSha stored — the N12 setup shape)"
  else
    fail "judge-artifact (D15): round 10 recorded without --page but the stored line lacks page:null + pageSha"
  fi
else
  fail "judge-artifact (D15): round 10 graded record without --page failed — see $work/judge-t43.log"
  cat "$work/judge-t43.log" >&2 || true
fi
# (44) N12 ATTACK: a regrade artifact prepared for page2.html cited on
# feedback for round 10 (graded on page.html, recorded without
# --page), feedback itself passing no --page → exit 2. Before the
# red-team fix this recorded: the artifact's own page became the
# binding and the round's pageSha was never consulted.
if ! node "$judge_report_mjs" --project "$jr_proj" prepare --round 10 --kind regrade --grader other-model --brief-type landing --mode full --page design/page2.html --out design/judge/round-10-regrade-wrong.md >"$work/judge-prep-10-regrade-wrong.log" 2>&1; then
  fail "judge-artifact (D15): prepare of the wrong-page regrade artifact failed — case (44) will cascade; see $work/judge-prep-10-regrade-wrong.log"
  cat "$work/judge-prep-10-regrade-wrong.log" >&2 || true
fi
jr_fill_scores "$jr_proj/design/judge/round-10-regrade-wrong.md" 5 5 5 5
jr_reject "feedback regrade artifact bound to a different page than the round graded (no --page anywhere)" "$work/judge-t44.log" "page whose hash differs" \
  node "$run_log_mjs" --project "$jr_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 10 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-10-regrade-wrong.md
# (45) N12 CONTROL: a regrade artifact for the page round 10 actually
# graded (page.html), feedback still passing no --page → exit 0.
jr_prep 10 regrade --grader other-model
jr_fill_scores "$jr_proj/design/judge/round-10-regrade.md" 4 4 4 4
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 10 --score-after 4,4,4,4 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-10-regrade.md >"$work/judge-t45.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"judgeReport":"design/judge/round-10-regrade.md"'; then
    ok "run-log records feedback whose regrade artifact binds to the page the round graded (pageSha match, no --page needed)"
  else
    fail "judge-artifact (D15): N12 control feedback recorded but the stored line lacks the regrade citation"
  fi
else
  fail "judge-artifact (D15): N12 control feedback (correct page, no --page) failed — see $work/judge-t45.log"
  cat "$work/judge-t45.log" >&2 || true
fi
# (46) PW-TIE POSITIVE: the two pairwise derivations DISAGREE (call 1
# keeps the challenger in its A/B terms; call 2, swapped, keeps the
# incumbent in its) — the derived verdict is tie, and recording
# --pairwise tie transcribes it (companion to (27): the same
# disagreement cited as a keep is refused).
jr_prep 11 absolute
jr_prep 11 pairwise --index 1 --shots-a design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --shots-b design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png
jr_prep 11 pairwise --index 2 --shots-a design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png --shots-b design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png
jr_fill_scores "$jr_proj/design/judge/round-11.md" 4 4 4 4
jr_fill_pairwise "$jr_proj/design/judge/round-11-pairwise-1.md" A
jr_fill_pairwise "$jr_proj/design/judge/round-11-pairwise-2.md" A
jr_before="$(jr_lines)"
if node "$run_log_mjs" --project "$jr_proj" record --round 11 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-11.md --gate pass $jr_legs --pairwise tie --pairwise-reports design/judge/round-11-pairwise-1.md,design/judge/round-11-pairwise-2.md >"$work/judge-t46.log" 2>&1; then
  if [[ "$(jr_lines)" == "$((jr_before + 1))" ]] && tail -n 1 "$jr_log" | grep -q '"pairwise":"tie"'; then
    ok "run-log records --pairwise tie when the two pairwise artifacts' derivations disagree (the derived verdict)"
  else
    fail "judge-artifact (D15): pairwise tie recorded but the stored line lacks pairwise:tie"
  fi
else
  fail "judge-artifact (D15): pairwise tie positive failed — see $work/judge-t46.log"
  cat "$work/judge-t46.log" >&2 || true
fi
# (47) READ-PATH fake shapes: a hand-written log whose scored lines
# carry (i) grader null, (ii) no grader key at all, (iii) a citation
# naming a nonexistent file with an invented sha. runlog-check must
# fail it (grader + citation-verification messages), and `best` must
# crown none of it.
fake_proj="$work/fake-proj"
mkdir -p "$fake_proj/design"
printf '%s\n' '{"kind":"round","round":1,"grader":null,"scores":{"type":5,"layout":5,"colour":5,"space":5},"gate":"pass"}' > "$fake_proj/design/run-log.jsonl"
printf '%s\n' '{"kind":"round","round":2,"scores":{"type":5,"layout":5,"colour":5,"space":5},"gate":"pass"}' >> "$fake_proj/design/run-log.jsonl"
printf '%s\n' '{"kind":"round","round":3,"grader":"judge-subagent","scores":{"type":5,"layout":5,"colour":5,"space":5},"gate":"pass","judgeReport":"design/judge/round-3.md","judgeReportSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' >> "$fake_proj/design/run-log.jsonl"
if node "$runlog_check_mjs" "$fake_proj/design/run-log.jsonl" >"$work/judge-t47a.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a hand-written log of grader-less / fake-citation scored lines"
elif ! grep -q "carries no grader" "$work/judge-t47a.log" || ! grep -q "does not exist or cannot be read" "$work/judge-t47a.log"; then
  fail "judge-artifact (D15): runlog-check failed the fake log but not via the grader / citation-verification messages — see $work/judge-t47a.log"
  cat "$work/judge-t47a.log" >&2 || true
elif ! node "$run_log_mjs" --project "$fake_proj" best >"$work/judge-t47b.log" 2>&1 || ! grep -q "no graded rounds yet" "$work/judge-t47b.log"; then
  fail "judge-artifact (D15): best crowned a hand-written fake round — see $work/judge-t47b.log"
  cat "$work/judge-t47b.log" >&2 || true
else
  ok "runlog-check fails grader-less and fake-citation scored lines, and best crowns none of them (read-path verification)"
fi
# (48) PREPARE CONTAINMENT: design/judge is a symlink to a directory
# OUTSIDE the project — prepare must refuse (exit 2) and write nothing
# there. (A lexical inside-design/judge check alone passes this.)
esc_proj="$work/judge-escape-proj"
mkdir -p "$esc_proj/design/screenshots" "$esc_proj/design/crosscheck" "$work/judge-outside"
cp "$work/tokens.css" "$esc_proj/design/tokens.css"
cp "$work/page-d15-orig.html" "$esc_proj/design/page.html"
for v in 1440 768 390; do printf 'PNG-%s-A' "$v" > "$esc_proj/design/screenshots/$v.png"; done
printf 'GATE RESULT: PASS\n' > "$esc_proj/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$esc_proj/design/gate-leg2.log"
printf 'cross-check report r1\n' > "$esc_proj/design/crosscheck/round-1.md"
touch -d '2026-11-11 12:00' "$esc_proj/design/tokens.css"
touch -d '2026-11-11 12:01' "$esc_proj/design/page.html"
touch -d '2026-11-11 12:02' "$esc_proj/design/screenshots/"*.png "$esc_proj/design/gate-leg1.log" "$esc_proj/design/gate-leg2.log" "$esc_proj/design/crosscheck/round-1.md"
if ! node "$run_log_mjs" --project "$esc_proj" crosscheck --slice d15 --round 1 --severe 0 --warning 0 --report design/crosscheck/round-1.md --checker security-expert --basis "$jr_basis" >"$work/judge-cc-esc.log" 2>&1; then
  fail "judge-artifact (D15): escape-project setup cross-check failed — case (48) will cascade; see $work/judge-cc-esc.log"
  cat "$work/judge-cc-esc.log" >&2 || true
fi
ln -s "$work/judge-outside" "$esc_proj/design/judge"
if node "$judge_report_mjs" --project "$esc_proj" prepare --round 1 --kind absolute --grader judge-subagent --brief-type landing --mode full --page design/page.html >"$work/judge-t48.log" 2>&1; then
  fail "judge-artifact (D15): prepare wrote a skeleton through a design/judge symlink pointing outside the project"
elif ! grep -q "outside the project" "$work/judge-t48.log"; then
  fail "judge-artifact (D15): prepare refused the symlinked design/judge but not via the containment message — see $work/judge-t48.log"
  cat "$work/judge-t48.log" >&2 || true
elif [[ -n "$(ls -A "$work/judge-outside")" ]]; then
  fail "judge-artifact (D15): prepare refused but a file still landed outside the project"
else
  ok "judge-report prepare refuses when design/judge resolves outside the project (exit 2, nothing written)"
fi
# (49) PREPARE CONTAINMENT: an explicit --shots path resolving outside
# the project → exit 2, no skeleton written.
printf 'PNG-OUT' > "$work/outside-shot.png"
if node "$judge_report_mjs" --project "$jr_proj" prepare --round 12 --kind absolute --grader judge-subagent --brief-type landing --mode full --page design/page.html --shots ../outside-shot.png >"$work/judge-t49.log" 2>&1; then
  fail "judge-artifact (D15): prepare accepted a --shots path resolving outside the project"
elif ! grep -q "resolves outside the project" "$work/judge-t49.log"; then
  fail "judge-artifact (D15): prepare refused the outside --shots path but not via the containment message — see $work/judge-t49.log"
  cat "$work/judge-t49.log" >&2 || true
elif [[ -f "$jr_proj/design/judge/round-12.md" ]]; then
  fail "judge-artifact (D15): prepare refused the outside --shots path but still wrote the skeleton"
else
  ok "judge-report prepare refuses a --shots path resolving outside the project (exit 2, no file)"
fi

# --- Red-team-round-2 cases (50)–(60): anchor poisoning (NA4,
# SEVERE), the land precondition (NA19), and the read-path family
# (C3 cross-round citation, NA1 deleted juror artifacts, NA2
# juryReportShas shape, NA3 gate-key-absent, NA8 symlink citation),
# plus the NA20 exception control. A dedicated project: round 1
# graded 3,3,3,3 (absolute), round 2 a jury round (median 5,5,5,5),
# rounds 4/5 absolute artifacts prepared but never recorded (citation
# targets for the appended-line cases).
rp_proj="$work/readpath-proj"
mkdir -p "$rp_proj/design/screenshots" "$rp_proj/design/screenshots-prev" "$rp_proj/design/judge" "$rp_proj/design/crosscheck"
cp "$work/tokens.css" "$rp_proj/design/tokens.css"
cp "$work/page-d15-orig.html" "$rp_proj/design/page.html"
cp "$jr_proj/design/page2.html" "$rp_proj/design/page2.html"
for v in 1440 768 390; do
  printf 'PNG-%s-A' "$v" > "$rp_proj/design/screenshots/$v.png"
  printf 'PNG-%s-B' "$v" > "$rp_proj/design/screenshots-prev/$v.png"
done
printf 'GATE RESULT: PASS\n' > "$rp_proj/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n' > "$rp_proj/design/gate-leg2.log"
for r in 1 2 3 4 5 12; do printf 'cross-check report r%s\n' "$r" > "$rp_proj/design/crosscheck/round-$r.md"; done
touch -d '2026-11-11 12:00' "$rp_proj/design/tokens.css"
touch -d '2026-11-11 12:01' "$rp_proj/design/page.html" "$rp_proj/design/page2.html"
touch -d '2026-11-11 12:02' "$rp_proj/design/screenshots/"*.png "$rp_proj/design/screenshots-prev/"*.png "$rp_proj/design/gate-leg1.log" "$rp_proj/design/gate-leg2.log" "$rp_proj/design/crosscheck/"*.md
rp_log="$rp_proj/design/run-log.jsonl"
rp_lines() { if [[ -f "$rp_log" ]]; then grep -c . "$rp_log" || true; else printf '0'; fi; }
rp_legs="--gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html"
rp_setup_ok=1
for r in 1 2 3 4 5 12; do
  node "$run_log_mjs" --project "$rp_proj" crosscheck --slice d15 --round $r --severe 0 --warning 0 --report "design/crosscheck/round-$r.md" --checker security-expert --basis "$jr_basis" >"$work/rp-cc-$r.log" 2>&1 || rp_setup_ok=0
done
rp_prep() { # round kind [extra prepare args...]
  local round="$1" kind="$2"; shift 2
  if ! node "$judge_report_mjs" --project "$rp_proj" prepare --round "$round" --kind "$kind" --grader judge-subagent --brief-type landing --mode full --page design/page.html "$@" >"$work/rp-prep-$round-$kind.log" 2>&1; then
    fail "judge-artifact (D15): read-path project prepare round $round kind $kind failed — cases (50)–(60) will cascade; see $work/rp-prep-$round-$kind.log"
    cat "$work/rp-prep-$round-$kind.log" >&2 || true
    rp_setup_ok=0
  fi
}
rp_prep 1 absolute
jr_fill_scores "$rp_proj/design/judge/round-1.md" 3 3 3 3
node "$run_log_mjs" --project "$rp_proj" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-1.md --gate pass $rp_legs >"$work/rp-rec-1.log" 2>&1 || rp_setup_ok=0
rp_prep 2 absolute
rp_prep 2 jury --index 1 --family fam1
rp_prep 2 jury --index 2 --family fam2
rp_prep 2 jury --index 3 --family fam3
jr_fill_scores "$rp_proj/design/judge/round-2.md" 5 5 5 5
jr_fill_scores "$rp_proj/design/judge/round-2-jury-1.md" 5 5 5 5
jr_fill_scores "$rp_proj/design/judge/round-2-jury-2.md" 5 5 5 4
jr_fill_scores "$rp_proj/design/judge/round-2-jury-3.md" 5 4 5 5
node "$run_log_mjs" --project "$rp_proj" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 5,5,5,5 --judge-report design/judge/round-2.md --gate pass $rp_legs --outcome stopped --jury 5,5,5,5 --jury-mode disjoint-3 --jury-votes "5,5,5,5;5,5,5,4;5,4,5,5" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/rp-rec-2.log" 2>&1 || rp_setup_ok=0
rp_prep 4 absolute
jr_fill_scores "$rp_proj/design/judge/round-4.md" 4 4 4 4
rp_prep 5 absolute
jr_fill_scores "$rp_proj/design/judge/round-5.md" 5 5 5 5
if [[ "$rp_setup_ok" != 1 ]]; then
  fail "judge-artifact (D15): read-path project setup failed — cases (50)–(60) will cascade; see $work/rp-*.log"
fi
rp_page_sha="$(sha256sum "$rp_proj/design/page.html" | cut -d' ' -f1)"
rp_page2_sha="$(sha256sum "$rp_proj/design/page2.html" | cut -d' ' -f1)"
rp_r1_sha="$(sha256sum "$rp_proj/design/judge/round-1.md" | cut -d' ' -f1)"
rp_r4_sha="$(sha256sum "$rp_proj/design/judge/round-4.md" | cut -d' ' -f1)"
rp_r5_sha="$(sha256sum "$rp_proj/design/judge/round-5.md" | cut -d' ' -f1)"
# rp_reject <name> <logfile> <pattern> <cmd...>: like jr_reject, for
# the read-path project's log.
rp_reject() {
  local name="$1" logf="$2" pat="$3"; shift 3
  local before; before="$(rp_lines)"
  if "$@" >"$logf" 2>&1; then
    fail "judge-artifact (D15): $name exited 0 — must be refused (exit 2)"
  elif [[ "$(rp_lines)" != "$before" ]]; then
    fail "judge-artifact (D15): $name wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "$pat" "$logf"; then
    fail "judge-artifact (D15): $name was refused but not via the expected message (/$pat/) — see $logf"
    cat "$logf" >&2 || true
  else
    ok "run-log refuses $name (exit 2, nothing written)"
  fi
}
# (50) POSITIVE CONTROL: runlog-check passes the genuine read-path
# log (graded + jury lines) under the round-2 rule-6 extensions —
# the shape/parse checks must not false-positive on writer output.
if node "$runlog_check_mjs" "$rp_log" >"$work/rp-t50.log" 2>&1; then
  ok "runlog-check passes a genuine graded + jury run log under the round-2 rule extensions"
else
  fail "judge-artifact (D15): runlog-check failed the genuine read-path log — see $work/rp-t50.log"
  cat "$work/rp-t50.log" >&2 || true
fi
# (51) POSITIVE CONTROL: best crowns the genuine jury round — the
# parse + juror-artifact verification must not break real crowning.
if node "$run_log_mjs" --project "$rp_proj" best >"$work/rp-t51.log" 2>&1 && grep -q "best: round 2" "$work/rp-t51.log" && grep -q "jury median" "$work/rp-t51.log"; then
  ok "best crowns the genuine jury round (citation parses, juror artifacts verify)"
else
  fail "judge-artifact (D15): best did not crown the genuine jury round — see $work/rp-t51.log"
  cat "$work/rp-t51.log" >&2 || true
fi
# (52) NA1: one juror artifact DELETED after the jury round recorded
# — best must skip the jury line entirely and crown round 1, not the
# jury round on its absolute citation alone.
rm "$rp_proj/design/judge/round-2-jury-2.md"
if node "$run_log_mjs" --project "$rp_proj" best >"$work/rp-t52.log" 2>&1 && grep -q "best: round 1" "$work/rp-t52.log"; then
  ok "best skips a jury round whose juror artifacts no longer verify (NA1) and crowns the genuine absolute round"
else
  fail "judge-artifact (D15): best crowned a jury round with a deleted juror artifact (NA1) — see $work/rp-t52.log"
  cat "$work/rp-t52.log" >&2 || true
fi
# (53) C3: a hand-appended round-6 line citing round 1's REAL
# artifact (path + true sha copied from the genuine line — the hash
# verifies) with the artifact's own scores. runlog-check must fail
# it on the PARSE half (header round 1 != line round 6), and best
# must not crown it.
printf '%s\n' "{\"kind\":\"round\",\"round\":6,\"grader\":\"judge-subagent\",\"independenceBasis\":\"fresh context, no production history\",\"scores\":{\"type\":3,\"layout\":3,\"colour\":3,\"space\":3},\"grade\":\"graded\",\"gate\":\"pass\",\"judgeReport\":\"design/judge/round-1.md\",\"judgeReportSha\":\"$rp_r1_sha\",\"pageSha\":\"$rp_page_sha\"}" >> "$rp_log"
if node "$runlog_check_mjs" "$rp_log" >"$work/rp-t53a.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a line citing another round's artifact (C3)"
elif ! grep -q "report for round 1, not round 6" "$work/rp-t53a.log"; then
  fail "judge-artifact (D15): runlog-check failed the cross-round citation but not via the parse message — see $work/rp-t53a.log"
  cat "$work/rp-t53a.log" >&2 || true
elif ! node "$run_log_mjs" --project "$rp_proj" best >"$work/rp-t53b.log" 2>&1 || ! grep -q "best: round 1" "$work/rp-t53b.log"; then
  fail "judge-artifact (D15): best crowned the cross-round citation line (C3) — see $work/rp-t53b.log"
  cat "$work/rp-t53b.log" >&2 || true
else
  ok "runlog-check fails a cross-round citation on the parse half and best does not crown it (C3)"
fi
# (54) NA2: a scored line whose juryReportShas is "nothex" — the
# citation itself is genuine (round 4's real artifact, its own
# scores), so only the juryReportShas shape rule can fail it.
cp "$rp_log" "$rp_proj/design/run-log-na2.jsonl"
printf '%s\n' "{\"kind\":\"round\",\"round\":4,\"grader\":\"judge-subagent\",\"independenceBasis\":\"fresh context, no production history\",\"scores\":{\"type\":4,\"layout\":4,\"colour\":4,\"space\":4},\"grade\":\"graded\",\"gate\":\"pass\",\"judgeReport\":\"design/judge/round-4.md\",\"judgeReportSha\":\"$rp_r4_sha\",\"pageSha\":\"$rp_page_sha\",\"jury\":{\"type\":5,\"layout\":5,\"colour\":5,\"space\":5},\"juryMode\":\"disjoint-3\",\"juryReportShas\":\"nothex\"}" >> "$rp_proj/design/run-log-na2.jsonl"
if node "$runlog_check_mjs" "$rp_proj/design/run-log-na2.jsonl" >"$work/rp-t54.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a scored line with juryReportShas \"nothex\" (NA2)"
elif ! grep -q "juryReportShas" "$work/rp-t54.log"; then
  fail "judge-artifact (D15): runlog-check failed the NA2 line but not via the juryReportShas message — see $work/rp-t54.log"
  cat "$work/rp-t54.log" >&2 || true
else
  ok "runlog-check fails a scored line whose juryReportShas is not three 64-hex values (NA2)"
fi
# (55) NA8: a scored line citing a SYMLINK to round 1's artifact
# (the target's true sha — the hash verifies through the link).
# Only the lstat symlink rule can fail it.
ln -sf round-1.md "$rp_proj/design/judge/link-1.md"
cp "$rp_log" "$rp_proj/design/run-log-na8.jsonl"
printf '%s\n' "{\"kind\":\"round\",\"round\":1,\"grader\":\"judge-subagent\",\"independenceBasis\":\"fresh context, no production history\",\"scores\":{\"type\":3,\"layout\":3,\"colour\":3,\"space\":3},\"grade\":\"graded\",\"gate\":\"pass\",\"judgeReport\":\"design/judge/link-1.md\",\"judgeReportSha\":\"$rp_r1_sha\",\"pageSha\":\"$rp_page_sha\"}" >> "$rp_proj/design/run-log-na8.jsonl"
if node "$runlog_check_mjs" "$rp_proj/design/run-log-na8.jsonl" >"$work/rp-t55.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a scored line citing a symlinked judge artifact (NA8)"
elif ! grep -q "is a symlink" "$work/rp-t55.log"; then
  fail "judge-artifact (D15): runlog-check failed the NA8 line but not via the symlink message — see $work/rp-t55.log"
  cat "$work/rp-t55.log" >&2 || true
else
  ok "runlog-check fails a scored line citing a symlinked judge artifact (NA8)"
fi
# (56) NA4, land half: an appended scoreless pageSha line for round
# 3 (a round with a clear cross-check but NO genuine round record)
# must NOT satisfy land's precondition → exit 2.
printf '%s\n' "{\"kind\":\"round\",\"round\":3,\"grader\":null,\"scores\":null,\"grade\":\"gate green, vision not available\",\"gate\":\"pass\",\"page\":\"design/page2.html\",\"pageSha\":\"$rp_page2_sha\",\"judgeReport\":null,\"judgeReportSha\":null}" >> "$rp_log"
rp_reject "land whose only round record is an appended scoreless pageSha line" "$work/rp-t56.log" "has no round record" \
  node "$run_log_mjs" --project "$rp_proj" land --slice d15 --round 3 --gate pass $rp_legs
# (57) NA4, feedback half (SEVERE): the same poison appended for
# round 1 — which HAS a genuine graded record on page.html — plus a
# regrade artifact prepared for page2.html. Before the round-2 fix
# the appended line (the LATER pageSha carrier) anchored the
# regrade and this recorded; the anchor now comes only from the
# verified graded record → exit 2.
printf '%s\n' "{\"kind\":\"round\",\"round\":1,\"grader\":null,\"scores\":null,\"grade\":\"gate green, vision not available\",\"gate\":\"pass\",\"page\":\"design/page2.html\",\"pageSha\":\"$rp_page2_sha\",\"judgeReport\":null,\"judgeReportSha\":null}" >> "$rp_log"
if ! node "$judge_report_mjs" --project "$rp_proj" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page2.html >"$work/rp-prep-1-regrade-p2.log" 2>&1; then
  fail "judge-artifact (D15): prepare of the NA4 wrong-page regrade failed — case (57) will cascade; see $work/rp-prep-1-regrade-p2.log"
  cat "$work/rp-prep-1-regrade-p2.log" >&2 || true
fi
jr_fill_scores "$rp_proj/design/judge/round-1-regrade.md" 5 5 5 5
rp_reject "feedback regrade anchored only by an appended scoreless pageSha line" "$work/rp-t57.log" "not the recorded page" \
  node "$run_log_mjs" --project "$rp_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md
# (58) NA4, checker half: runlog-check flags the appended scoreless
# pageSha lines themselves (the impossible shape) → exit 1.
if node "$runlog_check_mjs" "$rp_log" >"$work/rp-t58.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed the log carrying appended scoreless pageSha lines (NA4)"
elif ! grep -q "carries a pageSha" "$work/rp-t58.log"; then
  fail "judge-artifact (D15): runlog-check failed the NA4 log but not via the scoreless-pageSha message — see $work/rp-t58.log"
  cat "$work/rp-t58.log" >&2 || true
else
  ok "runlog-check fails scoreless lines carrying a pageSha (the NA4 poison shape)"
fi
# (59) NA3: a scored line with NO gate key at all, citing round 5's
# real artifact with the artifact's own scores (the citation parses
# and verifies — the absent gate is the only defect). best must not
# crown it: crowning requires gate exactly "pass".
printf '%s\n' "{\"kind\":\"round\",\"round\":5,\"grader\":\"judge-subagent\",\"independenceBasis\":\"fresh context, no production history\",\"scores\":{\"type\":5,\"layout\":5,\"colour\":5,\"space\":5},\"grade\":\"graded\",\"judgeReport\":\"design/judge/round-5.md\",\"judgeReportSha\":\"$rp_r5_sha\",\"pageSha\":\"$rp_page_sha\"}" >> "$rp_log"
if node "$run_log_mjs" --project "$rp_proj" best >"$work/rp-t59.log" 2>&1 && grep -q "best: round 1" "$work/rp-t59.log"; then
  ok "best does not crown a scored line with no gate key (NA3 — crowning requires gate exactly pass)"
else
  fail "judge-artifact (D15): best crowned a scored line with no gate key (NA3) — see $work/rp-t59.log"
  cat "$work/rp-t59.log" >&2 || true
fi
# (60) NA20 CONTROL (behaviour retained, not changed): feedback
# --score-after for a round with NO round record at all still
# records, anchored by --page (the pre-D15 fallback form).
rp_prep 12 regrade --grader other-model
jr_fill_scores "$rp_proj/design/judge/round-12-regrade.md" 4 4 4 4
rp_before="$(rp_lines)"
if node "$run_log_mjs" --project "$rp_proj" feedback --from "user: darker ink" --change "--color-ink: #000" --round 12 --score-after 4,4,4,4 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-12-regrade.md --page design/page.html >"$work/rp-t60.log" 2>&1 && [[ "$(rp_lines)" == "$((rp_before + 1))" ]]; then
  ok "run-log records feedback for a round with no round record, --page-anchored (NA20 behaviour retained)"
else
  fail "judge-artifact (D15): NA20 control feedback (no round record, --page given) failed — see $work/rp-t60.log"
  cat "$work/rp-t60.log" >&2 || true
fi

# --- Red-team-round-3 cases (61)–(68): the shared-verifier round.
# Round 2 hardened the read paths call-site by call-site; round 3
# proved the drift (B1 scored-poison anchor, B1b leg-as-artifact,
# B2 jury median trusted on read, B3 no-grade leg citations never
# opened, B4 runlog-check fallback not fail-closed, B5 grader
# misattribution, B6 stale-page pageSha edit, B7 symlink asymmetry).
# The fix routes every read consumer through ONE full verification
# (run-log.mjs verifyGradedLine + verifyJuryLine; runlog-check was
# written to mirror it and fail closed when its parser sibling is
# absent — red-team round 4 proved the mirror had drifted, and the
# verifiers now live in judge-report.mjs, imported by BOTH
# consumers; see the round-4 cases (69)–(78) below).
# Each case gets its own small project, built like the read-path
# project above.
r3_legs="--gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html"
r3_mkproj() { # dir — tokens/page/page2/shots/legs + cross-checks rounds 1..3 (slice r3)
  local P="$1" r
  mkdir -p "$P/design/screenshots" "$P/design/screenshots-prev" "$P/design/judge" "$P/design/crosscheck"
  cp "$work/tokens.css" "$P/design/tokens.css"
  cp "$work/page-d15-orig.html" "$P/design/page.html"
  printf '<html><body><main id="main"><h1>Other page</h1></main></body></html>\n' > "$P/design/page2.html"
  for v in 1440 768 390; do
    printf 'PNG-%s-A' "$v" > "$P/design/screenshots/$v.png"
    printf 'PNG-%s-B' "$v" > "$P/design/screenshots-prev/$v.png"
  done
  printf 'GATE RESULT: PASS\n' > "$P/design/gate-leg1.log"
  printf '===== gate verdict: GREEN =====\n' > "$P/design/gate-leg2.log"
  for r in 1 2 3; do printf 'cross-check report r%s\n' "$r" > "$P/design/crosscheck/round-$r.md"; done
  touch -d '2026-11-11 12:00' "$P/design/tokens.css"
  touch -d '2026-11-11 12:01' "$P/design/page.html" "$P/design/page2.html"
  touch -d '2026-11-11 12:02' "$P/design/screenshots/"*.png "$P/design/screenshots-prev/"*.png "$P/design/gate-leg1.log" "$P/design/gate-leg2.log" "$P/design/crosscheck/"*.md
  for r in 1 2 3; do
    node "$run_log_mjs" --project "$P" crosscheck --slice r3 --round $r --severe 0 --warning 0 --report "design/crosscheck/round-$r.md" --checker security-expert --basis "$jr_basis" >"$work/r3-cc-$r.log" 2>&1 \
      || fail "judge-artifact (D15): round-3 project setup cross-check round $r failed — cases (61)–(68) using it will cascade; see $work/r3-cc-$r.log"
  done
}
r3_prep() { # proj round kind [extra prepare args...] — bound to design/page.html
  local P="$1" round="$2" kind="$3"; shift 3
  node "$judge_report_mjs" --project "$P" prepare --round "$round" --kind "$kind" --grader judge-subagent --brief-type landing --mode full --page design/page.html "$@" >"$work/r3-prep-$round-$kind.log" 2>&1 \
    || fail "judge-artifact (D15): round-3 prepare round $round kind $kind failed — dependent cases will cascade; see $work/r3-prep-$round-$kind.log"
}
r3_reject() { # name logfile pattern projlog cmd... — like jr_reject, for a named project log
  local name="$1" logf="$2" pat="$3" plog="$4"; shift 4
  local before; before="$(grep -c . "$plog" || true)"
  if "$@" >"$logf" 2>&1; then
    fail "judge-artifact (D15): $name exited 0 — must be refused (exit 2)"
  elif [[ "$(grep -c . "$plog" || true)" != "$before" ]]; then
    fail "judge-artifact (D15): $name wrote to the run log — a refused entry must write nothing"
  elif ! grep -q "$pat" "$logf"; then
    fail "judge-artifact (D15): $name was refused but not via the expected message (/$pat/) — see $logf"
    cat "$logf" >&2 || true
  else
    ok "run-log refuses $name (exit 2, nothing written)"
  fi
}
# (61) B1: a scored COPY of the genuine round-1 line with pageSha
# swapped to page2's hash. Its citation verifies (same artifact), so
# only the page binding can refuse it: the copy must not anchor a
# feedback regrade of page2, and runlog-check must fail the log on
# the pageSha cross-check.
r3p="$work/r3-b1"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log >"$work/r3-t61-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B1 setup graded record failed — case (61) will cascade; see $work/r3-t61-setup.log"
r3_page2_sha="$(sha256sum "$r3p/design/page2.html" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r3_page2_sha" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
g=[o for o in lines if o.get('kind')=='round' and o.get('round')==1][0]
poison=dict(g); poison['pageSha']=sys.argv[2]; poison['at']="2026-11-11T12:11:00.000Z"
open(sys.argv[1],"a").write(json.dumps(poison)+"\n")
EOF
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page2.html >"$work/r3-prep-1-regrade-p2.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B1 wrong-page regrade prepare failed — case (61) will cascade; see $work/r3-prep-1-regrade-p2.log"
jr_fill_scores "$r3p/design/judge/round-1-regrade.md" 5 5 5 5
r3_reject "feedback regrade of page2 anchored by a scored poison line (pageSha swapped)" "$work/r3-t61a.log" "page whose hash differs" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md
if node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t61b.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check passed a log carrying a scored line whose pageSha names a different page than its artifact binds (B1)"
elif ! grep -q "pageSha" "$work/r3-t61b.log"; then
  fail "judge-artifact (D15): runlog-check failed the B1 log but not via the pageSha cross-check — see $work/r3-t61b.log"
  cat "$work/r3-t61b.log" >&2 || true
else
  ok "runlog-check fails a scored line whose pageSha does not match its cited artifact's page binding (B1)"
fi
# (62) B1b: a scored line citing the GATE LEG as its "judge artifact"
# (true hash — the citation's hash verifies; the file is not a judge
# report). It must anchor nothing and satisfy no land precondition.
r3p="$work/r3-b1b"; r3_mkproj "$r3p"
r3_leg1_sha="$(sha256sum "$r3p/design/gate-leg1.log" | cut -d' ' -f1)"
r3_page2_sha="$(sha256sum "$r3p/design/page2.html" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r3_leg1_sha" "$r3_page2_sha" <<'EOF'
import json,sys
legsha,pagesha=sys.argv[2],sys.argv[3]
line={"kind":"round","round":1,"grader":"judge-subagent","independenceBasis":"fresh context, no production history","scores":{"type":4,"layout":4,"colour":4,"space":4},"grade":"A","evidence":"x","gate":"pass","gateLeg1":"design/gate-leg1.log","gateLeg2":"design/gate-leg2.log","gateLeg1Sha":legsha,"gateLeg2Sha":legsha,"gateFindings":None,"variant":None,"tokensHash":None,"fixClass":None,"outcome":"stopped","page":None,"trigger":None,"pairwise":None,"pairwiseAgrees":None,"jury":None,"juryMode":None,"juryVotes":None,"notRegraded":None,"expertMotion":None,"expertMotionEvidence":None,"expertUx":None,"expertUxEvidence":None,"judgeReport":"design/gate-leg1.log","judgeReportSha":legsha,"pageSha":pagesha,"pairwiseReports":None,"pairwiseReportShas":None,"juryReportShas":None,"expertMotionReport":None,"expertMotionReportSha":None,"expertUxReport":None,"expertUxReportSha":None,"notes":None,"at":"2026-11-11T12:06:00.000Z"}
open(sys.argv[1],"a").write(json.dumps(line)+"\n")
EOF
r3_reject "land whose only round record cites the gate leg as its judge artifact" "$work/r3-t62a.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page2.html >"$work/r3-prep-1-regrade-b1b.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B1b regrade prepare failed — case (62) will cascade; see $work/r3-prep-1-regrade-b1b.log"
jr_fill_scores "$r3p/design/judge/round-1-regrade.md" 5 5 5 5
r3_reject "feedback regrade anchored by a line citing the gate leg as its judge artifact" "$work/r3-t62b.log" "never anchors" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md
# (63) B2: the jury-median edit — a genuine jury round (jurors
# 2/3/2, median 2,2,2,2) whose LINE jury + juryVotes are edited to
# 5,5,5,5, juror artifacts untouched. best must skip the edited line
# (it crowns nothing — the round was the only one), and
# runlog-check must fail the log on the jury verification.
r3p="$work/r3-b2"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
r3_prep "$r3p" 2 jury --index 1 --family fam1
r3_prep "$r3p" 2 jury --index 2 --family fam2
r3_prep "$r3p" 2 jury --index 3 --family fam3
jr_fill_scores "$r3p/design/judge/round-2.md" 3 3 3 3
jr_fill_scores "$r3p/design/judge/round-2-jury-1.md" 2 2 2 2
jr_fill_scores "$r3p/design/judge/round-2-jury-2.md" 3 3 3 3
jr_fill_scores "$r3p/design/judge/round-2-jury-3.md" 2 2 2 2
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $r3_legs --outcome stopped --jury 2,2,2,2 --jury-mode disjoint-3 --jury-votes "2,2,2,2;3,3,3,3;2,2,2,2" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/r3-t63-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B2 setup jury record failed — case (63) will cascade; see $work/r3-t63-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r3-t63a.log" 2>&1
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round' and o.get('round')==2:
        o['jury']={"type":5,"layout":5,"colour":5,"space":5}
        o['juryVotes']=[{"type":5,"layout":5,"colour":5,"space":5}]*3
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r3-t63b.log" 2>&1
if ! grep -q "best: round 2" "$work/r3-t63a.log" || ! grep -q "T2/L2/C2/S2" "$work/r3-t63a.log"; then
  fail "judge-artifact (D15): best did not crown the genuine jury round at its honest median before the B2 edit — see $work/r3-t63a.log"
  cat "$work/r3-t63a.log" >&2 || true
elif ! grep -q "no graded rounds" "$work/r3-t63b.log"; then
  fail "judge-artifact (D15): best crowned a jury round whose line jury/juryVotes were edited to 5,5,5,5 (B2) — see $work/r3-t63b.log"
  cat "$work/r3-t63b.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t63c.log" 2>&1 || ! grep -q "jury" "$work/r3-t63c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the jury-edited log on the jury verification (B2) — see $work/r3-t63c.log"
  cat "$work/r3-t63c.log" >&2 || true
else
  ok "best skips a jury round whose recorded median was edited (the juror artifacts derive 2,2,2,2, not the edited 5,5,5,5) and runlog-check fails it on the jury verification (B2)"
fi
# (64) B3: a hand-written no-grade line in the FULL writer shape —
# gate pass, both leg citations present — but the leg paths never
# existed and the leg shas are invented. land must refuse: the
# no-grade half of the precondition now verifies the cited legs on
# disk against the stored shas.
r3p="$work/r3-b3"; r3_mkproj "$r3p"
r3_hx="$(printf 'x' | sha256sum | cut -d' ' -f1)"
r3_hy="$(printf 'y' | sha256sum | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r3_hx" "$r3_hy" <<'EOF'
import json,sys
hx,hy=sys.argv[2],sys.argv[3]
line={"kind":"round","round":2,"grader":None,"independenceBasis":None,"scores":None,"grade":"gate green, vision not available","evidence":None,"gate":"pass","gateLeg1":"design/never-ran-1.log","gateLeg2":"design/never-ran-2.log","gateLeg1Sha":hx,"gateLeg2Sha":hy,"gateFindings":None,"variant":None,"tokensHash":None,"fixClass":None,"outcome":None,"page":None,"trigger":None,"pairwise":None,"pairwiseAgrees":None,"jury":None,"juryMode":None,"juryVotes":None,"notRegraded":None,"expertMotion":None,"expertMotionEvidence":None,"expertUx":None,"expertUxEvidence":None,"judgeReport":None,"judgeReportSha":None,"pageSha":None,"pairwiseReports":None,"pairwiseReportShas":None,"juryReportShas":None,"expertMotionReport":None,"expertMotionReportSha":None,"expertUxReport":None,"expertUxReportSha":None,"notes":None,"at":"2026-11-11T12:04:00.000Z"}
open(sys.argv[1],"a").write(json.dumps(line)+"\n")
EOF
r3_reject "land whose only round record is a full-shape no-grade line citing legs that never existed" "$work/r3-t64.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs
# (65) B4: the runlog-check fallback is GONE — a copy of the checker
# without its judge-report.mjs sibling (or with an unparseable one)
# must FAIL a genuine scored log with "judge-report parser
# unavailable" (fail closed), while the full tree passes it.
r3p="$work/r3-b4"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r3-t65-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B4 setup graded record failed — case (65) will cascade; see $work/r3-t65-setup.log"
r3_gate_dir="$(dirname "$runlog_check_mjs")"
mkdir -p "$work/r3-notree/gate" "$work/r3-brokentree/gate"
cp "$r3_gate_dir/runlog-check.mjs" "$r3_gate_dir/json-dup-keys.mjs" "$work/r3-notree/gate/"
cp "$r3_gate_dir/runlog-check.mjs" "$r3_gate_dir/json-dup-keys.mjs" "$work/r3-brokentree/gate/"
cp "$(dirname "$judge_report_mjs")/judge-report.mjs" "$work/r3-brokentree/judge-report.mjs"
printf '\n@@@ this is not javascript @@@\n' >> "$work/r3-brokentree/judge-report.mjs"
if ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t65a.log" 2>&1; then
  fail "judge-artifact (D15): the full-tree runlog-check failed a genuine scored log (B4 control) — see $work/r3-t65a.log"
  cat "$work/r3-t65a.log" >&2 || true
elif node "$work/r3-notree/gate/runlog-check.mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t65b.log" 2>&1 || ! grep -q "judge-report parser unavailable" "$work/r3-t65b.log"; then
  fail "judge-artifact (D15): a runlog-check copy WITHOUT its judge-report.mjs sibling did not fail a scored log as unverifiable (B4 fallback) — see $work/r3-t65b.log"
  cat "$work/r3-t65b.log" >&2 || true
elif node "$work/r3-brokentree/gate/runlog-check.mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t65c.log" 2>&1 || ! grep -q "judge-report parser unavailable" "$work/r3-t65c.log"; then
  fail "judge-artifact (D15): a runlog-check copy with an UNPARSEABLE judge-report.mjs sibling did not fail a scored log as unverifiable (B4 fallback) — see $work/r3-t65c.log"
  cat "$work/r3-t65c.log" >&2 || true
else
  ok "runlog-check fails closed when its judge-report parser sibling is absent or unparseable — no fallback parser (B4)"
fi
# (66) B5: the genuine round-1 line's grader field edited to
# muse-manager (the artifact still names judge-subagent). best must
# skip the line rather than print the misattributed grader, and
# runlog-check must fail the log on the grader cross-check.
r3p="$work/r3-b5"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r3-t66-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B5 setup graded record failed — case (66) will cascade; see $work/r3-t66-setup.log"
sed -i 's/"grader":"judge-subagent"/"grader":"muse-manager"/' "$r3p/design/run-log.jsonl"
node "$run_log_mjs" --project "$r3p" best >"$work/r3-t66a.log" 2>&1
if grep -q "muse-manager" "$work/r3-t66a.log" || ! grep -q "no graded rounds" "$work/r3-t66a.log"; then
  fail "judge-artifact (D15): best crowned a line whose grader field was edited away from its artifact's grader (B5) — see $work/r3-t66a.log"
  cat "$work/r3-t66a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t66b.log" 2>&1 || ! grep -q "misattributes" "$work/r3-t66b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the grader-edited log on the grader cross-check (B5) — see $work/r3-t66b.log"
  cat "$work/r3-t66b.log" >&2 || true
else
  ok "best skips a line whose grader field was edited (the artifact's grader governs) and runlog-check fails it on the grader cross-check (B5)"
fi
# (67) B6: the page edited to a new version AND the line's pageSha
# edited to the new version's hash — the artifact still binds the
# judged version. best must not crown the transferred grade, and
# runlog-check must fail the log on the pageSha cross-check.
r3p="$work/r3-b6"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r3-t67-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B6 setup graded record failed — case (67) will cascade; see $work/r3-t67-setup.log"
printf '<html><body><main id="main"><h1>Totally different page</h1></main></body></html>\n' > "$r3p/design/page.html"
touch -d '2026-11-11 12:03' "$r3p/design/page.html"
r3_v2_sha="$(sha256sum "$r3p/design/page.html" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r3_v2_sha" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['pageSha']=sys.argv[2]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r3-t67a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r3-t67a.log"; then
  fail "judge-artifact (D15): best crowned a grade whose pageSha was edited to a page version the artifact never bound (B6) — see $work/r3-t67a.log"
  cat "$work/r3-t67a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t67b.log" 2>&1 || ! grep -q "pageSha" "$work/r3-t67b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the pageSha-edited log on the pageSha cross-check (B6) — see $work/r3-t67b.log"
  cat "$work/r3-t67b.log" >&2 || true
else
  ok "best does not crown a grade transferred to an unjudged page version and runlog-check fails it on the pageSha cross-check (B6)"
fi
# (68) B7: the citation rewritten to a SYMLINK naming the genuine
# artifact (hash verifies through the link). best and runlog-check
# must AGREE: both reject — round 2's asymmetry (the checker
# refused, best crowned) is closed by the shared lstat rule.
r3p="$work/r3-b7"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r3-t68-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-3 B7 setup graded record failed — case (68) will cascade; see $work/r3-t68-setup.log"
ln -s round-1.md "$r3p/design/judge/link.md"
sed -i 's#"judgeReport":"design/judge/round-1.md"#"judgeReport":"design/judge/link.md"#' "$r3p/design/run-log.jsonl"
node "$run_log_mjs" --project "$r3p" best >"$work/r3-t68a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r3-t68a.log"; then
  fail "judge-artifact (D15): best crowned a round citing its judge artifact through a symlink (B7) — see $work/r3-t68a.log"
  cat "$work/r3-t68a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r3-t68b.log" 2>&1 || ! grep -q "is a symlink" "$work/r3-t68b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the symlink-citation log on the lstat rule (B7) — see $work/r3-t68b.log"
  cat "$work/r3-t68b.log" >&2 || true
else
  ok "best and runlog-check agree on a symlink citation: both reject it (B7)"
fi

# --- Red-team-round-4 cases (69)–(78): the shared-verifier parity
# round. Round 3 unified the read verifier inside run-log.mjs but
# left runlog-check.mjs holding private re-implementations of it;
# round 4 proved the drift (F1 the checker's parse half skipped the
# basis independence check and the body Round line agreement, F2
# juror device+inode distinctness checked by neither copy, F3 juror
# bases unchecked on read, F4 the checker verified a jury only when
# jury/juryVotes were present, F5 the line's independenceBasis /
# tokensHash transcription fields compared by nobody, F6 citation
# containment differed — project root vs design/, F7 expert
# citations opened by no read path). The fix relocated the
# verifiers into judge-report.mjs, SHARED by run-log.mjs and
# runlog-check.mjs (the copies are deleted), and added the missing
# halves to the one verifier. Each case below runs BOTH consumers
# on the same adversarial log: the checker and a run-log read path
# must agree.
r4_bad_basis="graded by the builder in the same context after building it"
# (69) F1a: the cited artifact's OWN basis confesses self-grading
# (header + body edited after a genuine record; the line's
# judgeReportSha updated to match). Record time refuses such an
# artifact; on read, the shared verifier's basis half must refuse
# it in BOTH consumers — round 3's checker parse half never applied
# the basis check and passed this log.
r3p="$work/r4-f1a"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t69-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F1a setup graded record failed — case (69) will cascade; see $work/r4-t69-setup.log"
sed -i "s/fresh context, no production history/$r4_bad_basis/g" "$r3p/design/judge/round-1.md"
r4_new_sha="$(sha256sum "$r3p/design/judge/round-1.md" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r4_new_sha" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['judgeReportSha']=sys.argv[2]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t69a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t69a.log"; then
  fail "judge-artifact (D15): best crowned a round whose judge artifact's basis confesses self-grading (F1) — see $work/r4-t69a.log"
  cat "$work/r4-t69a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t69b.log" 2>&1 || ! grep -q "independence basis" "$work/r4-t69b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the self-confessed-basis log on the basis independence check (F1) — see $work/r4-t69b.log"
  cat "$work/r4-t69b.log" >&2 || true
else
  ok "best and runlog-check both refuse a judge artifact whose basis confesses self-grading (F1)"
fi
# (70) F1b: the artifact's BODY Round line names a different grader
# than its header (header untouched; the line's judgeReportSha
# updated). The shared verifier compares the body line against the
# header; round 3's checker parse half never looked at the body.
r3p="$work/r4-f1b"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t70-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F1b setup graded record failed — case (70) will cascade; see $work/r4-t70-setup.log"
sed -i 's/^Round 1 — grader: judge-subagent /Round 1 — grader: muse-manager /' "$r3p/design/judge/round-1.md"
r4_new_sha="$(sha256sum "$r3p/design/judge/round-1.md" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r4_new_sha" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['judgeReportSha']=sys.argv[2]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t70a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t70a.log"; then
  fail "judge-artifact (D15): best crowned a round whose artifact body Round line names a different grader than its header (F1) — see $work/r4-t70a.log"
  cat "$work/r4-t70a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t70b.log" 2>&1 || ! grep -q "body Round line" "$work/r4-t70b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the body/header grader mismatch on the body Round line check (F1) — see $work/r4-t70b.log"
  cat "$work/r4-t70b.log" >&2 || true
else
  ok "best and runlog-check both refuse an artifact whose body Round line disagrees with its header (F1)"
fi
# (71) F2: juror-2 HARDLINKED to juror-1 under single-family (one
# opinion counted as two jurors; the line's votes, median and
# juryReportShas edited to match the duplicated file, so hash,
# votes, median and family checks all pass). Only the shared
# verifier's new device+inode distinctness half can refuse it.
r3p="$work/r4-f2"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
r3_prep "$r3p" 2 jury --index 1 --family famX
r3_prep "$r3p" 2 jury --index 2 --family famX
r3_prep "$r3p" 2 jury --index 3 --family famX
jr_fill_scores "$r3p/design/judge/round-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-1.md" 5 5 5 5
jr_fill_scores "$r3p/design/judge/round-2-jury-2.md" 3 3 3 3
jr_fill_scores "$r3p/design/judge/round-2-jury-3.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-2.md --gate pass $r3_legs --outcome stopped --jury 4,4,4,4 --jury-mode single-family --jury-votes "5,5,5,5;3,3,3,3;4,4,4,4" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/r4-t71-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F2 setup jury record failed — case (71) will cascade; see $work/r4-t71-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t71a.log" 2>&1
rm "$r3p/design/judge/round-2-jury-2.md"
ln "$r3p/design/judge/round-2-jury-1.md" "$r3p/design/judge/round-2-jury-2.md"
r4_s1="$(sha256sum "$r3p/design/judge/round-2-jury-1.md" | cut -d' ' -f1)"
r4_s3="$(sha256sum "$r3p/design/judge/round-2-jury-3.md" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r4_s1" "$r4_s3" <<'EOF'
import json,sys
s1,s3=sys.argv[2],sys.argv[3]
v=lambda n: {"type":n,"layout":n,"colour":n,"space":n}
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        o['juryVotes']=[v(5),v(5),v(4)]; o['jury']=v(5); o['juryReportShas']=";".join([s1,s1,s3])
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t71b.log" 2>&1
if ! grep -q "best: round 2" "$work/r4-t71a.log" || ! grep -q "no graded rounds" "$work/r4-t71b.log"; then
  fail "judge-artifact (D15): best did not crown the genuine single-family jury before the hardlink, or crowned it after juror-2 was hardlinked to juror-1 (F2) — see $work/r4-t71a.log / $work/r4-t71b.log"
  cat "$work/r4-t71a.log" "$work/r4-t71b.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t71c.log" 2>&1 || ! grep -q "same file" "$work/r4-t71c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the hardlinked-juror log on the distinctness check (F2) — see $work/r4-t71c.log"
  cat "$work/r4-t71c.log" >&2 || true
else
  ok "best and runlog-check both refuse a jury whose juror slot is a hardlink to another juror (F2 distinctness)"
fi
r3_reject "land on the hardlinked-juror log" "$work/r4-t71d.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs
# (72) F3: juror-1's basis edited to confess self-grading (its
# juryReportShas entry updated; votes and scores untouched). Record
# time independence-checks every juror's basis; the shared verifier
# now does it on read in both consumers.
r3p="$work/r4-f3"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
r3_prep "$r3p" 2 jury --index 1 --family fam1
r3_prep "$r3p" 2 jury --index 2 --family fam2
r3_prep "$r3p" 2 jury --index 3 --family fam3
jr_fill_scores "$r3p/design/judge/round-2.md" 3 3 3 3
jr_fill_scores "$r3p/design/judge/round-2-jury-1.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-3.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 3,3,3,3 --judge-report design/judge/round-2.md --gate pass $r3_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "4,4,4,4;4,4,4,4;4,4,4,4" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/r4-t72-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F3 setup jury record failed — case (72) will cascade; see $work/r4-t72-setup.log"
sed -i "s/fresh context, no production history/$r4_bad_basis/g" "$r3p/design/judge/round-2-jury-1.md"
r4_ns="$(sha256sum "$r3p/design/judge/round-2-jury-1.md" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r4_ns" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        parts=o['juryReportShas'].split(';'); parts[0]=sys.argv[2]; o['juryReportShas']=";".join(parts)
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t72a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t72a.log"; then
  fail "judge-artifact (D15): best crowned a jury round whose juror's basis confesses self-grading (F3) — see $work/r4-t72a.log"
  cat "$work/r4-t72a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t72b.log" 2>&1 || ! grep -q "independence basis" "$work/r4-t72b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the juror-basis log on the basis independence check (F3) — see $work/r4-t72b.log"
  cat "$work/r4-t72b.log" >&2 || true
else
  ok "best and runlog-check both refuse a jury whose juror's basis confesses self-grading (F3)"
fi
# (73) F4: a genuine absolute line edited to carry juryReportShas
# ONLY (jury / juryVotes stay null; the three shas are well-formed
# but invented, and no juror files exist). The ONE shared jury-line
# definition (any of jury / juryVotes / juryReportShas present and
# non-null) makes the jury half verify in every consumer — round
# 3's checker triggered jury verification on jury/juryVotes only
# and passed this line.
r3p="$work/r4-f4"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t73-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F4 setup graded record failed — case (73) will cascade; see $work/r4-t73-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys,hashlib
h=lambda s: hashlib.sha256(s.encode()).hexdigest()
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['juryReportShas']=";".join([h("a"),h("b"),h("c")])
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t73a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t73a.log"; then
  fail "judge-artifact (D15): best crowned a juryReportShas-only line whose jury does not verify (F4) — see $work/r4-t73a.log"
  cat "$work/r4-t73a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t73b.log" 2>&1 || ! grep -q "jury" "$work/r4-t73b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the juryReportShas-only line on the jury verification (F4) — see $work/r4-t73b.log"
  cat "$work/r4-t73b.log" >&2 || true
else
  ok "best and runlog-check both refuse a juryReportShas-only line (F4: one jury-line definition)"
fi
r3_reject "land on the juryReportShas-only log" "$work/r4-t73c.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
# (74) F5a: the LINE's independenceBasis edited to confess
# self-grading — the artifact is untouched and genuine, and its
# hash, scores and page binding all verify. Only the shared
# verifier's new line-vs-header transcription equality refuses it.
r3p="$work/r4-f5a"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t74-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F5a setup graded record failed — case (74) will cascade; see $work/r4-t74-setup.log"
python3 - "$r3p/design/run-log.jsonl" "$r4_bad_basis" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['independenceBasis']=sys.argv[2]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t74a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t74a.log"; then
  fail "judge-artifact (D15): best crowned a line whose independenceBasis field was edited away from its artifact's basis (F5) — see $work/r4-t74a.log"
  cat "$work/r4-t74a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t74b.log" 2>&1 || ! grep -q "independenceBasis" "$work/r4-t74b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the basis-edited line on the independenceBasis transcription check (F5) — see $work/r4-t74b.log"
  cat "$work/r4-t74b.log" >&2 || true
else
  ok "best and runlog-check both refuse a line whose independenceBasis does not transcribe its artifact (F5)"
fi
# (75) F5b: the LINE's tokensHash edited to another valid 64-hex
# value (page2's hash) — the artifact still binds the real tokens.
# Only the tokensHash transcription equality refuses it.
r3p="$work/r4-f5b"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t75-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F5b setup graded record failed — case (75) will cascade; see $work/r4-t75-setup.log"
r4_p2_sha="$(sha256sum "$r3p/design/page2.html" | cut -d' ' -f1)"
python3 - "$r3p/design/run-log.jsonl" "$r4_p2_sha" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['tokensHash']=sys.argv[2]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t75a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t75a.log"; then
  fail "judge-artifact (D15): best crowned a line whose tokensHash was edited away from its artifact's tokens binding (F5) — see $work/r4-t75a.log"
  cat "$work/r4-t75a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t75b.log" 2>&1 || ! grep -q "tokensHash" "$work/r4-t75b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the tokensHash-edited line on the tokensHash transcription check (F5) — see $work/r4-t75b.log"
  cat "$work/r4-t75b.log" >&2 || true
else
  ok "best and runlog-check both refuse a line whose tokensHash does not transcribe its artifact (F5)"
fi
# (76) F6: the citation rewritten to a copy of the artifact at the
# PROJECT ROOT (report.md — same bytes, same hash, outside
# design/). Containment is design/ in every consumer (the shared
# verifier); round 3's checker resolved against the project root
# and passed it.
r3p="$work/r4-f6"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t76-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F6 setup graded record failed — case (76) will cascade; see $work/r4-t76-setup.log"
cp "$r3p/design/judge/round-1.md" "$r3p/report.md"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['judgeReport']="report.md"
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t76a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r4-t76a.log"; then
  fail "judge-artifact (D15): best crowned a round citing its artifact at the project root, outside design/ (F6) — see $work/r4-t76a.log"
  cat "$work/r4-t76a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t76b.log" 2>&1 || ! grep -q "outside <project>/design/" "$work/r4-t76b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the root-level citation on the design/ containment check (F6) — see $work/r4-t76b.log"
  cat "$work/r4-t76b.log" >&2 || true
else
  ok "best and runlog-check both refuse a citation outside design/ (F6: containment is design/ everywhere)"
fi
# (77) F7: fabricated expert scores — an appended copy of a genuine
# line carrying expertMotion 5 / expertUx 5 whose citations name
# files that do not exist (invented shas). Before round 4 NO read
# path opened an expert citation. The checker must fail the log;
# and when the fake-expert copy is the ONLY round line, it must
# count for nothing (land refuses).
r3p="$work/r4-f7"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r4-t77-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F7 setup graded record failed — case (77) will cascade; see $work/r4-t77-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys,hashlib
fake=hashlib.sha256(b"no such expert report").hexdigest()
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
g=[o for o in lines if o.get('kind')=='round'][0]
c=dict(g); c['expertMotion']=5; c['expertMotionEvidence']="scroll reveal measured 420ms ease-out"
c['expertMotionReport']="design/judge/round-1-expert-motion.md"; c['expertMotionReportSha']=fake
c['expertUx']=5; c['expertUxEvidence']="tap targets measured 48px"
c['expertUxReport']="design/judge/round-1-expert-ux.md"; c['expertUxReportSha']=fake
c['at']="2026-11-11T12:10:00.000Z"
open(sys.argv[1],"a").write(json.dumps(c)+"\n")
EOF
if node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t77a.log" 2>&1 || ! grep -q "expert" "$work/r4-t77a.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the fabricated-expert log on the expert citation verification (F7) — see $work/r4-t77a.log"
  cat "$work/r4-t77a.log" >&2 || true
else
  ok "runlog-check fails a line carrying fabricated expert scores with nonexistent citations (F7)"
fi
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
fake=[o for o in lines if o.get('kind')=='round' and o.get('expertMotion')==5]
others=[o for o in lines if o.get('kind')!='round']
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in others+fake)+"\n")
EOF
r3_reject "land whose only round record carries fabricated expert citations" "$work/r4-t77b.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
# (78) F7 POSITIVE CONTROL: a genuine graded round carrying genuine
# expert-motion + expert-ux artifacts verifies on every read path —
# best crowns it and runlog-check passes the log.
r3p="$work/r4-f7pos"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
if ! node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind expert-motion --brief-type landing --mode full --page design/page.html >"$work/r4-prep-1-expert-motion.log" 2>&1; then
  fail "judge-artifact (D15): round-4 F7 positive expert-motion prepare failed — case (78) will cascade; see $work/r4-prep-1-expert-motion.log"
  cat "$work/r4-prep-1-expert-motion.log" >&2 || true
fi
jr_fill_expert "$r3p/design/judge/round-1-expert-motion.md" Motion motion-expert 5 "scroll reveal measured 420ms ease-out"
if ! node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind expert-ux --brief-type landing --mode full --page design/page.html >"$work/r4-prep-1-expert-ux.log" 2>&1; then
  fail "judge-artifact (D15): round-4 F7 positive expert-ux prepare failed — case (78) will cascade; see $work/r4-prep-1-expert-ux.log"
  cat "$work/r4-prep-1-expert-ux.log" >&2 || true
fi
jr_fill_expert "$r3p/design/judge/round-1-expert-ux.md" UX ux-expert 4 "tap targets measured 48px"
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs --expert-motion 5 --expert-motion-evidence "scroll reveal measured 420ms ease-out" --expert-motion-report design/judge/round-1-expert-motion.md --expert-ux 4 --expert-ux-evidence "tap targets measured 48px" --expert-ux-report design/judge/round-1-expert-ux.md >"$work/r4-t78-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-4 F7 positive graded record with experts failed — case (78) will cascade; see $work/r4-t78-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r4-t78a.log" 2>&1
if ! grep -q "best: round 1" "$work/r4-t78a.log"; then
  fail "judge-artifact (D15): best did not crown the genuine expert-carrying round (F7 positive control) — see $work/r4-t78a.log"
  cat "$work/r4-t78a.log" >&2 || true
elif ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r4-t78b.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check failed a genuine expert-carrying log (F7 positive control) — see $work/r4-t78b.log"
  cat "$work/r4-t78b.log" >&2 || true
else
  ok "best crowns and runlog-check passes a genuine expert-carrying round (F7 positive control)"
fi

# --- Red-team-round-5 cases (79)–(86): the field-coverage round.
# Round 5 found no new mechanism — every break was a FIELD of the
# stored line the shared verifier never compared: the line's gate
# (N1), its evidence (N2), the jurors' page binding (N3), its
# expert evidence (N6), and its whole pairwise transcription (N5),
# which no read path opened at all. The fixes complete the field
# coverage inside the ONE shared verifier (verifyGradedLine now
# requires gate exactly "pass" and the derived evidence, and calls
# verifyPairwiseLine; verifyJuryLine binds jurors to the round's
# page; verifyExpertCitations compares expert evidence), plus the
# line-local pairwiseReportShas shape rule in runlog-check (N5b).
# (N4 — a juror artifact naming a different grader than the line —
# was observed and is NOT a break: record time does not compare a
# juror's grader either; write/read parity already holds.)
# (79) N1: a genuine graded line flipped to gate "fail" after the
# fact (scores, citation, artifacts all genuine). The writer never
# writes scores behind a failed gate: the line must verify
# NOWHERE — checker fails it, best crowns nothing, land's
# precondition and feedback's anchor both refuse it.
r3p="$work/r5-n1"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r5-t79-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N1 setup graded record failed — case (79) will cascade; see $work/r5-t79-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['gate']='fail'
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t79a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r5-t79a.log"; then
  fail "judge-artifact (D15): best crowned a graded line flipped to gate fail (N1) — see $work/r5-t79a.log"
  cat "$work/r5-t79a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t79b.log" 2>&1 || ! grep -q 'not "pass"' "$work/r5-t79b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the gate-flipped line on the gate requirement (N1) — see $work/r5-t79b.log"
  cat "$work/r5-t79b.log" >&2 || true
else
  ok "best and runlog-check both refuse a graded line flipped to gate fail (N1: the shared shape requires gate exactly pass)"
fi
r3_reject "land whose only round record is a gate-flipped graded line" "$work/r5-t79c.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page.html >"$work/r5-prep-1-regrade.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N1 regrade prepare failed — case (79) feedback half will cascade; see $work/r5-prep-1-regrade.log"
jr_fill_scores "$r3p/design/judge/round-1-regrade.md" 5 5 5 5
r3_reject "feedback regrade anchored by a gate-flipped graded line" "$work/r5-t79d.log" "never anchors" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md
# (80) N2: a genuine graded line whose stored EVIDENCE was edited
# after the fact (artifact untouched; scores, hash, basis all
# genuine). The record's evidence is DERIVED from the artifact's
# cells — an edited evidence field is not a transcription.
r3p="$work/r5-n2"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r5-t80-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N2 setup graded record failed — case (80) will cascade; see $work/r5-t80-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['evidence']='invented evidence naming nothing at all whatsoever'
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t80a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r5-t80a.log"; then
  fail "judge-artifact (D15): best crowned a line whose stored evidence was edited away from its artifact's cells (N2) — see $work/r5-t80a.log"
  cat "$work/r5-t80a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t80b.log" 2>&1 || ! grep -q "evidence" "$work/r5-t80b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the evidence-edited line on the evidence transcription check (N2) — see $work/r5-t80b.log"
  cat "$work/r5-t80b.log" >&2 || true
else
  ok "best and runlog-check both refuse a line whose evidence does not transcribe its artifact's evidence cells (N2)"
fi
# (81) N3: a genuine jury round whose three juror slots are
# replaced by GENUINE juror artifacts of a DIFFERENT page (page2 —
# prepared and filled normally, votes/median/families unchanged,
# juryReportShas updated to the new files). Only the jurors' page
# binding can refuse it: record time binds jurors to the record's
# page, and the shared verifier now does it on read too.
r3p="$work/r5-n3"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
r3_prep "$r3p" 2 jury --index 1 --family fam1
r3_prep "$r3p" 2 jury --index 2 --family fam2
r3_prep "$r3p" 2 jury --index 3 --family fam3
jr_fill_scores "$r3p/design/judge/round-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-1.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-3.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-2.md --gate pass $r3_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "4,4,4,4;4,4,4,4;4,4,4,4" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/r5-t81-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N3 setup jury record failed — case (81) will cascade; see $work/r5-t81-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t81a.log" 2>&1
for k in 1 2 3; do
  node "$judge_report_mjs" --project "$r3p" prepare --round 2 --kind jury --index $k --family fam$k --grader judge-subagent --brief-type landing --mode full --page design/page2.html --out "design/judge/alt-jury-$k.md" >"$work/r5-prep-alt-jury-$k.log" 2>&1 \
    || fail "judge-artifact (D15): round-5 N3 page2 juror prepare $k failed — case (81) will cascade; see $work/r5-prep-alt-jury-$k.log"
  jr_fill_scores "$r3p/design/judge/alt-jury-$k.md" 4 4 4 4
  cp "$r3p/design/judge/alt-jury-$k.md" "$r3p/design/judge/round-2-jury-$k.md"
done
python3 - "$r3p/design/run-log.jsonl" "$r3p" <<'EOF'
import json,sys,hashlib,os
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        o['juryReportShas']=";".join(hashlib.sha256(open(os.path.join(sys.argv[2],"design/judge",f"round-2-jury-{k}.md"),"rb").read()).hexdigest() for k in (1,2,3))
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t81b.log" 2>&1
if ! grep -q "best: round 2" "$work/r5-t81a.log" || ! grep -q "no graded rounds" "$work/r5-t81b.log"; then
  fail "judge-artifact (D15): best did not crown the genuine jury before the juror swap, or crowned it after its jurors were replaced by another page's jurors (N3) — see $work/r5-t81a.log / $work/r5-t81b.log"
  cat "$work/r5-t81a.log" "$work/r5-t81b.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t81c.log" 2>&1 || ! grep -q "pageSha" "$work/r5-t81c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the wrong-page-juror log on the juror page binding (N3) — see $work/r5-t81c.log"
  cat "$work/r5-t81c.log" >&2 || true
else
  ok "best and runlog-check both refuse a jury whose jurors graded a different page than the round (N3)"
fi
r3_reject "land on the wrong-page-juror log" "$work/r5-t81d.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs
# (82) N6: a genuine expert-carrying round whose stored
# expertMotionEvidence was edited after the fact (the expert
# artifact untouched). Record time equality-checks the evidence
# flag against the artifact before storing it; the shared
# verifier now compares it on read too.
r3p="$work/r5-n6"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind expert-motion --brief-type landing --mode full --page design/page.html >"$work/r5-prep-1-expert-motion.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N6 expert-motion prepare failed — case (82) will cascade; see $work/r5-prep-1-expert-motion.log"
jr_fill_expert "$r3p/design/judge/round-1-expert-motion.md" Motion motion-expert 5 "scroll reveal measured 420ms ease-out"
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind expert-ux --brief-type landing --mode full --page design/page.html >"$work/r5-prep-1-expert-ux.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N6 expert-ux prepare failed — case (82) will cascade; see $work/r5-prep-1-expert-ux.log"
jr_fill_expert "$r3p/design/judge/round-1-expert-ux.md" UX ux-expert 4 "tap targets measured 48px"
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs --expert-motion 5 --expert-motion-evidence "scroll reveal measured 420ms ease-out" --expert-motion-report design/judge/round-1-expert-motion.md --expert-ux 4 --expert-ux-evidence "tap targets measured 48px" --expert-ux-report design/judge/round-1-expert-ux.md >"$work/r5-t82-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N6 setup expert record failed — case (82) will cascade; see $work/r5-t82-setup.log"
r5_n6_control=0
node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t82a.log" 2>&1 || r5_n6_control=$?
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['expertMotionEvidence']='scroll reveal measured 999ms ease-out'
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t82b.log" 2>&1
r5_n6_attack=0
node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t82c.log" 2>&1 || r5_n6_attack=$?
if [ "$r5_n6_control" -ne 0 ]; then
  fail "judge-artifact (D15): round-5 N6 control failed — runlog-check failed the genuine expert log before the evidence edit; see $work/r5-t82a.log"
  cat "$work/r5-t82a.log" >&2 || true
elif ! grep -q "no graded rounds" "$work/r5-t82b.log"; then
  fail "judge-artifact (D15): best crowned a line whose expertMotionEvidence was edited away from its expert artifact (N6) — see $work/r5-t82b.log"
  cat "$work/r5-t82b.log" >&2 || true
elif [ "$r5_n6_attack" -eq 0 ] || ! grep -q "expertMotionEvidence" "$work/r5-t82c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the expert-evidence-edited log on the expert evidence transcription check (N6) — see $work/r5-t82c.log"
  cat "$work/r5-t82c.log" >&2 || true
else
  ok "best and runlog-check both refuse a line whose expert evidence does not transcribe its expert artifact (N6)"
fi
# (83) N5 POSITIVE CONTROL: a genuine pairwise-carrying round
# (two swapped pairwise artifacts deriving keep-challenger, the
# verdict recorded from them) verifies on EVERY read path — best
# crowns it, runlog-check passes the log, land records.
r3p="$work/r5-n5"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
r3_prep "$r3p" 1 pairwise --index 1 --shots-a design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --shots-b design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png
r3_prep "$r3p" 1 pairwise --index 2 --shots-a design/screenshots-prev/1440.png,design/screenshots-prev/768.png,design/screenshots-prev/390.png --shots-b design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png
jr_fill_pairwise "$r3p/design/judge/round-1-pairwise-1.md" A
jr_fill_pairwise "$r3p/design/judge/round-1-pairwise-2.md" B
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs --pairwise keep-challenger --pairwise-agrees yes --pairwise-reports design/judge/round-1-pairwise-1.md,design/judge/round-1-pairwise-2.md >"$work/r5-t83-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N5 setup pairwise record failed — cases (83)/(84) will cascade; see $work/r5-t83-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t83a.log" 2>&1
if ! grep -q "best: round 1" "$work/r5-t83a.log"; then
  fail "judge-artifact (D15): best did not crown the genuine pairwise-carrying round (N5 positive control) — see $work/r5-t83a.log"
  cat "$work/r5-t83a.log" >&2 || true
elif ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t83b.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check failed a genuine pairwise-carrying log (N5 positive control) — see $work/r5-t83b.log"
  cat "$work/r5-t83b.log" >&2 || true
elif ! node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs >"$work/r5-t83c.log" 2>&1; then
  fail "judge-artifact (D15): land refused a genuine pairwise-carrying round (N5 positive control) — see $work/r5-t83c.log"
  cat "$work/r5-t83c.log" >&2 || true
else
  ok "a genuine pairwise-carrying round verifies on every read path — best crowns it, runlog-check passes it, land records (N5 positive control)"
fi
# (84) N5: the same round's stored pairwise VERDICT flipped to
# keep-incumbent (artifacts untouched — they derive
# keep-challenger). Before round 5 no read path re-derived the
# verdict; the line verified on its absolute citation alone.
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['pairwise']='keep-incumbent'
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t84a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r5-t84a.log"; then
  fail "judge-artifact (D15): best crowned a round whose pairwise verdict was flipped against its artifacts (N5) — see $work/r5-t84a.log"
  cat "$work/r5-t84a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t84b.log" 2>&1 || ! grep -q "derive" "$work/r5-t84b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the verdict-flipped log on the pairwise re-derivation (N5) — see $work/r5-t84b.log"
  cat "$work/r5-t84b.log" >&2 || true
else
  ok "best and runlog-check both refuse a round whose pairwise verdict does not re-derive from its artifacts (N5)"
fi
# (85) N5: FAKE pairwise fields on an otherwise genuine
# absolute-only round — invented pairwiseReports (files that do
# not exist) and well-formed invented pairwiseReportShas. The
# line must verify NOWHERE: its pairwise transcription cannot
# re-derive, so nothing trusts the line at all.
r3p="$work/r5-n5b"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r5-t85-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-5 N5-fake setup graded record failed — case (85) will cascade; see $work/r5-t85-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys,hashlib
h=lambda s: hashlib.sha256(s.encode()).hexdigest()
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        o['pairwise']='keep-challenger'; o['pairwiseAgrees']=True
        o['pairwiseReports']='design/judge/round-1-pairwise-1.md;design/judge/round-1-pairwise-2.md'
        o['pairwiseReportShas']=";".join([h("pairwise one"),h("pairwise two")])
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r5-t85a.log" 2>&1
if ! grep -q "no graded rounds" "$work/r5-t85a.log"; then
  fail "judge-artifact (D15): best crowned a round carrying fabricated pairwise fields (N5) — see $work/r5-t85a.log"
  cat "$work/r5-t85a.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r5-t85b.log" 2>&1 || ! grep -q "pairwise" "$work/r5-t85b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the fabricated-pairwise log on the pairwise verification (N5) — see $work/r5-t85b.log"
  cat "$work/r5-t85b.log" >&2 || true
else
  ok "best and runlog-check both refuse a round carrying fabricated pairwise fields (N5)"
fi
r3_reject "land whose only round record carries fabricated pairwise fields" "$work/r5-t85c.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
# (86) N5b: the line-LOCAL shape rule — checkRunLogLine WITHOUT a
# project root (a pure line-local caller) must flag a
# pairwiseReportShas that is not exactly two 64-hex values, the
# NA2 jury shape rule applied to the pairwise citation set; and
# must return no problem for the genuine pairwise line of case
# (83)'s project (read before its verdict flip — the shape the
# writer writes).
cat > "$work/r5-noroot.mjs" <<'EOF'
import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
const m = await import(pathToFileURL(process.argv[2]).href);
const lines = readFileSync(process.argv[3], 'utf8').split('\n').filter((l) => l.trim());
for (const l of lines) console.log(m.checkRunLogLine(l) ?? 'NULL');
EOF
python3 - "$work/r5-fake-shas.jsonl" <<'EOF'
import json,sys
line={"kind":"round","round":1,"grader":"judge-subagent","scores":{"type":4,"layout":4,"colour":4,"space":4},"judgeReport":"design/judge/round-1.md","judgeReportSha":"a"*64,"pairwise":"keep-challenger","pairwiseReportShas":"nothex;nothex"}
open(sys.argv[1],"w").write(json.dumps(line)+"\n")
EOF
grep '"kind": *"round"' "$work/r5-n5/design/run-log.jsonl" | head -n 1 > "$work/r5-genuine-line.jsonl" || true
if ! node "$work/r5-noroot.mjs" "$runlog_check_mjs" "$work/r5-fake-shas.jsonl" >"$work/r5-t86a.log" 2>&1 || ! grep -q "pairwiseReportShas" "$work/r5-t86a.log"; then
  fail "judge-artifact (D15): line-local checkRunLogLine did not flag a malformed pairwiseReportShas (N5b) — see $work/r5-t86a.log"
  cat "$work/r5-t86a.log" >&2 || true
elif ! node "$work/r5-noroot.mjs" "$runlog_check_mjs" "$work/r5-genuine-line.jsonl" >"$work/r5-t86b.log" 2>&1 || ! grep -q "^NULL$" "$work/r5-t86b.log"; then
  fail "judge-artifact (D15): line-local checkRunLogLine flagged the genuine pairwise line's shape (N5b control) — see $work/r5-t86b.log"
  cat "$work/r5-t86b.log" >&2 || true
else
  ok "line-local checkRunLogLine flags a malformed pairwiseReportShas and passes a genuine pairwise line's shape (N5b)"
fi

# --- Red-team-round-6 cases (87)–(92): the crosscheck channel (X1)
# and the last unbound fields (X2–X5). Round 6 found the crosscheck
# channel verified by NOBODY on read: land trusted the latest stored
# verdict, prepare derived its cross-check bit from it, and
# runlog-check never looked at crosscheck lines — one hand-appended
# "clear" line over a genuine blocked verdict overrode the block in
# all three consumers. The fix is one shared verifyCrosscheckLine
# (verdict re-derived from the line's own counts, checker allowlist,
# independence basis, cited report on disk) called by all three,
# plus the graded line's own gate legs verified on read (X2), the
# juror/expert tokens binding (X3/X4), and the not-regraded
# transcription (X5) inside the shared verifier.
# (87) X1: a genuine graded round + genuine clear cross-check land
# and prepare cleanly (setup controls); a genuine BLOCKED
# cross-check then refuses land (latest-wins); a hand-appended
# self-contradictory "clear" line (verdict clear over severe 3,
# checker not on the allowlist) over it must refuse land AND
# prepare AND fail runlog-check — with no fallback to the earlier
# genuine lines.
r3p="$work/r6-x1"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r6-t87-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X1 setup graded record failed — case (87) will cascade; see $work/r6-t87-setup.log"
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs >"$work/r6-t87-pos-land.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X1 POSITIVE control failed — land behind a genuine clear cross-check + genuine graded record was refused; see $work/r6-t87-pos-land.log"
node "$judge_report_mjs" --project "$r3p" prepare --round 2 --kind absolute --grader judge-subagent --brief-type landing --mode full --page design/page.html >"$work/r6-t87-pos-prep.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X1 POSITIVE control failed — prepare behind a genuine clear cross-check was refused; see $work/r6-t87-pos-prep.log"
node "$run_log_mjs" --project "$r3p" crosscheck --slice r3 --round 1 --severe 1 --warning 0 --report design/crosscheck/round-1.md --checker security-expert --basis "$jr_basis" >"$work/r6-t87-blocked.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X1 setup blocked cross-check record failed — case (87) will cascade; see $work/r6-t87-blocked.log"
r3_reject "land behind a genuine BLOCKED cross-check (latest-wins control)" "$work/r6-t87a.log" "is BLOCKED" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
for rnd in (1,2):
    fake={"kind":"crosscheck","slice":"r3","round":rnd,"severe":3,"warning":2,"waived":0,"verdict":"clear","report":"design/crosscheck/round-1.md","checker":"other-model","independenceBasis":"fresh context, no production history","notes":None,"at":"2026-11-11T12:08:00.000Z"}
    open(sys.argv[1],"a").write(json.dumps(fake)+"\n")
EOF
r3_reject "land behind an appended self-contradictory clear cross-check line" "$work/r6-t87b.log" "does not verify" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
if node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t87c.log" 2>&1 || ! grep -q "contradicts its own counts" "$work/r6-t87c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the log carrying a self-contradictory crosscheck line on the verdict re-derivation (X1) — see $work/r6-t87c.log"
  cat "$work/r6-t87c.log" >&2 || true
elif node "$judge_report_mjs" --project "$r3p" prepare --round 2 --kind absolute --grader judge-subagent --brief-type landing --mode full --page design/page.html >"$work/r6-t87d.log" 2>&1 || ! grep -q "does not verify" "$work/r6-t87d.log"; then
  fail "judge-artifact (D15): prepare derived its cross-check bit from an appended self-contradictory clear line instead of refusing (X1) — see $work/r6-t87d.log"
  cat "$work/r6-t87d.log" >&2 || true
else
  ok "runlog-check and prepare both refuse an appended self-contradictory clear cross-check line (X1: the verdict re-derives from the counts in every consumer)"
fi
# (88) X1, consistent-counts variant: the appended clear line's
# counts DO derive clear and its checker/basis are genuine — only
# its cited report does not exist. Record time never writes a
# verdict behind a missing report, so all three consumers refuse.
r3p="$work/r6-x1b"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r6-t88-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X1-variant setup graded record failed — case (88) will cascade; see $work/r6-t88-setup.log"
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
for rnd in (1,2):
    fake={"kind":"crosscheck","slice":"r3","round":rnd,"severe":0,"warning":0,"waived":0,"verdict":"clear","report":"design/crosscheck/round-99.md","checker":"security-expert","independenceBasis":"fresh context, no production history","notes":None,"at":"2026-11-11T12:09:00.000Z"}
    open(sys.argv[1],"a").write(json.dumps(fake)+"\n")
EOF
r3_reject "land behind an appended clear cross-check line whose report does not exist" "$work/r6-t88a.log" "does not verify" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
if node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t88b.log" 2>&1 || ! grep -q "does not exist" "$work/r6-t88b.log"; then
  fail "judge-artifact (D15): runlog-check did not fail a crosscheck line whose cited report does not exist (X1 variant) — see $work/r6-t88b.log"
  cat "$work/r6-t88b.log" >&2 || true
elif node "$judge_report_mjs" --project "$r3p" prepare --round 2 --kind absolute --grader judge-subagent --brief-type landing --mode full --page design/page.html >"$work/r6-t88c.log" 2>&1 || ! grep -q "does not exist" "$work/r6-t88c.log"; then
  fail "judge-artifact (D15): prepare derived its cross-check bit from a clear line whose report does not exist (X1 variant) — see $work/r6-t88c.log"
  cat "$work/r6-t88c.log" >&2 || true
else
  ok "runlog-check and prepare both refuse a consistent-counts clear cross-check line whose report does not exist (X1 variant)"
fi
# (89) X2, as re-scoped by round 8 (C4 — the epoch rule) and by
# the LIVE PROOF ROUND 2 adjudication (the leg-currency
# deadlock): a genuine graded line whose stored gateLeg1Sha /
# gateLeg2Sha were edited to garbage after the fact (legs,
# citation and scores all genuine). Round 6 held EVERY read
# consumer to leg currency, so `best` refused the line; round 8
# split the consumers — leg currency bound the live epoch, and
# this log's round line being the LATEST round line, runlog-check
# still flagged it. THE CHECKER SUB-ASSERTION IS NOW SUPERSEDED:
# gate.sh §1.1 folds runlog-check's output into leg 1's verdict,
# so any currency check left in the checker fires inside the gate
# run that must supersede the still-latest line and deadlocks
# the loop (no later round can ever record — proven live on the
# Brief 1 proof project). Leg currency is a property of LIVE
# OPERATIONS only: runlog-check now holds NO stored line to
# currency (shape + artifact binding only), so it PASSES this
# edited line; land (a live operation) still refuses it below,
# and `best` crowns the round through its judge artifact alone:
# the grade is verified history, and the edited leg shas are a
# defect the live operations catch, not a defect of the grade.
# (The pre-round-8 best expectation was superseded at round 8;
# the round-8 checker expectation is superseded here — see the
# D15 live-proof-round-2 addendum.)
r3p="$work/r6-x2"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r6-t89-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X2 setup graded record failed — case (89) will cascade; see $work/r6-t89-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t89a.log" 2>&1
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        o['gateLeg1Sha']='f'*64; o['gateLeg2Sha']='f'*64
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t89b.log" 2>&1
if ! grep -q "best: round 1" "$work/r6-t89a.log" || ! grep -q "best: round 1" "$work/r6-t89b.log"; then
  fail "judge-artifact (D15): best did not crown the genuine graded round before the leg-sha edit, or stopped crowning it after (round-8 epoch rule: best verifies the grade through its judge artifact, not leg currency) — see $work/r6-t89a.log / $work/r6-t89b.log"
  cat "$work/r6-t89a.log" "$work/r6-t89b.log" >&2 || true
elif ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t89c.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check still fails the leg-sha-edited graded line — the checker's leg-currency tripwire was superseded by the LIVE PROOF ROUND 2 deadlock adjudication (currency binds live operations only; land below still refuses this line) — see $work/r6-t89c.log"
  cat "$work/r6-t89c.log" >&2 || true
else
  ok "runlog-check passes a graded line whose stored gate-leg shas were edited (X2 — checker leg currency superseded by the live-proof-round-2 deadlock adjudication) while best crowns the same round through its judge artifact and land still refuses it (live-operation currency)"
fi
r3_reject "land whose only round record has edited gate-leg shas" "$work/r6-t89d.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs
# (90) X3: a genuine jury round whose three juror slots are replaced
# by GENUINE juror artifacts prepared against a DIFFERENT tokens.css
# (votes/median/shas re-cited consistently at 5,5,5,5). Record time
# binds jurors to the record's tokensHash; the shared verifier now
# compares the juror headers' tokens-sha256 on read too.
r3p="$work/r6-x3"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
r3_prep "$r3p" 2 jury --index 1 --family fam1
r3_prep "$r3p" 2 jury --index 2 --family fam2
r3_prep "$r3p" 2 jury --index 3 --family fam3
jr_fill_scores "$r3p/design/judge/round-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-1.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-2.md" 4 4 4 4
jr_fill_scores "$r3p/design/judge/round-2-jury-3.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-2.md --gate pass $r3_legs --outcome stopped --jury 4,4,4,4 --jury-mode disjoint-3 --jury-votes "4,4,4,4;4,4,4,4;4,4,4,4" --judge-reports design/judge/round-2-jury-1.md,design/judge/round-2-jury-2.md,design/judge/round-2-jury-3.md >"$work/r6-t90-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X3 setup jury record failed — case (90) will cascade; see $work/r6-t90-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t90a.log" 2>&1
cp -r "$r3p" "$work/r6-x3v2"
printf ':root { --bg: #000000; --ink: #ffffff; --space: 99px; }\nbody { background: var(--bg); color: var(--ink); }\n' > "$work/r6-x3v2/design/tokens.css"
touch -d '2026-11-11 12:00' "$work/r6-x3v2/design/tokens.css"
for k in 1 2 3; do
  node "$judge_report_mjs" --project "$work/r6-x3v2" prepare --round 2 --kind jury --index $k --family fam$k --grader judge-subagent --brief-type landing --mode full --page design/page.html --out "design/judge/alt-jury-$k.md" >"$work/r6-prep-alt-jury-$k.log" 2>&1 \
    || fail "judge-artifact (D15): round-6 X3 tokens-v2 juror prepare $k failed — case (90) will cascade; see $work/r6-prep-alt-jury-$k.log"
  jr_fill_scores "$work/r6-x3v2/design/judge/alt-jury-$k.md" 5 5 5 5
  cp "$work/r6-x3v2/design/judge/alt-jury-$k.md" "$r3p/design/judge/round-2-jury-$k.md"
done
python3 - "$r3p/design/run-log.jsonl" "$r3p" <<'EOF'
import json,sys,hashlib,os
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round':
        o['juryReportShas']=";".join(hashlib.sha256(open(os.path.join(sys.argv[2],"design/judge",f"round-2-jury-{k}.md"),"rb").read()).hexdigest() for k in (1,2,3))
        o['jury']={"type":5,"layout":5,"colour":5,"space":5}
        o['juryVotes']=[{"type":5,"layout":5,"colour":5,"space":5}]*3
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t90b.log" 2>&1
if ! grep -q "best: round 2" "$work/r6-t90a.log" || ! grep -q "no graded rounds" "$work/r6-t90b.log"; then
  fail "judge-artifact (D15): best did not crown the genuine jury, or crowned it after its jurors were replaced by another tokens version's jurors (X3) — see $work/r6-t90a.log / $work/r6-t90b.log"
  cat "$work/r6-t90a.log" "$work/r6-t90b.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t90c.log" 2>&1 || ! grep -q "tokens-sha256" "$work/r6-t90c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the wrong-tokens-juror log on the juror tokens binding (X3) — see $work/r6-t90c.log"
  cat "$work/r6-t90c.log" >&2 || true
else
  ok "best and runlog-check both refuse a jury whose jurors graded a different tokens version than the round (X3)"
fi
r3_reject "land on the wrong-tokens-juror log" "$work/r6-t90d.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs
# (91) X4: a genuine expert-carrying round whose expert-motion
# artifact is replaced by a GENUINE expert artifact prepared
# against a different tokens.css (score 4 -> 5, sha re-cited).
# Record time validates expert artifacts with no tokens
# expectation, so the read-side tokens binding is the only check
# that can refuse it — and genuine same-build expert artifacts
# carry the build's tokens hash, so genuine lines still verify.
r3p="$work/r6-x4"; r3_mkproj "$r3p"
r3_prep "$r3p" 2 absolute
jr_fill_scores "$r3p/design/judge/round-2.md" 4 4 4 4
node "$judge_report_mjs" --project "$r3p" prepare --round 2 --kind expert-motion --brief-type landing --mode full --page design/page.html >"$work/r6-prep-2-expert-motion.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X4 expert-motion prepare failed — case (91) will cascade; see $work/r6-prep-2-expert-motion.log"
jr_fill_expert "$r3p/design/judge/round-2-expert-motion.md" Motion motion-expert 4 "hero reveal travels 24px in 220ms"
node "$run_log_mjs" --project "$r3p" record --round 2 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-2.md --gate pass $r3_legs --expert-motion 4 --expert-motion-evidence "hero reveal travels 24px in 220ms" --expert-motion-report design/judge/round-2-expert-motion.md >"$work/r6-t91-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X4 setup expert record failed — case (91) will cascade; see $work/r6-t91-setup.log"
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs >"$work/r6-t91-pos.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X4 POSITIVE control failed — land on the genuine expert-carrying round was refused; see $work/r6-t91-pos.log"
cp -r "$r3p" "$work/r6-x4v2"
printf ':root { --bg: #000000; --ink: #ffffff; --space: 99px; }\nbody { background: var(--bg); color: var(--ink); }\n' > "$work/r6-x4v2/design/tokens.css"
touch -d '2026-11-11 12:00' "$work/r6-x4v2/design/tokens.css"
node "$judge_report_mjs" --project "$work/r6-x4v2" prepare --round 2 --kind expert-motion --brief-type landing --mode full --page design/page.html --out design/judge/alt-expert-motion.md >"$work/r6-prep-alt-expert.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X4 tokens-v2 expert prepare failed — case (91) will cascade; see $work/r6-prep-alt-expert.log"
jr_fill_expert "$work/r6-x4v2/design/judge/alt-expert-motion.md" Motion motion-expert 5 "hero reveal travels 24px in 220ms"
cp "$work/r6-x4v2/design/judge/alt-expert-motion.md" "$r3p/design/judge/round-2-expert-motion.md"
python3 - "$r3p/design/run-log.jsonl" "$r3p" <<'EOF'
import json,sys,hashlib,os
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
sha=hashlib.sha256(open(os.path.join(sys.argv[2],"design/judge/round-2-expert-motion.md"),"rb").read()).hexdigest()
for o in lines:
    if o.get('kind')=='round':
        o['expertMotion']=5; o['expertMotionReportSha']=sha
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
if node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t91a.log" 2>&1 || ! grep -q "tokens-sha256" "$work/r6-t91a.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the wrong-tokens-expert log on the expert tokens binding (X4) — see $work/r6-t91a.log"
  cat "$work/r6-t91a.log" >&2 || true
else
  ok "runlog-check refuses an expert artifact that binds a different tokens version than the round (X4)"
fi
r3_reject "land on the wrong-tokens-expert log" "$work/r6-t91b.log" "has no round record" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs
# (92) X5: a genuine cheap record made with --not-regraded
# "#hero,#footer" whose LINE notRegraded is edited to [] after the
# fact (artifact untouched). Record validates the header's
# not-regraded set against the record's set for either kind; the
# shared verifier now compares the stored field on read.
r3p="$work/r6-x5"; r3_mkproj "$r3p"
node "$judge_report_mjs" --project "$r3p" prepare --round 3 --kind cheap --grader judge-subagent --brief-type landing --mode cheap --page design/page.html --shots design/screenshots/1440.png,design/screenshots/768.png,design/screenshots/390.png --not-regraded "#hero,#footer" >"$work/r6-prep-3-cheap.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X5 cheap prepare failed — case (92) will cascade; see $work/r6-prep-3-cheap.log"
jr_fill_scores "$r3p/design/judge/round-3-cheap.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 3 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-3-cheap.md --gate pass $r3_legs --not-regraded "#hero,#footer" >"$work/r6-t92-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-6 X5 setup cheap record failed — case (92) will cascade; see $work/r6-t92-setup.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t92a.log" 2>&1
python3 - "$r3p/design/run-log.jsonl" <<'EOF'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for o in lines:
    if o.get('kind')=='round': o['notRegraded']=[]
open(sys.argv[1],"w").write("\n".join(json.dumps(o) for o in lines)+"\n")
EOF
node "$run_log_mjs" --project "$r3p" best >"$work/r6-t92b.log" 2>&1
if ! grep -q "best: round 3" "$work/r6-t92a.log" || ! grep -q "no graded rounds" "$work/r6-t92b.log"; then
  fail "judge-artifact (D15): best did not crown the genuine cheap round, or crowned it after its notRegraded was edited to [] (X5) — see $work/r6-t92a.log / $work/r6-t92b.log"
  cat "$work/r6-t92a.log" "$work/r6-t92b.log" >&2 || true
elif node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r6-t92c.log" 2>&1 || ! grep -q "not-regraded" "$work/r6-t92c.log"; then
  fail "judge-artifact (D15): runlog-check did not fail the notRegraded-edited line on the not-regraded transcription check (X5) — see $work/r6-t92c.log"
  cat "$work/r6-t92c.log" >&2 || true
else
  ok "best and runlog-check both refuse a cheap line whose notRegraded does not transcribe its artifact's not-regraded set (X5)"
fi

# --- Round 7 (F1/F2/A7): taste-lock lines, land lines and the
# crosscheck selection-key types verify on read. Before round 7 no
# read path verified a taste-lock line (the brief adopted the
# highest-version stored line verbatim; the lock command's version
# check counted every stored line) and no consumer verified a
# stored land line (show printed it as fact; the checker never
# looked at one); a crosscheck line with a string-typed round also
# passed the checker while no consumer's strict === selection
# would ever act on it. Fixture: a genuine project — lock v1,
# clear crosscheck, graded round 1, genuine land — built once per
# case so the appends never interact.
r7_mkproj() {
  local p="$1"
  mkdir -p "$p/design/screenshots" "$p/design/judge"
  cp "$work/tokens.css" "$p/design/tokens.css"
  printf '<!doctype html><html><head><title>R7</title></head><body><main id="main"><h1>Verify fixture</h1></main></body></html>\n' > "$p/design/page.html"
  printf 'PNGDATA' > "$p/design/screenshots/round-1-1440.png"
  printf 'GATE RESULT: PASS\n' > "$p/design/gate-leg1.log"
  printf '===== gate verdict: GREEN =====\n' > "$p/design/gate-leg2.log"
  printf '# Cross-check report (verify fixture)\n\nIndependent check: 0 severe, 0 warning.\n' > "$p/design/cc.md"
  # Same fixed-time discipline as the fixtures above: tokens/page at
  # 12:00, gate legs at 12:01, and jr_fill_scores touches the judge
  # artifact to 12:05 — every freshness chain (legs >= page, artifact
  # >= tokens) holds by construction.
  touch -d '2026-11-11 12:00' "$p/design/tokens.css" "$p/design/page.html"
  touch -d '2026-11-11 12:01' "$p/design/gate-leg1.log" "$p/design/gate-leg2.log"
  node "$run_log_mjs" --project "$p" lock --tokens design/tokens.css --refs "Ref A (verify.test)" --purpose "verify purpose" --approved-by human >/dev/null 2>&1 || return 1
  node "$run_log_mjs" --project "$p" crosscheck --slice r7 --round 1 --severe 0 --warning 0 --report design/cc.md --checker crosscheck-subagent --basis "separate agent instance, no production history" >/dev/null 2>&1 || return 1
  node "$judge_report_mjs" --project "$p" prepare --round 1 --kind absolute --grader muse-manager --brief-type landing --mode full --page design/page.html --shots design/screenshots/round-1-1440.png --locked-refs "Ref A (verify.test)" >/dev/null 2>&1 || return 1
  jr_fill_scores "$p/design/judge/round-1.md" 4 4 4 4
  node "$run_log_mjs" --project "$p" record --round 1 --grader muse-manager --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html --gate-findings "no findings" >/dev/null 2>&1 || return 1
  node "$run_log_mjs" --project "$p" land --slice r7 --round 1 --gate pass --gate-leg1 design/gate-leg1.log --gate-leg2 design/gate-leg2.log --page design/page.html >/dev/null 2>&1 || return 1
}
r7_tokhash() { sha256sum "$1" | cut -d' ' -f1; }

# (93) Genuine positives: the brief builds on the genuine lock and
# shows it; a genuine v2 lock records; a duplicate genuine version
# is still refused; the checker exits 0 on the whole genuine log
# (genuine land line included — the F2 positive).
r7p="$work/r7-genuine"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 genuine fixture failed to build — case (93) cannot run; see the r7 setup commands"
else
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t93.log" 2>&1
  if ! grep -q "Lock version: 1" "$work/r7-t93.log"; then
    fail "judge-artifact (D15): the brief did not build on the genuine lock v1 (F1 positive) — see $work/r7-t93.log"
    cat "$work/r7-t93.log" >&2 || true
  elif ! node "$run_log_mjs" --project "$r7p" lock --version 2 --tokens design/tokens.css --refs "Ref A (verify.test)" --approved-by human >"$work/r7-t93b.log" 2>&1; then
    fail "judge-artifact (D15): a genuine lock --version 2 was refused (F1 positive) — see $work/r7-t93b.log"
    cat "$work/r7-t93b.log" >&2 || true
  elif node "$run_log_mjs" --project "$r7p" lock --version 2 --tokens design/tokens.css --refs "Ref A (verify.test)" --approved-by human >"$work/r7-t93c.log" 2>&1; then
    fail "judge-artifact (D15): a duplicate genuine lock --version 2 was RECORDED — a verifying line still occupies its version (F1) — see $work/r7-t93c.log"
    cat "$work/r7-t93c.log" >&2 || true
  elif ! node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t93d.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check failed the genuine log (genuine locks + genuine land) (F1/F2 positives) — see $work/r7-t93d.log"
    cat "$work/r7-t93d.log" >&2 || true
  else
    ok "genuine lock verifies end to end: brief shows v1, v2 records, a duplicate genuine version is refused, and runlog-check passes the genuine log incl. its land line (F1/F2)"
  fi
fi

# (94) F1, wrong hash: a hand-appended v99 lock line whose
# tokensHash is not the tokens file's hash — the brief refuses it
# (verification notice, v99 never presented as the lock of record)
# and the checker flags the log.
r7p="$work/r7-wronghash"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (94) cannot run"
else
  printf '{"kind":"taste-lock","lockVersion":99,"tokens":"design/tokens.css","tokensHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","references":["Fake Ref (evil.test)"],"purpose":"attacker purpose","approvedBy":"attacker","at":"2026-11-12T00:00:00.000Z"}\n' >> "$r7p/design/run-log.jsonl"
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t94.log" 2>&1
  if ! grep -q "could not be verified" "$work/r7-t94.log" || grep -q "Lock version: 99" "$work/r7-t94.log"; then
    fail "judge-artifact (D15): the brief adopted or silently buried a v99 lock line whose tokensHash is wrong (F1) — see $work/r7-t94.log"
    cat "$work/r7-t94.log" >&2 || true
  elif node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t94b.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check passed a log whose latest lock line carries a wrong tokensHash (F1) — see $work/r7-t94b.log"
    cat "$work/r7-t94b.log" >&2 || true
  else
    ok "a lock line whose tokensHash is not its tokens file's hash is refused by the brief with a verification notice and flagged by runlog-check (F1)"
  fi
fi

# (95) F1, missing file: the appended v99 line names a tokens file
# that does not exist — the brief refuses it, and the line does
# NOT occupy version 99 (a genuine lock --version 99 records).
r7p="$work/r7-missing"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (95) cannot run"
else
  printf '{"kind":"taste-lock","lockVersion":99,"tokens":"design/missing.css","tokensHash":"%s","references":["Fake Ref (evil.test)"],"purpose":"attacker purpose","approvedBy":"attacker","at":"2026-11-12T00:00:00.000Z"}\n' "$(r7_tokhash "$r7p/design/tokens.css")" >> "$r7p/design/run-log.jsonl"
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t95.log" 2>&1
  if ! grep -q "could not be verified" "$work/r7-t95.log"; then
    fail "judge-artifact (D15): the brief did not refuse a lock line naming a missing tokens file (F1) — see $work/r7-t95.log"
    cat "$work/r7-t95.log" >&2 || true
  elif ! node "$run_log_mjs" --project "$r7p" lock --version 99 --tokens design/tokens.css --refs "Ref B (verify.test)" --approved-by human >"$work/r7-t95b.log" 2>&1; then
    fail "judge-artifact (D15): the unverifiable v99 line still OCCUPIED version 99 against a genuine lock (F1) — see $work/r7-t95b.log"
    cat "$work/r7-t95b.log" >&2 || true
  else
    ok "a lock line naming a missing tokens file is refused by the brief and does not occupy its version against a genuine lock (F1)"
  fi
fi

# (96) F1, escaping path: the appended v99 line names a tokens
# path outside design/ — the brief refuses it and the checker
# flags the log.
r7p="$work/r7-escape"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (96) cannot run"
else
  printf '{"kind":"taste-lock","lockVersion":99,"tokens":"../outside.css","tokensHash":"%s","references":["Fake Ref (evil.test)"],"purpose":"attacker purpose","approvedBy":"attacker","at":"2026-11-12T00:00:00.000Z"}\n' "$(r7_tokhash "$r7p/design/tokens.css")" >> "$r7p/design/run-log.jsonl"
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t96.log" 2>&1
  if ! grep -q "could not be verified" "$work/r7-t96.log"; then
    fail "judge-artifact (D15): the brief did not refuse a lock line whose tokens path escapes design/ (F1) — see $work/r7-t96.log"
    cat "$work/r7-t96.log" >&2 || true
  elif node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t96b.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check passed a log whose latest lock line's tokens path escapes design/ (F1) — see $work/r7-t96b.log"
    cat "$work/r7-t96b.log" >&2 || true
  else
    ok "a lock line whose tokens path escapes design/ is refused by the brief and flagged by runlog-check (F1)"
  fi
fi

# (97) F1, bad version shape: the appended line's lockVersion is
# the STRING "99" — outside the writer's shape; the brief refuses
# it and the checker flags the log.
r7p="$work/r7-badversion"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (97) cannot run"
else
  printf '{"kind":"taste-lock","lockVersion":"99","tokens":"design/tokens.css","tokensHash":"%s","references":["Fake Ref (evil.test)"],"purpose":"attacker purpose","approvedBy":"attacker","at":"2026-11-12T00:00:00.000Z"}\n' "$(r7_tokhash "$r7p/design/tokens.css")" >> "$r7p/design/run-log.jsonl"
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t97.log" 2>&1
  if ! grep -q "could not be verified" "$work/r7-t97.log"; then
    fail "judge-artifact (D15): the brief did not refuse a lock line with a string-typed lockVersion (F1) — see $work/r7-t97.log"
    cat "$work/r7-t97.log" >&2 || true
  elif node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t97b.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check passed a log whose latest lock line has a string-typed lockVersion (F1) — see $work/r7-t97b.log"
    cat "$work/r7-t97b.log" >&2 || true
  else
    ok "a lock line with a string-typed lockVersion is refused by the brief and flagged by runlog-check (F1)"
  fi
fi

# (98) F1, stale lock: the tokens file is edited AFTER the genuine
# lock — the lock no longer matches its file. The brief refuses
# with the stale reason named, the checker flags the latest lock,
# version 1 does NOT stay occupied (the re-lock that supersedes
# the stale line records), and after the re-lock both the brief
# and the checker are green again (the older stale line is
# history, not held to currency).
r7p="$work/r7-stale"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (98) cannot run"
else
  printf '\n/* edited after the lock */\n' >> "$r7p/design/tokens.css"
  node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t98.log" 2>&1
  if ! grep -q "stale" "$work/r7-t98.log"; then
    fail "judge-artifact (D15): the brief did not refuse the stale lock (tokens edited after locking) with the stale reason (F1) — see $work/r7-t98.log"
    cat "$work/r7-t98.log" >&2 || true
  elif node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t98b.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check passed a log whose latest lock is stale (F1) — see $work/r7-t98b.log"
    cat "$work/r7-t98b.log" >&2 || true
  elif ! node "$run_log_mjs" --project "$r7p" lock --version 1 --tokens design/tokens.css --refs "Ref A (verify.test)" --approved-by human >"$work/r7-t98c.log" 2>&1; then
    fail "judge-artifact (D15): the stale line still OCCUPIED version 1 against the re-lock that supersedes it (F1) — see $work/r7-t98c.log"
    cat "$work/r7-t98c.log" >&2 || true
  elif ! node "$run_log_mjs" --project "$r7p" brief --round 2 >"$work/r7-t98d.log" 2>&1 || ! node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t98e.log" 2>&1; then
    fail "judge-artifact (D15): after the re-lock the brief or runlog-check is not green again — the older stale line must be history, not a standing violation (F1) — see $work/r7-t98d.log / $work/r7-t98e.log"
    cat "$work/r7-t98d.log" "$work/r7-t98e.log" >&2 || true
  else
    ok "a stale lock (tokens edited after locking) is refused by the brief as stale, flagged by runlog-check, does not block its own version's re-lock, and is history once superseded (F1)"
  fi
fi

# (99) F2: a hand-appended land line with invented gate legs and
# an invented cross-check report is flagged by runlog-check (the
# same log's genuine land line passed in case (93)).
r7p="$work/r7-fakeland"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (99) cannot run"
else
  printf '{"kind":"land","slice":"ghost","round":7,"gate":"pass","gateLeg1":"design/nope1.log","gateLeg2":"design/nope2.log","gateLeg1Sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","gateLeg2Sha":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","page":"design/page.html","crosscheckReport":"design/nope.md","notes":null,"at":"2026-11-12T00:00:00.000Z"}\n' >> "$r7p/design/run-log.jsonl"
  if node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t99.log" 2>&1 || ! grep -q "land line does not verify" "$work/r7-t99.log"; then
    fail "judge-artifact (D15): runlog-check did not flag the hand-appended land line with invented legs/report (F2) — see $work/r7-t99.log"
    cat "$work/r7-t99.log" >&2 || true
  else
    ok "runlog-check flags a hand-appended land line whose cited legs and cross-check report do not exist (F2)"
  fi
fi

# (100) A7: a hand-appended crosscheck line identical to a genuine
# one except its round is the STRING "1" — the checker flags it
# (consumers select with strict === and would never act on it, so
# it must not stand as a clean verdict either).
r7p="$work/r7-a7"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (100) cannot run"
else
  printf '{"kind":"crosscheck","slice":"r7","round":"1","severe":0,"warning":0,"waived":0,"verdict":"clear","report":"design/cc.md","checker":"crosscheck-subagent","independenceBasis":"separate agent instance, no production history","at":"2026-11-12T00:00:00.000Z"}\n' >> "$r7p/design/run-log.jsonl"
  if node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t100.log" 2>&1 || ! grep -q "not a positive integer or null" "$work/r7-t100.log"; then
    fail "judge-artifact (D15): runlog-check did not flag the crosscheck line with a string-typed round (A7) — see $work/r7-t100.log"
    cat "$work/r7-t100.log" >&2 || true
  else
    ok "runlog-check flags a crosscheck line whose round is string-typed — the writer's selection keys carry the writer's types (A7)"
  fi
fi

# (101) F2, purpose-fail: a genuine replan line passes the checker
# (its fields are the human's own prose — shape only), and an
# appended purpose-fail line outside the writer's shape (an
# action run-log.mjs never records) is flagged.
r7p="$work/r7-purposefail"
if ! r7_mkproj "$r7p"; then
  fail "judge-artifact (D15): round-7 fixture failed to build — case (101) cannot run"
else
  node "$run_log_mjs" --project "$r7p" replan --action re-pick --purpose "revised verify purpose" >"$work/r7-t101-setup.log" 2>&1 \
    || fail "judge-artifact (D15): round-7 replan setup failed — case (101) will cascade; see $work/r7-t101-setup.log"
  if ! node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t101.log" 2>&1; then
    fail "judge-artifact (D15): runlog-check failed a log carrying a GENUINE purpose-fail line (F2) — see $work/r7-t101.log"
    cat "$work/r7-t101.log" >&2 || true
  else
    printf '{"kind":"purpose-fail","action":"delete-everything","purpose":"attacker prose","round":null,"notes":null,"at":"2026-11-12T00:00:00.000Z"}\n' >> "$r7p/design/run-log.jsonl"
    if node "$runlog_check_mjs" "$r7p/design/run-log.jsonl" >"$work/r7-t101b.log" 2>&1; then
      fail "judge-artifact (D15): runlog-check passed a purpose-fail line with an action run-log.mjs never records (F2) — see $work/r7-t101b.log"
      cat "$work/r7-t101b.log" >&2 || true
    else
      ok "a genuine purpose-fail line passes runlog-check (shape only — human prose) and an off-shape one is flagged (F2)"
    fi
  fi
fi

# --- Red-team-round-8 case (102)–(103): leg rotation and the epoch
# rule (C4). The two canonical leg files are overwritten by every
# gate run, so a genuine round 2 rotates round 1's gate evidence
# away. Round 6 held every read consumer to leg currency and the
# genuine two-round log failed its own checker while `best` forgot
# round 1 — a fail-CLOSED false positive. Round 8's epoch rule:
# currency binds the live epoch only (the latest round line, the
# latest land line, feedback's anchor, land's precondition); a
# historical grade verifies through its judge artifact alone.
# (102) The genuine two-round flow: round 1 graded + land; the
# round-2 gate run overwrites both canonical legs; round 2 records
# no-grade and lands. The fully genuine log must pass runlog-check
# (round 1 is neither the latest round line nor the latest land
# line, so neither is held to leg currency) and `best` must still
# crown round 1.
r3p="$work/r8-c4"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r8-t102-setup.log" 2>&1 \
  || fail "judge-artifact (D15): round-8 C4 setup graded record failed — case (102) will cascade; see $work/r8-t102-setup.log"
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs >"$work/r8-t102-land1.log" 2>&1 \
  || fail "judge-artifact (D15): round-8 C4 setup land round 1 failed — case (102) will cascade; see $work/r8-t102-land1.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r8-t102-best1.log" 2>&1
if ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r8-t102-check1.log" 2>&1 || ! grep -q "best: round 1" "$work/r8-t102-best1.log"; then
  fail "judge-artifact (D15): round-8 C4 CONTROL failed — the genuine one-round landed log did not pass runlog-check, or best did not crown round 1 before rotation — see $work/r8-t102-check1.log / $work/r8-t102-best1.log"
  cat "$work/r8-t102-check1.log" "$work/r8-t102-best1.log" >&2 || true
fi
printf 'GATE RESULT: PASS\n(round 2 gate run)\n' > "$r3p/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n(round 2 gate run)\n' > "$r3p/design/gate-leg2.log"
touch -d '2026-11-11 12:03' "$r3p/design/gate-leg1.log" "$r3p/design/gate-leg2.log"
node "$run_log_mjs" --project "$r3p" record --round 2 --grader none --scores none --gate pass $r3_legs >"$work/r8-t102-record2.log" 2>&1 \
  || fail "judge-artifact (D15): round-8 C4 genuine round-2 no-grade record after leg rotation failed — case (102) will cascade; see $work/r8-t102-record2.log"
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 2 --gate pass $r3_legs >"$work/r8-t102-land2.log" 2>&1 \
  || fail "judge-artifact (D15): round-8 C4 genuine land round 2 after leg rotation failed — case (102) will cascade; see $work/r8-t102-land2.log"
node "$run_log_mjs" --project "$r3p" best >"$work/r8-t102-best2.log" 2>&1
if ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r8-t102-check2.log" 2>&1; then
  fail "judge-artifact (D15): runlog-check failed the fully genuine two-round landed log after canonical leg rotation (C4 — the round-1 lines are rotated history, not the live epoch) — see $work/r8-t102-check2.log"
  cat "$work/r8-t102-check2.log" >&2 || true
elif ! grep -q "best: round 1" "$work/r8-t102-best2.log"; then
  fail "judge-artifact (D15): best forgot the genuinely graded round 1 after the canonical legs rotated (C4) — see $work/r8-t102-best2.log"
  cat "$work/r8-t102-best2.log" >&2 || true
else
  ok "the genuine two-round landed log passes runlog-check after canonical leg rotation and best still crowns round 1 (C4 epoch rule)"
fi
# (103) The other half of the epoch rule: a feedback regrade is a
# LIVE operation, so it anchors only on a graded record whose gate
# evidence is still current. On the same rotated project, a genuine
# regrade artifact for round 1's page (prepared against the current
# legs, filled, hash-bound to the page round 1 graded) must still
# be REFUSED: round 1's cited legs no longer match the files on
# disk, so the round never anchors a regrade — the operator records
# a fresh round instead.
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page.html >"$work/r8-prep-1-regrade.log" 2>&1 \
  || fail "judge-artifact (D15): round-8 C4 regrade prepare failed — case (103) will cascade; see $work/r8-prep-1-regrade.log"
jr_fill_scores "$r3p/design/judge/round-1-regrade.md" 5 5 5 5
r3_reject "feedback regrade of a round whose gate legs rotated away" "$work/r8-t103.log" "never anchors a regrade" "$r3p/design/run-log.jsonl" \
  node "$run_log_mjs" --project "$r3p" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md

# --- Live-proof case (104): a genuine judge report must not trip
# gate leg 1 §1.1, and a secret planted in judge prose must still
# fail it. Found by the M1 live proof on Brief 1 (2026-11-12):
# judge-report.mjs stamps sha256 content hashes into the header of
# design/judge/round-*.md, and gitleaks' generic-api-key rule flagged
# the tokens-sha256 line — §1.1 failed on every project once its first
# judge report existed, so no second round could ever be gated (the
# M1 test environment had no gitleaks, which is how the miss survived
# to the proof). Fix: the gate's .gitleaks.toml allowlist now covers
# the canonical round-*.md names (path-only, the run-log treatment);
# gate.sh's 1.1 text pass still greps those files, so the planted
# half below must fail via the built-in grep, scanner or not.
g11p="$work/gate11-proj"; r3_mkproj "$g11p"
r3_prep "$g11p" 1 absolute
jr_fill_scores "$g11p/design/judge/round-1.md" 4 4 4 4
if ! node "$run_log_mjs" --project "$g11p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/gate11-setup.log" 2>&1; then
  fail "judge-artifact (D15): live-proof case (104) setup record failed — see $work/gate11-setup.log"
  cat "$work/gate11-setup.log" >&2 || true
else
  g11_gate_sh="$root/skills/frontend-kit/scripts/gate/gate.sh"
  g11_rc=0
  bash "$g11_gate_sh" --target "$g11p" --security-only >"$work/gate11-clean.log" 2>&1 || g11_rc=$?
  g11_clean_ok=1
  if grep -q "gitleaks found leaks" "$work/gate11-clean.log"; then g11_clean_ok=0; fi
  if grep -Eq "design/judge/round-1\.md:[0-9]+:" "$work/gate11-clean.log"; then g11_clean_ok=0; fi
  if command -v gitleaks >/dev/null 2>&1; then
    if ! grep -q "SECURITY 1.1: PASS — secret scan clean (gitleaks" "$work/gate11-clean.log"; then g11_clean_ok=0; fi
  else
    unverified "judge-artifact (D15) case (104): gitleaks not installed — the gitleaks half of the §1.1 assertion is not proven here; the built-in grep half is asserted below (the fail-closed no-scanner line is accepted for the clean project)"
    if ! grep -Eq "SECURITY 1.1: PASS|no secret scanner installed" "$work/gate11-clean.log"; then g11_clean_ok=0; fi
  fi
  g11b="$work/gate11-proj-bad"; cp -r "$g11p" "$g11b"
  printf '\nJudge note: pasted from a ticket, api_key = "sk-proj-ABCDEFGHIJKLMNOPQRSTUVWX" was visible in the client console.\n' >> "$g11b/design/judge/round-1.md"
  g11b_rc=0
  bash "$g11_gate_sh" --target "$g11b" --security-only >"$work/gate11-bad.log" 2>&1 || g11b_rc=$?
  if [[ "$g11_clean_ok" != 1 ]]; then
    fail "judge-artifact (D15): gate leg 1 §1.1 still trips on a genuine judge report (live-proof defect — the stamped tokens-sha256 header must not fail the secret scan) — see $work/gate11-clean.log"
    cat "$work/gate11-clean.log" >&2 || true
  elif [[ "$g11b_rc" == 0 ]] || ! grep -q "security 1.1: secret scan: high-confidence secret pattern found (built-in grep)" "$work/gate11-bad.log" || ! grep -Eq "design/judge/round-1\.md:[0-9]+:" "$work/gate11-bad.log"; then
    fail "judge-artifact (D15): a secret planted in a judge report's prose did NOT fail gate §1.1 via the built-in grep — the gitleaks allowlist must not blind the grep backstop — see $work/gate11-bad.log"
    cat "$work/gate11-bad.log" >&2 || true
  else
    ok "a genuine judge report passes gate leg 1 §1.1 and a secret planted in judge prose still fails it via the built-in grep (live-proof case)"
  fi
fi

# --- Live-proof-round-2 case (105): the leg-currency DEADLOCK.
# gate.sh §1.1 folds runlog-check's output into leg 1's verdict
# (gate.sh §1.1: the checker's output joins the 1.1 hits), and
# every gate run overwrites the two canonical leg files. Round 8
# left runlog-check a latest-line leg-currency check — so the
# genuine round-1 log below, the moment a round-2 gate run rotated
# its legs, failed its own checker while round 1 was STILL the
# latest round line: leg 1 failed on the fold-in, prepare
# refused, and round 2 could never record (proven live on the
# Brief 1 proof project, 2026-11-12: runlog-check exit 1 on the
# fully genuine log). Adjudication: leg currency is a property of
# LIVE OPERATIONS, not of the log's standing state — the checker
# now holds NO stored line to currency (shape + artifact binding
# only), while feedback's anchor and land's precondition keep
# re-checking currency at action time. (Case (103) pins the
# feedback half on a two-round log; case (89) pins the checker
# half on an edited line; the case below pins all three halves on
# the deadlocked single-round state itself.)
# (105) Genuine round 1 graded + landed; both canonical legs then
# rotated by a later gate run (round 1 is STILL the latest round
# line, its land STILL the latest land line). runlog-check must
# pass; a feedback regrade of round 1 must refuse (anchor
# currency); a second land for round 1 must refuse (precondition
# currency); neither refusal may write to the log.
r3p="$work/r10-deadlock"; r3_mkproj "$r3p"
r3_prep "$r3p" 1 absolute
jr_fill_scores "$r3p/design/judge/round-1.md" 4 4 4 4
node "$run_log_mjs" --project "$r3p" record --round 1 --grader judge-subagent --basis "$jr_basis" --scores 4,4,4,4 --judge-report design/judge/round-1.md --gate pass $r3_legs >"$work/r10-t105-setup.log" 2>&1 \
  || fail "judge-artifact (D15): live-proof-round-2 deadlock setup graded record failed — case (105) will cascade; see $work/r10-t105-setup.log"
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs >"$work/r10-t105-land1.log" 2>&1 \
  || fail "judge-artifact (D15): live-proof-round-2 deadlock setup land round 1 failed — case (105) will cascade; see $work/r10-t105-land1.log"
if ! node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r10-t105-check1.log" 2>&1; then
  fail "judge-artifact (D15): live-proof-round-2 deadlock CONTROL failed — the genuine one-round landed log did not pass runlog-check before rotation — see $work/r10-t105-check1.log"
  cat "$work/r10-t105-check1.log" >&2 || true
fi
printf 'GATE RESULT: PASS\n(round 2 gate run)\n' > "$r3p/design/gate-leg1.log"
printf '===== gate verdict: GREEN =====\n(round 2 gate run)\n' > "$r3p/design/gate-leg2.log"
touch -d '2026-11-11 12:03' "$r3p/design/gate-leg1.log" "$r3p/design/gate-leg2.log"
node "$runlog_check_mjs" "$r3p/design/run-log.jsonl" >"$work/r10-t105-check2.log" 2>&1
r10_check_rc=$?
node "$judge_report_mjs" --project "$r3p" prepare --round 1 --kind regrade --grader other-model --brief-type landing --mode full --page design/page.html >"$work/r10-prep-1-regrade.log" 2>&1 \
  || fail "judge-artifact (D15): live-proof-round-2 deadlock regrade prepare failed — case (105) will cascade; see $work/r10-prep-1-regrade.log"
jr_fill_scores "$r3p/design/judge/round-1-regrade.md" 5 5 5 5
r10_lines_before="$(grep -c . "$r3p/design/run-log.jsonl")"
node "$run_log_mjs" --project "$r3p" feedback --from "user: darker ink" --change "--color-ink: #000" --round 1 --score-after 5,5,5,5 --grader other-model --basis "$jr_basis" --judge-report design/judge/round-1-regrade.md >"$work/r10-t105-feedback.log" 2>&1
r10_fb_rc=$?
node "$run_log_mjs" --project "$r3p" land --slice r3 --round 1 --gate pass $r3_legs >"$work/r10-t105-land2.log" 2>&1
r10_land_rc=$?
if [[ "$r10_check_rc" != 0 ]]; then
  fail "judge-artifact (D15): runlog-check failed the genuine round-1 log after its legs rotated while round 1 is still the latest round line (the live-proof-round-2 deadlock — the checker must hold no stored line to leg currency) — see $work/r10-t105-check2.log"
  cat "$work/r10-t105-check2.log" >&2 || true
elif [[ "$r10_fb_rc" == 0 ]] || ! grep -q "never anchors a regrade" "$work/r10-t105-feedback.log"; then
  fail "judge-artifact (D15): a feedback regrade of the rotated round 1 was not refused on anchor leg currency (live-proof round 2 — live operations keep currency) — see $work/r10-t105-feedback.log"
  cat "$work/r10-t105-feedback.log" >&2 || true
elif [[ "$r10_land_rc" == 0 ]] || ! grep -q "no round record" "$work/r10-t105-land2.log"; then
  fail "judge-artifact (D15): a second land for the rotated round 1 was not refused on precondition leg currency (live-proof round 2 — live operations keep currency) — see $work/r10-t105-land2.log"
  cat "$work/r10-t105-land2.log" >&2 || true
elif [[ "$(grep -c . "$r3p/design/run-log.jsonl")" != "$r10_lines_before" ]]; then
  fail "judge-artifact (D15): a refused live operation wrote to the run log in the deadlocked state (live-proof round 2) — see $work/r10-t105-feedback.log / $work/r10-t105-land2.log"
else
  ok "the deadlocked state is split: runlog-check passes the genuine round-1 log after leg rotation while feedback and land still refuse the rotated round on leg currency (live-proof round 2)"
fi

# (106) M2 prepare parity — judge-report.mjs prepare applies the SAME
# --page rules record time applies (it claims parity in its own
# comment), so prepare must refuse the D13 edge-case spellings too,
# writing no skeleton: --page design/..html (dot-only stem),
# design/x.html.html (double extension), and
# design/../design/page.html (a ".." that cancels out). Round 13 is
# otherwise unused in §5c, so no round-13.md may appear.
for bad_page in "design/..html" "design/x.html.html" "design/../design/page.html"; do
  if node "$judge_report_mjs" --project "$jr_proj" prepare --round 13 --kind absolute --grader judge-subagent --brief-type landing --mode full --page "$bad_page" >"$work/judge-prep-13-bad.log" 2>&1; then
    fail "judge-artifact (D15): prepare with --page $bad_page exited 0 — prepare must refuse the D13 edge-case spellings (exit 2)"
  elif [[ -f "$jr_proj/design/judge/round-13.md" ]]; then
    fail "judge-artifact (D15): prepare with --page $bad_page wrote design/judge/round-13.md — a refused prepare must write nothing"
  else
    ok "judge-report prepare refuses --page $bad_page (exit 2, nothing written)"
  fi
done


# --- 6. Playwright eyes ------------------------------------------------------
# Skip-awareness (W-FIX-SKIP 2026-11-10): install.sh records --skip-eyes
# in $state_dir/skipped-subsystems.txt. When eyes was skipped at install,
# a missing/failing browser is EXPECTED, not a broken loop — report
# PENDING and skip the whole step (no --help, no screenshot, no FAIL, no
# UNVERIFIED). When eyes was NOT skipped, the step below runs unchanged:
# a missing/failing browser still FAILs (and a missing CLI is still
# UNVERIFIED in default mode / FAIL under --strict). The other verify
# steps need no such check: §8 already reports skipped hooks/mcp as
# PENDING (never FAIL), and no other step FAILs on a skipped hooks/mcp
# subsystem — §3/§4/§5 depend on the engine warm, §9 on Node, §7 on
# reference data, none on hooks/mcp/eyes skips.
eyes_skipped=0
if [[ -f "$state_dir/skipped-subsystems.txt" ]] && grep -qx 'eyes' "$state_dir/skipped-subsystems.txt" 2>/dev/null; then
  eyes_skipped=1
fi
if [[ "$eyes_skipped" == 0 ]]; then
  # Resolve the CLI + node to REAL binaries (clean-env 2026-11-11,
  # GAP-5 redo — the round-1 fix was incomplete and run 3 proved it):
  # `command -v playwright-cli` succeeding does NOT mean the CLI runs.
  # On mise-managed machines the PATH entry is a mise shim, and the shim
  # fails at EXEC time ("No version is set for shim: playwright-cli")
  # when invoked from a cwd outside the mise config chain — this step
  # runs its eyes commands from a temp dir under /tmp, so every eyes
  # invocation failed in run 3 even though install-browser (run from the
  # repo dir) had worked minutes earlier. Resolving the CLI to the real
  # binary alone is NOT enough either: the CLI is a node script with a
  # `#!/usr/bin/env node` shebang, and `node` on PATH is ALSO a mise
  # shim that fails from /tmp — the real CLI binary fails there too
  # (reproduced 2026-11-11). The fix is to prepend the npm-prefix bin
  # dir to PATH: it holds BOTH the real playwright-cli AND the real
  # node, so the shebang resolves to a real binary from any cwd. Do
  # this UNCONDITIONALLY (when the real bin exists) — not only when
  # `command -v` fails, as the round-1 code did — because a present
  # shim is exactly the broken case. `mise which` is the fallback
  # (same shape: its bin dir holds the real node too). PATH is restored
  # after the §6 block (red-team H7): the prepend is for the eyes step
  # only.
  # TWIN BLOCK (L4 — drift risk): install.sh contains a near-duplicate
  # of this resolve block (the Playwright eyes section). Any fix here
  # MUST also land there (and vice versa) — the two blocks drifted
  # apart before (round-1 fix incomplete, run 3 proved it) and only a
  # paired edit keeps them in step.
  _pw_saved_path="$PATH"
  _pw_saved_path_set=1
  # L1: extend the EXIT trap (which already removes $work) to restore
  # PATH too, so an early exit cannot leak the prepend into the
  # caller's shell. The sequential restore below stays: the trap is the
  # backstop, not the mechanism. NOTE: this script is EXECUTED, not
  # sourced — do NOT source it. A sourced run would leave the prepend
  # in the caller's shell if the script exits before the sequential
  # restore, and installing this trap clobbers any EXIT trap the caller
  # already had. The trap is unset (`trap - EXIT`) right after the
  # sequential restore, so it cannot linger past this section ($work is
  # removed eagerly there instead — it is not used past the restore).
  # Sentinel-guarded (L2) so an empty original PATH still restores
  # (empty, not unset). The trap ALSO removes the scratch dirs
  # (capdir/probe dir) so an early exit does not leak them (M4); the
  # normal path removes them too (idempotent).
  # (M5: the trap's real trigger is signals/aborts — fail() only counts
  # here and cannot trigger it, so "fail() between prepend and restore"
  # cannot fire it; the comment used to claim otherwise. L6: the
  # trap's `rm -rf "$work"` is guarded with -- and an empty-check.)
  trap 'if [[ -n "${work:-}" ]]; then rm -rf -- "$work" 2>/dev/null || true; fi; if [[ -n "${_pw_saved_path_set:-}" ]]; then PATH="$_pw_saved_path"; hash -r; fi; if [[ "${_pw_capdir_own:-0}" == 1 && -n "${_pw_capdir:-}" ]]; then rm -rf -- "$_pw_capdir" 2>/dev/null || true; fi; if [[ -n "${_pw_probe_dir:-}" && "${_pw_probe_dir:-}" != "${work:-}" ]]; then rm -rf -- "$_pw_probe_dir" 2>/dev/null || true; fi' EXIT
  # Probe helpers (round-3 re-QC: M-C, L-C, L-G). Every probe below runs
  # through _pw_timeout30 so a hung mise/shim cannot stall the script
  # forever; stderr is captured to files under $_pw_capdir and the first
  # line printed on failure instead of discarded (L-C). Defined here,
  # inside the block, so the block stays self-contained.
  # (M6: timeout(1) can only run EXTERNAL commands — every probe
  # argument below must be a PATH-resolved binary, never a shell
  # function. Detected with `type -P` (file only) so a function named
  # `timeout` cannot silently satisfy the check.)
  _pw_have_timeout=0; type -P timeout >/dev/null 2>&1 && _pw_have_timeout=1
  if [[ "$_pw_have_timeout" == 0 ]]; then printf 'WARNING: timeout(1) not found — probes run unbounded (a hung mise/shim can stall the script).\n' >&2; fi
  _pw_timeout30() { if [[ "$_pw_have_timeout" == 1 ]]; then timeout -k 5 30 "$@"; else "$@"; fi; }
  _pw_canon() { # <path> — canonical path, or the input unchanged
    # Portable canonicaliser (macOS phase, D12): GNU readlink -f first,
    # then python3 realpath (BSD readlink has no -f; python3 is a hard
    # prereq). If neither works, return the input unchanged — callers
    # treat that as "unresolved", never as an error. No `--` before the
    # path argument: with `python3 -c`, `--` lands in sys.argv[1]
    # instead of being stripped (verified 2026-11-11), so it would
    # canonicalise the literal `--`. All call sites pass absolute paths.
    local _c=""
    if [[ -n "${1:-}" ]]; then
      if command -v readlink >/dev/null 2>&1; then _c="$(readlink -f -- "$1" 2>/dev/null || true)"; fi
      if [[ -z "$_c" ]] && command -v python3 >/dev/null 2>&1; then _c="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || true)"; fi
    fi
    printf '%s' "${_c:-$1}"
  }
  _pw_same_file() { # <a> <b>: exit 0 if the same file, by canonical path or inode
    local _a="${1:-}" _b="${2:-}" _ca _cb _ia _ib
    [[ -z "$_a" || -z "$_b" ]] && return 1
    [[ "$_a" == "$_b" ]] && return 0
    _ca="$(_pw_canon "$_a")"; _cb="$(_pw_canon "$_b")"
    [[ "$_ca" == "$_cb" ]] && return 0
    if command -v stat >/dev/null 2>&1; then
      _ia="$(stat -c '%d:%i' -- "$_a" 2>/dev/null || true)"
      if [[ -z "$_ia" ]]; then _ia="$(stat -f '%d:%i' -- "$_a" 2>/dev/null || true)"; fi
      _ib="$(stat -c '%d:%i' -- "$_b" 2>/dev/null || true)"
      if [[ -z "$_ib" ]]; then _ib="$(stat -f '%d:%i' -- "$_b" 2>/dev/null || true)"; fi
      [[ -n "$_ia" && "$_ia" == "$_ib" ]] && return 0
    fi
    return 1
  }
  _pw_first_line() { [[ -s "${1:-}" ]] && head -n 1 -- "$1" || true; }
  # H1 (micro red-team): a failed cd must never be misread as a tool
  # failure. _pw_cd_ok <dir> exits 0 iff the dir can be entered.
  # Probe sites use rc 98 as the "cd failed — inconclusive" sentinel.
  _pw_cd_ok() { (cd -- "${1:-}" 2>/dev/null); }
  # Capture files for probe stdout/stderr (M-C/L-C): one scratch dir
  # under /tmp (TMPDIR forced — L-H: a poisoned TMPDIR must not move
  # these). If mktemp fails, fall back to /tmp itself with $$-suffixed
  # names (redirection creates the files; no mkdir needed).
  _pw_capdir="$(TMPDIR=/tmp mktemp -d 2>/dev/null || true)"
  _pw_capdir_own=1
  if [[ -z "$_pw_capdir" ]]; then _pw_capdir="/tmp"; _pw_capdir_own=0; printf 'WARNING: could not create a temp capture dir — probe output files use predictable /tmp/pw-*-$$.out names instead (a degraded /tmp).\n' >&2; fi
  _pw_npm_out="$_pw_capdir/pw-npm-prefix-$$.out"; _pw_npm_err="$_pw_capdir/pw-npm-prefix-$$.err"
  _pw_mise_cli_out="$_pw_capdir/pw-mise-cli-$$.out"; _pw_mise_cli_err="$_pw_capdir/pw-mise-cli-$$.err"
  _pw_mise_node_out="$_pw_capdir/pw-mise-node-$$.out"; _pw_mise_node_err="$_pw_capdir/pw-mise-node-$$.err"
  _pw_node_out="$_pw_capdir/pw-node-ver-$$.out"; _pw_node_err="$_pw_capdir/pw-node-ver-$$.err"
  _pw_cli_out="$_pw_capdir/pw-cli-ver-$$.out"; _pw_cli_err="$_pw_capdir/pw-cli-ver-$$.err"
  _pw_probe_err="$_pw_capdir/pw-probe-$$.err"
  hash -r
  _pw_npm_prefix=""
  _pw_npm_prefix_bad=""
  _pw_mise_bin=""
  _pw_mise_cli=""
  _pw_mise_cli_bad=""
  # H2 guard: $root must be a usable dir — `cd ""` is a silent no-op in
  # bash, so an empty $root would pin the resolvers below to the
  # invoker's cwd instead of failing (and an unset $root would abort
  # under set -u). With a bad $root the resolvers are skipped outright
  # and the M4 diagnostic below fires naming $root; the M1/H3 checks
  # downstream still fail safe on whatever is on PATH.
  _pw_root_ok=1
  if [[ -z "${root:-}" || ! -d "$root" ]]; then
    printf 'ERROR: $root is not a usable directory ("%s") — skipping the cwd-pinned resolvers below; the M4 diagnostic names the failed sources.\n' "${root-<unset>}" >&2
    _pw_root_ok=0
  fi
  # Probe dir (H3/L-D/L-H): created ONCE, up front, and reused by the
  # H1 node check, the M1 maybe-shim probe and the H3 CLI probe — all
  # three must run from a temp cwd outside the mise config chain, never
  # the script cwd (where shims work). TMPDIR is forced to /tmp for the
  # mktemp call: a TMPDIR pointing inside the mise chain (or the repo)
  # would make the probe test the wrong cwd class. If the dir lands
  # under $root anyway, fall back to $work (also a temp dir under /tmp).
  # A kill between mktemp and the removal after the --help probe leaks
  # one /tmp dir — accepted, /tmp is scratch.
  _pw_probe_dir="$(TMPDIR=/tmp mktemp -d 2>/dev/null || true)"
  if [[ -z "$_pw_probe_dir" ]]; then
    printf 'WARNING: could not create a temp probe dir — probes run from the temp work dir instead (weaker shim check).\n' >&2
    _pw_probe_dir="$work"
  else
    _pw_root_norm=""
    if [[ "$_pw_root_ok" == 1 && -n "${root:-}" && "$root" != "/" ]]; then _pw_root_norm="${root%/}"; fi
    if [[ -n "$_pw_root_norm" && ( "$_pw_probe_dir" == "$_pw_root_norm" || "$_pw_probe_dir" == "$_pw_root_norm"/* ) ]]; then
      printf 'WARNING: temp probe dir %s is under the repo dir %s — falling back to the temp work dir (weaker shim check).\n' "$_pw_probe_dir" "$root" >&2
      _pw_probe_dir="$work"
    fi
  fi
  _pw_cd_failed=0
  if [[ "$_pw_root_ok" == 1 ]] && command -v npm >/dev/null 2>&1; then
    # H2: resolve from the REPO dir, not the invoker's cwd — `npm config
    # get prefix` reads .npmrc from the cwd, and `mise which` exits
    # non-zero unless the tool resolves in the cwd. The subshell cd pins
    # both to $root; the outer cwd is untouched. (L-I: a failed cd warns
    # by name instead of vanishing into `|| true`; M-C: bounded to 30 s;
    # L-C: stderr is captured, not discarded.)
    # H1: the cd is tested in the PARENT first — a cd failure inside the
    # probe subshell would set no flag the parent can see, and M4 would
    # misreport it as "<empty>". _pw_cd_failed=1 names it there.
    _pw_npm_rc=0
    if ! _pw_cd_ok "$root"; then
      printf 'WARNING: could not cd to repo dir "%s" for `npm config get prefix` — resolvers below use an empty prefix.\n' "$root" >&2
      _pw_npm_rc=98; _pw_cd_failed=1
    else
      (cd "$root" && _pw_timeout30 npm config get prefix 2>"$_pw_npm_err") >"$_pw_npm_out" || _pw_npm_rc=$?
    fi
    _pw_npm_prefix="$(head -n 1 -- "$_pw_npm_out" 2>/dev/null || true)"
    if [[ "$_pw_npm_rc" == 124 ]]; then
      printf 'WARNING: `npm config get prefix` timed out after 30 s (or exited 124) — treating the prefix as empty.\n' >&2
    elif [[ "$_pw_npm_rc" == 98 ]]; then
      : # cd failure already warned above; prefix stays empty
    elif [[ -z "$_pw_npm_prefix" && -s "$_pw_npm_err" ]]; then
      printf 'WARNING: `npm config get prefix` failed: %s\n' "$(_pw_first_line "$_pw_npm_err")" >&2
    fi
    # L3: the prefix must be ABSOLUTE — a relative prefix would
    # re-resolve against whatever cwd the script is in mid-section
    # (/tmp during the probe below). A prefix outside $HOME is FINE
    # (system node lives at /usr on this VM) — only relative is rejected.
    case "$_pw_npm_prefix" in
      /*) ;;
      "") ;;
      *) printf 'WARNING: npm prefix "%s" is relative — ignoring it (a relative prefix re-resolves against the cwd).\n' "$_pw_npm_prefix" >&2; _pw_npm_prefix_bad="$_pw_npm_prefix"; _pw_npm_prefix="" ;;
    esac
    # L-G: normalise trailing slashes — a prefix of "/opt/foo/" would
    # otherwise build "/opt/foo//bin" and break the M2 comparison.
    while [[ "$_pw_npm_prefix" == */ && "$_pw_npm_prefix" != "/" ]]; do _pw_npm_prefix="${_pw_npm_prefix%/}"; done
  fi
  # Pick the dir holding the REAL playwright-cli: the npm-prefix bin
  # first, `mise which` as fallback. Prepend it whenever it holds an
  # executable CLI — whether or not it also holds node. (Round-3 QC:
  # the old elif fell through to the mise branch when node was missing
  # from the npm bin and prepended NOTHING, even when a real node was
  # already on PATH or available via `mise which node` — the CLI was
  # then unfindable although both real binaries existed. Reproduced
  # with stub npm/mise: npm bin with CLI but no node + real system
  # node, and mise CLI bin with no node + real mise node elsewhere,
  # both left `command -v playwright-cli` failing.)
  _pw_cli_dir=""
  if [[ -n "$_pw_npm_prefix" && -x "$_pw_npm_prefix/bin/playwright-cli" ]]; then
    _pw_cli_dir="$_pw_npm_prefix/bin"
  elif [[ "$_pw_root_ok" == 1 ]] && command -v mise >/dev/null 2>&1; then
    _pw_mise_cli_rc=0
    if ! _pw_cd_ok "$root"; then
      printf 'WARNING: could not cd to repo dir "%s" for `mise which playwright-cli` — the mise fallback is skipped.\n' "$root" >&2
      _pw_mise_cli_rc=98; _pw_cd_failed=1
    else
      (cd "$root" && _pw_timeout30 mise which playwright-cli 2>"$_pw_mise_cli_err") >"$_pw_mise_cli_out" || _pw_mise_cli_rc=$?
    fi
    _pw_mise_cli="$(head -n 1 -- "$_pw_mise_cli_out" 2>/dev/null || true)"
    if [[ "$_pw_mise_cli_rc" == 124 ]]; then
      printf 'WARNING: `mise which playwright-cli` timed out after 30 s (or exited 124) — treating it as empty.\n' >&2
    elif [[ "$_pw_mise_cli_rc" == 98 ]]; then
      : # cd failure already warned above; result stays empty
    elif [[ -z "$_pw_mise_cli" && -s "$_pw_mise_cli_err" ]]; then
      printf 'WARNING: `mise which playwright-cli` failed: %s\n' "$(_pw_first_line "$_pw_mise_cli_err")" >&2
    fi
    case "$_pw_mise_cli" in
      /*) ;;
      "") ;;
      *) printf 'WARNING: `mise which playwright-cli` returned a relative path "%s" — ignoring it.\n' "$_pw_mise_cli" >&2; _pw_mise_cli_bad="$_pw_mise_cli"; _pw_mise_cli="" ;;
    esac
    if [[ -n "$_pw_mise_cli" && -x "$_pw_mise_cli" ]]; then
      _pw_mise_bin="$(dirname -- "$_pw_mise_cli")"
      _pw_cli_dir="$_pw_mise_bin"
    fi
  fi
  # L-G: normalise trailing slashes on the selected dir — a trailing
  # slash would otherwise break the M2 comparison below.
  while [[ "$_pw_cli_dir" == */ && "$_pw_cli_dir" != "/" ]]; do _pw_cli_dir="${_pw_cli_dir%/}"; done
  if [[ -n "$_pw_cli_dir" ]]; then
    PATH="$_pw_cli_dir:$PATH"; hash -r
    if [[ -x "$_pw_cli_dir/node" ]]; then
      printf 'Playwright CLI + node resolved to real binaries: %s (mise shim bypassed — the shim fails from /tmp cwds)\n' "$_pw_cli_dir"
    else
      printf 'Playwright CLI resolved to real binary: %s/playwright-cli (mise shim bypassed — the shim fails from /tmp cwds; node resolved separately below if needed)\n' "$_pw_cli_dir"
    fi
  else
    # M4: ONE diagnostic line naming both attempted sources and their
    # (empty) results, before the existing UNVERIFIED path below.
    # (L-E: npm ABSENT is a different fact from npm present with no
    # bin — say which. H1: a failed cd to $root left the tool results
    # empty — say so, instead of printing "<empty>" as if mise had
    # run and returned it.)
    _pw_mise_disp="<mise not installed>"
    if command -v mise >/dev/null 2>&1; then _pw_mise_disp="<empty>"; fi
    [[ -n "$_pw_mise_cli" ]] && _pw_mise_disp="$_pw_mise_cli"
    [[ -n "$_pw_mise_cli_bad" ]] && _pw_mise_disp="<relative path \"$_pw_mise_cli_bad\" — ignored>"
    if [[ "${_pw_cd_failed:-0}" == 1 ]] && command -v mise >/dev/null 2>&1; then _pw_mise_disp="<not run — cd to repo dir failed>"; fi
    if [[ "${_pw_cd_failed:-0}" == 1 ]]; then
      printf 'Playwright CLI resolve: no real binary found — cd to the repo dir failed, so one or both resolvers never ran; see the WARNING above.\n'
    elif ! command -v npm >/dev/null 2>&1; then
      printf 'Playwright CLI resolve: no real binary found — npm is not installed, so no npm prefix was checked; `mise which playwright-cli` (from %s) returned "%s" — proceeding without the PATH prepend.\n' "${root-<unset>}" "$_pw_mise_disp"
    else
      _pw_npm_disp="${_pw_npm_prefix:-<npm not found or empty prefix>}"
      [[ -n "$_pw_npm_prefix_bad" ]] && _pw_npm_disp="<relative prefix \"$_pw_npm_prefix_bad\" — ignored>"
      printf 'Playwright CLI resolve: no real binary found — npm prefix "%s" has no bin/playwright-cli; `mise which playwright-cli` (from %s) returned "%s" — proceeding without the PATH prepend.\n' "$_pw_npm_disp" "${root-<unset>}" "$_pw_mise_disp"
    fi
  fi
  # The CLI is a node script (#!/usr/bin/env node), so a real node must
  # resolve too. If the CLI dir holds one, done. Otherwise try the real
  # node via `mise which node` — its bin dir can differ from the CLI's
  # (separate mise installs). If that fails as well, leave PATH as-is:
  # a real system node may already be on it, and the --help probe below
  # (which executes the CLI under this PATH) reports a broken shebang
  # instead of silently proceeding.
  if [[ -n "$_pw_cli_dir" && ! -x "$_pw_cli_dir/node" ]] && command -v mise >/dev/null 2>&1; then
    _pw_mise_node_rc=0
    if ! _pw_cd_ok "$root"; then
      printf 'WARNING: could not cd to repo dir "%s" for `mise which node` — the mise node fallback is skipped.\n' "$root" >&2
      _pw_mise_node_rc=98; _pw_cd_failed=1
    else
      (cd "$root" && _pw_timeout30 mise which node 2>"$_pw_mise_node_err") >"$_pw_mise_node_out" || _pw_mise_node_rc=$?
    fi
    _pw_mise_node="$(head -n 1 -- "$_pw_mise_node_out" 2>/dev/null || true)"
    if [[ "$_pw_mise_node_rc" == 124 ]]; then
      printf 'WARNING: `mise which node` timed out after 30 s (or exited 124) — treating it as empty.\n' >&2
    elif [[ "$_pw_mise_node_rc" == 98 ]]; then
      : # cd failure already warned above; result stays empty
    elif [[ -z "$_pw_mise_node" && -s "$_pw_mise_node_err" ]]; then
      printf 'WARNING: `mise which node` failed: %s\n' "$(_pw_first_line "$_pw_mise_node_err")" >&2
    fi
    case "$_pw_mise_node" in
      /*) ;;
      "") ;;
      *) printf 'WARNING: `mise which node` returned a relative path "%s" — ignoring it.\n' "$_pw_mise_node" >&2; _pw_mise_node="" ;;
    esac
    if [[ -n "$_pw_mise_node" && -x "$_pw_mise_node" ]]; then
      _pw_mise_node_bin="$(dirname -- "$_pw_mise_node")"
      if [[ "$_pw_mise_node_bin" != "$_pw_cli_dir" ]]; then
        PATH="$_pw_mise_node_bin:$PATH"; hash -r
        printf 'Node resolved to real binary: %s/node (mise shim bypassed — the shim fails from /tmp cwds)\n' "$_pw_mise_node_bin"
      fi
    fi
  fi
  # (M-A: no `mise reshim` here. It only ran when the CLI was still
  # missing, so its only product was a fresh mise shim — which the M1
  # check below rejects. A reshim step and a shim rejection cannot both
  # be right; the M4 diagnostic above is the accurate failure path.)
  # M2: print what the prepends actually resolved to, and assert the CLI
  # is the SELECTED one — the node-dir prepend above runs AFTER the
  # CLI-dir prepend, so a playwright-cli inside the node dir would
  # shadow the selected binary (the != guard only prevented a duplicate
  # prepend). If shadowed, re-prepend the CLI dir so the selected binary
  # wins, and re-check; a still-wrong resolution fails loud.
  _pw_cli_resolved="$(command -v playwright-cli 2>/dev/null || true)"
  _pw_node_resolved="$(command -v node 2>/dev/null || true)"
  printf 'Playwright CLI resolves to: %s\n' "${_pw_cli_resolved:-<not found>}"
  printf 'Node resolves to: %s\n' "${_pw_node_resolved:-<not found>}"
  _pw_resolve_ok=1
  # L-G: compare with _pw_same_file (canonical path or inode), not raw
  # strings — a node-dir CLI that is a symlink/hardlink to the selected
  # binary is the SAME file, not a shadow.
  if [[ -n "$_pw_cli_dir" && -n "$_pw_cli_resolved" ]] && ! _pw_same_file "$_pw_cli_resolved" "$_pw_cli_dir/playwright-cli"; then
    printf 'WARNING: the node-dir prepend shadowed the selected CLI (%s is not %s/playwright-cli) — re-prepending the CLI dir so the selected binary wins.\n' "$_pw_cli_resolved" "$_pw_cli_dir" >&2
    PATH="$_pw_cli_dir:$PATH"; hash -r
    _pw_cli_resolved="$(command -v playwright-cli 2>/dev/null || true)"
    _pw_node_resolved="$(command -v node 2>/dev/null || true)"
    printf 'Playwright CLI resolves to: %s\n' "${_pw_cli_resolved:-<not found>}"
    printf 'Node resolves to: %s\n' "${_pw_node_resolved:-<not found>}"
    if ! _pw_same_file "$_pw_cli_resolved" "$_pw_cli_dir/playwright-cli"; then
      fail "Playwright CLI still does not resolve to the selected binary $_pw_cli_dir/playwright-cli (resolves to ${_pw_cli_resolved:-<not found>}) — eyes step not run"
      _pw_resolve_ok=0
    fi
  fi
  # M1: canonicalise the resolved paths and reject shims. A shim (or a
  # symlink into a shims dir) passes -x, so executability never proved
  # the binary was real — that was the hole. If no canonicaliser is
  # available, the temp-cwd execution probe below is the minimum shim
  # check (H3 — already being added).
  # (M-E: the rejection is ANCHORED to the real mise shims dir —
  # ${MISE_DATA_DIR:-~/.local/share/mise}/shims — not to any path
  # component named "shims" (e.g. /opt/<team>/shims/bin is a real
  # install, not a mise shim). A canonical path under some OTHER
  # shims-like dir is only a SUSPECT: it is rejected only if it also
  # fails the temp-cwd execution probe just below (M-E fallback).
  # Canonicaliser (macOS phase, D12): _pw_canon tries GNU readlink -f,
  # then python3 realpath (BSD readlink has no -f). The gate below tests
  # whether either exists; when neither does, M1 is skipped and only the
  # execution probe runs. _pw_canon never returns empty for a non-empty
  # input (it falls back to the input), so there is no per-path
  # "could not canonicalise" warning anymore — an unresolved path is
  # still compared against the shims anchor, and the probe is the
  # backstop for a symlinked path it cannot see through.)
  _pw_canon_ok=0
  if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then _pw_canon_ok=1;
  elif command -v python3 >/dev/null 2>&1; then _pw_canon_ok=1; fi
  _pw_cli_maybe_shim=0; _pw_node_maybe_shim=0
  if [[ "$_pw_resolve_ok" == 1 && "$_pw_canon_ok" == 1 ]]; then
    _pw_cli_real=""; _pw_node_real=""
    [[ -n "$_pw_cli_resolved" ]] && _pw_cli_real="$(_pw_canon "$_pw_cli_resolved")"
    [[ -n "$_pw_node_resolved" ]] && _pw_node_real="$(_pw_canon "$_pw_node_resolved")"
    [[ -n "$_pw_cli_real" ]] && printf 'Playwright CLI canonical path: %s\n' "$_pw_cli_real"
    [[ -n "$_pw_node_real" ]] && printf 'Node canonical path: %s\n' "$_pw_node_real"
    # M2: the anchor is the CANONICAL mise shims dir. _pw_mise_data is
    # canonicalised (a symlinked mise data dir must still match), a
    # leading ~ is expanded, and HOME unset/empty leaves the anchor
    # undetermined (probe decides) instead of aborting under set -u.
    # L7: the anchor's effective value is logged once, so a
    # misconfigured MISE_DATA_DIR is visible.
    _pw_mise_data="${MISE_DATA_DIR:-}"
    if [[ -n "$_pw_mise_data" && "$_pw_mise_data" == "~/"* ]]; then _pw_mise_data="${HOME:-}/${_pw_mise_data:2}"; fi
    if [[ -z "$_pw_mise_data" ]]; then
      if [[ -n "${HOME:-}" ]]; then _pw_mise_data="$HOME/.local/share/mise"; else _pw_mise_data=""; fi
    fi
    if [[ -n "$_pw_mise_data" ]]; then _pw_mise_data="$(_pw_canon "$_pw_mise_data")"; fi
    while [[ "$_pw_mise_data" == */ && "$_pw_mise_data" != "/" ]]; do _pw_mise_data="${_pw_mise_data%/}"; done
    _pw_mise_shims=""
    case "$_pw_mise_data" in /*) _pw_mise_shims="$_pw_mise_data/shims" ;; esac
    printf 'Mise shims dir (anchor): %s\n' "${_pw_mise_shims:-<undetermined — probe decides>}"
    _pw_cli_is_shim=0; _pw_node_is_shim=0
    if [[ -n "$_pw_cli_real" ]]; then
      if [[ -n "$_pw_mise_shims" && ( "$_pw_cli_real" == "$_pw_mise_shims" || "$_pw_cli_real" == "$_pw_mise_shims"/* ) ]]; then
        _pw_cli_is_shim=1
      elif [[ "$_pw_cli_real" == */shims/* || "$_pw_cli_real" == */shims ]]; then
        _pw_cli_maybe_shim=1
      fi
    fi
    if [[ "$_pw_cli_is_shim" == 1 ]]; then
      # M2 probe backstop: the location says shim, but a real binary
      # hand-placed under the shims dir would execute — probe it first.
      # Only a probe that RUNS and FAILS confirms the rejection; a
      # successful execution exonerates it. A cd failure is
      # inconclusive — do not reject on it (H1), the H3 probe below is
      # the backstop.
      _pw_anchor_rc=0; _pw_anchor_ok=0
      if _pw_cd_ok "$_pw_probe_dir"; then
        (cd "$_pw_probe_dir" && _pw_timeout30 "$_pw_cli_resolved" --version >/dev/null 2>"$_pw_probe_err") || _pw_anchor_rc=$?
        if [[ "$_pw_anchor_rc" == 0 ]]; then _pw_anchor_ok=1; fi
      else
        printf 'WARNING: anchored-shim probe inconclusive (could not cd to probe dir "%s") — not rejecting on location alone.\n' "$_pw_probe_dir" >&2
        _pw_anchor_rc=98
      fi
      if [[ "$_pw_anchor_ok" == 1 ]]; then
        printf 'Playwright CLI at %s executes from the temp probe dir despite the shims location — treating it as a real binary, not a shim.\n' "$_pw_cli_real"
        _pw_cli_is_shim=0
      elif [[ "$_pw_anchor_rc" == 98 ]]; then
        _pw_cli_is_shim=0
      fi
    fi
    if [[ "$_pw_cli_is_shim" == 1 ]]; then
      fail "Playwright CLI canonical path $_pw_cli_real is under a shims dir — a shim passing -x is not a real binary; eyes step not run"
      _pw_resolve_ok=0
    fi
    if [[ "$_pw_resolve_ok" == 1 && -n "$_pw_node_real" ]]; then
      if [[ -n "$_pw_mise_shims" && ( "$_pw_node_real" == "$_pw_mise_shims" || "$_pw_node_real" == "$_pw_mise_shims"/* ) ]]; then
        _pw_node_is_shim=1
      elif [[ "$_pw_node_real" == */shims/* || "$_pw_node_real" == */shims ]]; then
        _pw_node_maybe_shim=1
      fi
    fi
    if [[ "$_pw_resolve_ok" == 1 && "$_pw_node_is_shim" == 1 ]]; then
      _pw_anchor_rc=0; _pw_anchor_ok=0
      if _pw_cd_ok "$_pw_probe_dir"; then
        (cd "$_pw_probe_dir" && _pw_timeout30 "$_pw_node_resolved" --version >/dev/null 2>"$_pw_probe_err") || _pw_anchor_rc=$?
        if [[ "$_pw_anchor_rc" == 0 ]]; then _pw_anchor_ok=1; fi
      else
        printf 'WARNING: anchored-shim probe inconclusive (could not cd to probe dir "%s") — not rejecting on location alone.\n' "$_pw_probe_dir" >&2
        _pw_anchor_rc=98
      fi
      if [[ "$_pw_anchor_ok" == 1 ]]; then
        printf 'Node at %s executes from the temp probe dir despite the shims location — treating it as a real binary, not a shim.\n' "$_pw_node_real"
        _pw_node_is_shim=0
      elif [[ "$_pw_anchor_rc" == 98 ]]; then
        _pw_node_is_shim=0
      fi
    fi
    if [[ "$_pw_resolve_ok" == 1 && "$_pw_node_is_shim" == 1 ]]; then
      fail "Node canonical path $_pw_node_real is under a shims dir — a shim passing -x is not a real binary; eyes step not run"
      _pw_resolve_ok=0
    fi
    # M-E fallback: a maybe-shim binary is proven real — or not — by
    # EXECUTING it from the temp probe dir (a mise shim fails there).
    # This probe runs now, before H1, so a rejected maybe-shim still
    # fails with the shim FAIL (and one failure count), not with a
    # misleading "node not found" from H1.
    if [[ "$_pw_resolve_ok" == 1 && ( "$_pw_cli_maybe_shim" == 1 || "$_pw_node_maybe_shim" == 1 ) ]]; then
      if [[ "$_pw_cli_maybe_shim" == 1 ]]; then
        _pw_probe_rc=0
        if ! _pw_cd_ok "$_pw_probe_dir"; then
          printf 'WARNING: maybe-shim probe inconclusive (could not cd to probe dir "%s") — not rejecting; the execution probe below is the backstop.\n' "$_pw_probe_dir" >&2
          _pw_probe_rc=98
        else
          (cd "$_pw_probe_dir" && _pw_timeout30 "$_pw_cli_resolved" --version >/dev/null 2>"$_pw_probe_err") || _pw_probe_rc=$?
        fi
        if [[ "$_pw_probe_rc" == 98 ]]; then
          : # inconclusive — do not reject on a probe that never ran
        elif [[ "$_pw_probe_rc" == 124 ]]; then
          printf 'WARNING: Playwright CLI --version from the temp probe dir timed out after 30 s (or exited 124) — a timeout is not evidence of a shim; not rejecting.\n' >&2
        elif [[ "$_pw_probe_rc" != 0 ]]; then
          # H2: only assert "shim" when the evidence supports it — the
          # failure text names a shim. Any other exec failure is a
          # broken binary, not a shim verdict; the H3 probe below
          # reports it with the right reason.
          if [[ -s "$_pw_probe_err" ]] && grep -qi 'shim' "$_pw_probe_err"; then
            printf 'WARNING: Playwright CLI --version from the temp probe dir failed: %s\n' "$(_pw_first_line "$_pw_probe_err")" >&2
            fail "Playwright CLI canonical path $_pw_cli_real is under a shims dir — a shim passing -x is not a real binary; eyes step not run"
            _pw_resolve_ok=0
          else
            printf 'WARNING: Playwright CLI --version from the temp probe dir failed (exit %s)%s — not a shim verdict; the execution probe below reports it.\n' "$_pw_probe_rc" "$([[ -s "$_pw_probe_err" ]] && printf ': %s' "$(_pw_first_line "$_pw_probe_err")")" >&2
          fi
        fi
      fi
      if [[ "$_pw_resolve_ok" == 1 && "$_pw_node_maybe_shim" == 1 ]]; then
        _pw_probe_rc=0
        if ! _pw_cd_ok "$_pw_probe_dir"; then
          printf 'WARNING: maybe-shim probe inconclusive (could not cd to probe dir "%s") — not rejecting; the execution probe below is the backstop.\n' "$_pw_probe_dir" >&2
          _pw_probe_rc=98
        else
          (cd "$_pw_probe_dir" && _pw_timeout30 "$_pw_node_resolved" --version >/dev/null 2>"$_pw_probe_err") || _pw_probe_rc=$?
        fi
        if [[ "$_pw_probe_rc" == 98 ]]; then
          : # inconclusive — do not reject on a probe that never ran
        elif [[ "$_pw_probe_rc" == 124 ]]; then
          printf 'WARNING: Node --version from the temp probe dir timed out after 30 s (or exited 124) — a timeout is not evidence of a shim; not rejecting.\n' >&2
        elif [[ "$_pw_probe_rc" != 0 ]]; then
          if [[ -s "$_pw_probe_err" ]] && grep -qi 'shim' "$_pw_probe_err"; then
            printf 'WARNING: Node --version from the temp probe dir failed: %s\n' "$(_pw_first_line "$_pw_probe_err")" >&2
            fail "Node canonical path $_pw_node_real is under a shims dir — a shim passing -x is not a real binary; eyes step not run"
            _pw_resolve_ok=0
          else
            printf 'WARNING: Node --version from the temp probe dir failed (exit %s)%s — not a shim verdict; the execution probe below reports it.\n' "$_pw_probe_rc" "$([[ -s "$_pw_probe_err" ]] && printf ': %s' "$(_pw_first_line "$_pw_probe_err")")" >&2
          fi
        fi
      fi
    fi
  elif [[ "$_pw_resolve_ok" == 1 ]]; then
    printf 'WARNING: no canonicaliser available (neither readlink -f nor python3 realpath) — the temp-cwd execution probe below is the only shim check (M1 fallback).\n' >&2
  fi
  # H1: after BOTH prepends, the node that will run the CLI must be
  # Node 22+ — the kit's hard gate (same as §9). Fail LOUD: a too-old
  # (or missing/unparseable) post-prepend node fails the run and the
  # eyes step is not run on it. (M5: the resolved node + CLI versions
  # are logged here and at the probe.)
  if [[ "$_pw_resolve_ok" == 1 ]]; then
    # L-D: run from the probe temp dir, not the script cwd — a shim
    # node reports v22+ from the repo dir and fails from /tmp. M-C:
    # bounded to 30 s; L-C: stderr captured, first line printed.
    # H1: a failed cd is INCONCLUSIVE, never "node not found" — the
    # probe never ran, so nothing about node is known.
    _pw_node_ver=""; _pw_node_rc=0
    if ! _pw_cd_ok "$_pw_probe_dir"; then
      printf 'WARNING: node --version probe inconclusive (could not cd to probe dir "%s") — cannot confirm Node 22+.\n' "$_pw_probe_dir" >&2
      _pw_node_rc=98
    else
      (cd "$_pw_probe_dir" && _pw_timeout30 node --version 2>"$_pw_node_err") >"$_pw_node_out" || _pw_node_rc=$?
    fi
    _pw_node_ver="$(head -n 1 -- "$_pw_node_out" 2>/dev/null || true)"
    if [[ "$_pw_node_rc" == 124 ]]; then
      printf 'WARNING: node --version timed out after 30 s (or exited 124) from the temp probe dir — cannot confirm Node 22+.\n' >&2
    elif [[ "$_pw_node_rc" == 98 ]]; then
      : # cd failure already warned above; version stays empty
    elif [[ "$_pw_node_rc" != 0 && -s "$_pw_node_err" ]]; then
      printf 'WARNING: node --version failed (exit %s): %s\n' "$_pw_node_rc" "$(_pw_first_line "$_pw_node_err")" >&2
    fi
    printf 'Node after PATH prepend: %s (required >= 22)\n' "${_pw_node_ver:-<not found>}"
    _pw_node_major="${_pw_node_ver#v}"; _pw_node_major="${_pw_node_major%%.*}"
    if [[ "$_pw_node_rc" == 98 ]]; then
      fail "node --version probe was inconclusive (could not cd to the temp probe dir) — cannot confirm Node 22+; eyes step not run"
      _pw_resolve_ok=0
    elif [[ -z "$_pw_node_ver" ]]; then
      fail "node not found on PATH after the Playwright PATH prepend — the CLI's #!/usr/bin/env node shebang cannot run; eyes step not run"
      _pw_resolve_ok=0
    elif [[ ! "$_pw_node_major" =~ ^[0-9]+$ ]]; then
      fail "node --version gave an unparseable result ('$_pw_node_ver') after the Playwright PATH prepend — cannot confirm Node 22+; eyes step not run"
      _pw_resolve_ok=0
    elif [[ "10#$_pw_node_major" -lt 22 ]]; then
      fail "Node $_pw_node_ver found after the Playwright PATH prepend; the kit requires Node 22+ (frontend-kit SKILL.md step 0.3; gate.mjs consistency.mjs needs the built-in WebSocket). Eyes step not run on it."
      _pw_resolve_ok=0
    fi
  fi
  # H3: capture the CLI version from a TEMP dir under /tmp (the probe
  # itself — `command -v` proves findable, not runnable, and the
  # invoker's cwd is inside the mise config chain, where shims work).
  # The dir is created once, reused for the --help probe below, and
  # removed there. If mktemp fails, $work (also a temp dir under /tmp)
  # is the fallback probe cwd. The captured output also records the CLI
  # version (H1/M5): a version other than the pin is a LOUD warning,
  # not a failure — drift, not a proven breakage (the CLI downloads
  # its own browser revision).
  # L-B: single pin source — read the pin from install.sh's
  # PLAYWRIGHT_CLI_VERSION assignment (same source install.sh uses),
  # falling back to the hardcoded literal if install.sh cannot be read
  # (e.g. the QC harness extracts this block standalone). The pin VALUE
  # is unchanged (0.1.24); only the source is single.
  # M1: the fallback is a warn() (stderr + counted), not a quiet
  # stdout line — a stale fallback must be visible. The matcher
  # accepts `export`, spaces around `=`, and a -beta / 4th-component
  # suffix (the leading dotted-triple is the pin; a suffix warns).
  # The file must also contain a second kit marker, so a stale or
  # foreign install.sh cannot silently supply the pin.
  _pw_cli_pin="0.1.24"
  _pw_cli_pin_src="hardcoded fallback"
  _pw_pin_file="${root:-}/install.sh"
  _pw_pin_line=""
  if [[ -n "${_pw_pin_file}" && -f "$_pw_pin_file" ]] && grep -q 'frontend-agent-kit' "$_pw_pin_file" 2>/dev/null; then
    _pw_pin_line="$(grep -m1 -E '^[[:space:]]*(export[[:space:]]+)?PLAYWRIGHT_CLI_VERSION[[:space:]]*=[[:space:]]*"[^"]*"' "$_pw_pin_file" 2>/dev/null || true)"
  fi
  _pw_pin_re='PLAYWRIGHT_CLI_VERSION[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)([^"]*)"'
  if [[ "$_pw_pin_line" =~ $_pw_pin_re ]]; then
    _pw_cli_pin="${BASH_REMATCH[1]}"; _pw_cli_pin_src="$_pw_pin_file"
    if [[ -n "${BASH_REMATCH[2]}" ]]; then
      warn "Playwright CLI pin in $_pw_pin_file has a suffix '${BASH_REMATCH[2]}' after the version — using the leading dotted-triple $_pw_cli_pin"
    fi
  else
    warn "Playwright CLI pin fell back to the hardcoded $_pw_cli_pin ($_pw_pin_file could not be read, lacked the kit marker, or had no PLAYWRIGHT_CLI_VERSION assignment) — re-pin install.sh to change it"
  fi
  printf 'Playwright CLI pin: %s (from %s)\n' "$_pw_cli_pin" "$_pw_cli_pin_src"
  _pw_cli_ver=""
  if [[ "$_pw_resolve_ok" == 1 ]] && command -v playwright-cli >/dev/null 2>&1; then
    # _pw_probe_dir was created up front (before M1) and reused here;
    # re-create it only if something cleared it.
    if [[ -z "${_pw_probe_dir:-}" ]]; then
      _pw_probe_dir="$(TMPDIR=/tmp mktemp -d 2>/dev/null || true)"
      [[ -z "$_pw_probe_dir" ]] && _pw_probe_dir="$work"
    fi
    # M-C/L-C: bounded to 30 s; stderr captured, first line printed on
    # failure (a non-executing CLI's real error used to be discarded).
    # H1: a failed cd is INCONCLUSIVE, never "does not execute" — the
    # probe never ran.
    _pw_cli_rc=0
    if ! _pw_cd_ok "$_pw_probe_dir"; then
      printf 'WARNING: `playwright-cli --version` probe inconclusive (could not cd to probe dir "%s").\n' "$_pw_probe_dir" >&2
      _pw_cli_rc=98
    else
      (cd "$_pw_probe_dir" && _pw_timeout30 playwright-cli --version 2>"$_pw_cli_err") >"$_pw_cli_out" || _pw_cli_rc=$?
    fi
    _pw_cli_ver="$(head -n 1 -- "$_pw_cli_out" 2>/dev/null || true)"
    if [[ "$_pw_cli_rc" == 124 ]]; then
      printf 'WARNING: `playwright-cli --version` timed out after 30 s (or exited 124) from the temp probe dir.\n' >&2
    elif [[ "$_pw_cli_rc" == 98 ]]; then
      : # cd failure already warned above; version stays empty
    elif [[ "$_pw_cli_rc" != 0 && -s "$_pw_cli_err" ]]; then
      printf 'WARNING: `playwright-cli --version` failed (exit %s): %s\n' "$_pw_cli_rc" "$(_pw_first_line "$_pw_cli_err")" >&2
    fi
    if [[ -n "$_pw_cli_ver" ]]; then
      printf 'Playwright CLI version: %s (pin %s)\n' "$_pw_cli_ver" "$_pw_cli_pin"
      # Exact match on the first dotted-triple in the output (H1): a
      # substring match would also accept 0.1.240 for pin 0.1.24, while
      # "playwright-cli 0.1.24" / "0.1.24-beta" still match.
      _pw_cli_ver_num=""
      if [[ "$_pw_cli_ver" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then _pw_cli_ver_num="${BASH_REMATCH[1]}"; fi
      if [[ "$_pw_cli_ver_num" != "$_pw_cli_pin" ]]; then
        warn "Playwright CLI version $_pw_cli_ver does NOT match the pinned $_pw_cli_pin — drift, not a proven breakage; continuing (the CLI downloads its own browser revision)"
      fi
    elif [[ "$_pw_cli_rc" == 98 ]]; then
      printf 'WARNING: playwright-cli probe was inconclusive (could not cd to the temp probe dir) — the --help probe below will report the same.\n' >&2
    else
      printf 'WARNING: playwright-cli is on PATH but does not execute from a temp dir (`playwright-cli --version` failed there — usually the #!/usr/bin/env node shebang resolving to a mise shim). The --help probe below will fail the same way.\n' >&2
    fi
  fi
  # Probe scratch cleanup: the capture files go with the scratch dir.
  # (The probe dir itself is NOT removed here — the --help probe below
  # still needs it; it is removed there.)
  rm -f -- "$_pw_npm_out" "$_pw_npm_err" "$_pw_mise_cli_out" "$_pw_mise_cli_err" "$_pw_mise_node_out" "$_pw_mise_node_err" "$_pw_node_out" "$_pw_node_err" "$_pw_cli_out" "$_pw_cli_err" "$_pw_probe_err"
  if [[ "$_pw_capdir_own" == 1 && -n "$_pw_capdir" ]]; then rm -rf -- "$_pw_capdir"; fi
fi
if [[ "$eyes_skipped" == 1 ]]; then
  pending_msg "Playwright eyes skipped at install (--skip-eyes) — eyes step not run (no browser expected). Run: npm install -g @playwright/cli@0.1.24, then playwright-cli install-browser chrome-for-testing"
elif [[ "${_pw_resolve_ok:-1}" == 0 ]]; then
  : # the resolve block above already failed loudly (shim / wrong binary / pre-22 node) — eyes not run on it
elif command -v playwright-cli >/dev/null 2>&1; then
  # H3: --help probe from a temp dir under /tmp (see the resolve block):
  # the invoker's cwd is inside the mise config chain, where shims work
  # — the probe must test the cwd class the eyes loop runs from ($work).
  # _pw_probe_dir was created by the resolve block; fall back to $work
  # (also a temp dir under /tmp) if it is empty.
  _pw_probe_cwd="${_pw_probe_dir:-$work}"
  # M-C/L-C: the --help probe is bounded to 30 s and its stderr is
  # captured — a failing CLI's real error is printed (first line) with
  # the failure instead of discarded. A timeout (exit 124) is named as
  # a timeout, not a generic failure. H1: a failed cd is INCONCLUSIVE,
  # never "failed" — the probe never ran.
  _pw_help_err="$work/pw-help-$$.err"
  _pw_help_rc=0
  if ! _pw_cd_ok "$_pw_probe_cwd"; then
    printf 'WARNING: `playwright-cli --help` probe inconclusive (could not cd to probe dir "%s").\n' "$_pw_probe_cwd" >&2
    _pw_help_rc=98
  else
    (cd "$_pw_probe_cwd" && _pw_timeout30 playwright-cli --help >/dev/null 2>"$_pw_help_err") || _pw_help_rc=$?
  fi
  if [[ "$_pw_help_rc" == 0 ]]; then ok "playwright-cli --help runs (from temp dir $_pw_probe_cwd; version ${_pw_cli_ver:-version not reported})";
  else
    _pw_help_msg="playwright-cli --help failed (from temp dir $_pw_probe_cwd)"
    if [[ "$_pw_help_rc" == 98 ]]; then _pw_help_msg="playwright-cli --help probe was inconclusive (could not cd to temp dir $_pw_probe_cwd)";
    elif [[ "$_pw_help_rc" == 124 ]]; then _pw_help_msg="$_pw_help_msg — timed out after 30 s (or exited 124)";
    elif [[ -s "$_pw_help_err" ]]; then _pw_help_msg="$_pw_help_msg: $(_pw_first_line "$_pw_help_err")"; fi
    fail "$_pw_help_msg"
  fi
  rm -f -- "$_pw_help_err"
  if [[ -n "${_pw_probe_dir:-}" && "$_pw_probe_dir" != "$work" ]]; then rm -rf -- "$_pw_probe_dir"; fi
  # Serve the fixture over http (module scripts and fetch do not run on file://).
  # The CLI writes .playwright-cli/ into the cwd, so run it from inside the
  # temp dir to keep the repo clean.
  # Q-1 redo (2026-11-10; FIX2-VERIFY-A base, FIX2-VERIFY-B spec pass):
  # the old code did `sleep 1` and then ran the CLI once, discarding ALL
  # of its output (>/dev/null 2>&1 on every command). The eyes step failed
  # 5/14 runs on a working loop (w-qc-lead Q-1) with zero diagnostic — the
  # session vanished between `open` and `resize` (reproduced 2/8 by B with
  # output preserved: open exit 0, then resize "The browser 'verify' is
  # not open"). Root cause undetermined (daemon stderr empty — truncated
  # on each daemon start) — see w-fix2-verify-b.md §4. Behaviour now:
  # (a) AT MOST 2 attempts; each attempt gets a FRESH session
  # (-s=verify-<pid>-a<N>, never reused across runs or attempts), a FRESH
  # port and a FRESH http server, so a dead session/port cannot poison
  # the retry; (b) the server is waited on (raw TCP connect poll, up to
  # 10 s — no proxy involved, no fixed `sleep 1`); (c) every eyes command
  # writes stdout+stderr to $work/eyes-attempt-N.log (nothing is
  # discarded), and on final failure ALL attempt logs print to stderr,
  # so a failure carries its diagnostic; (d) the fixture ships a real
  # favicon.ico, killing the deterministic favicon 404 console error.
  shot="$work/shot-390.png"
  eyes_ok=0
  eyes_browser=""
  eyes_attempts=0
  eyes_session=""
  eyes_port=""
  _server_pid=""
  # The CLI's default `open` wants system Google Chrome (/opt/google/chrome).
  # The kit installs chrome-for-testing via `playwright-cli install-browser`,
  # reached as --browser=chromium — try that first, then the default.
  for _attempt in 1 2; do
    eyes_attempts="$_attempt"
    _session="verify-$$-a$_attempt"
    _log="$work/eyes-attempt-$_attempt.log"
    rm -f -- "$shot"
    : > "$_log"
    # Fresh port + fresh server per attempt (Q-1: never the same dead session/port).
    _port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    eyes_port="$_port"
    python3 -m http.server "$_port" --bind 127.0.0.1 --directory "$work" >"$work/eyes-attempt-$_attempt-server.log" 2>&1 &
    _server_pid=$!
    # Wait for the server to answer: raw TCP connect, no proxy involved.
    # Arithmetic loop, not `seq` (GNU coreutils; stock macOS has no seq).
    _server_ready=0
    for ((_i=1; _i<=50; _i++)); do
      if python3 -c 'import socket,sys; s=socket.create_connection(("127.0.0.1",int(sys.argv[1])),timeout=2); s.close()' "$_port" >/dev/null 2>&1; then _server_ready=1; break; fi
      sleep 0.2
    done
    _opened=0
    if [[ "$_server_ready" != 1 ]]; then
      printf 'fixture http server on port %s never answered\n' "$_port" >>"$_log"
    elif (cd "$work" && playwright-cli -s="$_session" open --browser=chromium "http://127.0.0.1:$_port/index.html" >>"$_log" 2>&1); then
      eyes_browser="chromium"; _opened=1
    elif (cd "$work" && playwright-cli -s="$_session" open "http://127.0.0.1:$_port/index.html" >>"$_log" 2>&1); then
      eyes_browser="default (system Chrome)"; _opened=1
    fi
    if [[ "$_opened" == 1 ]]; then
      _ok=1
      (cd "$work" && playwright-cli -s="$_session" resize 390 844 >>"$_log" 2>&1) || _ok=0
      (cd "$work" && playwright-cli -s="$_session" screenshot --filename="$shot" >>"$_log" 2>&1) || _ok=0
      if [[ "$_ok" == 1 && -s "$shot" ]]; then eyes_ok=1; eyes_session="$_session"; break; fi
      printf 'eyes attempt %s failed (open/resize/screenshot); retrying with a fresh session/port\n' "$_attempt" >&2
    else
      printf 'eyes attempt %s failed (server/open); retrying with a fresh session/port\n' "$_attempt" >&2
    fi
    (cd "$work" && playwright-cli -s="$_session" close-all >>"$_log" 2>&1) || true
    kill "$_server_pid" 2>/dev/null || true
    wait "$_server_pid" 2>/dev/null || true
    _server_pid=""
  done
  if [[ "$eyes_ok" == 1 ]]; then
    if [[ "$eyes_attempts" -gt 1 ]]; then
      ok "headless screenshot at 390px succeeds via $eyes_browser ($(stat -c%s "$shot" 2>/dev/null || stat -f%z "$shot") bytes) — after $eyes_attempts attempt(s) (Q-1 retry: first attempt(s) flaked)"
    else
      ok "headless screenshot at 390px succeeds via $eyes_browser ($(stat -c%s "$shot" 2>/dev/null || stat -f%z "$shot") bytes)"
    fi
    (cd "$work" && playwright-cli -s="$eyes_session" console >/dev/null 2>&1) && ok "playwright-cli console runs" || warn "playwright-cli console failed (non-fatal)"
    (cd "$work" && playwright-cli -s="$eyes_session" close-all >/dev/null 2>&1) || true
  else
    fail "Playwright screenshot at 390px failed after $eyes_attempts attempt(s) (open/resize/screenshot; fresh session+port each attempt — last port $eyes_port). The eyes step is broken — see A7: do not grade blind. CLI output from all attempts:"
    for ((_a=1; _a<=eyes_attempts; _a++)); do
      printf -- '--- eyes attempt %s CLI log ---\n' "$_a" >&2
      cat "$work/eyes-attempt-$_a.log" >&2 || true
      if [[ -s "$work/eyes-attempt-$_a-server.log" ]]; then
        printf -- '--- eyes attempt %s http-server log ---\n' "$_a" >&2
        cat "$work/eyes-attempt-$_a-server.log" >&2 || true
      fi
    done
  fi
  # Cleanup: the success path still has its server running here (failed
  # attempts killed theirs inside the loop); _server_pid is empty then.
  if [[ -n "$_server_pid" ]]; then kill "$_server_pid" 2>/dev/null || true; wait "$_server_pid" 2>/dev/null || true; fi
else
  if [[ "$strict" == 1 ]]; then
    fail "playwright-cli not on PATH. --strict: this is fatal. Install the pinned CLI: npm install -g @playwright/cli@0.1.24, then playwright-cli install-browser chrome-for-testing"
  else
    unverified "playwright-cli not on PATH — eyes step not verified. Install the pinned CLI: npm install -g @playwright/cli@0.1.24, then playwright-cli install-browser chrome-for-testing"
  fi
fi
# Restore PATH (red-team H7) — see the resolve block above. L2:
# sentinel-guarded, so an empty original PATH restores as empty,
# not as unset. The EXIT trap set in the resolve block is the
# backstop for an early exit; this is the normal path.
if [[ -n "${_pw_saved_path_set:-}" ]]; then PATH="$_pw_saved_path"; hash -r; fi
# M-B: unset the EXIT trap now that PATH is restored sequentially —
# the restore above ran BEFORE this unset, so the unset cannot break
# it. No trap is re-armed: $work is not used past this point (§7–§9
# use $refs_dir/$state_dir only — do NOT use $work below here), so it
# is removed eagerly instead of leaving a trap behind.
trap - EXIT
if [[ -n "${work:-}" ]]; then rm -rf -- "$work" 2>/dev/null || printf 'WARNING: could not remove temp work dir %s (leaked).\n' "$work" >&2; fi

# --- 7. Pro Max search smoke (v1 behaviour kept) -----------------------------
if [[ -f "$refs_dir/ui-ux-pro-max/scripts/search.py" ]]; then
  if python3 "$refs_dir/ui-ux-pro-max/scripts/search.py" 'editorial portfolio' --domain style --max-results 1 2>/dev/null | grep -q 'Result 1'; then
    ok "Pro Max search smoke test"
  else
    warn "Pro Max search smoke test did not return 'Result 1' (reference data may be the stale v1 pin)"
  fi
else
  warn "Pro Max reference data not installed ($refs_dir/ui-ux-pro-max/scripts/search.py missing)"
fi

# --- 8. hook / MCP presence (H5/H6) -----------------------------------------
# A skipped or failed best-effort subsystem must be VISIBLE here, never
# silent. Two sources, both reported as PENDING (never a failure — these
# are best-effort subsystems, not loop steps — and never an OK for a
# subsystem that is not there):
#   (a) install.sh records every --skip-* flag in
#       $state_dir/skipped-subsystems.txt (one line per subsystem);
#   (b) live presence: the host's ACTUAL config must contain the
#       registration. An `mcp add` that exited 0 without writing anything
#       (H6 stub-claude repro) leaves no entry here, so it is PENDING,
#       not OK. Where no readable config exists at all, that is reported
#       as PENDING with the reason, not assumed.
if [[ -f "$state_dir/skipped-subsystems.txt" ]]; then
  while IFS= read -r _sk || [[ -n "$_sk" ]]; do
    [[ -z "$_sk" ]] && continue
    case "$_sk" in
      hooks) pending_msg "subsystem skipped at install: Impeccable hook (--skip-hooks) — run: npx --yes impeccable@4.8.2 install --providers=claude,codex --scope=global (accept the hook, then restart the host)" ;;
      mcp)   pending_msg "subsystem skipped at install: Playwright MCP (--skip-mcp) — run per host, e.g. Claude Code: claude mcp add --scope user playwright -- npx -y @playwright/mcp@0.0.85" ;;
      eyes)  pending_msg "subsystem skipped at install: Playwright CLI + browser (--skip-eyes) — run: npm install -g @playwright/cli@0.1.24, then playwright-cli install-browser chrome-for-testing" ;;
      *)     pending_msg "subsystem skipped at install: $_sk" ;;
    esac
  done < "$state_dir/skipped-subsystems.txt"
fi
# Live presence checks, per host actually checked (HOSTS). Hosts with no
# verified MCP/hook path (muse, cmd, copilot) are not checked and not
# reported — there is nothing to read back there.
mcp_config_for_host() { # <host> — prints the config file path, or nothing
  case "$1" in
    claude)   printf '%s\n%s\n' "$user_home/.claude.json" "$user_home/.claude/settings.json" ;;
    codex)    printf '%s' "$user_home/.codex/config.toml" ;;
    opencode) printf '%s' "$user_home/.config/opencode/opencode.json" ;;
    gemini)   printf '%s' "$user_home/.gemini/settings.json" ;;
  esac
}
mcp_manual_for_host() { # <host>
  case "$1" in
    claude)   printf '%s' "claude mcp add --scope user playwright -- npx -y @playwright/mcp@0.0.85" ;;
    codex)    printf '%s' "codex mcp add playwright -- npx -y @playwright/mcp@0.0.85" ;;
    opencode) printf '%s' "opencode mcp add playwright --global -- npx -y @playwright/mcp@0.0.85" ;;
    gemini)   printf '%s' "gemini mcp add --scope user playwright npx -y @playwright/mcp@0.0.85" ;;
  esac
}
hook_config_for_host() { # <host> — prints candidate hook-manifest paths
  # Hermes is NOT listed here: it is checked via `hermes plugins list`
  # in the hook loop below (S4 — directory presence is not verification).
  case "$1" in
    claude)   printf '%s\n%s\n' "$user_home/.claude/settings.json" "$user_home/.claude/settings.local.json" ;;
    # The project path is a fallback candidate only: install.sh promotes
    # the upstream installer's project hook to the global file, so a
    # fresh install has the global one. A project-only hook is reported
    # as PENDING (S3), never as wired; both present is warned (M2).
    codex)    printf '%s\n%s\n%s\n' "$user_home/.codex/hooks.json" "$user_home/.codex/config.toml" "$root/.codex/hooks.json" ;;
  esac
}
hook_manual_for_host() { # <host> — the exact manual command for that host
  case "$1" in
    hermes) printf '%s' "hermes plugins enable --no-allow-tool-override impeccable-design-hook" ;;
    *)      printf '%s' "npx --yes impeccable@4.8.2 install --providers=$1 --scope=global (accept the hook, then restart the host)" ;;
  esac
}
for host in "${HOSTS[@]}"; do
  # Playwright MCP presence (H5/H6).
  if _mc="$(mcp_config_for_host "$host")" && [[ -n "$_mc" ]]; then
    _mcp_found=0; _mcp_seen=0
    while IFS= read -r _cf || [[ -n "$_cf" ]]; do
      [[ -f "$_cf" ]] || continue
      _mcp_seen=1
      grep -qi 'playwright' "$_cf" && _mcp_found=1
    done <<< "$_mc"
    if [[ "$_mcp_found" == 1 ]]; then
      ok "Playwright MCP registered for $host (playwright entry in host config)"
    elif [[ "$_mcp_seen" == 1 ]]; then
      pending_msg "Playwright MCP NOT registered for $host (host config exists but has no playwright entry — nothing was registered there, whether the add failed silently or was never attempted; H6). Run: $(mcp_manual_for_host "$host")"
    else
      pending_msg "Playwright MCP presence not verifiable for $host (no readable host config at $(printf '%s' "$_mc" | tr '\n' ' ') — nothing was registered there, or the host was never configured). Run: $(mcp_manual_for_host "$host")"
    fi
  fi
  # Impeccable hook presence (H5/H6).
  # Hermes is checked via `hermes plugins list`, not directory presence
  # (S4): install.sh copies the plugin there, so `ls` succeeds by
  # construction even if the plugin is disabled. The "not enabled" row
  # contains the word "enabled", so exclude it first.
  if [[ "$host" == hermes ]]; then
    if command -v hermes >/dev/null 2>&1; then
      if hermes plugins list 2>/dev/null | grep -i 'impeccable' | grep -vi 'not enabled' | grep -qi 'enabled'; then
        ok "Impeccable hook wired for hermes (plugin listed as enabled)"
      elif ls "$user_home/.hermes/plugins" 2>/dev/null | grep -qi 'impeccable'; then
        pending_msg "Impeccable hook NOT wired for hermes (plugin is installed under ~/.hermes/plugins but not listed as enabled). Run: hermes plugins enable --no-allow-tool-override impeccable-design-hook"
      else
        pending_msg "Impeccable hook NOT wired for hermes (no impeccable plugin under ~/.hermes/plugins). Run: cp -r $root/vendor/impeccable/skill/hermes-plugin ~/.hermes/plugins/impeccable-design-hook, then hermes plugins enable --no-allow-tool-override impeccable-design-hook"
      fi
    else
      pending_msg "Impeccable hook presence not verifiable for hermes (hermes not on PATH). Run: hermes plugins enable --no-allow-tool-override impeccable-design-hook"
    fi
  elif _hc="$(hook_config_for_host "$host")" && [[ -n "$_hc" ]]; then
    _hook_found=0; _hook_seen=0; _hook_file=""; _hook_project=0
    while IFS= read -r _hf || [[ -n "$_hf" ]]; do
      if [[ -d "$_hf" ]]; then
        _hook_seen=1
        if ls "$_hf" 2>/dev/null | grep -qi 'impeccable'; then _hook_found=1; [[ -z "$_hook_file" ]] && _hook_file="$_hf"; fi
      elif [[ -f "$_hf" ]]; then
        _hook_seen=1
        if grep -qi 'impeccable' "$_hf"; then
          _hook_found=1; [[ -z "$_hook_file" ]] && _hook_file="$_hf"
          [[ "$_hf" == "$root/.codex/hooks.json" ]] && _hook_project=1
        fi
      fi
    done <<< "$_hc"
    if [[ "$_hook_found" == 1 ]]; then
      if [[ "$_hook_file" == "$root/.codex/hooks.json" ]]; then
        # S3: a project-only hook is NOT "wired" — it does not fire in
        # the user's real projects and needs trust + /hooks approval.
        # The install asked for --scope=global, so this is PENDING.
        pending_msg "Impeccable hook for $host is project-scoped only ($root/.codex/hooks.json — fires only when codex runs in that repo, after trust + /hooks approval). Promote it: cp $root/.codex/hooks.json ~/.codex/hooks.json (or re-run ./install.sh)."
      else
        ok "Impeccable hook wired for $host (impeccable entry in host hook config)"
        # M2: a project copy alongside the global one means codex fires
        # the hook twice in this repo — surface it, don't hide it.
        if [[ "$_hook_project" == 1 ]]; then
          warn "Duplicate Codex hook: $root/.codex/hooks.json also contains an impeccable entry — codex will fire the hook twice in this repo; remove the project copy (the global ~/.codex/hooks.json already covers it)."
        fi
      fi
    elif [[ "$_hook_seen" == 1 ]]; then
      pending_msg "Impeccable hook NOT wired for $host (host hook config exists but has no impeccable entry). Run: $(hook_manual_for_host "$host")"
    else
      pending_msg "Impeccable hook presence not verifiable for $host (no readable hook config at $(printf '%s' "$_hc" | tr '\n' ' ') — nothing was registered there). Run: $(hook_manual_for_host "$host")"
    fi
  fi
done

# --- 9. Node 22+ and system Chrome (H14) --------------------------------------
# ONE number, everywhere: Node 22+. The orchestrator (frontend-kit SKILL.md
# step 0.3) and consistency.mjs (built-in WebSocket, no npm deps) both
# require Node 22+; install.sh used to say "Node 18+" in its warnings and
# neither script checked anything, so a Node 18/20 machine installed
# cleanly and the step-3 gate then failed opaquely at runtime. A present
# but too-old Node is a hard FAIL here (the gate cannot run on it); a
# missing Node is UNVERIFIED (the loop step cannot be proven).
if command -v node >/dev/null 2>&1; then
  node_ver="$(node --version 2>/dev/null || echo '')"
  node_major="${node_ver#v}"; node_major="${node_major%%.*}"
  if [[ "$node_major" =~ ^[0-9]+$ ]] && [[ "10#$node_major" -ge 22 ]]; then
    ok "Node $node_ver (>= 22 — the kit's single required version)"
  elif [[ "$node_major" =~ ^[0-9]+$ ]]; then
    fail "Node $node_ver found; the kit requires Node 22+ (frontend-kit SKILL.md step 0.3; gate.mjs consistency.mjs needs the built-in WebSocket). Install Node 22+ — a Node $node_major machine installs cleanly but its step-3 gate fails at runtime."
  else
    unverified "node --version gave an unparseable result ('$node_ver') — cannot confirm Node 22+"
  fi
else
  unverified "node not found on PATH — gate.mjs and run-log.mjs cannot run. Install Node 22+."
fi
# System Chrome: consistency.mjs drives headless system Chrome via CDP.
# Its absence does NOT fail this verifier — the eyes step uses Playwright's
# chrome-for-testing instead — but it must be REPORTED, not discovered
# later when the browser leg fails: without system Chrome, gate.mjs must
# run with --skip-browser, which fails closed (H13), and the browser leg
# is skipped, not passed.
chrome_bin=""
for _cb in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$_cb" >/dev/null 2>&1; then chrome_bin="$(command -v "$_cb")"; break; fi
done
[[ -z "$chrome_bin" && -x /opt/google/chrome/chrome ]] && chrome_bin="/opt/google/chrome/chrome"
# macOS app-bundle locations (mirror skills/frontend-kit/scripts/gate/consistency.mjs
# findChrome, which already lists these before the Linux paths).
for _cp in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Chromium.app/Contents/MacOS/Chromium" "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "$HOME/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  if [[ -z "$chrome_bin" && -x "$_cp" ]]; then chrome_bin="$_cp"; break; fi
done
if [[ -n "$chrome_bin" ]]; then
  ok "system Chrome present ($chrome_bin) — gate.mjs consistency leg can run"
else
  warn "no system Chrome found (looked for google-chrome, google-chrome-stable, chromium, chromium-browser on PATH, /opt/google/chrome/chrome, and the macOS app bundles /Applications/Google Chrome.app, /Applications/Chromium.app, \$HOME/Applications/…) — gate.mjs consistency.mjs browser leg cannot run here; use --skip-browser (which fails closed, H13), and note the browser leg is SKIPPED, not passed. Playwright eyes are unaffected (they use chrome-for-testing)."
fi

# --- summary ------------------------------------------------------------------
printf '\nverify.sh: %s failure(s), %s unverified step(s), %s warning(s), %s pending item(s).\n' "$fails" "$unverified" "$warns" "$pending"
if [[ "$fails" -gt 0 ]]; then
  printf 'RESULT: FAIL — fix the failures above before relying on the loop.\n' >&2
  printf 'Reminder: skills/MCP/plugins load at session start. If this ran in the install session, restart the host and re-run ./verify.sh --strict in the NEW session.\n' >&2
  exit 1
fi
if [[ "$unverified" -gt 0 ]]; then
  printf 'RESULT: UNVERIFIED — loop not proven (%s step(s) could not run: see UNVERIFIED lines above). Files may be installed, but no loop step may be claimed as passing until these run green.\n' "$unverified" >&2
  printf 'Reminder: skills/MCP/plugins load at session start. If this ran in the install session, restart the host and re-run ./verify.sh --strict in the NEW session.\n' >&2
  exit 1
fi
if [[ "${eyes_skipped:-0}" == 1 ]]; then
  printf 'RESULT: OK — files, engine lockstep, detect and gate all pass (eyes skipped at install — PENDING, see above).\n'
else
  printf 'RESULT: OK — files, engine lockstep, detect, gate and eyes all pass.\n'
fi
printf 'Reminder: restart/reload each host, then re-run ./verify.sh --strict in the NEW session to confirm the skills actually load.\n'
