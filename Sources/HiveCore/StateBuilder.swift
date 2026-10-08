import Foundation

/// A row in the overview, same fields as in GET /api/state.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    public struct TaskLine: Codable, Equatable, Sendable {
        public let text: String
        /// line under the task, from the handover's `detail:` (optional)
        public var detail: String? = nil
        public let state: String?
        public let updatedAt: String?
        /// working, but the task line is older than an hour
        public let stale: Bool

        public init(text: String, detail: String? = nil, state: String?, updatedAt: String?, stale: Bool) {
            self.text = text
            self.detail = detail
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
    /// tmux pane per the registry ("%13"); the app uses this to find the tmux session, even after /rename
    public let tmuxPane: String?
    public let alive: Bool
    public let status: String
    public let waitingFor: String?
    public let statusUpdatedAt: String?
    public let branch: String?
    public let lastAssistant: Said?
    public let lastUser: Said?
    public let task: TaskLine?
    /// last work step (last tool_use) for the "Now" line; not in the Node server
    public let lastAction: WorkAction?
    /// last sentence of the last response; not in the Node server
    public let lastSentence: String?
    public let hasHandover: Bool
    /// background agents and shell commands still running (from the transcript tail); not in the Node server
    public let backgroundTasks: Int
    /// Remote Control is connected (registry `bridgeSessionId`)
    public let remoteControl: Bool
    /// Context window used in percent (from the status line), nil = unknown
    public let contextPercent: Double?
    /// read errors for this session (handover), for a hint in the card
    public let errors: [String]

    /// Unique even when a dead registry entry and a live session share the same name
    /// (the registry only renames live duplicates). Keep using `name` for selection in the app.
    public var id: String { pid.map { "\(name)|\($0)" } ?? name }

    public init(name: String, project: String = "", group: String, isPm: Bool = false, cwd: String? = nil,
                pid: Int? = nil, kind: String? = nil, tmuxPane: String? = nil, alive: Bool = false, status: String = "offline",
                waitingFor: String? = nil, statusUpdatedAt: String? = nil, branch: String? = nil,
                lastAssistant: Said? = nil, lastUser: Said? = nil, task: TaskLine? = nil,
                lastAction: WorkAction? = nil, lastSentence: String? = nil, hasHandover: Bool = false, backgroundTasks: Int = 0,
                remoteControl: Bool = false, contextPercent: Double? = nil, errors: [String] = []) {
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
        self.lastAction = lastAction
        self.lastSentence = lastSentence
        self.hasHandover = hasHandover
        self.backgroundTasks = backgroundTasks
        self.remoteControl = remoteControl
        self.contextPercent = contextPercent
        self.errors = errors
    }

    /// Like the synthesized decoder, but `backgroundTasks` may be missing (older JSON).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decode(String.self, forKey: .name), project: try c.decode(String.self, forKey: .project),
            group: try c.decode(String.self, forKey: .group), isPm: try c.decode(Bool.self, forKey: .isPm),
            cwd: try c.decodeIfPresent(String.self, forKey: .cwd), pid: try c.decodeIfPresent(Int.self, forKey: .pid),
            kind: try c.decodeIfPresent(String.self, forKey: .kind), tmuxPane: try c.decodeIfPresent(String.self, forKey: .tmuxPane),
            alive: try c.decode(Bool.self, forKey: .alive), status: try c.decode(String.self, forKey: .status),
            waitingFor: try c.decodeIfPresent(String.self, forKey: .waitingFor),
            statusUpdatedAt: try c.decodeIfPresent(String.self, forKey: .statusUpdatedAt),
            branch: try c.decodeIfPresent(String.self, forKey: .branch),
            lastAssistant: try c.decodeIfPresent(Said.self, forKey: .lastAssistant),
            lastUser: try c.decodeIfPresent(Said.self, forKey: .lastUser),
            task: try c.decodeIfPresent(TaskLine.self, forKey: .task),
            lastAction: try c.decodeIfPresent(WorkAction.self, forKey: .lastAction),
            lastSentence: try c.decodeIfPresent(String.self, forKey: .lastSentence),
            hasHandover: try c.decode(Bool.self, forKey: .hasHandover),
            backgroundTasks: try c.decodeIfPresent(Int.self, forKey: .backgroundTasks) ?? 0,
            remoteControl: try c.decodeIfPresent(Bool.self, forKey: .remoteControl) ?? false,
            contextPercent: try c.decodeIfPresent(Double.self, forKey: .contextPercent),
            errors: try c.decode([String].self, forKey: .errors))
    }
}

public struct HiveState: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sessions: [Session]
    /// Files in the registry that could not be read
    public let errors: [String]
}

/// Merges registry, handover, and conversation transcripts (like buildState() in hive/lib/state.js).
public enum StateBuilder {
    public static let defaultClaudeHome = "\(home)/.claude"
    public static let staleAfter: TimeInterval = 60 * 60
    static let maxText = 600
    /// corresponds to localeCompare in Node (checked with period, #, -, _, umlauts, capitalization)
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
            var background = 0
            if let sid = e.sessionId, !e.cwd.isEmpty {
                let text = Transcript.readTailFollowingContinuation(dir: "\(claudeHome)/projects/\(Project.slug(e.cwd))", sessionId: sid)
                tail = Transcript.parseTail(text)
                background = backgroundTasks(alive: e.alive, text: text, now: now)
            }
            let project = Project.fromCwd(e.cwd, devRoot: devRoot)
            let status = e.alive ? e.status : "offline"
            sessions.append(Session(
                name: e.name, project: project, group: Project.groupKey(e.name, project: project),
                isPm: Project.isPm(e.name), cwd: e.cwd, pid: e.pid, kind: e.kind, tmuxPane: e.tmuxPane, alive: e.alive, status: status,
                waitingFor: e.waitingFor, statusUpdatedAt: e.statusUpdatedAt, branch: tail.branch,
                lastAssistant: clip(tail.lastAssistant), lastUser: clip(tail.lastUser),
                task: taskOf(h, status: status, now: now), lastAction: tail.lastAction, lastSentence: tail.lastSentence,
                hasHandover: h != nil, backgroundTasks: background, remoteControl: e.alive && e.remoteControl,
                contextPercent: e.alive ? e.sessionId.flatMap { ContextUsage.percent(claudeHome: claudeHome, sessionId: $0) } : nil,
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

    /// Background tasks die with their Claude process, so only live sessions count them.
    static func backgroundTasks(alive: Bool, text: String, now: Date) -> Int {
        alive ? Transcript.backgroundTasks(text, now: now) : 0
    }

    static func taskOf(_ h: HandoverEntry?, status: String, now: Date) -> Session.TaskLine? {
        guard let h, let text = h.task else { return nil }
        let updated = h.updatedAt.flatMap(parseISO)
        let stale = status == "busy" && (updated.map { now.timeIntervalSince($0) > staleAfter } ?? true)
        return Session.TaskLine(text: text, detail: h.detail, state: h.state, updatedAt: h.updatedAt, stale: stale)
    }

    /// Truncates to 600 UTF-16 units like text.slice(0, 600) in JS.
    static func clip(_ s: Said?) -> Said? {
        guard let s, s.text.utf16.count > maxText else { return s }
        return Said(text: String(decoding: Array(s.text.utf16.prefix(maxText)), as: UTF16.self) + "…", at: s.at)
    }
}
