import Foundation
import HiveCore

/// Which sessions just finished, for the voice: the task line turned "done", or a session that worked for at least
/// `minWork` without a break is quiet again (short back-and-forth turns don't count). Waiting for the user is
/// not "done" (Attention announces that). The first update only takes stock, like AttentionTracker.
public struct DoneTracker {
    public static let minWork: TimeInterval = 120

    private var taskState: [String: String] = [:]
    private var busySince: [String: Date] = [:]
    private var started = false

    public init() {}

    /// name → what to tell (the task line, if any)
    public mutating func update(_ sessions: [Session], now: Date) -> [String: String] {
        var done: [String: String] = [:]
        var seen = Set<String>()
        for s in sessions where s.alive && seen.insert(s.name).inserted {
            let state = s.task?.state
            let task = s.task?.text ?? ""
            if started, state == "done", let before = taskState[s.name], before != "done" { done[s.name] = task }
            taskState[s.name] = state ?? ""

            let rank0 = SessionStatus(s).rank == 0
            if s.status == "busy" {
                if busySince[s.name] == nil { busySince[s.name] = now }
            } else if let since = busySince.removeValue(forKey: s.name) {
                if started, !rank0, now.timeIntervalSince(since) >= Self.minWork { done[s.name] = task }
            }
        }
        // gone sessions start over
        taskState = taskState.filter { seen.contains($0.key) }
        busySince = busySince.filter { seen.contains($0.key) }
        started = true
        return done
    }
}
