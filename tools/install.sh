#!/bin/sh
# install.sh — links bin/ and skills/ into ~/.claude, registers the hook,
# extends the global CLAUDE.md. Idempotent.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
home="${CC_HOME:-$HOME/.claude}"
settings="$home/settings.json"
claude_md="$home/CLAUDE.md"

mkdir -p "$home/bin" "$home/handover" "$home/skills"
# a fresh Claude Code install may not have a settings file yet
[ -f "$settings" ] || echo '{}' > "$settings"

for b in cc-task cc-handover-load cc-spawn cc-close cc-note; do
  chmod +x "$here/bin/$b"
  ln -sfn "$here/bin/$b" "$home/bin/$b"
  echo "bin: $home/bin/$b -> $here/bin/$b"
done
for s in status handover; do
  ln -sfn "$here/skills/$s" "$home/skills/$s"
  echo "skill: $home/skills/$s"
done

hook_cmd="$home/bin/cc-handover-load"
if [ -f "$settings" ]; then
  if ! jq -e --arg c "$hook_cmd" '[.hooks.SessionStart[]?.hooks[]?.command, .hooks.UserPromptSubmit[]?.hooks[]?.command] | index($c)' "$settings" >/dev/null 2>&1; then
    cp "$settings" "$settings.bak-$(date +%Y%m%d-%H%M%S)"
    tmp=$(mktemp)
    jq --arg c "$hook_cmd" '
      .hooks.SessionStart = ((.hooks.SessionStart // []) + [{"hooks":[{"type":"command","command":$c}]}]) |
      .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":$c}]}])
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    echo "hook: registered in $settings (SessionStart + UserPromptSubmit)"
  else
    echo "hook: already registered"
  fi
else
  echo "hook: $settings missing, not registered" >&2
fi

if ! grep -qE '^# Session[- ][Ss]tatus' "$claude_md" 2>/dev/null; then
  { printf '\n'; cat "$here/../docs/claude-md-session-status.md"; } >> "$claude_md"
  echo "CLAUDE.md: session status section appended"
else
  echo "CLAUDE.md: section already present"
fi
