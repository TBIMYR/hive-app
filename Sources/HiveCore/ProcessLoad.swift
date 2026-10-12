import Foundation

/// CPU load of a session: its own process plus everything it started (tests, builds, dev servers), measured
/// in percent of one core like Activity Monitor (250 = two and a half cores), shown as a share of the Mac.
/// Processes that detached themselves (reparented to launchd) are not counted.
public enum ProcessLoad {
    public struct Row: Equatable, Sendable {
        public let pid: Int
        public let ppid: Int
        public let cpu: Double

        public init(pid: Int, ppid: Int, cpu: Double) {
            self.pid = pid
            self.ppid = ppid
            self.cpu = cpu
        }
    }

    /// Share of the whole Mac in percent from which a session's load is shown / highlighted
    public static let showFrom = 5
    public static let warnFrom = 25

    /// Lines of `ps -axo pid=,ppid=,pcpu=`. The decimal sign follows the locale ("12,5").
    public static func parse(_ ps: String) -> [Row] {
        ps.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count == 3, let pid = Int(f[0]), let ppid = Int(f[1]),
                  let cpu = Double(f[2].replacingOccurrences(of: ",", with: ".")) else { return nil }
            return Row(pid: pid, ppid: ppid, cpu: cpu)
        }
    }

    /// Summed load per root over its process tree. A root below another root keeps its own subtree, so
    /// nothing is counted twice.
    public static func perRoot(_ rows: [Row], roots: [Int]) -> [Int: Double] {
        var children: [Int: [Row]] = [:]
        var cpu: [Int: Double] = [:]
        for r in rows {
            children[r.ppid, default: []].append(r)
            cpu[r.pid] = r.cpu
        }
        let rootSet = Set(roots)
        var result: [Int: Double] = [:]
        for root in rootSet {
            guard var sum = cpu[root] else { continue }
            var queue = [root]
            var seen: Set<Int> = [root]
            while let p = queue.popLast() {
                for c in children[p] ?? [] where !rootSet.contains(c.pid) && seen.insert(c.pid).inserted {
                    sum += c.cpu
                    queue.append(c.pid)
                }
            }
            result[root] = sum
        }
        return result
    }

    /// What the UI shows: the share of the whole Mac in percent (all cores busy = 100), nil below `showFrom`.
    public static func share(_ cpu: Double, cores: Int) -> Int? {
        let p = Int((cpu / Double(max(cores, 1))).rounded())
        return p >= showFrom ? min(p, 100) : nil
    }

    /// "3.2" style number of busy cores for the tooltip.
    public static func coresText(_ cpu: Double) -> String {
        let c = cpu / 100
        return c == c.rounded() ? "\(Int(c))" : String(format: "%.1f", c)
    }

    /// Current load per root PID (one `ps` call for all sessions); empty if `ps` fails.
    public static func sample(roots: [Int]) -> [Int: Double] {
        guard !roots.isEmpty else { return [:] }
        let r = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,pcpu="])
        guard r.status == 0 else { return [:] }
        return perRoot(parse(r.out), roots: roots)
    }
}
