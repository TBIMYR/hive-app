import Foundation
import HiveCore

/// Hive's state as a few compact lines for the model, sent along with every user turn.
public enum StateSummary {
    public static func lines(_ sessions: [Session], names: SpokenNames? = nil) -> String {
        let live = sessions.filter(\.alive).sorted { ($0.group, $0.name) < ($1.group, $1.name) }
        let offline = sessions.filter { !$0.alive && $0.hasHandover }.map(\.name).sorted()
        var out = live.map { line($0, spoken: names?.spoken[$0.name]) }
        if out.isEmpty { out.append("(no session running)") }
        if !offline.isEmpty { out.append("offline with handover: " + offline.joined(separator: ", ")) }
        return out.joined(separator: "\n")
    }

    static func line(_ s: Session, spoken: String? = nil) -> String {
        var parts = ["\(s.name) [project \(s.project.isEmpty ? s.group : s.project)\(s.isPm ? ", PM" : "")]"]
        if let spoken, spoken != s.name { parts[0] += " spoken \"\(spoken)\"" }
        parts.append("status: \(s.status)")
        if let w = s.waitingFor, !w.isEmpty { parts.append("waits for: \(clip(w, 140))") }
        if let t = s.task, !t.text.isEmpty {
            var task = "task: \"\(t.text)\""
            if let st = t.state { task += " (\(st)\(t.stale ? ", stale" : ""))" }
            if let d = t.detail, !d.isEmpty { task += " – \(d)" }
            parts.append(task)
        }
        if let last = s.lastSentence, !last.isEmpty { parts.append("last said: \"\(clip(last, 160))\"") }
        return "- " + parts.joined(separator: "; ")
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.count <= n ? one : String(one.prefix(n)) + "…"
    }
}
