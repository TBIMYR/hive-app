import Foundation

/// Context window usage per session, written by the status line script to
/// `~/.claude/hive/context/<sessionId>.json` (`{"used_percentage": 37, "written_at": …}`).
public enum ContextUsage {
    /// Percent used (0–100), nil if there is no readable file for this session.
    public static func percent(claudeHome: String, sessionId: String) -> Double? {
        guard Handover.isSafeName(sessionId),
              let data = FileManager.default.contents(atPath: "\(claudeHome)/hive/context/\(sessionId).json"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = number(obj["used_percentage"]) else { return nil }
        return min(max(p, 0), 100)
    }
}
