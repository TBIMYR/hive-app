#!/bin/sh
# restart.sh — hive-App bauen und neu starten. Die Sessions laufen im tmux-Server weiter.
#   sh restart.sh          bauen + neu starten
#   sh restart.sh --build  nur bauen
set -eu
cd "$(dirname "$0")"

swift build 2>&1 | grep -E "error|warning: unre|Build complete" || true
[ -x .build/debug/HiveApp ] || { echo "restart.sh: Build fehlt" >&2; exit 1; }
[ "${1:-}" = "--build" ] && exit 0

pid=$(pgrep -f '\.build/debug/HiveApp$' || true)
[ -z "$pid" ] || kill $pid
sleep 1
nohup .build/debug/HiveApp >/dev/null 2>&1 &
sleep 2
echo "App: PID $(pgrep -f '\.build/debug/HiveApp$' || echo 'läuft nicht')"
echo "tmux: $(tmux -L hive ls -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
