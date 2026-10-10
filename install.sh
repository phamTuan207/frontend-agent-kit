#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: ./install.sh [--no-warm]' '' 'Installs global skills for Codex, OpenCode and CommandCode on Linux.' 'Existing copies are moved to a dated backup in ~/.local/share/frontend-agent-kit/backups.' '--no-warm skips the first-run Impeccable engine download.'
  exit 0
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--no-warm" ) ]]; then
  printf 'Unknown argument. Run ./install.sh --help\n' >&2
  exit 2
fi
if [[ "$(uname -s)" != Linux ]]; then
  printf 'This package currently supports Linux only.\n' >&2
  exit 2
fi
for tool in cp mv mkdir date python3; do
  command -v "$tool" >/dev/null || { printf 'Missing command: %s\n' "$tool" >&2; exit 2; }
done

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
user_home="${HOME:?HOME must be set}"
backup="$user_home/.local/share/frontend-agent-kit/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
agent_skills="$user_home/.agents/skills"
opencode_skills="$user_home/.config/opencode/skills"
refs="$user_home/.local/share/agent-design-references"

install_dir() {
  local source="$1" target="$2" relative
  [[ -d "$source" ]] || { printf 'Missing package directory: %s\n' "$source" >&2; exit 1; }
  mkdir -p "$(dirname -- "$target")"
  if [[ -e "$target" || -L "$target" ]]; then
    relative="${target#"$user_home"/}"
    mkdir -p "$backup/$(dirname -- "$relative")"
    mv -- "$target" "$backup/$relative"
  fi
  cp -a -- "$source" "$target"
  printf 'Installed %s\n' "$target"
}

install_file() {
  local source="$1" target="$2" relative
  mkdir -p "$(dirname -- "$target")"
  if [[ -e "$target" || -L "$target" ]]; then
    relative="${target#"$user_home"/}"
    mkdir -p "$backup/$(dirname -- "$relative")"
    mv -- "$target" "$backup/$relative"
  fi
  cp -a -- "$source" "$target"
  printf 'Installed %s\n' "$target"
}

install_dir "$root/vendor/impeccable/codex-skill" "$agent_skills/impeccable"
install_dir "$root/vendor/impeccable/opencode-skill" "$opencode_skills/impeccable"
install_file "$root/opencode/commands/impeccable.md" "$user_home/.config/opencode/commands/impeccable.md"

for name in gsap-core gsap-timeline gsap-scrolltrigger gsap-plugins gsap-utils gsap-react gsap-performance gsap-frameworks; do
  install_dir "$root/vendor/gsap/$name" "$agent_skills/$name"
done
for name in threeui ui-ux-pro-max-reference taste-reference; do
  install_dir "$root/skills/$name" "$agent_skills/$name"
done
install_dir "$root/vendor/ui-ux-pro-max/reference" "$refs/ui-ux-pro-max"
install_dir "$root/vendor/taste/reference" "$refs/taste"

printf '\nChecking installed files...\n'
"$root/verify.sh"
if [[ "${1:-}" != "--no-warm" ]]; then
  printf '\nPreparing Impeccable engine for this Linux machine...\n'
  if ! "$agent_skills/impeccable/scripts/impeccable" engine-probe; then
    printf 'Impeccable engine download failed. The skills are installed; retry the launcher when network is available.\n' >&2
  fi
fi
printf '\nDone. Existing copies, if any, are backed up in %s\n' "$backup"
printf 'Open a new Codex/OpenCode/CommandCode session to load the skills.\n'
