# Roadmap: hive as a Mac app (as of 2026-10-16, version 0.3)

The app replaced the web dashboard and iTerm in Mika's daily work. The first roadmap (2026-10-03) planned three
stages; this version says what of it exists and what is still open. Specs live under `specs/`, plans under `plans/`.

## Starting point

- SwiftUI + SwiftTerm + own tmux server (`tmux -L hive`). The app reads everything itself (`HiveCore`); the Node
  server and the HTML dashboard were retired when the `hive` repo was merged in (2026-10-07).
- The real value is the **status model**: task line (`cc-task`), PM/worker, handover per name,
  `cc-spawn`/`cc-close`. Terminal and window are means to an end.
- **Biggest risk:** `~/.claude/sessions/*.json` and the JSONL transcript format are not an official Claude Code
  interface. They can change with any update.

## Done

From stage 1 (fit for daily use):

- hive logic in Swift with tests, file watching via FSEvents instead of polling.
- Notifications, a badge on the Dock icon, and a push to the phone via ntfy when the Mac is unattended.
- Session lifecycle in the app: New Session, Wake Up, Restart…, Close…, Force Quit…, Write Handover.
  Sessions get `HIVE_SESSION=<name>`.
- Dialogs in the card: questions and options of a session as text with reply buttons, quick reply.
- Favorites (the earlier "pinning") and three views: List, Tiles, Cards. Workers are grouped under their PM.
- New sessions can start other agents than Claude; those have a partial status model.

From stage 2 (complete app):

- Handover view and project info per session.
- Settings window, app bundle with icon via `restart.sh`, menu bar entries.

From stage 3 (open source):

- One repo with the session tools (`tools/`), MIT license, English UI and docs, made-up names in examples.

Added since, not on the first roadmap:

- The window is made of tiles that can be dragged, stacked as tabs, resized and collapsed to an icon bar with a
  temporary layer (`DockLayout`).
- A notepad per session (`cc-note`, ⌘T).
- CPU load per session, plan limits with outlook in the title bar, token usage by project and session.
- Keeps the Mac awake while sessions work; Sleep When Done puts it to sleep once all of them are finished (0.3).
- New Project… (⇧⌘N).
- Settings → Display: monochrome look and switches to hide details of the overview (0.3).

## Open

Daily use:

- Robustness: show visibly when the registry or a transcript looks unexpected; `claude agents --json` as a second
  source where possible.
- Terminal: ⌘1–9 for switching, ⌘+/− for font size, findings on selection and copy under tmux.
- Tiles: change the order of tabs by dragging, drag a tab out of a collapsed bar.
- The app's own CPU baseline (about 14 % of one core when idle).
- Full status for agents other than Claude ("waiting for you" via screen text or the agent's own notification).

Complete app:

- Search and filters in the overview.
- Decide between SwiftTerm and libghostty if the terminal isn't enough in daily use.
- Terminal appearance: adapt the ANSI palette to the hive colors, selection color, padding.
- Remembered window state beyond the tile layout, an Xcode project if `restart.sh` stops being enough.

Open source:

- Things tailored to Mika become configurable: `~/Development`, naming scheme `xx.pm`/`xx.01`, iTerm jump.
- Setup on first launch instead of `install.sh`: checks tmux, installs `cc-task`, the hooks and the CLAUDE.md
  section (with consent, showing the changes first).
- Documentation of the conventions (task line, handover, PM/worker) for others, CI build.
- German translation of the UI.
- Signing and notarization (Apple Developer account, $99/year), automatic updates (Sparkle).

## Decided

- PM presentation: no separate section. PMs appear among the sessions by status and stand out through project color
  and abbreviation (03.10.).
- Chat view instead of terminal: rejected. Prose exists only outside the terminal (cards, dialogs).
- Web dashboard: switched off, the app is the only front end (07.10.).
- One repo for app and tools (07.10.).
- Tile layout: the same for all sessions; the overview always keeps a tile of its own (12.10.).
