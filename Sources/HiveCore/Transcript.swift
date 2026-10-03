import Foundation

public struct Said: Codable, Equatable, Sendable {
    public let text: String
    public let at: String?

    public init(text: String, at: String?) {
        self.text = text
        self.at = at
    }
}

public struct Tail: Equatable, Sendable {
    public var lastAssistant: Said? = nil
    public var lastUser: Said? = nil
    public var branch: String? = nil
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
        for raw in text.components(separatedBy: "\n").reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if tail.branch == nil, let b = obj["gitBranch"] as? String { tail.branch = b }
            let content = (obj["message"] as? [String: Any])?["content"]
            let type = obj["type"] as? String
            let at = (obj["timestamp"] as? String).nonEmpty
            if tail.lastAssistant == nil && type == "assistant" {
                let t = textOf(content)
                if !t.isEmpty { tail.lastAssistant = Said(text: t, at: at) }
            } else if tail.lastUser == nil && type == "user" && (obj["isMeta"] as? Bool) != true {
                let t = textOf(content)
                if !t.isEmpty && !t.hasPrefix("<") { tail.lastUser = Said(text: t, at: at) }
            }
            if tail.lastAssistant != nil && tail.lastUser != nil && tail.branch != nil { break }
        }
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
}
