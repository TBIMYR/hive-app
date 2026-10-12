# Session-Status

- Sessions immer mit `claude -n <name>` starten (z. B. `lu.pm`, `lu.01`); der Name ist der Schlüssel für Dashboard und Handover.
- Aufgaben-Zeile selbst setzen bei Auftragsannahme, bei einem Blocker und bei Abschluss: `~/.claude/bin/cc-task "<Thema>" <working|blocked|waiting|done>` direkt per Bash, NICHT über den Skill `/status`. Den Aufruf parallel im selben Schritt wie einen ohnehin anstehenden Tool-Aufruf abschicken (z. B. mit dem ersten Read/Bash eines Auftrags oder mit der letzten Aktion davor), damit keine zusätzliche Modell-Anfrage entsteht.
- Die Aufgaben-Zeile nennt nur das Thema, höchstens 4 Wörter / 40 Zeichen, ohne Ticketnummern und ohne Ablauf (z. B. „Android-App“, „Neuer iPhone-Build“). Den Zustand zeigt das Dashboard ohnehin. `cc-task` lehnt längere Zeilen ab.
- Mehr Kontext optional als Subline: `cc-task --detail "<eine Zeile, höchstens 120 Zeichen>" "<Thema>" <state>`, z. B. was gerade konkret läuft oder worauf genau gewartet wird. Jeder Aufruf ersetzt sie, ohne `--detail` ist sie leer.
- `blocked` nur, wenn die Session ohne eine Entscheidung oder Freigabe von mir nicht weiterkommt. Ist die eigene Arbeit fertig und es fehlt nur noch eine Rückmeldung (von mir, Kim, einer anderen Session), dann `waiting` und in Klammern nennen, auf wen gewartet wird (z. B. „Release (lu.pm)“).
- Zettel: Sage ich „schreib das auf einen Zettel“ (z. B. eine Anleitung, die sonst im Verlauf verschwindet), den Text per `~/.claude/bin/cc-note "<Text>"` ablegen (Markdown, mehrzeilig möglich; langer Text per stdin). Hive zeigt die Zettel an der Session (⌘T). Nur auf Wunsch anlegen, nicht von selbst.
- Wann Handover + `/clear`, wann weiterlaufen lassen (jede Anfrage schickt den ganzen Verlauf mit; nach längerer Pause muss der Cache neu geschrieben werden; langer Verlauf verschlechtert die Qualität):
  - Handover + `/clear`: nächster Auftrag ist unabhängig (anderes Ticket), Session liegt voraussichtlich lange still, oder der Verlauf ist schon sehr groß.
  - Weiterlaufen lassen: Nachfrage oder Fix zum gerade erledigten Auftrag, Folgearbeit am selben Thema.
  - PM-Sessions laufen weiter, aktualisieren aber regelmäßig ihr Handover und werden nur bei einem Themenwechsel geleert.
  - Mittelweg: `/compact`, wenn die Session weiterarbeiten soll, der Verlauf aber zu lang wird. Überlebt keinen Neustart, das Handover schon.
- Statt `/clear` darf eine Session auch geschlossen und neu gestartet werden; entscheidend ist derselbe Name.
- Ablauf PM ↔ Worker:
  1. PM vergibt einen Auftrag per `~/.claude/bin/cc-spawn <name> <verzeichnis> "<Auftrag>"` (neuer iTerm-Tab, lädt das Handover zum Namen, lehnt laufende Namen ab).
     Freie Namen zuerst: Vor einem neuen Namen (z. B. `lu.05`) eine bestehende Offline-Session des Projekts mit Handover wiederverwenden (`lu.01` …); `cc-spawn` lädt ihr Handover. Neue Nummern nur, wenn alle vorhandenen laufen.
  2. Worker ist fertig: Handover schreiben, `cc-task … done` (oder `waiting`), dann seinem PM per SendMessage kurz melden, was fertig ist. Die Nachricht weckt den PM; niemand muss pollen.
  3. PM entscheidet: Folgearbeit am selben Thema → SendMessage an den Worker, er läuft weiter. Neues, unabhängiges Ticket oder nichts mehr zu tun → `~/.claude/bin/cc-close <name>` (tippt `/exit`, schließt den Tab; lehnt ab, solange der Worker arbeitet oder kein Handover hat) und bei Bedarf neu per `cc-spawn`.
  4. Bei einem neuen Verzeichnis (frischer Worktree) fragt Claude Code einmal nach Vertrauen; das bestätige ich selbst. Echte Entscheidungen bleiben `blocked`.
- `/handover` vor jedem geplanten Ende oder Neustart. Die Nachfolger-Session mit demselben Namen liest es beim Start automatisch.
- Die PM-Session darf `~/.claude/handover/<name>.md` der Worker jederzeit lesen, statt sie zu fragen.
