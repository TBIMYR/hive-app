import Foundation
import HiveCore

/// Which sessions just finished, for the voice: the task line turned "done", or a session that worked for at least
/// `minWork` without a break is quiet again (short back-and-forth turns don't count). Waiting for the user is
/// not "done" (Attention announces that). The first update only takes stock, like AttentionTracker.
/// Both signals usually come for the same finish a few seconds apart (cc-task done in the last turn, then quiet);
/// that is one report: a finish counts only if the session started working after the last report.
public struct DoneTracker {
    public static let minWork: TimeInterval = 120

    private var taskState: [String: String] = [:]
    private var busySince: [String: Date] = [:]
    /// start of the latest stretch of work, kept after it ends
    private var workStart: [String: Date] = [:]
    private var reported: [String: Date] = [:]
    private var started = false

    public init() {}

    /// name → what to tell (the task line, if any)
    public mutating func update(_ sessions: [Session], now: Date) -> [String: String] {
        var done: [String: String] = [:]
        var seen = Set<String>()
        for s in sessions where s.alive && seen.insert(s.name).inserted {
            let state = s.task?.state
            let task = s.task?.text ?? ""
            // already told about this work: the second signal of the same finish
            let new = reported[s.name].map { last in workStart[s.name].map { $0 > last } ?? false } ?? true
            if started, new, state == "done", let before = taskState[s.name], before != "done" { done[s.name] = task }
            taskState[s.name] = state ?? ""

            let rank0 = SessionStatus(s).rank == 0
            if s.status == "busy" {
                if busySince[s.name] == nil { busySince[s.name] = now; workStart[s.name] = now }
            } else if let since = busySince.removeValue(forKey: s.name) {
                if started, new, done[s.name] == nil, !rank0, now.timeIntervalSince(since) >= Self.minWork { done[s.name] = task }
            }
            if done[s.name] != nil { reported[s.name] = now }
        }
        // gone sessions start over
        taskState = taskState.filter { seen.contains($0.key) }
        busySince = busySince.filter { seen.contains($0.key) }
        workStart = workStart.filter { seen.contains($0.key) }
        reported = reported.filter { seen.contains($0.key) }
        started = true
        return done
    }
}
