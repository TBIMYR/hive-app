# hive-app – notes for agents

- Everything is in English: UI, code comments, test names, docs, commit messages.
- Names in docs, tests and examples are made up: projects `lumen`, `orbit`, `fjord`, `kiosk` with the
  session prefixes `lu`, `or`, `fj`, `ki`; "Mika" stands for the user. No real names or ticket numbers.
- Use `~/` for paths in commands (e.g. `git -C ~/Development/hive-app …`) so they work for everyone.
- Specs and plans live in the hive repo under `~/Development/hive/docs/specs/` and `docs/plans/`.
- Never quit Mika's running app: `sh restart.sh` restarts it. For trying things out, start a test
  instance with `HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh` and
  stop only its own PID.
- tmux: the sessions live on `tmux -L hive`; only read there in tests (use `-L hive-test`). Address
  sessions as `=name:` (names contain dots).
