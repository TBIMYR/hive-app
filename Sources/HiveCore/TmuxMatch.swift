import Foundation

/// Maps sessions to their tmux session in the hive server.
public enum TmuxMatch {
    /// `tmuxSessions`: names of the running tmux sessions; `sessionOfPane`: pane ID → tmux session.
    /// Returns session `id` → tmux session. Live sessions first via the pane ID from the registry:
    /// that stays valid when the session or the tmux session is renamed via /rename. Otherwise by
    /// the same name, but only if no live session already claims that tmux session (otherwise, e.g.,
    /// an old handover under the former name would mistake the running session for its own).
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
