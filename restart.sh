#!/bin/sh
# restart.sh — build the hive app, package it as an app bundle and restart it. Sessions keep running in the tmux server.
#   sh restart.sh          build + restart
#   sh restart.sh --build  only build and package
# The main app is a release build installed as /Applications/Hive.app (start it via Spotlight or the Dock).
# Notifications need a bundle identifier, hence a local, ad-hoc-signed bundle.
# Test instance alongside the main app (own identifier, doesn't steal its notifications):
#   HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh
set -eu
cd "$(dirname "$0")"
root=$(pwd -P)
appname="${HIVE_APP:-HiveApp}"
id="${HIVE_BUNDLE_ID:-io.github.tbimyr.hive-app}"
title=Hive; [ -z "${HIVE_APP:-}" ] || title="Hive ($appname)"
if [ -z "${HIVE_APP:-}" ]; then
  config=release; app="${HIVE_INSTALL:-/Applications}/Hive.app"
else
  config=debug; app=".build/$appname.app"
fi
case "$app" in /*) exe="$app/Contents/MacOS/HiveApp" ;; *) exe="$root/$app/Contents/MacOS/HiveApp" ;; esac
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build -c "$config" 2>&1 | grep -E "error|warning: unre|Build complete" || true
[ -x ".build/$config/HiveApp" ] || { echo "restart.sh: build missing" >&2; exit 1; }

# Build the bundle next to the old one and then swap: never overwrite the file of a running app
new=".build/new/$appname.app"
rm -rf .build/new
mkdir -p "$new/Contents/MacOS"
cp ".build/$config/HiveApp" "$new/Contents/MacOS/HiveApp"
# macOS picks the look of the window (e.g. the glass title bar from macOS 26) by the SDK version stamped
# into the binary. Newer SwiftPM stamps the deployment target there, so set the SDK that was really used.
sdk=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)
min=$(xcrun vtool -show-build "$new/Contents/MacOS/HiveApp" 2>/dev/null | awk '$1 == "minos" { print $2 }')
if [ -n "$sdk" ] && [ -n "$min" ]; then
  xcrun vtool -set-build-version macos "$min" "$sdk" -replace -output "$new/Contents/MacOS/HiveApp.sdk" "$new/Contents/MacOS/HiveApp" 2>/dev/null \
    && mv "$new/Contents/MacOS/HiveApp.sdk" "$new/Contents/MacOS/HiveApp" || rm -f "$new/Contents/MacOS/HiveApp.sdk"
fi
mkdir -p "$new/Contents/Resources"
cp Resources/AppIcon.icns "$new/Contents/Resources/AppIcon.icns"
cat > "$new/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleName</key><string>$title</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>HiveApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force -s - "$new"
# an mv onto an existing bundle would nest the new one inside it, so remove it first
rm -rf "$app"
mv "$new" "$app"
rmdir .build/new
# so permission prompts and clicking a notification (even with the app quit) can find the bundle
"$lsregister" -f "$app"
# the main app used to live in .build: remove that copy so only one bundle has its identifier
if [ -z "${HIVE_APP:-}" ] && [ -d .build/HiveApp.app ]; then
  old="$root/.build/HiveApp.app"
  pids_old=$(pgrep -f "^$old/Contents/MacOS/HiveApp\$" || true)
  [ -z "$pids_old" ] || kill $pids_old
  "$lsregister" -u "$old" 2>/dev/null || true
  rm -rf "$old"
fi
[ "${1:-}" = "--build" ] && exit 0

# Only quit the app from this folder (pattern anchored at the start). The main app's restart also
# quits the old, relatively started .build/debug/HiveApp; a test instance (HIVE_APP) never does.
pids=$(pgrep -f "^$exe\$" || true)
if [ -z "${HIVE_APP:-}" ]; then
  pids="$pids $(pgrep -f "^$root/\\.build/debug/HiveApp\$" || true)"
  # relatively started ones only if their working directory is this folder
  for p in $(pgrep -f '^\.build/debug/HiveApp$' || true); do
    if [ "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$root" ]; then pids="$pids $p"; fi
  done
fi
pids=$(echo $pids)
[ -z "$pids" ] || kill $pids
sleep 1
nohup "$exe" >/dev/null 2>&1 &
sleep 2
echo "App: PID $(pgrep -f "^$exe\$" || echo 'not running') ($app, $id)"
echo "tmux: $(tmux -L hive ls -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
