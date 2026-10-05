# hive-app

Mac app for parallel Claude Code sessions: the overview of all sessions on the left, the real
terminal of the selected session (tmux) on the right. Grew out of the prototype in
[hive](../hive) (`prototype/`); scripts (`cc-task`, `cc-spawn`, `cc-close`) and docs still live there.

Names in examples are made up.

## Features

- Views: List, Tiles, Cards
- Favorites with a star
- ⌘H jumps to the longest-waiting session, cursor into the terminal; press again for the next one
- Notifications and a dock badge count for sessions that need you
- Floating todo list (⌘T), stored in `~/.claude/hive/todos.md`
- Quick reply and reply buttons in the cards view
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
scripts/compare-node.sh            # comparison with the old Node server, as long as it's running
```

Test instance alongside the main app (own bundle identifier, doesn't steal its notifications):

```sh
HIVE_APP=HiveApp-dev HIVE_BUNDLE_ID=io.github.tbimyr.hive-app.dev sh restart.sh
```

Test todo file instead of `~/.claude/hive/todos.md`: `HIVE_TODOS=<path> swift run HiveApp`.

App icon: `swift scripts/make-icon.swift Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset`.

Attaching to a session from outside: `tmux -L hive attach -t '=<name>:'` (colon needed, otherwise tmux reads `.01` as a pane).

## Structure

- `HiveCore`: reads `~/.claude/sessions`, `~/.claude/handover` and the conversation transcripts under
  `~/.claude/projects`, same rules as the earlier `hive/lib/*.js`. Changes arrive via FSEvents.
- `HiveApp`: SwiftUI window, terminal via SwiftTerm, handover view via MarkdownUI, and its own tmux
  server (`tmux -L hive`).
- `hive-state`: prints the state as JSON.

## License

MIT, see [LICENSE](LICENSE).
