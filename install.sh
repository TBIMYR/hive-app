#!/bin/sh
# install.sh [--launchd] — verlinkt bin/ und skills/ nach ~/.claude, trägt den Hook ein,
# ergänzt die globale CLAUDE.md. Idempotent.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
home="${CC_HOME:-$HOME/.claude}"
settings="$home/settings.json"
claude_md="$home/CLAUDE.md"

mkdir -p "$home/bin" "$home/handover" "$home/skills"

for b in cc-task cc-handover-load; do
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
    echo "hook: eingetragen in $settings (SessionStart + UserPromptSubmit)"
  else
    echo "hook: bereits eingetragen"
  fi
else
  echo "hook: $settings fehlt, nicht eingetragen" >&2
fi

if ! grep -q '^# Session-Status' "$claude_md" 2>/dev/null; then
  cat >> "$claude_md" <<'EOF'

# Session-Status

- Sessions immer mit `claude -n <name>` starten (z. B. `lu.pm`, `lu.01`); der Name ist der Schlüssel für Dashboard und Handover.
- Aufgaben-Zeile selbst setzen bei Auftragsannahme, bei einem Blocker und bei Abschluss: `~/.claude/bin/cc-task "<eine Zeile>" <working|blocked|done>` direkt per Bash, NICHT über den Skill `/status`. Den Aufruf parallel im selben Schritt wie einen ohnehin anstehenden Tool-Aufruf abschicken (z. B. mit dem ersten Read/Bash eines Auftrags oder mit der letzten Aktion davor), damit keine zusätzliche Modell-Anfrage entsteht.
- `/handover` vor jedem geplanten Ende oder Neustart. Die Nachfolger-Session mit demselben Namen liest es beim Start automatisch.
- Die PM-Session darf `~/.claude/handover/<name>.md` der Worker jederzeit lesen, statt sie zu fragen.
EOF
  echo "CLAUDE.md: Abschnitt Session-Status angehängt"
else
  echo "CLAUDE.md: Abschnitt vorhanden"
fi

if [ "${1:-}" = "--launchd" ]; then
  plist="$HOME/Library/LaunchAgents/io.github.tbimyr.hive.plist"
  sed -e "s|__NODE__|$(command -v node)|g" -e "s|__DIR__|$here|g" "$here/launchd/io.github.tbimyr.hive.plist.template" > "$plist"
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
  echo "launchd: $plist geladen, http://127.0.0.1:7777"
fi
