# hive app (throwaway prototype)

The hive overview on the left, the real terminal of the selected session (tmux) on the right. Meant to
find out whether overview and terminal in one window beat dashboard plus iTerm.
Spec: [`../docs/specs/2026-10-03-app-prototype-design.md`](../docs/specs/2026-10-03-app-prototype-design.md).

## Running

```sh
brew install tmux          # once
cd prototype
swift run HiveApp          # hive must be running on 127.0.0.1:7777
swift run HiveApp --select lu.04   # with a preselected session
```

## Usage

- Click a tile → its terminal on the right, if the session runs in tmux.
- Sessions still running in iTerm show "Show in iTerm" (jumps there like the dashboard).
- "New session" starts `claude -n <name>` in tmux (without the tmux status bar).
- "Handover" at the top right toggles between the session's terminal and handover; for offline sessions the app shows the handover directly.
- The divider between left and right can be dragged. Closing the window does not end any session.
- From outside: `tmux attach -t '=<name>:'` (the colon is required, otherwise tmux reads `.01` as a pane).

## Limits

No live lines in the tiles, no keyboard shortcuts, no app bundle, no tests.

## Findings

_Fill in after a day of use: is the window better than dashboard + iTerm? Are scroll wheel and selection
bearable under tmux?_
