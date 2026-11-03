#!/bin/sh
# hive-voice.sh — voice prototype for Hive: build, wrap in a small app bundle (so macOS asks for the microphone
# and speech recognition for this app) and start it. The log goes to this terminal; Ctrl-C or ⌃⌥Q quits.
#   sh tools/voice/hive-voice.sh                     ElevenLabs (falls back to the macOS voice without a key)
#   sh tools/voice/hive-voice.sh --output apple      macOS voice
#   sh tools/voice/hive-voice.sh --text              type instead of talking (no microphone)
#   sh tools/voice/hive-voice.sh --names             how the voice says each session; own names in
#                                                    ~/.config/hive-voice/names.json, e.g. {"lu": "Luna", "or.pm": "Chefin"}
# More options: --model sonnet, --voice-id <ElevenLabs voice>, --eleven-model <model>.
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd -P)
swift build --product hive-voice 2>&1 | grep -E "error|Build complete" || true
[ -x .build/debug/hive-voice ] || { echo "hive-voice.sh: build missing" >&2; exit 1; }

app="$root/.build/HiveVoice.app"
mkdir -p "$app/Contents/MacOS"
cp .build/debug/hive-voice "$app/Contents/MacOS/hive-voice"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.tbimyr.hive-voice</string>
  <key>CFBundleName</key><string>Hive Voice</string>
  <key>CFBundleExecutable</key><string>hive-voice</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Push to talk: Hive Voice listens while you hold the hotkey.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Your speech is transcribed on this Mac.</string>
</dict></plist>
EOF
codesign --force --sign - "$app" >/dev/null 2>&1

case " $* " in
  *" --text "*|*" --names "*) exec "$app/Contents/MacOS/hive-voice" "$@" ;;   # stdin must stay with this terminal
esac
tty=$(tty)
trap 'pkill -f "$app/Contents/MacOS/hive-voice" || true' INT TERM
open -W -n --stdout "$tty" --stderr "$tty" "$app" --args "$@"
