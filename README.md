# hive-app

Mac-App für parallele Claude-Code-Sessions: links die Übersicht aller Sessions, rechts das echte
Terminal der gewählten Session (tmux). Hervorgegangen aus dem Prototyp in
[hive](../hive) (`prototype/`); Skripte (`cc-task`, `cc-spawn`, `cc-close`) und Doku liegen weiter dort.

## Starten

```sh
brew install tmux                  # einmalig
swift run HiveApp                  # braucht noch den hive-Server auf 127.0.0.1:7777
swift run HiveApp --select al.04   # mit vorgewählter Session
sh restart.sh                      # bauen und neu starten (beendet jede laufende .build/debug/HiveApp, auch den Prototyp)
```

Von außen an eine Session: `tmux -L hive attach -t '=<name>:'` (Doppelpunkt nötig, sonst liest tmux `.01` als Pane).

## Lizenz

MIT, siehe [LICENSE](LICENSE).
