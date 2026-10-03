import Foundation

/// Ordnet Sessions ihrer tmux-Session im hive-Server zu.
public enum TmuxMatch {
    /// `tmuxSessions`: Namen der laufenden tmux-Sessions; `sessionOfPane`: Pane-ID → tmux-Session.
    /// Liefert Session-`id` → tmux-Session. Lebende Sessions zuerst über die Pane-ID aus dem Register:
    /// die bleibt, wenn die Session per /rename oder die tmux-Session umbenannt wird. Sonst über den
    /// gleichen Namen, aber nur, wenn keine lebende Session diese tmux-Session schon belegt (sonst
    /// hielte z. B. ein altes Handover unter dem früheren Namen die laufende Session für seine).
    public static func resolve(_ sessions: [Session], tmuxSessions: Set<String>,
                               sessionOfPane: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        var taken = Set<String>()
        for s in sessions where s.alive {
            if let pane = s.tmuxPane, let t = sessionOfPane[pane] {
                result[s.id] = t
                taken.insert(t)
            }
        }
        for s in sessions where result[s.id] == nil && tmuxSessions.contains(s.name) && !taken.contains(s.name) {
            result[s.id] = s.name
        }
        return result
    }
}
