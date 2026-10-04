import Foundation
import Testing
@testable import HiveCore

private let file = fixture("transcript.jsonl")
private func full() throws -> String { try String(contentsOfFile: file, encoding: .utf8) }

@Test func lastTextReplyIsNotToolUseOrThinking() throws {
    let r = Transcript.parseTail(try full())
    #expect(r.lastAssistant?.text == "Ich fange mit dem Layout an.")
    #expect(r.lastAssistant?.at == "2026-09-30T10:00:02.000Z")
}

@Test func lastRealPromptExcludesMetaAngleBracketsAndToolResult() throws {
    #expect(Transcript.parseTail(try full()).lastUser?.text == "Bitte die Startseite umbauen")
}

@Test func branchFromMostRecentLineWithGitBranch() throws {
    #expect(Transcript.parseTail(try full()).branch == "feat/startseite")
}

@Test func emptyTextYieldsEmptyResult() {
    #expect(Transcript.parseTail("") == Tail())
}

@Test func readsAtMostNBytesAndCutsAtLineBoundary() throws {
    let t = Transcript.readTail(file, bytes: 200)
    #expect(t.utf8.count <= 200)
    #expect(t.isEmpty || t.hasPrefix("{\"type\"") || t.hasPrefix("{not json"))
    #expect(Transcript.readTail(file, bytes: 1 << 20) == (try full()))
}

@Test func missingFileYieldsEmptyString() {
    #expect(Transcript.readTail("/nonexistent.jsonl", bytes: 100) == "")
}
