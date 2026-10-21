# Roadmap (version 0.3)

## Basis

- SwiftUI app with SwiftTerm as the terminal and its own tmux server (`tmux -L hive`). `HiveCore` reads all state
  itself; there is no server and no web front end.
- The core is the **status model**: the task line (`cc-task`), PM and worker sessions, a handover per session
  name, `cc-spawn` and `cc-close`. Terminal and window are the means to show it.
- **Biggest risk:** `~/.claude/sessions/*.json` and the JSONL transcript format are not an official Claude Code
  interface. Any Claude Code update can change them.

## Done

- Status of every session from the registry, transcripts and handover files, updated through file watching.
- Notifications, a badge on the Dock icon, and an optional push to the phone via ntfy when the Mac is unattended.
- Session lifecycle in the app: New Session, Wake Up, Restart…, Close…, Force Quit…, Write Handover.
  Sessions get `HIVE_SESSION=<name>`.
- Questions and options of a session shown in its card, with reply buttons and a quick reply.
- Favorites and three views: List, Tiles, Cards. Workers are grouped under their PM.
- Other agents than Claude can be started; their status is only partly known.
- Handover view, project info and a notepad per session (`cc-note`, ⌘T).
- Tiles that can be dragged, stacked as tabs, resized and collapsed into an icon bar.
- CPU load per session, plan limits with an outlook, token usage by project and session.
- Keep Awake while sessions work or always; Sleep When Done puts the Mac to sleep once all of them are finished.
- New Project… (⇧⌘N).
- Settings → Display: monochrome look and switches to hide details of the overview.
- Session tools in the same repo (`tools/`), MIT license.

## Open

Daily use:

- Robustness: show clearly when the registry or a transcript looks unexpected; use `claude agents --json` as a
  second source where possible.
- Terminal: ⌘1–9 to switch sessions, ⌘+/− for the font size, better selection and copy under tmux.
- Tiles: reorder tabs by dragging, drag a tab out of a collapsed bar.
- Lower the app's own CPU use when idle (about 14 % of one core today).
- Full status for agents other than Claude.

App:

- Search and filters in the overview.
- Terminal appearance: ANSI palette matching the app colors, selection color, padding.
- Remember more of the window state than the tile layout.

Open source:

- Make fixed assumptions configurable: the projects folder `~/Development`, the naming scheme `xx.pm` / `xx.01`,
  the jump to iTerm.
- Setup on first launch instead of `install.sh`: check tmux, install the tools, the hook and the CLAUDE.md
  section, showing every change first.
- Documentation of the conventions (task line, handover, PM and worker), a CI build.
- Translations of the UI.
- Signing and notarization, automatic updates.

## Decided

- PM sessions have no section of their own; they stand out through project color and abbreviation.
- No chat view instead of the terminal; prose appears only outside it (cards, dialogs).
- The app is the only front end.
- App and session tools live in one repo.
- One tile layout for all sessions; the overview always keeps a tile of its own.
