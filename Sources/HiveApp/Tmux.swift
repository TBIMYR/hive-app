import Foundation
import HiveCore

enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// tmux deutet ".01" in "al.01" sonst als Pane; "=name:" trifft genau die Session.
    static func target(_ name: String) -> String { SessionControl.target(name) }

    /// Eigener Server nur für die App (`tmux -L hive`), damit ihre Einstellungen nicht mit
    /// einem selbst gestarteten tmux kollidieren. `-f` gilt nur beim Start des Servers.
    static let socket = "hive"

    static let config = """
    # von der hive-App geschrieben, wird bei jedem Start überschrieben
    set -g status off                       # verdeckt sonst die unterste Zeile von Claude Code
    set -g mouse on                         # Mausrad blättert im Verlauf statt in der Eingabe-Historie
    set -sg escape-time 0                   # Esc sofort an Claude durchreichen
    set -g history-limit 50000
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",xterm-256color:RGB"   # True Color statt 256 Farben
    set -s extended-keys on                 # Shift+Enter u. a. unterscheidbar
    set -g focus-events on
    set -s set-clipboard on                 # Kopieren per OSC 52 ins System
    set -g aggressive-resize on             # Größe folgt dem gerade angezeigten Terminal
    """

    static let configPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "hive")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "tmux.conf")
        try? config.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }()

    static var serverArgs: [String] { ["-L", socket, "-f", configPath] }

    static func attachArgs(_ name: String) -> [String] { serverArgs + ["attach-session", "-t", target(name)] }

    struct Panes: Equatable {
        /// tmux-Session → Befehl, der gerade vorn läuft („claude.exe“, „zsh“, „codex“ …)
        var commands: [String: String] = [:]
        /// Pane-ID („%13“) → tmux-Session, für die Zuordnung über das Register
        var sessionOfPane: [String: String] = [:]
        /// tmux-Session → Ordner ihrer ersten Pane (für „Restart“ bei Sessions ohne Register)
        var paths: [String: String] = [:]
    }

    static func panes() -> Panes {
        let r = run(["list-panes", "-a", "-F", "#{session_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"])
        guard r.status == 0 else { return Panes() }   // kein tmux-Server = keine Sessions
        var p = Panes()
        for line in r.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { continue }
            if p.commands[parts[0]] == nil { p.commands[parts[0]] = parts[2]; p.paths[parts[0]] = parts[3] }
            p.sessionOfPane[parts[1]] = parts[0]
        }
        return p
    }

    static func hasSession(_ name: String) -> Bool {
        run(["has-session", "-t", target(name)]).status == 0
    }

    /// Öffnet eine Shell in einer neuen tmux-Session im Ordner und tippt `claude -n <name>` vor,
    /// ohne Enter: man startet selbst und kann die Zeile vorher ändern (z. B. `codex`, `--resume`).
    /// Mit `submit` (Restart) folgt Enter, Claude startet also gleich.
    /// `HIVE_SESSION` trägt den Namen, egal welcher Agent später läuft. Liefert eine Fehlermeldung oder nil.
    static func newSession(name: String, dir: String, submit: Bool = false) -> String? {
        scrubServer()
        let r = run(["new-session", "-d", "-s", name, "-c", dir, "-e", "HIVE_SESSION=\(name)"])
        guard r.status == 0 else { return r.output.isEmpty ? "tmux error \(r.status)" : r.output }
        // erst tippen, wenn die Shell ihre Startdateien gelesen hat
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let cmds = SessionControl.typeArgs(SessionControl.claudeCommand(name), into: name)
            _ = run(cmds[0])
            if submit { _ = run(cmds[1]) }
        }
        return nil
    }

    /// Tippt Text in die Session und schickt ihn mit Enter ab. Blockiert kurz, darum nicht auf dem
    /// Main Thread aufrufen. Liefert eine Fehlermeldung oder nil.
    static func type(_ text: String, into name: String) -> String? {
        let cmds = SessionControl.typeArgs(text, into: name)
        let r = run(cmds[0])
        guard r.status == 0 else { return failure(r) }
        // kurze Pause, damit Claude Code Enter nicht als Teil eines eingefügten Texts nimmt
        Thread.sleep(forTimeInterval: 0.15)
        let e = run(cmds[1])
        return e.status == 0 ? nil : failure(e)
    }

    /// Bildschirm der Session als Text, nil bei einem Fehler.
    static func capture(_ name: String) -> String? {
        let r = run(SessionControl.captureArgs(name))
        return r.status == 0 ? r.output : nil
    }

    static let dialogChanged = "Dialog changed – answer in the terminal"

    /// Antwort-Knopf: Dialog auf dem Bildschirm suchen, Ziffer der Option tippen; steht derselbe Dialog
    /// danach noch da und ist die Option markiert, zusätzlich Enter. Findet sich die Option nicht oder
    /// tippt gerade jemand in eine Freitext-Option, wird nichts gesendet. Blockiert kurz, nicht auf dem
    /// Main Thread aufrufen. `known`: Optionen laut Protokoll. Liefert eine Meldung oder nil.
    static func answer(_ answer: ScreenDialog.Answer, known: [String], in name: String) -> String? {
        guard let before = capture(name).flatMap(ScreenDialog.parse), let option = before.pick(answer)
        else { return dialogChanged }
        if case .option = answer, before.selectionOutside(known) { return dialogChanged }
        let r = run(SessionControl.keyArgs(String(option.number), into: name))
        guard r.status == 0 else { return failure(r) }
        Thread.sleep(forTimeInterval: 0.3)
        // Dialog weg oder ein anderer: die Ziffer hat schon gewählt
        guard let after = capture(name).flatMap(ScreenDialog.parse),
              after.options.map(\.label) == before.options.map(\.label) else { return nil }
        // gleiche Optionen, aber anderer Text darüber: womöglich schon die nächste Frage, kein Enter
        guard after.sameDialog(as: before) else { return "Check the terminal" }
        let marked = after.options.filter(\.selected)
        guard marked.map(\.number) == [option.number] else { return dialogChanged }
        let e = run(SessionControl.keyArgs("Enter", into: name))
        return e.status == 0 ? nil : failure(e)
    }

    /// Beendet die tmux-Session (genau diese). Liefert eine Fehlermeldung oder nil.
    static func kill(_ name: String) -> String? {
        let r = run(SessionControl.killArgs(name))
        return r.status == 0 ? nil : failure(r)
    }

    private static func failure(_ r: (status: Int32, output: String)) -> String {
        r.output.isEmpty ? "tmux error \(r.status)" : r.output
    }

    /// Variablen einer Claude-Session, die nie in neue Sessions durchsickern dürfen
    /// (sonst hält sich die neue Session für ein Kind der startenden: Session-ID, Nachrichten-Socket …).
    static func isInherited(_ key: String) -> Bool {
        key.hasPrefix("CLAUDE") || key == "AI_AGENT" || key == "TMUX" || key == "TMUX_PANE"
    }

    /// Der tmux-Server übernimmt die Umgebung dessen, der ihn startet, und gibt sie an jede neue
    /// Session weiter. Darum vor jedem Start die Claude-Variablen aus seiner globalen Umgebung entfernen.
    static func scrubServer() {
        let r = run(["show-environment", "-g"])
        guard r.status == 0 else { return }
        for line in r.output.split(separator: "\n") {
            let key = String(line.split(separator: "=", maxSplits: 1).first ?? "")
            if isInherited(key) { _ = run(["set-environment", "-g", "-u", key]) }
        }
    }

    /// Umgebung für tmux-Aufrufe: ohne TMUX (sonst verweigert tmux das Verschachteln) und ohne Claude-Variablen.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !isInherited($0.key) }
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if let loginPath { env["PATH"] = loginPath }
        return env
    }

    static func environmentList() -> [String] { environment().map { "\($0.key)=\($0.value)" } }

    // Aus dem Dock gestartet erbt die App keinen Login-PATH; den holen wir einmal aus zsh.
    private static let loginPath: String? = shell("print -r -- $PATH")

    private static func shell(_ cmd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }

    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        guard let path else { return (-1, "tmux not installed") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = serverArgs + args
        p.environment = environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (p.terminationStatus, s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
