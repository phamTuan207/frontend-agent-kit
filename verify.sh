#!/usr/bin/env bash
set -euo pipefail

user_home="${HOME:?HOME must be set}"
agent_skills="$user_home/.agents/skills"
opencode_skills="$user_home/.config/opencode/skills"
refs="$user_home/.local/share/agent-design-references"

for name in impeccable gsap-core gsap-timeline gsap-scrolltrigger gsap-plugins gsap-utils gsap-react gsap-performance gsap-frameworks threeui ui-ux-pro-max-reference taste-reference; do
  [[ -f "$agent_skills/$name/SKILL.md" ]] || { printf 'MISSING: %s\n' "$agent_skills/$name/SKILL.md" >&2; exit 1; }
done
[[ -f "$opencode_skills/impeccable/SKILL.md" ]]
[[ -f "$user_home/.config/opencode/commands/impeccable.md" ]]
[[ -f "$refs/ui-ux-pro-max/scripts/search.py" ]]
[[ -f "$refs/taste/SKILL.md" ]]
python3 "$refs/ui-ux-pro-max/scripts/search.py" 'editorial portfolio' --domain style --max-results 1 | grep -q 'Result 1'
printf 'OK: 12 design/reference skills, OpenCode Impeccable command, Pro Max search, Taste reference.\n'
printf 'Codex/OpenCode/CommandCode discover skills after a new session starts.\n'
