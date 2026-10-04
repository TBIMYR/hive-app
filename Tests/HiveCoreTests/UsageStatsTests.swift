import Foundation
import Testing
@testable import HiveCore

private var utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private let now = parseISO("2027-01-15T12:00:00Z")!

/// One assistant line like Claude Code writes it (only the fields the scanner reads, plus some content).
private func assistant(id: String, req: String = "req_1", session: String = "sid-a", cwd: String = "/Users/dev/Development/lumen",
                       at: String = "2027-01-15T10:00:00.000Z", input: Int = 3, output: Int = 100,
                       create: Int = 1000, read: Int = 50000, model: String = "claude-model-x") -> String {
    #"{"type":"assistant","sessionId":"\#(session)","cwd":"\#(cwd)","timestamp":"\#(at)","requestId":"\#(req)","#
        + #""message":{"id":"\#(id)","model":"\#(model)","role":"assistant","content":[{"type":"text","text":"usage is fine"}],"#
        + #""usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(create),"#
        + #""cache_read_input_tokens":\#(read)}}}"#
}

private func title(_ name: String, session: String = "sid-a") -> String {
    #"{"type":"custom-title","customTitle":"\#(name)","sessionId":"\#(session)"}"#
}

private func user(_ text: String) -> String {
    #"{"type":"user","sessionId":"sid-a","message":{"role":"user","content":"\#(text)"}}"#
}

/// Temporary ~/.claude/projects
private final class ProjectsDir {
    let path: String

    init() throws {
        path = NSTemporaryDirectory() + "hive-usage-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    @discardableResult
    func write(_ rel: String, _ lines: [String], newline: Bool = true) throws -> String {
        let file = "\(path)/\(rel)"
        try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + (newline ? "\n" : "")).utf8).write(to: URL(fileURLWithPath: file))
        // as if written at the test's `now` (the scanner skips files older than 8 days)
        try touch(rel, now)
        return file
    }

    func append(_ rel: String, _ text: String) throws {
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: "\(path)/\(rel)"))
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
        try touch(rel, now)
    }

    func touch(_ rel: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: "\(path)/\(rel)")
    }
}

private func scanner(_ dir: ProjectsDir) -> UsageScanner {
    UsageScanner(projectsDir: dir.path, devRoot: dev, calendar: utc)
}

@Test func parsesUsageFromAssistantLine() throws {
    let line = try #require(UsageScanner.Line.parse(assistant(id: "msg_1")))
    let r = try #require(UsageScanner.record(line, devRoot: dev, fallbackProject: "x"))
    #expect(r.key == "msg_1|req_1")
    #expect(r.sessionId == "sid-a")
    #expect(r.project == "lumen")
    #expect(r.model == "claude-model-x")
    #expect(r.tokens == TokenCounts(input: 3, output: 100, cacheCreation: 1000, cacheRead: 50000))
    #expect(r.tokens.total == 51103)
    #expect(r.at == parseISO("2027-01-15T10:00:00Z"))
}

@Test func linesWithoutUsageAreIgnored() throws {
    let line = try #require(UsageScanner.Line.parse(user("hi")))
    #expect(UsageScanner.record(line, devRoot: dev, fallbackProject: "x") == nil)
}

@Test func dedupesStreamedLinesKeepingTheLargest() throws {
    let dir = try ProjectsDir()
    try dir.write("-Users-dev-Development-lumen/sid-a.jsonl", [
        title("lu.01"),
        assistant(id: "msg_1", output: 10),
        assistant(id: "msg_1", output: 240),
        assistant(id: "msg_1", output: 120),
        user("next"),
        assistant(id: "msg_2", req: "req_2", output: 5, create: 0, read: 1000),
    ])
    let stats = scanner(dir).scan(now: now)
    #expect(stats.today.output == 245)
    #expect(stats.today.cacheRead == 51000)
    #expect(stats.today.input == 6)
    #expect(stats.sessionsToday.map(\.name) == ["lu.01"])
    #expect(stats.projectsToday.map(\.name) == ["lumen"])
}

@Test func aggregatesPerDayProjectAndSession() throws {
    let dir = try ProjectsDir()
    try dir.write("-Users-dev-Development-lumen/sid-a.jsonl", [
        title("lu.01"),
        assistant(id: "m1", output: 100, create: 0, read: 0),
        assistant(id: "m2", at: "2027-01-14T23:59:00Z", output: 7, create: 0, read: 0),   // yesterday
        assistant(id: "m3", at: "2027-01-09T08:00:00Z", output: 3, create: 0, read: 0),   // 6 days ago
        assistant(id: "m4", at: "2027-01-08T08:00:00Z", output: 1000, create: 0, read: 0), // 7 days ago: not in the week
    ])
    try dir.write("-Users-dev-Development-orbit/sid-b.jsonl", [
        assistant(id: "m5", session: "sid-bbbbbbbb-1111", cwd: "/Users/dev/Development/orbit", output: 300, create: 0, read: 0),
    ])
    let stats = scanner(dir).scan(now: now)
    #expect(stats.today.output == 400)
    #expect(stats.last7Days.output == 410)
    #expect(stats.days.first?.tokens.output == 400)
    #expect(stats.days.count == 7)
    #expect(stats.days.map(\.tokens.output) == [400, 7, 0, 0, 0, 0, 3])
    #expect(stats.projectsToday.map(\.name) == ["orbit", "lumen"])
    // without a title: short session id
    #expect(stats.sessionsToday.map(\.name) == ["sid-bbbb", "lu.01"])
}

@Test func subagentTranscriptsCountForTheirSession() throws {
    let dir = try ProjectsDir()
    try dir.write("-Users-dev-Development-lumen/sid-a.jsonl", [title("lu.pm"), assistant(id: "m1", output: 10)])
    try dir.write("-Users-dev-Development-lumen/sid-a/subagents/agent-x1.jsonl", [
        assistant(id: "m2", cwd: "/Users/dev/Development/kiosk", output: 20),
    ])
    let stats = scanner(dir).scan(now: now)
    #expect(stats.today.output == 30)
    #expect(stats.sessionsToday.map(\.name) == ["lu.pm"])
    #expect(Set(stats.projectsToday.map(\.name)) == ["lumen", "kiosk"])
}

@Test func symlinkedProjectFoldersAreNotFollowed() throws {
    let dir = try ProjectsDir()
    try dir.write("-Users-dev-Development-lumen/sid-a.jsonl", [assistant(id: "m1", output: 10)])
    try FileManager.default.createSymbolicLink(atPath: "\(dir.path)/-Users-dev-Development-lumen-old",
                                               withDestinationPath: "./-Users-dev-Development-lumen")
    let s = scanner(dir)
    #expect(s.scan(now: now).today.output == 10)
    #expect(s.trackedFiles == 1)
}

@Test func readsIncrementallyAndWaitsForCompleteLines() throws {
    let dir = try ProjectsDir()
    let rel = "-Users-dev-Development-lumen/sid-a.jsonl"
    try dir.write(rel, [assistant(id: "m1", output: 10)])
    let s = scanner(dir)
    #expect(s.scan(now: now).today.output == 10)

    // a half-written line is not counted yet
    let line = assistant(id: "m2", req: "r2", output: 5)
    try dir.append(rel, String(line.prefix(40)))
    #expect(s.scan(now: now).today.output == 10)
    try dir.append(rel, String(line.dropFirst(40)) + "\n")
    #expect(s.scan(now: now).today.output == 15)

    // a later streamed line for the same response raises it
    try dir.append(rel, assistant(id: "m2", req: "r2", output: 50) + "\n")
    #expect(s.scan(now: now).today.output == 60)
}

@Test func oldFilesAndRecordsAreLeftOut() throws {
    let dir = try ProjectsDir()
    try dir.write("-Users-dev-Development-lumen/old.jsonl", [assistant(id: "m1", at: "2027-01-01T10:00:00Z", output: 10)])
    try dir.touch("-Users-dev-Development-lumen/old.jsonl", parseISO("2027-01-01T10:00:00Z")!)
    try dir.write("-Users-dev-Development-lumen/new.jsonl", [
        assistant(id: "m2", at: "2027-01-02T10:00:00Z", output: 20),   // older than 8 days, in a fresh file
        assistant(id: "m3", output: 30),
    ])
    let s = scanner(dir)
    let stats = s.scan(now: now)
    #expect(stats.today.output == 30)
    #expect(stats.last7Days.output == 30)
    #expect(s.trackedFiles == 1)
}

@Test func emptyStatsWithoutFolder() {
    let s = UsageScanner(projectsDir: "/nonexistent/hive-usage", devRoot: dev, calendar: utc)
    let stats = s.scan(now: now)
    #expect(stats.today == TokenCounts())
    #expect(stats.projectsToday.isEmpty)
}

@Test func lineParserSkipsNestedContentAndDecodesEscapes() throws {
    let text = #"{"message":{"content":[{"type":"text","text":"a \"usage\":{ } ] [ brace"},{"input":{"cwd":"/wrong"}}],"#
        + #""id":"m1","usage":{"input_tokens":1,"output_tokens":2.0,"cache_creation":{"x":1},"cache_read_input_tokens":4}},"#
        + #""wireToolInputs":[[1,2,{"a":null}]],"type":"assistant","ok":true,"n":-1.5e3,"#
        + #""cwd":"/Users/dev/Development/fjörd","sessionId":"s"}"#
    let line = try #require(UsageScanner.Line.parse(text))
    #expect(line.cwd == "/Users/dev/Development/fjörd")
    #expect(line.messageId == "m1")
    #expect(line.type == "assistant")
    #expect(line.usage?.output == 2)
    #expect(line.usage?.cacheRead == 4)
    #expect(line.usage?.cacheCreation == nil)
    #expect(UsageScanner.Line.parse(#"{"type":"assistant","message":{"id":"#) == nil)
}

@Test func fastTimestampParsing() {
    #expect(fastISO("2027-01-15T10:00:00.123Z") == parseISO("2027-01-15T10:00:00.123Z"))
    #expect(fastISO("2027-01-15T10:00:00Z") == parseISO("2027-01-15T10:00:00Z"))
    #expect(fastISO("2027-01-15T12:00:00+02:00") == parseISO("2027-01-15T10:00:00Z"))
    #expect(fastISO("nonsense") == nil)
}
