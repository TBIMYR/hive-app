#!/bin/sh
# Vergleicht HiveCore mit dem Node-Server (GET /api/state) auf echten Daten.
# Ohne Zeitstempel und Fehlertexte (Meldungen von Node und Foundation unterscheiden sich),
# null-Felder fallen weg (Swift lässt sie aus). Sessions, die gerade arbeiten, können sich
# zwischen den beiden Abrufen ändern: bei einem Unterschied einfach noch einmal laufen lassen.
set -eu
cd "$(dirname "$0")/.."
norm='del(.generatedAt, .errors) | .sessions |= map(del(.errors)) | walk(if type == "object" then with_entries(select(.value != null)) else . end)'
tmp=$(mktemp -d)
swift build -q --product hive-state
curl -sf http://127.0.0.1:7777/api/state | jq -S "$norm" > "$tmp/node.json"
.build/debug/hive-state | jq -S "$norm" > "$tmp/swift.json"
if diff -u "$tmp/node.json" "$tmp/swift.json"; then
  echo "gleich ($(jq '.sessions | length' "$tmp/swift.json") Sessions)"
fi
