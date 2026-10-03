# Roadmap: hive als Mac-App (Stand 2026-10-03)

Der Wegwerf-Prototyp (`prototype/`) hat bestätigt, dass Übersicht und Terminal in einem Fenster
tragen. Diese Roadmap beschreibt den Weg zur echten App. Jede Etappe bekommt eine eigene Spec unter
`superpowers/specs/`, gebaut wird erst nach Mikas Alltagstest des Prototyps.

## Ausgangslage

- Prototyp: SwiftUI + SwiftTerm + eigener tmux-Server (`tmux -L hive`). Die Daten kommen vom
  Node-Server (`server.js`, `lib/*.js`, etwa 370 Zeilen Logik) über `/api/state`.
- Der eigentliche Wert ist das **Statusmodell**: Aufgaben-Zeile (`cc-task`), PM/Worker, Handover pro
  Name, `cc-spawn`/`cc-close`. Terminal und Fenster sind Mittel zum Zweck.
- **Größtes Risiko:** `~/.claude/sessions/*.json` und das JSONL-Format der Gesprächsprotokolle sind
  keine offizielle Schnittstelle von Claude Code. Sie können sich mit jedem Update ändern.

## Etappe 1: Alltagstauglich für Mika (1–2 Wochen)

Ziel: Mika arbeitet täglich in der App statt mit Dashboard und iTerm.

1. **hive-Logik in Swift.** Register, Handover, Gesprächsprotokoll und Projektzuordnung als
   Swift-Modul mit Tests. Dateiüberwachung (FSEvents) statt Abfrage alle 2 s. Die App braucht den
   Node-Server nicht mehr. Das Web-Dashboard bleibt vorerst unverändert parallel bestehen.
2. **Mitteilungen.** macOS-Mitteilung und Zahl am Dock-Symbol, sobald eine Session dich braucht
   (wartet auf dich, blockiert, wartet beim Start). Ein Klick auf die Mitteilung wählt die Session.
3. **Session-Lebenszyklus in der App.** Starten (vorhanden), Beenden (`/exit`, wie `cc-close`),
   Neustart mit Handover, iTerm-Session in die App umziehen (beenden und in tmux neu starten).
   App und `cc-spawn`/`cc-close` nutzen dieselben Regeln (Server `hive`, gefilterte Umgebung).
4. **Terminal-Grundlagen.** ⌘1–9 und ↑↓ zum Wechseln, ⌘+/− für die Schriftgröße. Den Befund zu
   Markieren und Kopieren unter tmux aus dem Alltagstest einarbeiten.
5. **Dialoge in der Karte.** Freigabe- und Start-Abfragen per `tmux capture-pane -e` erkennen, Frage
   und Optionen in der Karte als normalen Text mit Knöpfen zeigen. Erst Mikas Klick tippt die
   Antwort per `send-keys`, es gibt keine automatischen Antworten. Solange das Terminal den Fokus
   hat, sind die Knöpfe gesperrt (sonst kollidiert es mit der eigenen Eingabe). Das Erkennen am
   Text ist anfällig: Unbekannte Dialoge fallen auf „wartet auf dich“ zurück.
6. **Agentenoffen, tmux als führende Liste.** Neue Sessions starten als Shell mit vorgetipptem
   `claude -n <name>` (seit 03.10. im Prototyp). Damit kann jeder Agent laufen (Codex, Claude mit
   `--resume` …). Folgen:
   - Die Liste der Sessions kommt aus tmux, ihr Name ist der tmux-Name. Die Zuordnung zum Agenten
     läuft über die Prozess-ID des Bereichs. Bei Claude ergänzen Register, Hooks und
     Gesprächsprotokoll wie bisher.
   - Andere Agenten bekommen ein Teil-Statusmodell: Aktivität über tmux, Aufgaben-Zeile über
     `cc-task` (Regel in `AGENTS.md`). „Wartet auf dich“ nur über den Bildschirmtext oder über Codex'
     eigenen Benachrichtigungs-Mechanismus (noch zu prüfen).
   - Die App setzt `HIVE_SESSION=<name>` in jeder Session. `cc-task` sollte den Namen künftig daraus
     lesen können.
7. **Robustheit.** Wenn Register oder Gesprächsprotokoll unerwartet aussehen, zeigt die App das
   sichtbar an (statt still falsch). Wo möglich `claude agents --json` als zweite Quelle.

## Etappe 2: Vollständige App (1–2 Wochen)

- Handover und Details der Session ansehen (wie die Seitenleiste im Dashboard).
- Suche und Filter, Einstellungsfenster (Entwicklungsordner, Pfade, Schrift, Layout der PMs).
- Xcode-Projekt mit App-Bundle, Waben-Icon, Menüleiste, Fensterzustand merken.
- Entscheidung SwiftTerm oder libghostty, falls das Terminal im Alltag nicht reicht.
- **Terminal-Darstellung:** ANSI-Palette (16 Farben) an die hive-Farben anpassen, Markierungsfarbe
  (tmux `mode-style`), Innenabstand. Optional Claude-Theme „nur ANSI-Farben“, damit die Palette das
  ganze Farbbild bestimmt. Zeilenabstand in SwiftTerm prüfen.

## Etappe 3: Open Source (2–3 Wochen)

- Eigenes Repo, MIT-Lizenz, englische Oberfläche mit deutscher Übersetzung.
- Auf Mika Zugeschnittenes wird einstellbar: `~/Development`, Namensschema `xx.pm`/`xx.01`,
  iTerm-Sprung.
- Einrichtung beim ersten Start statt `install.sh`: prüft tmux, installiert `cc-task`, die Hooks und
  den CLAUDE.md-Abschnitt (mit Zustimmung, zeigt vorher die Änderungen).
- Dokumentation der Konventionen (Aufgaben-Zeile, Handover, PM/Worker) für Fremde, README mit
  Screenshots, CI-Build, Tests.
- Signieren und Notarisieren (Apple-Developer-Account, 99 $/Jahr), automatische Updates (Sparkle).

## Entschieden

- PM-Darstellung: kein eigener Abschnitt. PMs stehen bei den Karten nach Status und heben sich durch
  Projektfarbe und Kürzel ab (03.10., `4349150`).
- Chat-Ansicht statt Terminal: verworfen. Fließtext gibt es nur außerhalb des Terminals (Karten, Dialoge).

## Offene Entscheidungen

- Web-Dashboard: nach Etappe 1 abschalten, weiterführen (dann gemeinsame Logik?) oder als
  Fernansicht behalten.
- Eigenes Repo schon ab Etappe 1 oder erst ab Etappe 3.
