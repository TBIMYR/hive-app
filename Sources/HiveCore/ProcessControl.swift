import Foundation

/// Ends a session's process directly by PID, for sessions Hive can't reach via tmux
/// (iTerm tabs, background sessions) or that no longer react to `/exit`.
public enum ProcessControl {
    /// Start time of a process; a reused PID has a different one. nil = no such process.
    public static func startTime(_ pid: Int) -> Date? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(truncatingIfNeeded: pid)]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }

    /// SIGTERM, after `grace` seconds SIGKILL. Only if the PID still belongs to the process that
    /// started at `started` (see `startTime`). Returns an error message or nil.
    public static func forceQuit(pid: Int, started: Date, grace: TimeInterval = 3) async -> String? {
        guard pid > 1, pid != Int(getpid()) else { return "Refusing to end PID \(pid)" }
        guard let now = startTime(pid) else { return nil }
        guard now == started else { return "PID \(pid) now belongs to another process" }
        let p = pid_t(truncatingIfNeeded: pid)
        if kill(p, SIGTERM) != 0 { return errno == ESRCH ? nil : "Could not end PID \(pid): \(String(cString: strerror(errno)))" }
        let gone = { startTime(pid) != started }
        if await SessionControl.waitUntil(timeout: grace, interval: 0.1, { gone() }) { return nil }
        if kill(p, SIGKILL) != 0, errno != ESRCH { return "Could not kill PID \(pid): \(String(cString: strerror(errno)))" }
        if await SessionControl.waitUntil(timeout: 2, interval: 0.1, { gone() }) { return nil }
        return "PID \(pid) is still running"
    }
}
