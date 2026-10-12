import Foundation
import Testing
@testable import HiveCore

private func tempRoot() -> String { NSTemporaryDirectory() + "notes-\(UUID().uuidString)" }

@Test func notesAreStoredPerSessionNewestFirst() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let a = try #require(Notes.add(root: root, session: "lu.01", text: "  first\nline two \n", now: t))
    let b = try #require(Notes.add(root: root, session: "lu.01", text: "second", now: t.addingTimeInterval(5)))
    Notes.add(root: root, session: "or.pm", text: "other session", now: t)

    #expect(a.text == "first\nline two")
    #expect(Notes.list(root: root, session: "lu.01").map(\.id) == [b.id, a.id])
    #expect(Notes.list(root: root, session: "lu.01").first?.created == t.addingTimeInterval(5))
    #expect(Notes.list(root: root, session: "fj.02").isEmpty)
    #expect(Notes.counts(root: root) == ["lu.01": 2, "or.pm": 1])
}

@Test func notesCanBeEditedAndRemoved() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let a = try #require(Notes.add(root: root, session: "lu.01", text: "draft", now: t))
    // a blank note to write on
    let b = try #require(Notes.add(root: root, session: "lu.01", now: t.addingTimeInterval(5)))
    #expect(Notes.list(root: root, session: "lu.01").map(\.text) == ["", "draft"])

    Notes.save(root: root, session: "lu.01", id: a.id, text: "final\n")
    Notes.save(root: root, session: "lu.01", id: b.id, text: "written")
    #expect(Notes.list(root: root, session: "lu.01").map(\.text) == ["written", "final"])
    // clearing the text keeps the note
    Notes.save(root: root, session: "lu.01", id: a.id, text: "  ")
    #expect(Notes.list(root: root, session: "lu.01").map(\.text) == ["written", ""])

    Notes.remove(root: root, session: "lu.01", id: a.id)
    // a late save doesn't bring a deleted note back
    Notes.save(root: root, session: "lu.01", id: a.id, text: "ghost")
    #expect(Notes.list(root: root, session: "lu.01").map(\.id) == [b.id])
    Notes.remove(root: root, session: "lu.01", id: b.id)
    #expect(Notes.counts(root: root).isEmpty)
}

@Test func notesRejectUnsafeNames() {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    #expect(Notes.add(root: root, session: "../lu", text: "x") == nil)
    #expect(Notes.add(root: root, session: "lu/01", text: "x") == nil)
    #expect(Notes.add(root: root, session: "", text: "x") == nil)
    #expect(Notes.validName("lu.pm") && Notes.validName("ki_02#a-b"))
    Notes.remove(root: root, session: "lu.01", id: "../x.md")
    Notes.save(root: root, session: "lu.01", id: "../x.md", text: "x")
    #expect(!FileManager.default.fileExists(atPath: root))
}

@Test func notesReadFilesWrittenByCcNote() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: "\(root)/lu.01", withIntermediateDirectories: true)
    try "from the tool\n".write(toFile: "\(root)/lu.01/20261012-141502-4242.md", atomically: true, encoding: .utf8)
    try "x".write(toFile: "\(root)/lu.01/.cc-note.tmp", atomically: true, encoding: .utf8)
    let notes = Notes.list(root: root, session: "lu.01")
    #expect(notes.map(\.text) == ["from the tool"])
    #expect(notes.first?.created != nil)
}

@Test func recentRepliesOffersFullAnswersNewestFirst() throws {
    let home = NSTemporaryDirectory() + "reply-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    let cwd = "/tmp/lumen"
    let dir = "\(home)/projects/\(Project.slug(cwd))"
    try FileManager.default.createDirectory(atPath: "\(home)/sessions", withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let pid = ProcessInfo.processInfo.processIdentifier
    try #"{"pid":\#(pid),"name":"lu.01","cwd":"\#(cwd)","sessionId":"sid-1","startedAt":1}"#
        .write(toFile: "\(home)/sessions/\(pid).json", atomically: true, encoding: .utf8)
    let long = String(repeating: "step ", count: 2000) + "done"
    let second = String(repeating: "a second answer ", count: 5)
    let lines = [
        #"{"type":"user","message":{"content":"how do I do it?"}}"#,
        #"{"type":"assistant","timestamp":"2026-10-12T10:00:00.000Z","message":{"content":[{"type":"text","text":"\#(long)"}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"Checking the tests now."},{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"an assistant would say: \#(long)"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-10-12T10:05:00.000Z","message":{"content":[{"type":"text","text":"\#(second)"}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"AskUserQuestion","input":{}}]}}"#,
    ]
    try lines.joined(separator: "\n").write(toFile: "\(dir)/sid-1.jsonl", atomically: true, encoding: .utf8)

    let replies = Notes.recentReplies(claudeHome: home, session: "lu.01")
    #expect(replies.map(\.text) == [second.trimmingCharacters(in: .whitespaces), long])
    #expect(replies.first?.at == "2026-10-12T10:05:00.000Z")
    #expect(Notes.recentReplies(claudeHome: home, session: "lu.01", limit: 1).count == 1)
    #expect(Notes.recentReplies(claudeHome: home, session: "or.pm").isEmpty)
}
