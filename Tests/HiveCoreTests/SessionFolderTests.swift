import Foundation
import Testing
@testable import HiveCore

private func projects(_ files: [String: (lines: [String], age: TimeInterval)]) throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sf-\(UUID().uuidString)").path
    for (rel, f) in files {
        let p = "\(root)/\(rel)"
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try (f.lines.joined(separator: "\n") + "\n").write(toFile: p, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-f.age)], ofItemAtPath: p)
    }
    return root
}

private func title(_ n: String) -> String { #"{"type":"custom-title","customTitle":"\#(n)","sessionId":"x"}"# }
private func cwd(_ d: String) -> String { #"{"type":"user","cwd":"\#(d)","message":{}}"# }

@Test func folderFromNewestTranscriptWithThatName() throws {
    let a = FileManager.default.temporaryDirectory.path, b = NSHomeDirectory()
    let root = try projects([
        "-a/old.jsonl": ([title("lu.01"), cwd(a)], 3_600),
        "-b/new.jsonl": ([cwd(b), title("lu.01"), cwd("\(b)/sub")], 60),
        "-c/other.jsonl": ([cwd(a), title("lu.02")], 10),
    ])
    #expect(SessionFolder.find("lu.01", projectsDir: root) == b)
    #expect(SessionFolder.find("lu.02", projectsDir: root) == a)
    #expect(SessionFolder.find("lu.03", projectsDir: root) == nil)
}

@Test func folderUsesLastTitleAfterRename() throws {
    let a = FileManager.default.temporaryDirectory.path
    let root = try projects(["-a/s.jsonl": ([cwd(a), title("lu.01"), title("or.01")], 60)])
    #expect(SessionFolder.find("or.01", projectsDir: root) == a)
    #expect(SessionFolder.find("lu.01", projectsDir: root) == nil)
}

@Test func folderSkipsMissingDirsAndOldTranscripts() throws {
    let a = FileManager.default.temporaryDirectory.path
    let root = try projects([
        "-a/gone.jsonl": ([cwd("/nonexistent/hive-test"), title("lu.01")], 60),
        "-b/old.jsonl": ([cwd(a), title("lu.01")], 200 * 86_400),
    ])
    #expect(SessionFolder.find("lu.01", projectsDir: root) == nil)
}
