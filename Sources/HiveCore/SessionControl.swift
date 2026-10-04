import Foundation

/// Bausteine zum Steuern einer Session in tmux: Adressierung, Argumente, Entscheidung „beendet?“.
/// Die Aufrufe selbst macht die App (HiveApp/Tmux.swift).
public enum SessionControl {
    /// tmux deutet „.01“ in „lu.01“ sonst als Fenster/Pane; „=name:“ trifft genau diese Session (kein Präfix).
    public static func target(_ name: String) -> String { "=\(name):" }

    /// Text wörtlich tippen (`-l`, `--` auch für Text mit „-“ vorn), danach als eigener Aufruf Enter.
    public static func typeArgs(_ text: String, into name: String) -> [[String]] {
        [["send-keys", "-t", target(name), "-l", "--", text],
         ["send-keys", "-t", target(name), "Enter"]]
    }

    public static func killArgs(_ name: String) -> [String] { ["kill-session", "-t", target(name)] }

    /// Text aus dem Antwortfeld ohne Rand; nil = nichts schicken.
    public static func replyText(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Startzeile für eine Session in tmux.
    public static func claudeCommand(_ name: String) -> String { "claude -n \(shellQuote(name))" }

    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-+/:@%"))
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Ist der Agent nach `/exit` weg? Ja, wenn die tmux-Session fehlt, vorn eine Shell läuft oder
    /// eine zuvor lebende Session im Register nicht mehr lebt. Stand sie nie lebend im Register
    /// (z. B. codex), entscheidet nur die Pane.
    public static func hasExited(wasAlive: Bool, aliveNow: Bool, paneCommand: String?) -> Bool {
        guard let cmd = paneCommand else { return true }
        if SessionStatus.isShell(cmd) { return true }
        return wasAlive && !aliveNow
    }

    /// Zusatzwarnungen für „Close“/„Restart“.
    public static func closeWarnings(_ s: Session) -> [String] {
        var w: [String] = []
        if s.status == "busy" { w.append("It is still working") }
        if !s.hasHandover { w.append("It has no handover yet") }
        return w
    }

    /// Prüft alle `interval` Sekunden, bis `check` true liefert oder `timeout` um ist.
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
