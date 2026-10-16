#!/bin/sh
# demo.sh — a second app instance with made-up sessions, for screenshots. Nothing of it touches the real
# sessions: own home folder (HIVE_HOME), own tmux server (HIVE_TMUX), own bundle identifier.
#   sh scripts/demo.sh          write the demo data and start "Hive (HiveApp-demo)"; every terminal is staged text
#   sh scripts/demo.sh claude   the same, but lu.01 runs a real Claude Code in a small sample project (uses your
#                               login and tokens; its transcript is kept in your real ~/.claude/projects)
#   sh scripts/demo.sh stop     quit it, stop its tmux server and remove the data
set -eu
cd "$(dirname "$0")/.."
root=$(pwd -P)
appname=HiveApp-demo
id=io.github.tbimyr.hive-app.demo
socket=hive-demo
# under /tmp, so no path in a screenshot carries a user name
demo=/private/tmp/hive-demo
claude="$demo/.claude"
dev="$demo/Development"
exe="$root/.build/$appname.app/Contents/MacOS/HiveApp"
tmux_bin=$(command -v tmux || echo /opt/homebrew/bin/tmux)
conf="$HOME/Library/Application Support/hive/tmux.conf"
# Variables of a calling Claude or hive session must not leak into the demo (same as in cc-spawn)
unset_args=""
for k in $(env | sed -nE 's/^(CLAUDE[A-Za-z0-9_]*|AI_AGENT|TMUX|TMUX_PANE|HIVE_[A-Z_]*|CC_[A-Z_]*)=.*/\1/p'); do
  unset_args="$unset_args -u $k"
done
T() {
  if [ -f "$conf" ]; then env $unset_args "$tmux_bin" -L "$socket" -f "$conf" "$@"
  else env $unset_args "$tmux_bin" -L "$socket" "$@"; fi
}

stop() {
  pids=$(pgrep -f "^$exe\$" || true)
  [ -z "$pids" ] || kill $pids
  T kill-server 2>/dev/null || true
  rm -rf "$demo"
}

if [ "${1:-}" = "stop" ]; then
  stop
  defaults delete "$id" 2>/dev/null || true
  echo "demo.sh: stopped"
  exit 0
fi

real=""; [ "${1:-}" != "claude" ] || real=1
stop
mkdir -p "$claude/sessions" "$claude/handover" "$claude/projects" "$claude/project-info" \
  "$claude/hive/context" "$claude/hive/notes" "$demo/term"
for p in lumen orbit fjord kiosk; do mkdir -p "$dev/$p"; done

now=$(date +%s)
ago() { date -u -v"-$1"M '+%Y-%m-%dT%H:%M:%S.000Z'; }   # ISO time, minutes ago
n=0

# session NAME PROJECT STATUS MINUTES_SINCE_STATUS CONTEXT_PERCENT [WAITING_FOR]
# starts a tmux session that shows $demo/term/NAME.txt and registers its process like Claude Code does
session() {
  name=$1; cwd="$dev/$2"; sid="demo-$(echo "$1" | tr . -)"
  T new-session -d -s "$name" -x 110 -y 40 -c "$cwd" "clear; cat '$demo/term/$name.txt'; exec sleep 864000"
  info=$(T display-message -p -t "=$name:" '#{window_id}.#{pane_id} #{pane_pid}')
  pid=${info#* }
  waiting=""; [ -z "${6:-}" ] || waiting=",\"waitingFor\":\"$6\""
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":%s000,"name":"%s","nameSource":"user","status":"%s","statusUpdatedAt":%s000,"tmux":"%s:%s"%s}\n' \
    "$pid" "$sid" "$cwd" "$((now - 7200))" "$name" "$3" "$((now - $4 * 60))" "$name" "${info% *}" "$waiting" \
    > "$claude/sessions/$pid.json"
  printf '{"used_percentage":%s,"written_at":%s}\n' "$5" "$now" > "$claude/hive/context/$sid.json"
}

# handover NAME PROJECT STATE MINUTES TASK [DETAIL]; the body comes from stdin
handover() {
  {
    printf -- '---\nsession: %s\nproject: %s\ntask: %s\n' "$1" "$2" "$5"
    [ -z "${6:-}" ] || printf 'detail: %s\n' "$6"
    printf 'state: %s\nupdated: %s\n---\n' "$3" "$(ago "$4")"
    cat
  } > "$claude/handover/$1.md"
}

# transcript NAME PROJECT BRANCH; lines from stdin: "u MIN text", "a MIN text", "t MIN tool|command|description",
# "r MIN" (result of the last tool). Every answer carries token counts for the usage view.
transcript() {
  name=$1; cwd="$dev/$2"; sid="demo-$(echo "$1" | tr . -)"
  dir="$claude/projects/$(printf %s "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$dir"
  out="$dir/$sid.jsonl"
  printf '{"type":"custom-title","customTitle":"%s","sessionId":"%s"}\n' "$name" "$sid" > "$out"
  while read -r kind min text; do
    n=$((n + 1))
    head="\"sessionId\":\"$sid\",\"cwd\":\"$cwd\",\"gitBranch\":\"$3\",\"timestamp\":\"$(ago "$min")\""
    use="\"usage\":{\"input_tokens\":$((n * 7)),\"output_tokens\":$((900 + n * 310)),\"cache_creation_input_tokens\":$((4000 + n * 900)),\"cache_read_input_tokens\":$((180000 + n * 41000))}"
    msg="\"id\":\"msg_demo_$n\",\"model\":\"claude-opus-5-5\",\"role\":\"assistant\""
    case "$kind" in
      u) printf '{"type":"user",%s,"message":{"role":"user","content":"%s"}}\n' "$head" "$text" ;;
      a) printf '{"type":"assistant",%s,"requestId":"req_demo_%s","message":{%s,"content":[{"type":"text","text":"%s"}],%s}}\n' \
           "$head" "$n" "$msg" "$text" "$use" ;;
      t) tool=${text%%|*}; rest=${text#*|}
         printf '{"type":"assistant",%s,"requestId":"req_demo_%s","message":{%s,"content":[{"type":"tool_use","id":"toolu_demo_%s","name":"%s","input":{"command":"%s","description":"%s"}}],%s}}\n' \
           "$head" "$n" "$msg" "$n" "$tool" "${rest%%|*}" "${rest#*|}" "$use"
         last=$n ;;
      r) printf '{"type":"user",%s,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_demo_%s","content":"ok"}]}}\n' "$head" "$last" ;;
    esac
  done >> "$out"
}

line="────────────────────────────────────────────────────────────────────────────────"

# ---- lumen: a PM with two workers ----

cat > "$demo/term/lu.pm.txt" <<EOF
> lu.01 reports the calendar grid as done. What is left for the release?

⏺ Three things are left for release 2.4:

  1. Calendar view: lu.01 is on the list view, the grid is done
  2. Sync conflict: lu.02 has the fix and is waiting to push it
  3. Release notes: drafted, they need your look

  I will tell you as soon as both workers are through. Should the release notes
  go out to the testers today already?

$line
❯
$line
  ? for shortcuts
EOF
handover lu.pm lumen waiting 12 "Release 2.4 (Mika)" "release notes drafted, two workers still on it" <<'EOF'
# Handover lu.pm — as of 2026-10-12

## Situation
- Release 2.4 is planned for Thursday. Scope: calendar view, sync conflict fix, new empty states.
- `lu.01` builds the calendar view (grid done, list view next).
- `lu.02` fixed the sync conflict and waits for the approval to push.
- Release notes are drafted in `docs/release-2.4.md`.

## Open
- Mika: read the release notes, decide whether testers get them today.
- After both workers are done: merge, tag, build for TestFlight.

## Rules and lessons
- Never merge on a red pipeline, not even for "only docs".
- Workers report with a short message, the PM does not poll.
EOF
transcript lu.pm lumen main <<'EOF'
u 30 lu.01 reports the calendar grid as done. What is left for the release?
t 29 Bash|git log --oneline main..release/2.4|Compare the release branch with main
r 29
a 12 Three things are left for release 2.4: the list view of the calendar, the push of the sync fix and your look at the release notes. Should the release notes go out to the testers today already?
EOF
session lu.pm lumen idle 12 34

handover lu.01 lumen working 6 "Calendar view" "grid done, list view next" <<'EOF'
# Handover lu.01 — as of 2026-10-12

## Situation
- Ticket: calendar view with a month grid and a list.
- The month grid is done and tested (`CalendarGridView`).
- The list view shares the month model; first version is written, tests are running.

## Open
- Empty state for months without entries.
- Check the list on the small phone.

## Rules and lessons
- Dates always through the app's calendar, never `Date()` plus seconds.
EOF
if [ -z "$real" ]; then
cat > "$demo/term/lu.01.txt" <<EOF
> The grid looks good. Please build the list view next, same data source.

⏺ I will reuse the month model and add a list layout on top of it.

⏺ Update(Sources/Calendar/CalendarListView.swift)
  ⎿  Added 84 lines

⏺ Update(Tests/CalendarTests/CalendarListTests.swift)
  ⎿  Added 41 lines

⏺ Bash(swift test --filter Calendar)
  ⎿  Running…

✻ Running the calendar tests… (48s · esc to interrupt)

$line
❯
$line
  ? for shortcuts
EOF
transcript lu.01 lumen feat/calendar-view <<'EOF'
u 22 The grid looks good. Please build the list view next, same data source.
a 21 I will reuse the month model and add a list layout on top of it.
t 4 Bash|swift test --filter Calendar|Running the calendar tests
EOF
session lu.01 lumen busy 1 58
else
  # A real Claude Code in a small sample project. It registers in the real ~/.claude, so its registry file and
  # its transcript folder are linked into the demo home; cc-task and cc-note write into the demo (CC_HOME).
  wt="$dev/lumen/worktrees/calendar-view"
  mkdir -p "$wt/Sources/Lumen" "$wt/Tests/LumenTests"
  cat > "$wt/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lumen",
    targets: [
        .target(name: "Lumen"),
        .testTarget(name: "LumenTests", dependencies: ["Lumen"]),
    ]
)
EOF
  cat > "$wt/Sources/Lumen/CalendarMonth.swift" <<'EOF'
import Foundation

/// One entry in the calendar.
public struct Entry: Equatable {
    public let day: Int
    public let title: String

    public init(day: Int, title: String) {
        self.day = day
        self.title = title
    }
}

/// One month as the grid shows it: weeks from Monday to Sunday, `nil` before the first and after the last day.
public struct CalendarMonth: Equatable {
    public let year: Int
    public let month: Int
    public let weeks: [[Int?]]

    public init(year: Int, month: Int, calendar: Calendar = Calendar(identifier: .iso8601)) {
        self.year = year
        self.month = month
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        // weekday 1 is Sunday; the grid starts on Monday
        let lead = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...count).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}
EOF
  cat > "$wt/Tests/LumenTests/CalendarMonthTests.swift" <<'EOF'
import XCTest
@testable import Lumen

final class CalendarMonthTests: XCTestCase {
    func testOctober2026StartsOnAThursday() {
        let month = CalendarMonth(year: 2026, month: 10)
        XCTAssertEqual(month.weeks.first, [nil, nil, nil, 1, 2, 3, 4])
        XCTAssertEqual(month.weeks.count, 5)
    }

    func testFebruary2027FillsFourWeeks() {
        XCTAssertEqual(CalendarMonth(year: 2027, month: 2).weeks.count, 4)
    }
}
EOF
  cat > "$wt/README.md" <<'EOF'
# lumen

Calendar for the lumen app.

- Done: the month grid (`CalendarMonth`)
- Next: a list view of the month: one row per day that has entries, days without entries are left out
EOF
  printf '.build/\n' > "$wt/.gitignore"
  git -C "$wt" init -q -b feat/calendar-view
  git -C "$wt" -c user.name=Mika -c user.email=mika@lumen.example add -A
  git -C "$wt" -c user.name=Mika -c user.email=mika@lumen.example commit -q -m "Month grid for the calendar"
  git -C "$wt" config user.name Mika
  git -C "$wt" config user.email mika@lumen.example
  T new-session -d -s lu.01 -x 110 -y 40 -c "$wt" -e CC_HOME="$claude" -e CC_DEV_ROOT="$dev" -e HIVE_SESSION=lu.01 \
    "exec $(command -v claude || echo claude) -n lu.01"
  pid=$(T display-message -p -t '=lu.01:' '#{pane_pid}')
  slug=$(printf %s "$wt" | sed 's/[^A-Za-z0-9]/-/g')
  ln -s "$HOME/.claude/sessions/$pid.json" "$claude/sessions/$pid.json"
  ln -s "$HOME/.claude/projects/$slug" "$claude/projects/$slug"
fi
printf 'Test accounts\n\n- staging: `mika@lumen.example`\n- reset the demo data: `make seed`\n\n---\n\nRun `make seed`, then restart the dev server.\n' \
  > "$claude/hive/notes/lu.01.md"

cat > "$demo/term/lu.02.txt" <<EOF
⏺ The fix is in: when two devices change the same entry, the newer change wins and
  the older one is kept as a copy. All 212 tests pass.

⏺ Bash(git push origin fix/sync-conflict)
  ⎿  Running…

$line
 Bash command

   git push origin fix/sync-conflict
   Push the branch with the sync fix

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for git push commands in this project
   3. No, and tell Claude what to do differently (esc)
EOF
handover lu.02 lumen working 9 "Sync conflict" "fix done, all tests green" <<'EOF'
# Handover lu.02 — as of 2026-10-12

## Situation
- Bug: two devices change the same entry, one change got lost.
- Fix: the newer change wins, the older one is kept as a copy.
- 212 tests pass, four of them new.

## Open
- Push the branch and open the pull request.

## Rules and lessons
- Reproduce a sync bug with two simulators before touching code.
EOF
transcript lu.02 lumen fix/sync-conflict <<'EOF'
u 40 Two devices changed the same entry and one change was lost. Please find out why.
a 9 The fix is in: when two devices change the same entry, the newer change wins and the older one is kept as a copy. All 212 tests pass.
t 3 Bash|git push origin fix/sync-conflict|Push the branch with the sync fix
EOF
session lu.02 lumen waiting 3 41 "Claude needs your permission to use Bash"

# ---- orbit ----

cat > "$demo/term/or.pm.txt" <<EOF
> Is the billing export through?

⏺ Yes. The export is merged and live since this morning. or.01 is now on the
  invoice PDF, nothing else is open on my side.

$line
❯
$line
  ? for shortcuts
EOF
handover or.pm orbit done 95 "Billing export" <<'EOF'
# Handover or.pm — as of 2026-10-12

## Situation
- The billing export is merged and live.
- `or.01` works on the invoice PDF.

## Open
- Nothing on the PM's side.

## Rules and lessons
- Amounts are integers in cents everywhere.
EOF
transcript or.pm orbit main <<'EOF'
u 96 Is the billing export through?
a 95 Yes. The export is merged and live since this morning. or.01 is now on the invoice PDF, nothing else is open on my side.
EOF
session or.pm orbit idle 95 22

cat > "$demo/term/or.01.txt" <<EOF
> The invoice PDF needs the new address block and page numbers.

⏺ I will start with the address block, then the page numbers.

⏺ Update(app/invoices/pdf_template.py)
  ⎿  Added 37 lines, removed 12 lines

✻ Rendering three sample invoices… (12s · esc to interrupt)

$line
❯
$line
  ? for shortcuts
EOF
handover or.01 orbit working 3 "Invoice PDF" "address block, then page numbers" <<'EOF'
# Handover or.01 — as of 2026-10-12

## Situation
- The invoice PDF gets the new address block and page numbers.
- The address block is in the template.

## Open
- Page numbers, then compare three sample invoices with the old ones.

## Rules and lessons
- Always render the sample with the longest address.
EOF
transcript or.01 orbit feat/invoice-pdf <<'EOF'
u 14 The invoice PDF needs the new address block and page numbers.
a 13 I will start with the address block, then the page numbers.
t 2 Bash|python tools/render_samples.py --count 3|Rendering three sample invoices
EOF
session or.01 orbit busy 1 29

# ---- fjord: blocked ----

cat > "$demo/term/fj.01.txt" <<EOF
⏺ The redirect after login can go two ways and I cannot decide that for you:

  A. Back to the page the visitor came from
  B. Always to the dashboard

  A is friendlier, B is what the old app did. Which one do you want?

$line
❯
$line
  ? for shortcuts
EOF
handover fj.01 fjord blocked 26 "Login redirect" "back to the last page or always to the dashboard?" <<'EOF'
# Handover fj.01 — as of 2026-10-12

## Situation
- After login the visitor lands on an empty page.
- Cause found: the target is lost when the session is renewed.

## Open
- Decision: back to the page the visitor came from, or always to the dashboard.

## Rules and lessons
- Test the login in a private window, cookies hide this bug.
EOF
transcript fj.01 fjord fix/login-redirect <<'EOF'
u 50 After login I land on an empty page. Please fix that.
a 26 The redirect after login can go two ways and I cannot decide that for you: back to the page the visitor came from, or always to the dashboard. Which one do you want?
EOF
session fj.01 fjord idle 26 47

# ---- kiosk: offline ----

handover ki.pm kiosk done 1500 "Price labels" <<'EOF'
# Handover ki.pm — as of 2026-10-11

## Situation
- The price labels print correctly on both printers.

## Open
- Nothing.

## Rules and lessons
- Test on the small label printer first.
EOF
handover ki.01 kiosk done 1440 "Receipt layout" <<'EOF'
# Handover ki.01 — as of 2026-10-11

## Situation
- The receipt has the new layout with the logo on top.

## Open
- Nothing.

## Rules and lessons
- The printer cuts off the last line without a trailing line feed.
EOF

# ---- project info, plan limits, favorites ----

cat > "$claude/project-info/lumen.md" <<EOF
---
folder: $dev/lumen
prefix: lu
---
# lumen

## Links
- Staging: https://staging.lumen.example
- Board: https://board.lumen.example/release-2-4
- Design: https://design.lumen.example/calendar

## Test accounts
- staging: mika@lumen.example (password in the password manager)

## Notes
- Release every second Thursday
- TestFlight builds come from the branch \`release/*\`
EOF

printf '{"written_at":%s,"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":%s},"seven_day":{"used_percentage":66,"resets_at":%s}}}\n' \
  "$now" "$((now + 8040))" "$((now + 183600))" > "$claude/hive/usage.json"

defaults delete "$id" 2>/dev/null || true
defaults write "$id" pinned -array lu.pm or.pm

env $unset_args HIVE_HOME="$demo" HIVE_TMUX="$socket" HIVE_APP="$appname" HIVE_BUNDLE_ID="$id" sh restart.sh | sed -n '/^App:/p'
echo "demo.sh: sessions $(T ls -F '#{session_name}' | tr '\n' ' ')"
[ -z "$real" ] || echo "demo.sh: lu.01 runs a real Claude Code in $dev/lumen/worktrees/calendar-view (README.md says what is next)"
echo "demo.sh: stop it with: sh scripts/demo.sh stop"
