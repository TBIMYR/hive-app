# hive-app

Mac-App für parallele Claude-Code-Sessions: links die Übersicht aller Sessions, rechts das echte
Terminal der gewählten Session (tmux). Hervorgegangen aus dem Prototyp in
[hive](../hive) (`prototype/`); Skripte (`cc-task`, `cc-spawn`, `cc-close`) und Doku liegen weiter dort.

## Starten

```sh
brew install tmux                  # einmalig
swift run HiveApp
swift run HiveApp --select al.04   # mit vorgewählter Session
sh restart.sh                      # bauen und neu starten (beendet jede laufende .build/debug/HiveApp, auch den Prototyp)
swift test                         # Tests von HiveCore
scripts/compare-node.sh            # Vergleich mit dem alten Node-Server, solange er läuft
```

Von außen an eine Session: `tmux -L hive attach -t '=<name>:'` (Doppelpunkt nötig, sonst liest tmux `.01` als Pane).

## Aufbau

- `HiveCore`: liest `~/.claude/sessions`, `~/.claude/handover` und die Gesprächsprotokolle unter
  `~/.claude/projects`, gleiche Regeln wie früher `hive/lib/*.js`. Änderungen kommen per FSEvents.
- `HiveApp`: SwiftUI-Fenster, Terminal über SwiftTerm und einen eigenen tmux-Server (`tmux -L hive`).
- `hive-state`: gibt den Zustand als JSON aus.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
