import Foundation

public struct RegistryEntry: Equatable, Sendable {
    public let pid: Int
    public var name: String
    public let cwd: String
    public let sessionId: String?
    public var status: String
    public var waitingFor: String?
    public let kind: String?
    /// tmux pane Claude is running in ("%13"), independent of session and tmux names
    public let tmuxPane: String?
    public let startedAt: Double
    public var statusUpdatedAt: String?
    public let alive: Bool
    /// Background session: its job; window: which job it handed its conversation over to
    public let jobId: String?
    public let parkedJobId: String?
    /// Remote Control is on (the registry carries a `bridgeSessionId` while it is connected)
    public var remoteControl: Bool = false
}

/// Reads the Claude registry ~/.claude/sessions/*.json like hive/lib/registry.js.
public enum Registry {
    public static func isAlive(_ pid: Int) -> Bool {
        kill(pid_t(truncatingIfNeeded: pid), 0) == 0 || errno == EPERM
    }

    /// "keeper.01:@13.%13" → "%13". The pane id stays the same when the session or tmux is renamed.
    public static func paneOf(_ tmux: String?) -> String? {
        guard let tmux, let r = tmux.range(of: #"%\d+$"#, options: .regularExpression) else { return nil }
        return String(tmux[r])
    }

    public static func read(_ dir: String, isAlive: (Int) -> Bool = Registry.isAlive) -> (entries: [RegistryEntry], errors: [String]) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return ([], []) }
        var entries: [RegistryEntry] = []
        var errors: [String] = []
        for f in files.sorted() where f.hasSuffix(".json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(f)"))
                guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pidValue = number(j["pid"]),
                      // Int(Double) crashes on 1e20 or NaN; such entries aren't processes
                      let pid = Int(exactly: pidValue.rounded(.towardZero)) else { continue }
                // Spare process of Claude Code for the next background session, not a session yet
                if j["spare"] as? Bool == true { continue }
                // JS: j.statusUpdatedAt ?? j.updatedAt
                let updated = j["statusUpdatedAt"].flatMap { $0 is NSNull ? nil : $0 } ?? j["updatedAt"]
                entries.append(RegistryEntry(
                    pid: pid,
                    name: string(j["name"]) ?? "pid-\(pid)",
                    cwd: string(j["cwd"]) ?? "",
                    sessionId: string(j["sessionId"]),
                    status: string(j["status"]) ?? "unknown",
                    waitingFor: string(j["waitingFor"]),
                    kind: string(j["kind"]),
                    tmuxPane: paneOf(string(j["tmux"])),
                    startedAt: number(j["startedAt"]) ?? 0,
                    statusUpdatedAt: number(updated).map { isoString(ms: $0) },
                    alive: isAlive(pid),
                    jobId: string(j["jobId"]),
                    parkedJobId: string(j["parkedJobId"]),
                    remoteControl: string(j["bridgeSessionId"]) != nil
                ))
            } catch {
                errors.append("\(f): \(error.localizedDescription)")
            }
        }
        // If a window has handed its conversation to a background session (parkedJobId), the work
        // runs there and the window only displays it: one session with the status from there.
        var jobs: [String: Int] = [:]
        for (i, e) in entries.enumerated() where e.alive { if let j = e.jobId { jobs[j] = i } }
        var parked = Set<Int>()
        for i in entries.indices where entries[i].alive {
            guard let p = entries[i].parkedJobId, let k = jobs[p], k != i else { continue }
            entries[i].status = entries[k].status
            entries[i].waitingFor = entries[k].waitingFor
            entries[i].statusUpdatedAt = entries[k].statusUpdatedAt
            entries[i].remoteControl = entries[i].remoteControl || entries[k].remoteControl
            parked.insert(k)
        }
        entries = entries.enumerated().filter { !parked.contains($0.offset) }.map(\.element)
        // Duplicates among live entries: the name is kept first by a session with
        // a window (kind != "bg"), then by the newest; all others get #pid.
        // Background sessions run without a window and would otherwise be unfindable.
        var byName: [String: [Int]] = [:]
        for (i, e) in entries.enumerated() where e.alive { byName[e.name, default: []].append(i) }
        for indices in byName.values where indices.count > 1 {
            let ranked = indices.sorted { a, b in
                let (x, y) = (entries[a], entries[b])
                let (bgX, bgY) = (x.kind == "bg" ? 1 : 0, y.kind == "bg" ? 1 : 0)
                if bgX != bgY { return bgX < bgY }
                if x.startedAt != y.startedAt { return x.startedAt > y.startedAt }
                return a < b
            }
            for i in ranked.dropFirst() { entries[i].name = "\(entries[i].name)#\(entries[i].pid)" }
        }
        return (entries, errors)
    }
}
