import Foundation

enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// tmux would otherwise read ".01" in "lu.01" as a pane; "=name:" matches exactly the session.
    static func target(_ name: String) -> String { "=\(name):" }

    /// Dedicated server just for the app (`tmux -L hive`), so its settings do not clash with
    /// a tmux you started yourself. `-f` only applies when the server starts.
    static let socket = "hive"

    static let config = """
    # written by the hive app, overwritten on every launch
    set -g status off                       # otherwise hides Claude Code's bottom line
    set -g mouse on                         # mouse wheel scrolls the scrollback instead of the input history
    set -sg escape-time 0                   # pass Esc to Claude immediately
    set -g history-limit 50000
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",xterm-256color:RGB"   # true color instead of 256 colors
    set -s extended-keys on                 # makes Shift+Enter etc. distinguishable
    set -g focus-events on
    set -s set-clipboard on                 # copy to the system clipboard via OSC 52
    set -g aggressive-resize on             # size follows the currently displayed terminal
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

    /// Running tmux sessions with their current foreground command ("claude.exe", "zsh", "codex" …).
    static func panes() -> [String: String] {
        let r = run(["list-panes", "-a", "-F", "#{session_name}\t#{pane_current_command}"])
        guard r.status == 0 else { return [:] }   // no tmux server = no sessions
        var m: [String: String] = [:]
        for line in r.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if let name = parts.first, m[name] == nil { m[name] = parts.count > 1 ? parts[1] : "" }
        }
        return m
    }

    static func hasSession(_ name: String) -> Bool {
        run(["has-session", "-t", target(name)]).status == 0
    }

    /// Opens a shell in a new tmux session in the folder and pre-types `claude -n <name>`,
    /// without Enter: you start it yourself and can edit the line first (e.g. `codex`, `--resume`).
    /// `HIVE_SESSION` carries the name, whichever agent runs later. Returns an error message or nil.
    static func newSession(name: String, dir: String) -> String? {
        scrubServer()
        let r = run(["new-session", "-d", "-s", name, "-c", dir, "-e", "HIVE_SESSION=\(name)"])
        guard r.status == 0 else { return r.output.isEmpty ? "tmux error \(r.status)" : r.output }
        // only type once the shell has read its startup files
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            _ = run(["send-keys", "-t", target(name), "-l", "claude -n \(name)"])
        }
        return nil
    }

    static func isShell(_ command: String) -> Bool {
        ["zsh", "bash", "fish", "sh", "-zsh", "-bash", "login"].contains(command)
    }

    /// Variables of a Claude session that must never leak into new sessions
    /// (otherwise the new session thinks it is a child of the launching one: session ID, message socket …).
    static func isInherited(_ key: String) -> Bool {
        key.hasPrefix("CLAUDE") || key == "AI_AGENT" || key == "TMUX" || key == "TMUX_PANE"
    }

    /// The tmux server inherits the environment of whoever starts it and passes it on to every new
    /// session. So remove the Claude variables from its global environment before each start.
    static func scrubServer() {
        let r = run(["show-environment", "-g"])
        guard r.status == 0 else { return }
        for line in r.output.split(separator: "\n") {
            let key = String(line.split(separator: "=", maxSplits: 1).first ?? "")
            if isInherited(key) { _ = run(["set-environment", "-g", "-u", key]) }
        }
    }

    /// Environment for tmux calls: without TMUX (otherwise tmux refuses to nest) and without Claude variables.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !isInherited($0.key) }
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if let loginPath { env["PATH"] = loginPath }
        return env
    }

    static func environmentList() -> [String] { environment().map { "\($0.key)=\($0.value)" } }

    // Launched from the Dock, the app inherits no login PATH; fetch it once from zsh.
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
