import Foundation
import HiveCore

/// What a session wrote, as sentences to read out on request: headings, paragraphs and list items word for word,
/// code and tables left out (they can't be followed by ear). Stops after about `limit` characters, so a long answer
/// doesn't run for minutes (and ElevenLabs bills by the character); the rest is in the card.
public enum ReadAloud {
    public static let limit = 1200
    public static let more = "Den Rest findest du in der Karte."

    public static func sentences(_ answer: String, limit: Int = limit) -> [String] {
        var out: [String] = []
        var used = 0
        var splitter = SentenceSplitter()
        for block in AnswerText.blocks(answer) {
            let text: String
            switch block {
            case .heading(let h): text = h + "."
            case .paragraph(let p): text = p
            case .item(_, let t, _): text = t
            case .code: continue
            }
            for s in splitter.feed(text + "\n") {
                guard used + s.count <= limit || out.isEmpty else { return out + [more] }
                out.append(s)
                used += s.count
            }
        }
        return out + splitter.flush()
    }
}
