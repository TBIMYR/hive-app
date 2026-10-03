import Foundation

/// Eine Zeile der Übersicht, gleiche Felder wie in GET /api/state.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    public struct TaskLine: Codable, Equatable, Sendable {
        public let text: String
        public let state: String?
        public let updatedAt: String?
        /// arbeitet, aber die Aufgaben-Zeile ist älter als eine Stunde
        public let stale: Bool

        public init(text: String, state: String?, updatedAt: String?, stale: Bool) {
            self.text = text
            self.state = state
            self.updatedAt = updatedAt
            self.stale = stale
        }
    }

    public let name: String
    public let project: String
    public let group: String
    public let isPm: Bool
    public let cwd: String?
    public let pid: Int?
    public let kind: String?
    /// tmux-Pane laut Register („%13“); die App findet darüber die tmux-Session, auch nach /rename
    public let tmuxPane: String?
    public let alive: Bool
    public let status: String
    public let waitingFor: String?
    public let statusUpdatedAt: String?
    public let branch: String?
    public let lastAssistant: Said?
    public let lastUser: Said?
    public let task: TaskLine?
    public let hasHandover: Bool
    /// Lesefehler zu dieser Session (Handover), für einen Hinweis in der Karte
    public let errors: [String]

    /// Eindeutig auch dann, wenn ein toter Register-Eintrag und eine lebende Session denselben Namen tragen
    /// (das Register benennt nur lebende Duplikate um). Für die Auswahl in der App weiter `name` nehmen.
    public var id: String { pid.map { "\(name)|\($0)" } ?? name }

    public init(name: String, project: String = "", group: String, isPm: Bool = false, cwd: String? = nil,
                pid: Int? = nil, kind: String? = nil, tmuxPane: String? = nil, alive: Bool = false, status: String = "offline",
                waitingFor: String? = nil, statusUpdatedAt: String? = nil, branch: String? = nil,
                lastAssistant: Said? = nil, lastUser: Said? = nil, task: TaskLine? = nil,
                hasHandover: Bool = false, errors: [String] = []) {
        self.name = name
        self.project = project
        self.group = group
        self.isPm = isPm
        self.cwd = cwd
        self.pid = pid
        self.kind = kind
        self.tmuxPane = tmuxPane
        self.alive = alive
        self.status = status
        self.waitingFor = waitingFor
        self.statusUpdatedAt = statusUpdatedAt
        self.branch = branch
        self.lastAssistant = lastAssistant
        self.lastUser = lastUser
        self.task = task
        self.hasHandover = hasHandover
        self.errors = errors
    }
}

public struct HiveState: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sessions: [Session]
    /// Dateien im Register, die sich nicht lesen ließen
    public let errors: [String]
}

/// Führt Register, Handover und Gesprächsprotokolle zusammen (wie buildState() in hive/lib/state.js).
public enum StateBuilder {
    public static let defaultClaudeHome = "\(home)/.claude"
    public static let staleAfter: TimeInterval = 60 * 60
    static let maxText = 600
    /// entspricht localeCompare in Node (geprüft mit Punkt, #, -, _, Umlauten, Großschreibung)
    private static let collation = Locale(identifier: "en")

    public static func build(claudeHome: String = defaultClaudeHome, devRoot: String = Project.defaultDevRoot,
                             now: Date = Date(), isAlive: (Int) -> Bool = Registry.isAlive) -> HiveState {
        let reg = Registry.read("\(claudeHome)/sessions", isAlive: isAlive)
        let handovers = Handover.readDir("\(claudeHome)/handover")
        var sessions: [Session] = []
        var seen = Set<String>()

        for e in reg.entries {
            let h = handovers[e.name]
            if !e.alive && h == nil { continue }
            var tail = Tail()
            if let sid = e.sessionId, !e.cwd.isEmpty {
                tail = Transcript.parseTail(Transcript.readTail("\(claudeHome)/projects/\(Project.slug(e.cwd))/\(sid).jsonl"))
            }
            let project = Project.fromCwd(e.cwd, devRoot: devRoot)
            let status = e.alive ? e.status : "offline"
            sessions.append(Session(
                name: e.name, project: project, group: Project.groupKey(e.name, project: project),
                isPm: Project.isPm(e.name), cwd: e.cwd, pid: e.pid, kind: e.kind, tmuxPane: e.tmuxPane, alive: e.alive, status: status,
                waitingFor: e.waitingFor, statusUpdatedAt: e.statusUpdatedAt, branch: tail.branch,
                lastAssistant: clip(tail.lastAssistant), lastUser: clip(tail.lastUser),
                task: taskOf(h, status: status, now: now), hasHandover: h != nil,
                errors: h?.error.map { ["handover: \($0)"] } ?? []
            ))
            seen.insert(e.name)
        }

        for (name, h) in handovers where !seen.contains(name) {
            let project = h.project ?? ""
            sessions.append(Session(
                name: name, project: project, group: Project.groupKey(name, project: project),
                isPm: Project.isPm(name), task: taskOf(h, status: "offline", now: now), hasHandover: true,
                errors: h.error.map { ["handover: \($0)"] } ?? []
            ))
        }

        sessions.sort { a, b in
            let g = a.group.compare(b.group, locale: collation)
            if g != .orderedSame { return g == .orderedAscending }
            if a.isPm != b.isPm { return a.isPm }
            return a.name.compare(b.name, locale: collation) == .orderedAscending
        }
        return HiveState(generatedAt: isoString(ms: now.timeIntervalSince1970 * 1000), sessions: sessions, errors: reg.errors)
    }

    static func taskOf(_ h: HandoverEntry?, status: String, now: Date) -> Session.TaskLine? {
        guard let h, let text = h.task else { return nil }
        let updated = h.updatedAt.flatMap(parseISO)
        let stale = status == "busy" && (updated.map { now.timeIntervalSince($0) > staleAfter } ?? true)
        return Session.TaskLine(text: text, state: h.state, updatedAt: h.updatedAt, stale: stale)
    }

    /// Kürzt auf 600 UTF-16-Einheiten wie text.slice(0, 600) in JS.
    static func clip(_ s: Said?) -> Said? {
        guard let s, s.text.utf16.count > maxText else { return s }
        return Said(text: String(decoding: Array(s.text.utf16.prefix(maxText)), as: UTF16.self) + "…", at: s.at)
    }
}
