import Foundation
import Testing
@testable import HiveCore

private let file = fixture("transcript.jsonl")
private func full() throws -> String { try String(contentsOfFile: file, encoding: .utf8) }

@Test func lastTextReplyIsNotToolUseOrThinking() throws {
    let r = Transcript.parseTail(try full())
    #expect(r.lastAssistant?.text == "I will start with the layout.")
    #expect(r.lastAssistant?.at == "2026-09-30T10:00:02.000Z")
}

@Test func lastRealPromptExcludesMetaAngleBracketsAndToolResult() throws {
    #expect(Transcript.parseTail(try full()).lastUser?.text == "Please rebuild the home page")
}

@Test func branchFromMostRecentLineWithGitBranch() throws {
    #expect(Transcript.parseTail(try full()).branch == "feat/home-page")
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

@Test func readTailFollowingContinuationJumpsToTheNewTranscript() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hive-cont-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try #"{"type":"user","message":{"role":"user","content":"old"}}\#n{"type":"continued-in","continuedInSessionId":"new"}\#n"#
        .write(toFile: "\(dir)/old.jsonl", atomically: true, encoding: .utf8)
    try #"{"type":"user","message":{"role":"user","content":"fresh"}}\#n"#
        .write(toFile: "\(dir)/new.jsonl", atomically: true, encoding: .utf8)
    #expect(Transcript.readTailFollowingContinuation(dir: dir, sessionId: "old").contains("fresh"))
    // without a continuation the file itself is read
    #expect(Transcript.readTailFollowingContinuation(dir: dir, sessionId: "new").contains("fresh"))
}

@Test func readTailFollowingContinuationStopsAtMissingFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hive-cont-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try #"{"type":"user","message":{"role":"user","content":"old"}}\#n{"type":"continued-in","continuedInSessionId":"gone"}\#n"#
        .write(toFile: "\(dir)/old.jsonl", atomically: true, encoding: .utf8)
    #expect(Transcript.readTailFollowingContinuation(dir: dir, sessionId: "old").contains("old"))
}

@Test func modelOfTheLastRealAssistantMessage() {
    let text = """
    {"type":"assistant","message":{"model":"claude-sonnet-5-5","content":[{"type":"text","text":"a"}]}}
    {"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"b"}]}}
    {"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"API error"}]}}
    {"type":"user","message":{"content":"next"}}
    """
    #expect(Transcript.parseTail(text).model == "claude-opus-5-5")
    #expect(Transcript.parseTail(#"{"type":"user","message":{"content":"hi"}}"#).model == nil)
}

@Test func answerIsTheWholeTurnSinceTheLastPrompt() {
    func line(_ type: String, _ content: String, _ t: Int) -> String {
        #"{"type":"\#(type)","timestamp":"2026-09-30T10:00:0\#(t).000Z","message":{"content":\#(content)}}"#
    }
    let text = [
        line("user", #""Earlier question""#, 0),
        line("assistant", #"[{"type":"text","text":"Earlier answer."}]"#, 1),
        line("user", #""Check the layout""#, 2),
        line("assistant", #"[{"type":"text","text":"I read the grid first."},{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/x/Grid.swift"}}]"#, 3),
        line("user", #"[{"type":"tool_result","tool_use_id":"a","content":"…"}]"#, 4),
        line("assistant", #"[{"type":"tool_use","id":"b","name":"Bash","input":{"command":"swift test"}}]"#, 5),
        line("user", #"[{"type":"tool_result","tool_use_id":"b","content":"ok"}]"#, 6),
        line("assistant", #"[{"type":"text","text":"All tests pass:\n1. Grid\n2. Cards"}]"#, 7),
    ].joined(separator: "\n")
    let t = Transcript.parseTail(text)
    #expect(t.lastUser?.text == "Check the layout")
    #expect(t.answer?.text == "I read the grid first.\n\nAll tests pass:\n1. Grid\n2. Cards")
    #expect(t.answer?.at == "2026-09-30T10:00:07.000Z")
    #expect(t.steps.count == 2 && t.steps.last?.pending == false)
    // the earlier turn is not part of it
    #expect(t.answer?.text.contains("Earlier") == false)
}
