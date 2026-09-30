---
name: status
description: Setzt die Aufgaben-Zeile dieser Session für das Session-Dashboard. Nur wenn der User /status ausdrücklich aufruft. Für die automatische Pflege cc-task direkt per Bash nutzen (Regel in der globalen CLAUDE.md), nicht diesen Skill.
---

Führe genau einen Bash-Aufruf aus, sonst nichts:

    ~/.claude/bin/cc-task "<eine Zeile: was du gerade tust, mit Ticket/PR-Nummer falls vorhanden>" <state>

`state` ist `working` (Auftrag läuft), `blocked` (kommt ohne Entscheidung oder Freigabe von Mika nicht weiter), `waiting` (eigene Arbeit fertig, wartet nur noch auf Rückmeldung von Menschen oder einer anderen Session) oder `done` (Auftrag abgeschlossen, wartet auf den nächsten).

Wurde ein Text als Argument übergeben, nimm ihn unverändert. Keine Rückfrage, keine Erklärung, keine weitere Ausgabe außer einer Zeile Bestätigung.

Meldet das Skript „Session-Name unbekannt“, sag dem User in einem Satz, dass die Session mit `claude -n <name>` gestartet werden muss, und mach weiter.
