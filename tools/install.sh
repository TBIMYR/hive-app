#!/bin/sh
# install.sh [--launchd] — links bin/ and skills/ into ~/.claude, registers the hook,
# extends the global CLAUDE.md. Idempotent.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
home="${CC_HOME:-$HOME/.claude}"
settings="$home/settings.json"
claude_md="$home/CLAUDE.md"

mkdir -p "$home/bin" "$home/handover" "$home/skills"

for b in cc-task cc-handover-load cc-spawn cc-close; do
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

if ! grep -q '^# Session-Status' "$claude_md" 2>/dev/null; then
  { printf '\n'; cat "$here/docs/claude-md-session-status.md"; } >> "$claude_md"
  echo "CLAUDE.md: Session-Status section appended"
else
  echo "CLAUDE.md: section already present"
fi

if [ "${1:-}" = "--launchd" ]; then
  plist="$HOME/Library/LaunchAgents/io.github.tbimyr.hive.plist"
  sed -e "s|__NODE__|$(command -v node)|g" -e "s|__DIR__|$here|g" "$here/launchd/io.github.tbimyr.hive.plist.template" > "$plist"
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
  echo "launchd: $plist loaded, http://127.0.0.1:7777"
fi
