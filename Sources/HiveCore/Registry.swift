import Foundation

public struct RegistryEntry: Equatable, Sendable {
    public let pid: Int
    public var name: String
    public let cwd: String
    public let sessionId: String?
    public let status: String
    public let waitingFor: String?
    public let kind: String?
    /// tmux-Pane, in der Claude läuft („%13“), unabhängig von Session- und tmux-Namen
    public let tmuxPane: String?
    public let startedAt: Double
    public let statusUpdatedAt: String?
    public let alive: Bool
}

/// Liest das Claude-Register ~/.claude/sessions/*.json wie hive/lib/registry.js.
public enum Registry {
    public static func isAlive(_ pid: Int) -> Bool {
        kill(pid_t(truncatingIfNeeded: pid), 0) == 0 || errno == EPERM
    }

    /// "keeper.01:@13.%13" → "%13". Die Pane-ID bleibt, wenn Session oder tmux umbenannt werden.
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
                      // Int(Double) stürzt bei 1e20 oder NaN ab; solche Einträge sind keine Prozesse
                      let pid = Int(exactly: pidValue.rounded(.towardZero)) else { continue }
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
                    alive: isAlive(pid)
                ))
            } catch {
                errors.append("\(f): \(error.localizedDescription)")
            }
        }
        // Duplikate unter lebenden Einträgen: den Namen behält zuerst eine Session mit
        // Fenster (kind != "bg"), danach die jüngste; alle anderen bekommen #pid.
        // Hintergrund-Sessions laufen ohne Fenster und wären sonst nicht auffindbar.
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
