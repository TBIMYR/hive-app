import Foundation
import Testing
@testable import HiveCore

private func line(_ text: String) -> String {
    #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"2026-10-08T10:00:00Z"}"# + "\n"
}

@Test func cacheParsesOnlyChangedTranscripts() throws {
    let dir = NSTemporaryDirectory() + "tc-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = "\(dir)/s1.jsonl"
    try line("first answer.").write(toFile: path, atomically: true, encoding: .utf8)
    let cache = TranscriptCache()
    let a = cache.read(dir: dir, sessionId: "s1")
    let b = cache.read(dir: dir, sessionId: "s1")
    #expect(cache.parses == 1)
    #expect(a.tail == b.tail)
    #expect(a.tail == Transcript.parseTail(Transcript.readTail(path)))
    let h = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try h.seekToEnd()
    try h.write(contentsOf: Data(line("second answer.").utf8))
    try h.close()
    let c = cache.read(dir: dir, sessionId: "s1")
    #expect(cache.parses == 2)
    #expect(c.tail.lastSentence != a.tail.lastSentence)
}

@Test func cacheFollowsContinuationChanges() throws {
    let dir = NSTemporaryDirectory() + "tc-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try (line("old.") + #"{"type":"continued-in","continuedInSessionId":"new"}"# + "\n")
        .write(toFile: "\(dir)/old.jsonl", atomically: true, encoding: .utf8)
    try line("fresh one.").write(toFile: "\(dir)/new.jsonl", atomically: true, encoding: .utf8)
    let cache = TranscriptCache()
    _ = cache.read(dir: dir, sessionId: "old")
    let h = try FileHandle(forWritingTo: URL(fileURLWithPath: "\(dir)/new.jsonl"))
    try h.seekToEnd()
    try h.write(contentsOf: Data(line("fresher one.").utf8))
    try h.close()
    _ = cache.read(dir: dir, sessionId: "old")
    #expect(cache.parses == 2)
}
