import Foundation

public struct Said: Codable, Equatable, Sendable {
    public let text: String
    public let at: String?

    public init(text: String, at: String?) {
        self.text = text
        self.at = at
    }
}

/// Letzter Arbeitsschritt des Assistenten (letzter tool_use), kurz beschrieben für die Zeile „Now“.
public struct WorkAction: Codable, Equatable, Sendable {
    /// Werkzeugname wie im Protokoll („Bash“, „Edit“ …)
    public let tool: String
    /// kurzer Text („Running tests“, „Editing Kalender.swift“)
    public let text: String
    /// Befehl oder Pfad, einzeilig und gekürzt
    public let detail: String?
    public let at: String?
    /// noch ohne tool_result (läuft oder wartet auf Freigabe)
    public let pending: Bool
    /// AskUserQuestion: Beschriftungen der Optionen der ersten Frage
    public let options: [String]?

    public init(tool: String, text: String, detail: String?, at: String?, pending: Bool, options: [String]? = nil) {
        self.tool = tool
        self.text = text
        self.detail = detail
        self.at = at
        self.pending = pending
        self.options = options
    }
}

public struct Tail: Equatable, Sendable {
    public var lastAssistant: Said? = nil
    public var lastUser: Said? = nil
    public var branch: String? = nil
    public var lastAction: WorkAction? = nil
    /// letzter Satz der letzten Textantwort, ohne Markdown, gekürzt
    public var lastSentence: String? = nil
}

/// Liest das Ende eines Gesprächsprotokolls (JSONL) wie hive/lib/transcript.js.
public enum Transcript {
    public static let defaultTailBytes = 64 * 1024

    /// Letzte `bytes` Bytes; ist die Datei länger, fällt die angeschnittene erste Zeile weg.
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

    public static func parseTail(_ text: String) -> Tail {
        var tail = Tail()
        // tool_results aus jüngeren Zeilen (rückwärts gelesen also schon gesehen)
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

    /// Text aus einem String oder aus den text-Blöcken einer Liste.
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

    // MARK: Arbeitsschritt

    static let maxDetail = 80
    static let maxSentence = 140

    static func describe(_ use: [String: Any], at: String?, pending: Bool) -> WorkAction {
        let tool = (use["name"] as? String).nonEmpty ?? "Tool"
        let input = use["input"] as? [String: Any] ?? [:]
        func str(_ k: String) -> String? { (input[k] as? String).map(oneLine).nonEmpty }
        let text: String
        var detail: String? = nil
        var options: [String]? = nil
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
            let first = (input["questions"] as? [Any])?.first as? [String: Any]
            text = (first?["question"] as? String).map(oneLine).nonEmpty.map { clip($0, maxSentence) } ?? tool
            options = (first?["options"] as? [Any])?.compactMap { o in
                ((o as? [String: Any])?["label"] as? String).map(oneLine).nonEmpty.map { clip($0, 60) }
            }
        default:
            text = tool
        }
        return WorkAction(tool: tool, text: text, detail: detail, at: at, pending: pending, options: options)
    }

    // MARK: letzter Satz

    /// Letzter Satz des letzten Absatzes (bei einer Liste: letzter Punkt), Markdown grob entfernt.
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

    /// Länge eines Listen- oder Überschriftenzeichens am Zeilenanfang („- “, „1. “, „## “, „> “).
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

    /// Rest nach dem letzten Satzende ([.!?] + Leerzeichen); Ein-Buchstaben-Abkürzungen („z. B.“) zählen nicht.
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

    // MARK: Hilfen

    /// Zeilenumbrüche und Mehrfach-Leerzeichen zu einem Leerzeichen.
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
