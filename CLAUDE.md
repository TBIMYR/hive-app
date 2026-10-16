# hive-app – notes for agents

One repo for the Mac app (`Sources/`, `Tests/`) and the session tools it reads from (`tools/`:
`cc-task`, `cc-spawn`, `cc-close`, `cc-handover-load`, `cc-note`, skills `/status` and `/handover`).

- Everything is in English: UI, code comments, script output, test names, docs, commit messages.
  Deliberately German: `docs/claude-md-session-status.md` (copy of the user's German global CLAUDE.md;
  `tools/install.sh` greps for `# Session-Status`), the handover headings `## Lage` / `## Offen` /
  `## Regeln und Lehren` and the task line `neu gestartet, Handover gelesen` (other tools compare them).
- Names in docs, tests and examples are made up: projects `lumen`, `orbit`, `fjord`, `kiosk` with the
  session prefixes `lu`, `or`, `fj`, `ki`; "Mika" stands for the user. No real names, home paths or
  ticket numbers. Check with `git grep` before committing.
- Use `~/` for paths in commands (e.g. `git -C ~/Development/hive-app …`) so they work for everyone.
  Rules with the real home folder belong in `.claude/settings.local.json` (not checked in).
- Specs and plans live outside the repo in `~/.claude/hive-app-docs/specs/` and `.../plans/` (they describe
  Mika's way of working). No tool-specific folders or header lines.
- Log changes made outside the repo (global settings, handover files, other projects' hooks) in
  `~/.claude/keeper-log.md`. It is not part of the repo because it describes Mika's personal setup.
- `tools/bin/*` and `tools/skills/*` are symlinked into `~/.claude` (`sh tools/install.sh`), so changes
  there are live immediately for every running session.
- Never quit Mika's running app (`/Applications/Hive.app`): `sh restart.sh` rebuilds and restarts it. For trying things out, start a test
  instance with `HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh` and
  stop only its own PID.
- tmux: the sessions live on `tmux -L hive`; only read there in tests (use `-L hive-test`). Address
  sessions as `=name:` (names contain dots).
- Tests: `swift test` (app) and `node --test tools/test/*.test.js` (tools).
