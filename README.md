# hive-app

Mac app for parallel Claude Code sessions: the overview of all sessions on the left, the real
terminal of the selected session (tmux) on the right. The session tools the app reads from
(`cc-task`, `cc-spawn`, `cc-close`, `cc-handover-load`, `cc-note`) live in `tools/`. Until 2026-10-07 they were a
separate repo `hive` together with a Node/HTML dashboard; its history is merged in here.

What the master session `keeper` changed (including outside the repo): `docs/keeper-log.md`
Current session rules for the global CLAUDE.md: `docs/claude-md-session-status.md`

Names in examples are made up.

## Features

- Views: List, Tiles, Cards
- Favorites with a star
- ⌘H jumps to the longest-waiting session, cursor into the terminal; press again for the next one
- Notifications and a dock badge count for sessions that need you
- A notepad per session (Notes, ⌘T): Markdown, stored in `~/.claude/hive/notes/<session>.md`; write it yourself or
  let the session add to it with `cc-note`
- Session area with Terminal, Handover, Project and Notes as tabs; drag a tab onto the area to place it beside or
  below the others (drop on an edge) or back onto another tile's tabs (drop in the middle), drag the lines to resize.
  The arrangement is the same for all sessions; View → Reset Session Area Layout puts everything back into one tile
- Quick reply and reply buttons in the cards view
- Keeps the Mac awake while sessions work (switch in the title bar and in Settings, ⌘,)
- Own right-click menu: Wake Up / Remote Control / Write Handover, Favorite / Start next, Restart… / Close… / Force Quit…
- Drag & drop into the terminal

## Starting

```sh
brew install tmux                  # once
swift run HiveApp
swift run HiveApp --select lu.04   # with a preselected session
sh restart.sh                      # release build, install as /Applications/Hive.app and restart
                                    # (HIVE_INSTALL=~/Applications for another folder)
                                    # (quits only apps started from this folder, including the prototype)
swift test                         # HiveCore tests
```

Test instance alongside the main app (own bundle identifier, doesn't steal its notifications):

```sh
HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh
```

Test notes folder instead of `~/.claude/hive/notes`: `HIVE_NOTES=<path> swift run HiveApp`.

App icon: `swift scripts/make-icon.swift Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset`.

Attaching to a session from outside: `tmux -L hive attach -t '=<name>:'` (colon needed, otherwise tmux reads `.01` as a pane).

## Structure

- `HiveCore`: reads `~/.claude/sessions`, `~/.claude/handover` and the conversation transcripts under
  `~/.claude/projects`. Changes arrive via FSEvents.
- `HiveApp`: SwiftUI window, terminal via SwiftTerm, handover view via MarkdownUI, and its own tmux
  server (`tmux -L hive`).
- `hive-state`: prints the state as JSON.

## Session tools

```sh
sh tools/install.sh                          # symlinks into ~/.claude, hook, CLAUDE.md section
node --test tools/test/*.test.js             # tool tests, no tokens
```

Handover file `~/.claude/handover/<name>.md`, written only by `cc-task`:

```markdown
---
session: lu.01
project: lumen
task: Calendar view          # topic only, at most 4 words / 40 characters
detail: grid done, list view next   # optional subline, at most 120 characters
state: working               # working | blocked | waiting | done | handover
updated: 2026-09-30T16:09:00+02:00
---
# Handover lu.01 — Stand 30.09.2026
## Lage
## Offen
## Regeln und Lehren
```

The name is the key: a new session started with `claude -n lu.01` gets the file as context at
startup (hook `cc-handover-load`), and its task line is set to "neu gestartet" ("restarted").
Previous versions live under `~/.claude/handover/archive/<name>/`. The handover template stays
German on purpose.

```sh
cc-task "Topic" [state]                      # set the task line (body is kept)
cc-task --detail "One line of context" "Topic" working
cc-task --name or.02 "Topic" done            # set another session's line (PM)
cc-task --archive --body file.md "Topic" handover   # write a handover
cc-spawn lu.01 ~/Development/lumen/worktrees/x "Ticket: …"   # new session (hive tmux or iTerm tab)
cc-close lu.01                               # type /exit; refused when busy or without handover
cc-close --force lu.01                       # close anyway
cc-note "Run `make seed`, then restart"      # add to this session's notes (Markdown; long text on stdin)
```

Skills (symlinked into `~/.claude/skills/`): `/status` sets the task line by hand; `/handover`
writes the body to the scratchpad and passes it to `cc-task --archive --body`.

## License

MIT, see [LICENSE](LICENSE).
