# hive-App (Wegwerf-Prototyp)

Links die hive-Übersicht, rechts das echte Terminal der gewählten Session (tmux). Soll klären, ob
Übersicht und Terminal in einem Fenster besser sind als Dashboard plus iTerm.
Spec: [`../docs/superpowers/specs/2026-10-03-app-prototype-design.md`](../docs/superpowers/specs/2026-10-03-app-prototype-design.md).

## Starten

```sh
brew install tmux          # einmalig
cd prototype
swift run HiveApp          # hive muss auf 127.0.0.1:7777 laufen
swift run HiveApp --select lu.04   # mit vorgewählter Session
```

## Bedienung

- Kachel anklicken → rechts das Terminal, wenn die Session in tmux läuft.
- Sessions, die noch in iTerm laufen, zeigen „In iTerm zeigen“ (springt wie das Dashboard).
- „Neue Session“ startet `claude -n <name>` in tmux (ohne tmux-Statusleiste).
- Trennlinie zwischen links und rechts ist ziehbar. Fenster schließen beendet keine Session.
- Von außen: `tmux attach -t '=<name>:'` (Doppelpunkt nötig, sonst liest tmux `.01` als Pane).

## Grenzen

Keine Live-Zeilen in den Kacheln, kein Handover, keine Tastenkürzel, kein App-Bundle, keine Tests.

## Befund

_Nach einem Tag Nutzung hier eintragen: Fenster besser als Dashboard + iTerm? Mausrad und Markieren
unter tmux erträglich?_
