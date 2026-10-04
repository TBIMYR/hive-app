# Roadmap: hive as a Mac app (as of 2026-10-03)

The throwaway prototype (`prototype/`) confirmed that overview and terminal in one window
work. This roadmap describes the path to the real app. Each stage gets its own spec under
`specs/`; building starts only after Mika's daily-use test of the prototype.

## Starting point

- Prototype: SwiftUI + SwiftTerm + own tmux server (`tmux -L hive`). The data comes from the
  Node server (`server.js`, `lib/*.js`, about 370 lines of logic) via `/api/state`.
- The real value is the **status model**: task line (`cc-task`), PM/worker, handover per
  name, `cc-spawn`/`cc-close`. Terminal and window are means to an end.
- **Biggest risk:** `~/.claude/sessions/*.json` and the JSONL transcript format are not an
  official Claude Code interface. They can change with any update.

## Stage 1: fit for daily use by Mika (1–2 weeks)

Goal: Mika works in the app every day instead of the dashboard and iTerm.

1. **hive logic in Swift.** Registry, handover, transcript and project mapping as a
   Swift module with tests. File watching (FSEvents) instead of polling every 2 s. The app no longer
   needs the Node server. The web dashboard stays in parallel, unchanged, for now.
2. **Notifications.** macOS notification and a badge on the Dock icon as soon as a session needs you
   (waiting for you, blocked, waiting at start). A click on the notification selects the session.
3. **Session lifecycle in the app.** Start (exists), quit (`/exit`, like `cc-close`),
   restart with handover, move an iTerm session into the app (quit and restart in tmux).
   App and `cc-spawn`/`cc-close` use the same rules (server `hive`, filtered environment).
4. **Terminal basics.** ⌘1–9 and ↑↓ for switching, ⌘+/− for font size. Incorporate the findings on
   selection and copy under tmux from the daily-use test.
5. **Dialogs in the card.** Detect permission and start prompts via `tmux capture-pane -e`, show the
   question and options in the card as normal text with buttons. Only Mika's click types the
   answer via `send-keys`; there are no automatic answers. While the terminal has focus, the
   buttons are disabled (otherwise it collides with one's own input). Detection by text is
   fragile: unknown dialogs fall back to "waiting for you".
6. **Agent-agnostic, tmux as the leading list.** New sessions start as a shell with a pre-typed
   `claude -n <name>` (in the prototype since 03.10.). That way any agent can run (Codex, Claude with
   `--resume` …). Consequences:
   - The session list comes from tmux, its name is the tmux name. The mapping to the agent
     goes via the pane's process ID. For Claude, registry, hooks and transcript supplement it
     as before.
   - Other agents get a partial status model: activity via tmux, task line via
     `cc-task` (rule in `AGENTS.md`). "Waiting for you" only via the screen text or via Codex's
     own notification mechanism (still to check).
   - The app sets `HIVE_SESSION=<name>` in every session. `cc-task` should be able to read the name
     from it in future.
   **New (03.10.), comes right after notifications:** pin sessions at the top, pinned sessions
   preferably shown in reduced form; multiple views in general. Separate design with Mika.
7. **Robustness.** If the registry or transcript look unexpected, the app shows this
   visibly (instead of being silently wrong). Where possible, `claude agents --json` as a second source.

## Stage 2: complete app (1–2 weeks)

- View the handover and session details (like the sidebar in the dashboard).
- Search and filters, settings window (development folder, paths, font, PM layout).
- Xcode project with app bundle, honeycomb icon, menu bar, remembered window state.
- Decide between SwiftTerm and libghostty if the terminal isn't enough in daily use.
- **Terminal appearance:** adapt the ANSI palette (16 colors) to the hive colors, selection color
  (tmux `mode-style`), padding. Optionally a Claude theme "ANSI colors only", so the palette
  determines the whole color scheme. Check line spacing in SwiftTerm.

## Stage 3: open source (2–3 weeks)

- Own repo, MIT license, English UI with German translation.
- Things tailored to Mika become configurable: `~/Development`, naming scheme `xx.pm`/`xx.01`,
  iTerm jump.
- Setup on first launch instead of `install.sh`: checks tmux, installs `cc-task`, the hooks and
  the CLAUDE.md section (with consent, showing the changes first).
- Documentation of the conventions (task line, handover, PM/worker) for others, README with
  screenshots, CI build, tests.
- Signing and notarization (Apple Developer account, $99/year), automatic updates (Sparkle).

## Decided

- PM presentation: no separate section. PMs appear among the cards by status and stand out through
  project color and abbreviation (03.10., `4349150`).
- Chat view instead of terminal: rejected. Prose exists only outside the terminal (cards, dialogs).

## Open decisions

- Web dashboard: switch off after stage 1, keep developing (shared logic then?) or keep as a
  remote view.
- Own repo from stage 1 or only from stage 3.
