---
name: status
description: Setzt die Aufgaben-Zeile dieser Session für das Session-Dashboard. Selbst aufrufen bei Auftragsannahme, bei einem Blocker und bei Abschluss eines Auftrags; außerdem wenn der User /status aufruft.
---

Führe genau einen Bash-Aufruf aus, sonst nichts:

    ~/.claude/bin/cc-task "<eine Zeile: was du gerade tust, mit Ticket/PR-Nummer falls vorhanden>" <state>

`state` ist `working` (Auftrag läuft), `blocked` (wartet auf Entscheidung, Freigabe oder eine andere Session) oder `done` (Auftrag abgeschlossen, wartet auf den nächsten).

Wurde ein Text als Argument übergeben, nimm ihn unverändert. Keine Rückfrage, keine Erklärung, keine weitere Ausgabe außer einer Zeile Bestätigung.

Meldet das Skript „Session-Name unbekannt“, sag dem User in einem Satz, dass die Session mit `claude -n <name>` gestartet werden muss, und mach weiter.
