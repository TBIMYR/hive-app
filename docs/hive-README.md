# hive

Local dashboard for all running Claude Code sessions, plus one global handover
location per session name. No dependencies, a single Node process.

Design: `docs/specs/2026-09-30-session-dashboard-design.md`
What the master session `keeper` changed (including outside the repo): `docs/keeper-log.md`
Current session rules for the global CLAUDE.md: `docs/claude-md-session-status.md`

Names in examples are made up.

## Start

```sh
node server.js              # http://127.0.0.1:7777, PORT can be overridden
sh install.sh               # symlinks into ~/.claude, hook, CLAUDE.md section
sh install.sh --launchd     # additionally as a LaunchAgent (always runs after login)
node --test                 # all tests, no tokens
```

LaunchAgent logs: `/tmp/hive.log`, `/tmp/hive.err`.
Restart after changes to `server.js`: `launchctl kickstart -k gui/$(id -u)/io.github.tbimyr.hive`.
`public/index.html` is re-read on every request, so it needs no restart.

## Data sources

| Source | Provides | Written by |
|---|---|---|
| `~/.claude/sessions/<pid>.json` | name, directory, status (busy/idle/waiting/shell), waitingFor | Claude Code |
| Transcript `~/.claude/projects/<slug>/<sessionId>.jsonl` (last 64 KB) | last reply, last prompt, branch | Claude Code |
| `~/.claude/handover/<name>.md` | task line (frontmatter) and handover (body) | the session via `cc-task` |

## Handover file

```markdown
---
session: lu.01
project: lumen
task: Calendar view layout #41, PR open
state: working        # working | blocked | waiting | done | handover
updated: 2026-09-30T16:09:00+02:00
---
# Handover lu.01 — Stand 30.09.2026
## Lage
## Offen
## Regeln und Lehren
```

The name is the key: a new session started with `claude -n lu.01` gets the file
as context at startup (hook `cc-handover-load`), and its task line is set to
"neu gestartet" ("restarted"). Previous versions live under
`~/.claude/handover/archive/<name>/`. The handover template (title line and the three
section headings) stays German on purpose.

## Session side

```sh
cc-task "Text" [state]                       # set the task line (body is kept)
cc-task --name or.02 "Text" done             # set another session's line (PM)
cc-task --archive --body file.md "Short" handover   # write a handover
cc-task --no-create "Text"                   # only if the file exists (hook)
```

Dashboard grouping (in this order): waiting for input → "Needs you";
working (`busy`) → "Working", even if the line still says `blocked`; line `blocked` →
"Needs you"; line `waiting` → top of "Ready" (violet); otherwise "Ready".

```sh
cc-spawn lu.01 ~/Development/lumen/worktrees/x "Ticket #17: …"   # new iTerm tab with claude -n
cc-close lu.01                     # type /exit, close the tab; refused when busy or without handover
cc-close --force lu.01             # close anyway
```

`cc-task` finds the name via `$CLAUDE_PID` and the registry. Sessions with a
derived name (no `-n`) get no handover.

Skills (global, symlinked into `~/.claude/skills/`):

- `/status`: calls `cc-task` with one line, for manual use only.
  For automatic updates, sessions call `cc-task` directly via Bash, bundled with a
  tool call that is due anyway (rule in `~/.claude/CLAUDE.md`). Reason: every
  extra model request re-reads the whole context (on 2026-09-30 just under
  500,000 tokens per request on average); going through the skill would mean two.
- `/handover`: writes the body to the scratchpad and passes it to `cc-task --archive --body`.

## API

- `GET /api/state`: all sessions as JSON, fresh on every request.
- `GET /icons/hive.svg`, `/icons/hive-512.png`, `/icons/favicon-32.png`, `/apple-touch-icon.png`,
  `/favicon.ico`: honeycomb icon (fixed list, no directory serving).
- `GET /api/handover/<name>`: the raw handover file.
- `POST /api/focus/<pid>`: brings the session's iTerm window and tab to the front
  (PID → tty via `ps`, then AppleScript). Only for live sessions from the registry,
  not for background sessions, and only from this page itself (origin check).
  In the dashboard: clicking a tile jumps to iTerm; the "Handover" or
  "Details" button opens the sidebar.

Sessions without a live process but with a handover file show up as
`offline`. The row disappears when the file is deleted or the session is
restarted.
