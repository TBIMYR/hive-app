import Foundation
import Testing
@testable import HiveCore

private func found(_ text: String) -> [String] {
    let ns = text as NSString
    return NoteMarkdown.spans(text).map { s in
        let piece = ns.substring(with: s.range)
        switch s.kind {
        case .heading(let l): return "h\(l):\(piece)"
        case .bold: return "bold:\(piece)"
        case .code: return "code:\(piece)"
        case .codeBlock: return "block:\(piece)"
        case .listMarker: return "list:\(piece)"
        case .listItem(let prefix): return "item:\(ns.substring(with: prefix))|\(piece)"
        case .markup(let scope): return "markup:\(piece)|\(ns.substring(with: scope))"
        }
    }
}

@Test func noteMarkdownFindsHeadingsListsAndInlineMarkup() {
    #expect(found("## Setup") == ["h2:## Setup", "markup:## |## Setup"])
    #expect(found("1. run `make seed` **now**") == [
        "item:1. |1. run `make seed` **now**", "list:1.",
        "code:make seed", "markup:`|1. run `make seed` **now**", "markup:`|1. run `make seed` **now**",
        "bold:now", "markup:**|1. run `make seed` **now**", "markup:**|1. run `make seed` **now**",
    ])
    #expect(found("  - nested\n* star") == ["item:  - |  - nested", "list:-", "item:* |* star", "list:*"])
    // no markup: hashtag, a minus without a space, stars inside code, lone stars
    #expect(found("#tag\n-x\n3.14\n2 ** 3") == [])
    #expect(found("`a ** b ** c`") == ["code:a ** b ** c", "markup:`|`a ** b ** c`", "markup:`|`a ** b ** c`"])
}

@Test func noteMarkdownFindsFencedCode() {
    let text = "before\n```sh\nnpm run dev\n\n  --port **3000**\n```\nafter **x**"
    let block = "```sh\nnpm run dev\n\n  --port **3000**\n```"
    #expect(found(text) == [
        "markup:```sh|\(block)", "block:npm run dev", "block:  --port **3000**", "markup:```|\(block)",
        "bold:x", "markup:**|after **x**", "markup:**|after **x**",
    ])
    // still being typed: code look, the fence stays as it is
    #expect(found("```\nopen") == ["block:open"])
    #expect(found("").isEmpty)
}

@Test func noteMarkdownRangesAreUTF16() {
    let text = "ü 🙂 **bold**"
    let span = NoteMarkdown.spans(text).first { $0.kind == .bold }
    #expect(span.map { (text as NSString).substring(with: $0.range) } == "bold")
}

@Test func markupShowsOnlyOnTheCursorLine() {
    let scope = NSRange(location: 10, length: 5)
    #expect(!NoteMarkdown.showsMarkup(scope: scope, selection: nil))
    #expect(!NoteMarkdown.showsMarkup(scope: scope, selection: NSRange(location: 9, length: 0)))
    #expect(NoteMarkdown.showsMarkup(scope: scope, selection: NSRange(location: 10, length: 0)))
    #expect(NoteMarkdown.showsMarkup(scope: scope, selection: NSRange(location: 15, length: 0)))
    #expect(!NoteMarkdown.showsMarkup(scope: scope, selection: NSRange(location: 16, length: 3)))
    #expect(NoteMarkdown.showsMarkup(scope: scope, selection: NSRange(location: 0, length: 12)))
}
