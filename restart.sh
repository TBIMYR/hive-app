#!/bin/sh
# restart.sh — hive-App bauen, als App-Paket verpacken und neu starten. Die Sessions laufen im tmux-Server weiter.
#   sh restart.sh          bauen + neu starten
#   sh restart.sh --build  nur bauen und verpacken
# Mitteilungen brauchen eine Bundle-Kennung, darum ein lokales, ad-hoc-signiertes Paket.
# Testinstanz neben der Haupt-App (eigene Kennung, nimmt ihr keine Mitteilungen weg):
#   HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh
set -eu
cd "$(dirname "$0")"
root=$(pwd -P)
appname="${HIVE_APP:-HiveApp}"
id="${HIVE_BUNDLE_ID:-io.github.tbimyr.hive-app}"
title=hive; [ -z "${HIVE_APP:-}" ] || title="hive ($appname)"
app=".build/$appname.app"
exe="$root/$app/Contents/MacOS/HiveApp"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build 2>&1 | grep -E "error|warning: unre|Build complete" || true
[ -x .build/debug/HiveApp ] || { echo "restart.sh: Build fehlt" >&2; exit 1; }

# Paket daneben bauen und dann tauschen: nie die Datei einer laufenden App überschreiben
new=".build/new/$appname.app"
rm -rf .build/new
mkdir -p "$new/Contents/MacOS"
cp .build/debug/HiveApp "$new/Contents/MacOS/HiveApp"
cat > "$new/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$title</string>
  <key>CFBundleExecutable</key><string>HiveApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force -s - "$new"
# ein mv auf ein vorhandenes Paket würde das neue hineinlegen, darum erst weg damit
rm -rf "$app"
mv "$new" "$app"
rmdir .build/new
# damit Erlaubnis und Klick auf eine Mitteilung (auch bei beendeter App) das Paket finden
"$lsregister" -f "$app"
[ "${1:-}" = "--build" ] && exit 0

# Nur die App aus diesem Ordner beenden (Muster am Anfang verankert). Die Haupt-App beendet im
# Übergang auch die alte, relativ gestartete .build/debug/HiveApp; eine Testinstanz (HIVE_APP) nie.
pids=$(pgrep -f "^$exe\$" || true)
if [ -z "${HIVE_APP:-}" ]; then
  pids="$pids $(pgrep -f "^$root/\\.build/debug/HiveApp\$" || true)"
  # relativ gestartete nur, wenn ihr Arbeitsordner dieser Ordner ist
  for p in $(pgrep -f '^\.build/debug/HiveApp$' || true); do
    if [ "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$root" ]; then pids="$pids $p"; fi
  done
fi
pids=$(echo $pids)
[ -z "$pids" ] || kill $pids
sleep 1
nohup "$exe" >/dev/null 2>&1 &
sleep 2
echo "App: PID $(pgrep -f "^$exe\$" || echo 'läuft nicht') ($app, $id)"
echo "tmux: $(tmux -L hive ls -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
