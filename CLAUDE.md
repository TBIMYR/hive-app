# hive – notes for agents

- Everything is in English: code comments, script output, dashboard UI, tests, docs, commit messages.
  Deliberately German: `docs/claude-md-session-status.md` (copy of the user's German global CLAUDE.md;
  `install.sh` greps for `# Session-Status`), the handover headings `## Lage` / `## Offen` /
  `## Regeln und Lehren` and the task line `neu gestartet, Handover gelesen` (other tools compare them).
- Names in docs, tests and examples are made up: projects `lumen`, `orbit`, `fjord`, `kiosk` with the
  session prefixes `lu`, `or`, `fj`, `ki`; "Mika" stands for the user. No real names, home paths or
  ticket numbers. Check with `git grep` before committing.
- Use `~/` for paths in commands (e.g. `git -C ~/Development/hive-app …`) so they work for everyone.
  Rules with the real home folder belong in `.claude/settings.local.json` (not checked in).
- Specs live in `docs/specs/`, plans in `docs/plans/`. No tool-specific folders or header lines.
- Log changes made outside the repo (global settings, LaunchAgent, handover files) in `docs/keeper-log.md`.
- The Node service runs as LaunchAgent `io.github.tbimyr.hive`; restart after changes to `server.js` or
  `lib/`: `launchctl kickstart -k gui/$(id -u)/io.github.tbimyr.hive`. `bin/*` and `skills/*` are
  symlinked into `~/.claude`, so changes there are live immediately.
- Tests: `node --test test/*.test.js`.
