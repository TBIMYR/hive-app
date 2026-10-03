import Foundation

enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// tmux deutet ".01" in "lu.01" sonst als Pane; "=name:" trifft genau die Session.
    static func target(_ name: String) -> String { "=\(name):" }

    static func listSessions() -> Set<String> {
        let r = run(["list-sessions", "-F", "#{session_name}"])
        guard r.status == 0 else { return [] }   // kein tmux-Server = keine Sessions
        return Set(r.output.split(separator: "\n").map(String.init))
    }

    static func hasSession(_ name: String) -> Bool {
        run(["has-session", "-t", target(name)]).status == 0
    }

    /// Startet `claude -n <name>` in einer neuen tmux-Session. Liefert eine Fehlermeldung oder nil.
    static func newSession(name: String, dir: String) -> String? {
        guard let claude = claudePath else { return "claude nicht gefunden" }
        scrubServer()
        // ohne Statusleiste: sie verdeckt sonst die unterste Zeile von Claude Code
        let r = run(["new-session", "-d", "-s", name, "-c", dir, claude, "-n", name,
                     ";", "set-option", "-t", target(name), "status", "off"])
        return r.status == 0 ? nil : (r.output.isEmpty ? "tmux-Fehler \(r.status)" : r.output)
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
    private static let claudePath: String? = shell("command -v claude")

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
        guard let path else { return (-1, "tmux nicht installiert") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
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
