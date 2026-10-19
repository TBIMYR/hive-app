import Foundation

/// Search field of the overview: a session stays visible when every word of the query appears in one of its fields
/// (name, project, task, …), ignoring case and accents.
public enum SessionSearch {
    public static func matches(_ query: String, in fields: [String?]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let texts = fields.compactMap { $0 }.filter { !$0.isEmpty }
        return words.allSatisfy { w in
            texts.contains { $0.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
