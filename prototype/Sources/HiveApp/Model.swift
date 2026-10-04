import Foundation
import SwiftUI

let hiveURL = URL(string: "http://127.0.0.1:7777")!

struct Session: Decodable, Identifiable, Equatable {
    struct Task: Decodable, Equatable {
        let text: String?
        let state: String?
        let updatedAt: String?
        let stale: Bool?
    }

    struct Said: Decodable, Equatable {
        let text: String
        let at: String?
    }

    let name: String
    let group: String?
    let project: String?
    let isPm: Bool?
    let status: String?
    let alive: Bool?
    let kind: String?
    let waitingFor: String?
    let statusUpdatedAt: String?
    let branch: String?
    let cwd: String?
    let pid: Int?
    let task: Task?
    let lastAssistant: Said?
    let hasHandover: Bool?

    var id: String { name }

    /// Group key as in the dashboard (hive groups by name prefix).
    var groupKey: String { group ?? name }

    /// Project abbreviation like abbr() in the dashboard.
    var abbr: String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        let p = (project ?? group ?? "?").filter { $0.isLetter || $0.isNumber }
        return String(p.prefix(2))
    }
}

/// Same order as classify() in public/index.html.
struct Status {
    let rank: Int
    let cls: String
    let label: String
    let color: Color
    let solid: Bool
    let why: String?

    /// `tmuxCommand`: what runs in the foreground of the tmux session (nil = not in the hive tmux server).
    /// If the session is not (alive) in the Claude registry, this command decides:
    /// shell → "Shell", Claude → stuck before startup (usually the trust prompt), otherwise another agent.
    init(_ s: Session, tmuxCommand: String? = nil) {
        let state = s.task?.state
        switch true {
        case tmuxCommand.map(Tmux.isShell) == true && s.alive != true:
            self.init(2, "shell", "Shell", Hive.shell, false)
        case tmuxCommand?.hasPrefix("claude") == true && s.alive != true:
            self.init(0, "need", "waiting at startup", Hive.need, true, why: "Answer the startup prompt in the terminal")
        case tmuxCommand != nil && s.alive != true:
            self.init(2, "agent", tmuxCommand!, Hive.ink2, false)
        case s.status == "offline":
            self.init(3, "off", "offline", Hive.off, false)
        case s.status == "waiting":
            self.init(0, "need", "waiting for you", Hive.need, true, why: s.waitingFor ?? "Input needed")
        case s.status == "busy":
            // a session that is working is not blocked, even if its task line still says "blocked"
            self.init(1, "busy", "working", Hive.busy, true)
        case state == "blocked":
            self.init(0, "block", "blocked", Hive.block, true, why: "Blocked – needs a decision")
        case state == "waiting":
            self.init(2, "wait", "waiting for feedback", Hive.wait, true)
        case s.status == "shell":
            self.init(2, "shell", "Shell", Hive.shell, false)
        default:
            self.init(2, "idle", "ready", Hive.idle, false)
        }
    }

    private init(_ rank: Int, _ cls: String, _ label: String, _ color: Color, _ solid: Bool, why: String? = nil) {
        self.rank = rank
        self.cls = cls
        self.label = label
        self.color = color
        self.solid = solid
        self.why = why
    }
}

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var error: String?
    /// One-second tick for "x min ago", even when the data does not change
    @Published private(set) var now = Date()
    /// Running tmux sessions → foreground command (fetched once per poll)
    @Published private(set) var tmuxPanes: [String: String] = [:]
    var tmuxNames: Set<String> { Set(tmuxPanes.keys) }

    /// Reload right after creating a session instead of waiting up to 2 s.
    func refreshSoon() { Task { await refresh() } }
    private var timer: Timer?

    private struct Payload: Decodable { let sessions: [Session] }

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: hiveURL.appending(path: "api/state"))
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            if payload.sessions != sessions { sessions = payload.sessions }
            error = nil
            let panes = await Task.detached { Tmux.panes() }.value
            if panes != tmuxPanes { tmuxPanes = panes }
        } catch {
            self.error = "hive not reachable (\(hiveURL.absoluteString)): \(error.localizedDescription)"
        }
        now = Date()
    }

    /// Status taking tmux into account (see Status.init).
    func status(_ s: Session) -> Status { Status(s, tmuxCommand: tmuxPanes[s.name]) }

    /// Sessions from hive plus tmux sessions hive does not know yet (no registry entry, no handover).
    var displaySessions: [Session] {
        let known = Set(sessions.map(\.name))
        let extra = tmuxNames.subtracting(known).sorted().map { name in
            Session(name: name, group: SessionNaming.prefix(name) ?? name, project: nil, isPm: name.hasSuffix(".pm"),
                    status: "offline", alive: false, kind: nil, waitingFor: nil, statusUpdatedAt: nil, branch: nil,
                    cwd: nil, pid: nil, task: nil, lastAssistant: nil, hasHandover: false)
        }
        return sessions + extra
    }

    /// Project name per group, like groupLabels() in the dashboard (the PM determines the name).
    var labels: [String: String] {
        var m: [String: String] = [:]
        for s in sessions {
            if m[s.groupKey] == nil { m[s.groupKey] = s.project?.isEmpty == false ? s.project! : s.groupKey }
            if s.isPm == true, let p = s.project, !p.isEmpty { m[s.groupKey] = p }
        }
        return m
    }

    /// Color per group: groups alphabetically, palette in order.
    func color(for group: String) -> Color {
        let keys = labels.keys.sorted()
        guard let i = keys.firstIndex(of: group) else { return Color(nsColor: NSColor(hex: 0x1B1B1B)) }
        return Color(nsColor: NSColor(hex: Hive.palette[i % Hive.palette.count]))
    }

    /// The session's handover without frontmatter, as in the dashboard sidebar. nil if there is none.
    func handover(_ name: String) async -> String? {
        guard let (data, res) = try? await URLSession.shared.data(from: hiveURL.appending(path: "api/handover/\(name)")),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex)
        else { return text }
        return String(text[end.upperBound...])
    }

    /// Jumps to the session's iTerm tab, like the dashboard. Returns an error message or nil.
    func focusInITerm(_ s: Session) async -> String? {
        guard let pid = s.pid else { return "no PID" }
        var req = URLRequest(url: hiveURL.appending(path: "api/focus/\(pid)"))
        req.httpMethod = "POST"
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            if (res as? HTTPURLResponse)?.statusCode == 200 { return nil }
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
            return reason ?? "Cannot jump to tab"
        } catch {
            return "hive not reachable"
        }
    }
}
