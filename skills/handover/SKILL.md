---
name: handover
description: Schreibt das Handover dieser Session nach ~/.claude/handover/<name>.md, damit eine Nachfolger-Session mit demselben Namen es beim Start liest. Aufrufen vor jedem geplanten Ende oder Neustart, oder wenn der User /handover sagt.
---

1. Schreibe den Handover-Text mit `Write` in eine Datei im Scratchpad (z. B. `<scratchpad>/handover.md`). Aufbau:

       # Handover <name> — Stand <Datum>

       ## Lage
       Repo-Stand, Branches, was gemergt/gepusht ist, laufende Server. Gemessen, nicht vermutet.

       ## Offen
       Was fehlt, wer entscheiden muss, welche Berechtigungen fehlen. Mit Ticket/PR-Nummern.

       ## Regeln und Lehren
       Was in dieser Session dazukam oder schiefging und der Nachfolger wissen muss.

   Gibt es im Projekt noch eine alte Handoff-Datei im bisherigen Format (z. B. `HANDOFF-<name>.md` oder `handoff/<datum>/…`), verweise im Abschnitt „Lage“ einmalig auf ihren Pfad.

2. Führe genau einen Bash-Aufruf aus:

       ~/.claude/bin/cc-task --archive --body <scratchpad>/handover.md "<eine Zeile Kurzfassung, was der Nachfolger zuerst tun soll>" handover

   Das archiviert die Vorversion und schreibt Frontmatter und Body in einem Schritt.

3. Bestätige dem User in einem Satz mit dem Pfad `~/.claude/handover/<name>.md`.

Fasse die Handover-Datei nie direkt mit `Write` oder `Edit` an; `cc-task` ist der einzige Schreiber.
