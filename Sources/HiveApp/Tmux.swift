import Foundation
import HiveCore

enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Otherwise tmux interprets ".01" in "al.01" as a pane; "=name:" matches exactly the session.
    static func target(_ name: String) -> String { SessionControl.target(name) }

    /// A dedicated server just for the app (`tmux -L hive`), so its settings don't collide
    /// with a manually started tmux. `-f` only applies when the server starts.
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
        /// tmux session → command currently running in front ("claude.exe", "zsh", "codex", …)
        var commands: [String: String] = [:]
        /// Pane ID ("%13") → tmux session, for mapping via the registry
        var sessionOfPane: [String: String] = [:]
        /// tmux session → folder of its first pane (for "Restart" on sessions without a registry)
        var paths: [String: String] = [:]
    }

    static func panes() -> Panes {
        let r = run(["list-panes", "-a", "-F", "#{session_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"])
        guard r.status == 0 else { return Panes() }   // no tmux server = no sessions
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

    /// Opens a shell in a new tmux session in the folder and pre-types `claude -n <name>`,
    /// without Enter: you start it yourself and can change the line beforehand (e.g. `codex`, `--resume`).
    /// With `submit` (Restart), Enter follows, so Claude starts right away.
    /// `HIVE_SESSION` carries the name, no matter which agent runs later. Returns an error message or nil.
    static func newSession(name: String, dir: String, submit: Bool = false) -> String? {
        scrubServer()
        let r = run(["new-session", "-d", "-s", name, "-c", dir, "-e", "HIVE_SESSION=\(name)"])
        guard r.status == 0 else { return r.output.isEmpty ? "tmux error \(r.status)" : r.output }
        // only type once the shell has read its startup files
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let cmds = SessionControl.typeArgs(SessionControl.claudeCommand(name), into: name)
            _ = run(cmds[0])
            if submit { _ = run(cmds[1]) }
        }
        return nil
    }

    /// Types text into the session and submits it with Enter. Blocks briefly, so don't call it
    /// on the main thread. Returns an error message or nil.
    static func type(_ text: String, into name: String) -> String? {
        let cmds = SessionControl.typeArgs(text, into: name)
        let r = run(cmds[0])
        guard r.status == 0 else { return failure(r) }
        // brief pause so Claude Code doesn't treat Enter as part of pasted text
        Thread.sleep(forTimeInterval: 0.15)
        let e = run(cmds[1])
        return e.status == 0 ? nil : failure(e)
    }

    /// Ends Remote Control: `/remote-control` opens Claude Code's dialog (Disconnect this session /
    /// Show QR code / Continue, with "Continue" preselected). Moves up to "Disconnect this session" and
    /// confirms with Enter. Blocks up to ~4 s, don't call it on the main thread. Returns an error message or nil.
    static func endRemoteControl(in name: String) -> String? {
        if let e = type("/remote-control", into: name) { return e }
        var shown = false
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            if capture(name)?.contains("Disconnect this session") == true { shown = true; break }
        }
        guard shown else { return "Remote Control dialog didn't appear – check the terminal" }
        for _ in 0..<4 {
            if capture(name)?.contains("❯ Disconnect this session") == true {
                let e = run(SessionControl.keyArgs("Enter", into: name))
                return e.status == 0 ? nil : failure(e)
            }
            _ = run(SessionControl.keyArgs("Up", into: name))
            Thread.sleep(forTimeInterval: 0.2)
        }
        return "Couldn't select Disconnect – check the terminal"
    }

    /// The session's screen as text, nil on error.
    static func capture(_ name: String) -> String? {
        let r = run(SessionControl.captureArgs(name))
        return r.status == 0 ? r.output : nil
    }

    static let dialogChanged = "Dialog changed – answer in the terminal"

    /// Answer button: find the dialog on the screen, type the option's digit; if the same dialog
    /// is still there afterward and the option is marked, also send Enter. If the option isn't found, or
    /// someone is currently typing into a free-text option, nothing is sent. Blocks briefly, don't call
    /// it on the main thread. `known`: options according to the transcript. Returns a message or nil.
    static func answer(_ answer: ScreenDialog.Answer, known: [String], in name: String) -> String? {
        guard let before = capture(name).flatMap(ScreenDialog.parse), let option = before.pick(answer)
        else { return dialogChanged }
        if case .option = answer, before.selectionOutside(known) { return dialogChanged }
        let r = run(SessionControl.keyArgs(String(option.number), into: name))
        guard r.status == 0 else { return failure(r) }
        Thread.sleep(forTimeInterval: 0.3)
        // dialog gone or a different one: the digit already made the selection
        guard let after = capture(name).flatMap(ScreenDialog.parse),
              after.options.map(\.label) == before.options.map(\.label) else { return nil }
        // same options but different text above: possibly already the next question, no Enter
        guard after.sameDialog(as: before) else { return "Check the terminal" }
        let marked = after.options.filter(\.selected)
        guard marked.map(\.number) == [option.number] else { return dialogChanged }
        let e = run(SessionControl.keyArgs("Enter", into: name))
        return e.status == 0 ? nil : failure(e)
    }

    /// Ends the tmux session (exactly this one). Returns an error message or nil.
    static func kill(_ name: String) -> String? {
        let r = run(SessionControl.killArgs(name))
        return r.status == 0 ? nil : failure(r)
    }

    private static func failure(_ r: (status: Int32, output: String)) -> String {
        r.output.isEmpty ? "tmux error \(r.status)" : r.output
    }

    /// Variables of a Claude session that must never leak into new sessions
    /// (otherwise the new session thinks it's a child of the one that started it: session ID, message socket, …).
    static func isInherited(_ key: String) -> Bool {
        key.hasPrefix("CLAUDE") || key == "AI_AGENT" || key == "TMUX" || key == "TMUX_PANE"
    }

    /// The tmux server inherits the environment of whoever starts it, and passes it on to every new
    /// session. So remove the Claude variables from its global environment before every start.
    static func scrubServer() {
        let r = run(["show-environment", "-g"])
        guard r.status == 0 else { return }
        for line in r.output.split(separator: "\n") {
            let key = String(line.split(separator: "=", maxSplits: 1).first ?? "")
            if isInherited(key) { _ = run(["set-environment", "-g", "-u", key]) }
        }
    }

    /// Environment for tmux calls: without TMUX (otherwise tmux refuses nesting) and without Claude variables.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !isInherited($0.key) }
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if let loginPath = LoginShell.path { env["PATH"] = loginPath }
        return env
    }

    static func environmentList() -> [String] { environment().map { "\($0.key)=\($0.value)" } }

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
