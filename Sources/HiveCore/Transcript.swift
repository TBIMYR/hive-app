import Foundation

public struct Said: Codable, Equatable, Sendable {
    public let text: String
    public let at: String?

    public init(text: String, at: String?) {
        self.text = text
        self.at = at
    }
}

/// Last work step of the assistant (last tool_use), briefly described for the "Now" line.
public struct WorkAction: Codable, Equatable, Sendable {
    /// tool name as in the log ("Bash", "Edit" …)
    public let tool: String
    /// short text ("Running tests", "Editing Kalender.swift")
    public let text: String
    /// command or path, single-line and truncated
    public let detail: String?
    public let at: String?
    /// still without tool_result (running or waiting for approval)
    public let pending: Bool
    /// AskUserQuestion: labels of the options of the first question
    public let options: [String]?
    /// AskUserQuestion: number of questions
    public let questionCount: Int?
    /// AskUserQuestion: first question with multi-select
    public let multiSelect: Bool?

    public init(tool: String, text: String, detail: String?, at: String?, pending: Bool, options: [String]? = nil,
                questionCount: Int? = nil, multiSelect: Bool? = nil) {
        self.tool = tool
        self.text = text
        self.detail = detail
        self.at = at
        self.pending = pending
        self.options = options
        self.questionCount = questionCount
        self.multiSelect = multiSelect
    }
}

public struct Tail: Equatable, Sendable {
    public var lastAssistant: Said? = nil
    public var lastUser: Said? = nil
    public var branch: String? = nil
    public var lastAction: WorkAction? = nil
    /// last sentence of the last text response, without Markdown, truncated
    public var lastSentence: String? = nil
}

/// Reads the end of a conversation transcript (JSONL) like hive/lib/transcript.js.
public enum Transcript {
    public static let defaultTailBytes = 64 * 1024

    /// Last `bytes` bytes; if the file is longer, the truncated first line is dropped.
    public static func readTail(_ path: String, bytes: Int = defaultTailBytes) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return "" }
        let len = min(UInt64(bytes), size)
        guard (try? h.seek(toOffset: size - len)) != nil else { return "" }
        var data = (try? h.read(upToCount: Int(len))) ?? Data()
        if len < size {
            if let nl = data.firstIndex(of: 0x0A) { data = data[(nl + 1)...] } else { data = Data() }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Like `readTail`, but follows `continued-in` lines: when a conversation moves to a background
    /// session, the old transcript ends with `{"type":"continued-in","continuedInSessionId":…}` and the
    /// registry may still point at it. Follows at most a few hops and only to files that exist.
    public static func readTailFollowingContinuation(dir: String, sessionId: String, bytes: Int = defaultTailBytes) -> String {
        var text = readTail("\(dir)/\(sessionId).jsonl", bytes: bytes)
        for _ in 0..<5 {
            guard let last = text.split(separator: "\n").last(where: { !$0.allSatisfy(\.isWhitespace) }),
                  last.contains("\"continued-in\""),
                  let obj = try? JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any],
                  obj["type"] as? String == "continued-in",
                  let next = obj["continuedInSessionId"] as? String,
                  FileManager.default.fileExists(atPath: "\(dir)/\(next).jsonl") else { break }
            text = readTail("\(dir)/\(next).jsonl", bytes: bytes)
        }
        return text
    }

    public static func parseTail(_ text: String) -> Tail {
        var tail = Tail()
        // tool_results from more recent lines (already seen, since we read backwards)
        var resultIds = Set<String>()
        var sawResult = false
        for raw in text.components(separatedBy: "\n").reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if tail.branch == nil, let b = obj["gitBranch"] as? String { tail.branch = b }
            let content = (obj["message"] as? [String: Any])?["content"]
            let type = obj["type"] as? String
            let at = (obj["timestamp"] as? String).nonEmpty
            if tail.lastAction == nil {
                if type == "user", let blocks = content as? [Any] {
                    for case let b as [String: Any] in blocks where b["type"] as? String == "tool_result" {
                        sawResult = true
                        if let id = b["tool_use_id"] as? String { resultIds.insert(id) }
                    }
                } else if type == "assistant", let blocks = content as? [Any],
                          let use = blocks.last(where: { ($0 as? [String: Any])?["type"] as? String == "tool_use" }) as? [String: Any] {
                    let id = use["id"] as? String
                    let pending = id.map { !resultIds.contains($0) } ?? !sawResult
                    tail.lastAction = describe(use, at: at, pending: pending)
                }
            }
            if tail.lastAssistant == nil && type == "assistant" {
                let t = textOf(content)
                if !t.isEmpty { tail.lastAssistant = Said(text: t, at: at) }
            } else if tail.lastUser == nil && type == "user" && (obj["isMeta"] as? Bool) != true {
                let t = textOf(content)
                if !t.isEmpty && !t.hasPrefix("<") { tail.lastUser = Said(text: t, at: at) }
            }
            if tail.lastAssistant != nil && tail.lastUser != nil && tail.branch != nil && tail.lastAction != nil { break }
        }
        tail.lastSentence = tail.lastAssistant.flatMap { lastSentence(of: $0.text) }
        return tail
    }

    // MARK: Background tasks

    /// Tasks started longer ago than this without a completion are ignored (crashed or lost notification).
    public static let backgroundStaleAfter: TimeInterval = 6 * 60 * 60

    /// Number of background agents and shell commands still running, from the given transcript tail.
    /// Started: a tool_result whose `toolUseResult` has `status: "async_launched"` + `agentId` (Agent/Task),
    /// `backgroundTaskId` (Bash with run_in_background) or `resumedAgentId` (SendMessage resumed an agent);
    /// without metadata the result text ("Async agent launched … agentId: X", "Command running in background
    /// with ID: X"). Finished: a `<task-notification>` with that `<task-id>` and a `<status>` (completed,
    /// failed, killed …) in a user message, a queue-operation or a queued_command attachment.
    /// Starts outside the tail are not seen; that is accepted.
    public static func backgroundTasks(_ text: String, now: Date) -> Int {
        var running: [String: Date?] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // cheap prefilter: only lines that can start or finish a task get parsed
            guard raw.contains("<task-notification>") || raw.contains("async_launched") || raw.contains("backgroundTaskId")
                    || raw.contains("resumedAgentId") || raw.contains("Async agent launched")
                    || raw.contains("running in background with ID") else { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            let at = (obj["timestamp"] as? String).flatMap(parseISO)
            if let (id, status) = notification(in: obj, type: type) {
                if status != "running" { running.removeValue(forKey: id) }
                continue
            }
            if type == "user" {
                for id in startedIds(obj) { running.updateValue(at, forKey: id) }
            }
        }
        return running.values.filter { start in
            guard let start else { return true }
            return now.timeIntervalSince(start) <= backgroundStaleAfter
        }.count
    }

    /// Task id and status of a task notification (only lines Claude Code writes itself, never assistant text).
    private static func notification(in obj: [String: Any], type: String?) -> (String, String)? {
        let text: String?
        switch type {
        case "user": text = (obj["message"] as? [String: Any])?["content"] as? String
        case "queue-operation": text = obj["operation"] as? String == "enqueue" ? obj["content"] as? String : nil
        case "attachment": text = (obj["attachment"] as? [String: Any])?["prompt"] as? String
        default: text = nil
        }
        guard let text, text.contains("<task-notification>"),
              let id = tag("task-id", in: text), let status = tag("status", in: text) else { return nil }
        return (id, status)
    }

    /// Ids of background tasks that a user line with tool_results starts.
    private static func startedIds(_ obj: [String: Any]) -> [String] {
        if let meta = obj["toolUseResult"] as? [String: Any] {
            if meta["status"] as? String == "async_launched", let id = (meta["agentId"] as? String).nonEmpty { return [id] }
            if let id = (meta["backgroundTaskId"] as? String).nonEmpty { return [id] }
            if let id = (meta["resumedAgentId"] as? String).nonEmpty { return [id] }
        }
        guard let blocks = (obj["message"] as? [String: Any])?["content"] as? [Any] else { return [] }
        var ids: [String] = []
        for case let b as [String: Any] in blocks where b["type"] as? String == "tool_result" {
            let text = (b["content"] as? String) ?? textOf(b["content"])
            if text.hasPrefix("Async agent launched"), let id = match(#"agentId: ([\w-]+)"#, in: text) {
                ids.append(id)
            } else if let id = match(#"^Command running in background with ID: ([\w-]+)"#, in: text) {
                ids.append(id)
            }
        }
        return ids
    }

    private static func tag(_ name: String, in text: String) -> String? {
        match("<\(name)>([^<]+)</\(name)>", in: text).map { $0.trimmingCharacters(in: .whitespaces) }.nonEmpty
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Text from a string or from the text blocks of a list.
    static func textOf(_ content: Any?) -> String {
        if let s = content as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [Any] else { return "" }
        return blocks
            .compactMap { b -> String? in
                guard let b = b as? [String: Any], b["type"] as? String == "text" else { return nil }
                return b["text"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Work step

    static let maxDetail = 80
    static let maxSentence = 140
    static let maxQuestion = 2000

    static func describe(_ use: [String: Any], at: String?, pending: Bool) -> WorkAction {
        let tool = (use["name"] as? String).nonEmpty ?? "Tool"
        let input = use["input"] as? [String: Any] ?? [:]
        func str(_ k: String) -> String? { (input[k] as? String).map(oneLine).nonEmpty }
        let text: String
        var detail: String? = nil
        var options: [String]? = nil
        var questionCount: Int? = nil
        var multiSelect: Bool? = nil
        switch tool {
        case "Bash":
            let cmd = str("command").map { $0.replacingOccurrences(of: home + "/", with: "~/") }
            text = str("description") ?? cmd.map { clip($0, 60) } ?? tool
            detail = cmd.map { clip($0, maxDetail) }
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read":
            let path = str("file_path") ?? str("notebook_path")
            let name = path.map { ($0 as NSString).lastPathComponent }
            text = name.map { (tool == "Read" ? "Reading " : "Editing ") + $0 } ?? tool
            detail = path.map { clip(tilde($0), maxDetail) }
        case "Grep", "Glob":
            text = str("pattern").map { "Searching " + clip($0, 60) } ?? tool
            detail = str("path").map { clip(tilde($0), maxDetail) }
        case "Task", "Agent":
            text = str("description").map { "Running agent: " + clip($0, 60) } ?? tool
        case "WebFetch":
            let url = str("url")
            text = url.map { "Browsing " + (URL(string: $0)?.host ?? clip($0, 60)) } ?? tool
            detail = url.map { clip($0, maxDetail) }
        case "WebSearch":
            text = str("query").map { "Browsing " + clip($0, 60) } ?? tool
        case "AskUserQuestion":
            let questions = input["questions"] as? [Any]
            let first = questions?.first as? [String: Any]
            questionCount = questions?.count
            multiSelect = first?["multiSelect"] as? Bool
            // whole question: without it the options can't be answered (only a guard against huge input)
            text = (first?["question"] as? String).map(oneLine).nonEmpty.map { clip($0, maxQuestion) } ?? tool
            options = (first?["options"] as? [Any])?.compactMap { o in
                ((o as? [String: Any])?["label"] as? String).map(oneLine).nonEmpty.map { clip($0, 60) }
            }
        default:
            text = tool
        }
        return WorkAction(tool: tool, text: text, detail: detail, at: at, pending: pending, options: options,
                          questionCount: questionCount, multiSelect: multiSelect)
    }

    // MARK: Last sentence

    /// Last sentence of the last paragraph (for a list: last item), Markdown roughly stripped.
    static func lastSentence(of text: String) -> String? {
        var paragraphs: [[String]] = [[]]
        var inCode = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); paragraphs.append([]); continue }
            if inCode { continue }
            if line.isEmpty || line.hasPrefix("|") { paragraphs.append([]); continue }
            paragraphs[paragraphs.count - 1].append(line)
        }
        guard let para = paragraphs.last(where: { !$0.isEmpty }) else { return nil }
        let last = para[para.count - 1]
        let joined = listMarker(last) != nil ? last : para.joined(separator: " ")
        let flat = stripMarkdown(joined)
        guard !flat.isEmpty else { return nil }
        return clip(sentenceTail(flat), maxSentence)
    }

    /// Length of a list or heading marker at the start of a line ("- ", "1. ", "## ", "> ").
    static func listMarker(_ line: String) -> Int? {
        guard let r = line.range(of: #"^(?:[-*+•]|\d+[.)]|#{1,6}|>)\s+"#, options: .regularExpression) else { return nil }
        return line.distance(from: line.startIndex, to: r.upperBound)
    }

    static func stripMarkdown(_ s: String) -> String {
        var t = s
        if let n = listMarker(t) { t = String(t.dropFirst(n)) }
        t = t.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`", "~~"] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        return oneLine(t)
    }

    /// Remainder after the last sentence end ([.!?] + space); single-letter abbreviations ("e.g.") don't count.
    static func sentenceTail(_ s: String) -> String {
        let chars = Array(s)
        var i = chars.count - 2
        while i > 0 {
            if ".!?".contains(chars[i]) && chars[i + 1] == " " {
                let abbreviation = chars[i] == "." && chars[i - 1].isLetter && (i < 2 || !chars[i - 2].isLetter)
                if !abbreviation {
                    let rest = String(chars[(i + 2)...]).trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { return rest }
                }
            }
            i -= 1
        }
        return s
    }

    // MARK: Helpers

    /// Line breaks and multiple spaces collapsed to one space.
    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func clip(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max)).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
