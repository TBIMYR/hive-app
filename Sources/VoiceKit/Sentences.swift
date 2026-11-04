import Foundation

/// Cuts streamed answer text into sentences, so speech can start after the first one
/// instead of waiting for the whole answer.
public struct SentenceSplitter {
    private var buffer = ""
    /// Very short pieces ("Ja.") are joined with the next sentence; one request per word sounds choppy.
    public var minLength: Int

    public init(minLength: Int = 12) { self.minLength = minLength }

    /// Adds streamed text and returns the sentences that are complete now.
    public mutating func feed(_ text: String) -> [String] {
        buffer += text
        var out: [String] = []
        while let end = Self.sentenceEnd(in: buffer, from: minLength) {
            let sentence = String(buffer[..<end])
            buffer = String(buffer[end...])
            if let s = Self.speakable(sentence) { out.append(s) }
        }
        return out
    }

    /// The rest when the answer is complete.
    public mutating func flush() -> [String] {
        defer { buffer = "" }
        return Self.speakable(buffer).map { [$0] } ?? []
    }

    /// Index after a sentence end (". ", "! ", "? ", "… " or a line break), not before `from` characters. A colon is
    /// none: "So sieht es aus:" as a request of its own sounds cut off.
    static func sentenceEnd(in s: String, from minLength: Int) -> String.Index? {
        var i = s.startIndex
        var count = 0
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            count += 1
            if c == "\n", count >= 2 { return next }
            if ".!?…".contains(c), next < s.endIndex, s[next].isWhitespace, count >= minLength {
                // "z. B." and "1. " are not sentence ends
                let before = s[s.startIndex..<i].split(separator: " ").last.map(String.init) ?? ""
                if c == ".", before.count <= 1 || Int(before) != nil || Self.abbreviations.contains(before.lowercased()) {
                    i = next
                    continue
                }
                return next
            }
            i = next
        }
        return nil
    }

    static let abbreviations: Set<String> = ["z", "b", "bzw", "ca", "usw", "evtl", "ggf", "d.h", "z.b", "u.a", "nr", "dr"]

    /// Strips what a voice should not read out (Markdown marks, list bullets); nil when nothing is left.
    public static func speakable(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        t = t.replacingOccurrences(of: #"^\s*[-*•]\s+"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains(where: { $0.isLetter || $0.isNumber }) ? t : nil
    }
}
