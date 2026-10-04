import Foundation

/// Building blocks for controlling a session in tmux: addressing, arguments, deciding "exited?".
/// The actual calls are made by the app (HiveApp/Tmux.swift).
public enum SessionControl {
    /// tmux would otherwise interpret ".01" in "lu.01" as a window/pane; "=name:" matches exactly this session (no prefix).
    public static func target(_ name: String) -> String { "=\(name):" }

    /// Type text literally (`-l`, `--` also for text starting with "-"), then Enter as a separate call.
    public static func typeArgs(_ text: String, into name: String) -> [[String]] {
        [["send-keys", "-t", target(name), "-l", "--", text],
         ["send-keys", "-t", target(name), "Enter"]]
    }

    /// Session screen as text (read-only).
    public static func captureArgs(_ name: String) -> [String] { ["capture-pane", "-p", "-t", target(name)] }

    /// Send a single key (digit of an option, "Enter").
    public static func keyArgs(_ key: String, into name: String) -> [String] { ["send-keys", "-t", target(name), key] }

    public static func killArgs(_ name: String) -> [String] { ["kill-session", "-t", target(name)] }

    /// Text from the reply field, trimmed; nil = send nothing.
    public static func replyText(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Start line for a session in tmux.
    public static func claudeCommand(_ name: String) -> String { "claude -n \(shellQuote(name))" }

    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-+/:@%"))
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Is the agent gone after `/exit`? Yes if the tmux session is missing, a shell is running in front,
    /// or a previously alive session in the registry is no longer alive. If it was never alive in the
    /// registry (e.g. codex), only the pane decides.
    public static func hasExited(wasAlive: Bool, aliveNow: Bool, paneCommand: String?) -> Bool {
        guard let cmd = paneCommand else { return true }
        if SessionStatus.isShell(cmd) { return true }
        return wasAlive && !aliveNow
    }

    /// Extra warnings for "Close"/"Restart".
    public static func closeWarnings(_ s: Session) -> [String] {
        var w: [String] = []
        if s.status == "busy" { w.append("It is still working") }
        if !s.hasHandover { w.append("It has no handover yet") }
        return w
    }

    /// Checks every `interval` seconds until `check` returns true or `timeout` runs out.
    public static func waitUntil(timeout: TimeInterval, interval: TimeInterval,
                                 _ check: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while true {
            if await check() { return true }
            if Date() >= end { return false }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
