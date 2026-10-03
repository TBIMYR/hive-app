import Foundation

enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// tmux deutet ".01" in "lu.01" sonst als Pane; "=name:" trifft genau die Session.
    static func target(_ name: String) -> String { "=\(name):" }

    static func hasSession(_ name: String) -> Bool {
        run(["has-session", "-t", target(name)]).status == 0
    }

    /// Startet `claude -n <name>` in einer neuen tmux-Session. Liefert eine Fehlermeldung oder nil.
    static func newSession(name: String, dir: String) -> String? {
        guard let claude = claudePath else { return "claude nicht gefunden" }
        // ohne Statusleiste: sie verdeckt sonst die unterste Zeile von Claude Code
        let r = run(["new-session", "-d", "-s", name, "-c", dir, claude, "-n", name,
                     ";", "set-option", "-t", target(name), "status", "off"])
        return r.status == 0 ? nil : (r.output.isEmpty ? "tmux-Fehler \(r.status)" : r.output)
    }

    /// Umgebung für tmux-Aufrufe: ohne TMUX (sonst verweigert tmux das Verschachteln).
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TMUX"] = nil
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
