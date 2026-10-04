#!/bin/sh
# Compares HiveCore with the Node server (GET /api/state) on real data.
# Without timestamps and error texts (messages from Node and Foundation differ),
# lastAction/lastSentence only exist in Swift, null fields drop out (Swift omits them).
# Sessions that are currently working can change between the two fetches: on a diff just run it again.
set -eu
cd "$(dirname "$0")/.."
norm='del(.generatedAt, .errors) | .sessions |= map(del(.errors, .lastAction, .lastSentence)) | walk(if type == "object" then with_entries(select(.value != null)) else . end)'
tmp=$(mktemp -d)
swift build -q --product hive-state
curl -sf http://127.0.0.1:7777/api/state | jq -S "$norm" > "$tmp/node.json"
.build/debug/hive-state | jq -S "$norm" > "$tmp/swift.json"
if diff -u "$tmp/node.json" "$tmp/swift.json"; then
  echo "same ($(jq '.sessions | length' "$tmp/swift.json") sessions)"
fi
