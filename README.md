# hive

Lokales Dashboard für alle laufenden Claude-Code-Sessions plus ein globaler
Handover-Ort je Session-Name. Keine Abhängigkeiten, ein Node-Prozess.

Design: `docs/superpowers/specs/2026-09-30-session-dashboard-design.md`

## Start

```sh
node server.js              # http://127.0.0.1:7777, PORT überschreibbar
sh install.sh               # Symlinks nach ~/.claude, Hook, CLAUDE.md-Abschnitt
sh install.sh --launchd     # zusätzlich als LaunchAgent (läuft nach Login immer)
node --test                 # 52 Tests, keine Tokens
```

Logs des LaunchAgents: `/tmp/hive.log`, `/tmp/hive.err`.
Neustart nach Änderungen an `server.js`: `launchctl kickstart -k gui/$(id -u)/io.github.tbimyr.hive`.
`public/index.html` wird bei jedem Abruf neu gelesen, dafür ist kein Neustart nötig.

## Datenquellen

| Quelle | Liefert | Wer schreibt |
|---|---|---|
| `~/.claude/sessions/<pid>.json` | Name, Verzeichnis, Status (busy/idle/waiting/shell), waitingFor | Claude Code |
| Transkript `~/.claude/projects/<slug>/<sessionId>.jsonl` (letzte 64 KB) | letzte Antwort, letzter Prompt, Branch | Claude Code |
| `~/.claude/handover/<name>.md` | Aufgaben-Zeile (Frontmatter) und Handover (Body) | die Session per `cc-task` |

## Handover-Datei

```markdown
---
session: lu.01
project: lumen
task: Kalender-Ansicht Layout #41, PR offen
state: working        # working | blocked | done | handover
updated: 2026-09-30T16:09:00+02:00
---
# Handover lu.01 — Stand 30.09.2026
## Lage
## Offen
## Regeln und Lehren
```

Der Name ist der Schlüssel: Eine neue Session mit `claude -n lu.01` bekommt die
Datei beim Start als Kontext (Hook `cc-handover-load`), und die Aufgaben-Zeile
steht auf „neu gestartet“. Vorversionen liegen unter
`~/.claude/handover/archive/<name>/`.

## Session-Seite

```sh
cc-task "Text" [state]                       # Aufgaben-Zeile setzen (Body bleibt)
cc-task --name or.02 "Text" done             # fremde Session setzen (PM)
cc-task --archive --body datei.md "Kurz" handover   # Handover schreiben
cc-task --no-create "Text"                   # nur wenn Datei existiert (Hook)
```

`cc-task` ermittelt den Namen über `$CLAUDE_PID` und das Register. Sessions mit
abgeleitetem Namen (ohne `-n`) bekommen kein Handover.

Skills (global, Symlinks nach `~/.claude/skills/`):

- `/status`: ruft `cc-task` mit einer Zeile auf, nur für den manuellen Gebrauch.
  Automatisch rufen Sessions `cc-task` direkt per Bash auf, gebündelt mit einem
  ohnehin anstehenden Tool-Aufruf (Regel in `~/.claude/CLAUDE.md`). Grund: Jede
  zusätzliche Modell-Anfrage liest den ganzen Kontext erneut (am 30.09.2026 im
  Schnitt knapp 500.000 Tokens pro Anfrage); über den Skill wären es zwei.
- `/handover`: schreibt den Body ins Scratchpad und übergibt ihn an `cc-task --archive --body`.

## API

- `GET /api/state`: alle Sessions als JSON, bei jedem Abruf frisch.
- `GET /api/handover/<name>`: die rohe Handover-Datei.
- `POST /api/focus/<pid>`: holt das iTerm-Fenster und den Tab der Session nach vorn
  (PID → tty per `ps`, dann AppleScript). Nur für lebende Sessions aus dem Register,
  nicht für Hintergrund-Sessions, nur von dieser Seite selbst (Origin-Prüfung).
  Im Dashboard: Klick auf die Kachel springt nach iTerm, der Knopf „Handover“ bzw.
  „Details“ öffnet die Seitenleiste.

Sessions ohne lebenden Prozess, aber mit Handover-Datei, erscheinen als
`offline`. Die Zeile verschwindet, wenn die Datei gelöscht oder die Session
neu gestartet wird.
