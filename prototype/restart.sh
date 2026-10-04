#!/bin/sh
# restart.sh — build and restart the hive app. Sessions keep running in the tmux server.
#   sh prototype/restart.sh          build + restart
#   sh prototype/restart.sh --build  build only
set -eu
cd "$(dirname "$0")"

swift build 2>&1 | grep -E "error|warning: unre|Build complete" || true
[ -x .build/debug/HiveApp ] || { echo "restart.sh: build missing" >&2; exit 1; }
[ "${1:-}" = "--build" ] && exit 0

pid=$(pgrep -f '\.build/debug/HiveApp$' || true)
[ -z "$pid" ] || kill $pid
sleep 1
nohup .build/debug/HiveApp >/dev/null 2>&1 &
sleep 2
echo "App: PID $(pgrep -f '\.build/debug/HiveApp$' || echo 'not running')"
echo "tmux: $(tmux -L hive ls -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
