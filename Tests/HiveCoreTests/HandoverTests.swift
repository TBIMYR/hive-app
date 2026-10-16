import Foundation
import Testing
@testable import HiveCore

@Test func frontmatterFieldsAndBody() {
    let r = Handover.parseFrontmatter("---\na: 1\nb: x: y\n---\nbody\n")
    #expect(r.fields == ["a": "1", "b": "x: y"])
    #expect(r.body == "body\n")
}

@Test func withoutFrontmatterEverythingIsBody() {
    let r = Handover.parseFrontmatter("# Body only\n")
    #expect(r.fields.isEmpty)
    #expect(r.body == "# Body only\n")
}

@Test func unclosedFrontmatterHasNoFields() {
    #expect(Handover.parseFrontmatter("---\nsession: x\n").fields.isEmpty)
}

@Test func directoryIsReadByName() {
    let m = Handover.readDir(fixture("handover"))
    let e = m["al.01"]
    #expect(e?.task == "Home page layout #12, PR open")
    #expect(e?.state == "working")
    #expect(e?.updatedAt == "2026-09-30T16:09:00+02:00")
    #expect(e?.project == "alpha")
    #expect(m["archive"] == nil)
}

@Test func brokenFilesHaveNoTaskAndNoError() {
    let m = Handover.readDir(fixture("handover-broken"))
    #expect(m["broken"]?.task == nil)
    #expect(m["broken"]?.error == nil)
    #expect(m["nofm"]?.task == nil)
}

@Test func missingDirectoryIsEmpty() {
    #expect(Handover.readDir("/nonexistent").isEmpty)
}

@Test func textWithoutFrontmatterForTheView() {
    #expect(Handover.body("al.01", dir: fixture("handover"))?.hasPrefix("# Handover al.01") == true)
    #expect(Handover.body("nofm", dir: fixture("handover-broken")) == "# Body only\n")
    #expect(Handover.body("gibtsnicht", dir: fixture("handover")) == nil)
    #expect(Handover.body("../handover/al.01", dir: fixture("handover")) == nil, "only simple names, as in the server")
}

@Test func archiveMovesHandoverAway() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ho-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: "\(dir)/archive/lu.01", withIntermediateDirectories: true)
    try "---\nsession: lu.01\n---\nnew\n".write(toFile: "\(dir)/lu.01.md", atomically: true, encoding: .utf8)
    // an archived version from the same minute stays
    let now = Date()
    let first = try Handover.archive("lu.01", dir: dir, now: now)
    try "again\n".write(toFile: "\(dir)/lu.01.md", atomically: true, encoding: .utf8)
    let second = try Handover.archive("lu.01", dir: dir, now: now)
    #expect(first != second)
    #expect(second.hasSuffix("-2.md"))
    #expect(Handover.readDir(dir)["lu.01"] == nil)
    #expect(try String(contentsOfFile: first, encoding: .utf8).hasSuffix("new\n"))
    #expect(throws: (any Error).self) { try Handover.archive("../x", dir: dir) }
    #expect(throws: (any Error).self) { try Handover.archive("lu.02", dir: dir) }
}

@Test func detailIsReadAndPassedToTheTaskLine() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try "---\nsession: lu.01\ntask: Android app\ndetail: Enter the FCM key, then test build 214\nstate: working\n---\n"
        .write(toFile: "\(dir)/lu.01.md", atomically: true, encoding: .utf8)
    try "---\nsession: or.01\ntask: Release\n---\n".write(toFile: "\(dir)/or.01.md", atomically: true, encoding: .utf8)
    let m = Handover.readDir(dir)
    #expect(m["lu.01"]?.detail == "Enter the FCM key, then test build 214")
    #expect(m["or.01"]?.detail == nil)
    let line = StateBuilder.taskOf(m["lu.01"], status: "busy", now: Date())
    #expect(line?.text == "Android app")
    #expect(line?.detail == "Enter the FCM key, then test build 214")
}
