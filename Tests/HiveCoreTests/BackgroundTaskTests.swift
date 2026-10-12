import Foundation
import Testing
@testable import HiveCore

// MARK: Helpers: small transcript lines in the shapes Claude Code writes

private func json(_ o: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
}

private let now = parseISO("2026-10-04T12:00:00.000Z")!

/// tool_result line with Claude Code's `toolUseResult` metadata next to the message.
private func result(_ id: String, text: String, meta: [String: Any], at: String = "2026-10-04T11:00:00.000Z") -> String {
    json(["type": "user", "timestamp": at, "toolUseResult": meta,
          "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id,
                                                   "content": [["type": "text", "text": text]]]]]])
}

private func agentLaunched(_ agentId: String, at: String = "2026-10-04T11:00:00.000Z") -> String {
    result("toolu_\(agentId)", text: "Async agent launched successfully.\nagentId: \(agentId) (internal ID)\nThe agent is working in the background.",
           meta: ["isAsync": true, "status": "async_launched", "agentId": agentId, "description": "Review lumen plan"], at: at)
}

private func bashLaunched(_ taskId: String, at: String = "2026-10-04T11:00:00.000Z") -> String {
    result("toolu_\(taskId)", text: "Command running in background with ID: \(taskId). Output is being written to: /tmp/\(taskId).output.",
           meta: ["stdout": "", "stderr": "", "interrupted": false, "backgroundTaskId": taskId], at: at)
}

private func agentResumed(_ agentId: String, at: String = "2026-10-04T11:30:00.000Z") -> String {
    result("toolu_resume_\(agentId)", text: "{\"success\":true,\"message\":\"Resuming agent\",\"resumedAgentId\":\"\(agentId)\"}",
           meta: ["success": true, "message": "Resuming agent", "resumedAgentId": agentId], at: at)
}

private func notification(_ taskId: String, status: String?) -> String {
    let st = status.map { "<status>\($0)</status>\n" } ?? ""
    return "<task-notification>\n<task-id>\(taskId)</task-id>\n<output-file>/tmp/\(taskId).output</output-file>\n\(st)<summary>Agent \"x\" finished</summary>\n</task-notification>"
}

private func notified(_ taskId: String, status: String? = "completed", at: String = "2026-10-04T11:10:00.000Z") -> String {
    json(["type": "user", "timestamp": at, "origin": ["kind": "task-notification"],
          "message": ["role": "user", "content": notification(taskId, status: status)]])
}

private func enqueued(_ taskId: String, status: String = "completed", at: String = "2026-10-04T11:10:00.000Z") -> String {
    json(["type": "queue-operation", "operation": "enqueue", "timestamp": at, "content": notification(taskId, status: status)])
}

private func queuedAttachment(_ taskId: String, status: String = "completed", at: String = "2026-10-04T11:10:00.000Z") -> String {
    json(["type": "attachment", "timestamp": at, "attachment": ["type": "queued_command", "prompt": notification(taskId, status: status)]])
}

private func count(_ lines: String...) -> Int { Transcript.backgroundTasks(lines.joined(separator: "\n"), now: now) }

// MARK: Detection

@Test func noBackgroundTasksInPlainTranscript() throws {
    let text = try String(contentsOfFile: fixture("transcript.jsonl"), encoding: .utf8)
    #expect(Transcript.backgroundTasks(text, now: now) == 0)
    #expect(Transcript.backgroundTasks("", now: now) == 0)
}

@Test func launchedAgentAndShellCommandCountAsRunning() {
    #expect(count(agentLaunched("a1lu")) == 1)
    #expect(count(bashLaunched("b1or")) == 1)
    #expect(count(agentLaunched("a1lu"), bashLaunched("b1or")) == 2)
}

@Test func taskNotificationFinishesTheTask() {
    #expect(count(agentLaunched("a1lu"), bashLaunched("b1or"), notified("a1lu")) == 1)
    #expect(count(bashLaunched("b1or"), notified("b1or", status: "failed")) == 0)
    #expect(count(bashLaunched("b1or"), notified("b1or", status: "killed")) == 0)
}

@Test func queuedNotificationAlreadyFinishesTheTask() {
    // while the session is busy the notification waits in the queue; the task itself is done already
    #expect(count(agentLaunched("a1lu"), enqueued("a1lu")) == 0)
    #expect(count(agentLaunched("a1lu"), queuedAttachment("a1lu")) == 0)
}

@Test func notificationWithoutStatusDoesNotFinish() {
    // Monitor events arrive as task-notifications without <status>; the task keeps running
    #expect(count(bashLaunched("b1fj"), notified("b1fj", status: nil)) == 1)
}

@Test func notificationForUnknownTaskIsIgnored() {
    #expect(count(notified("a9lu"), agentLaunched("a1lu")) == 1)
}

@Test func resumedAgentRunsAgainUntilItsNextNotification() {
    #expect(count(agentLaunched("a1lu"), notified("a1lu"), agentResumed("a1lu")) == 1)
    #expect(count(agentLaunched("a1lu"), notified("a1lu"), agentResumed("a1lu"),
                  notified("a1lu", at: "2026-10-04T11:40:00.000Z")) == 0)
}

@Test func tasksStartedLongAgoWithoutCompletionAreStale() {
    #expect(count(agentLaunched("a1lu", at: "2026-10-04T05:30:00.000Z")) == 0)
    #expect(count(agentLaunched("a1lu", at: "2026-10-04T06:30:00.000Z")) == 1)
}

@Test func assistantTextQuotingANotificationIsIgnored() {
    let quote = json(["type": "assistant", "timestamp": "2026-10-04T11:20:00.000Z",
                      "message": ["role": "assistant", "content": [["type": "text", "text": notification("a1lu", status: "completed")]]]])
    #expect(count(agentLaunched("a1lu"), quote) == 1)
}

@Test func foregroundToolResultsDoNotCount() {
    let plain = result("toolu_1", text: "ok", meta: ["stdout": "ok", "stderr": "", "interrupted": false])
    let syncAgent = result("toolu_2", text: "done", meta: ["status": "completed", "agentId": "a2or"])
    #expect(count(plain, syncAgent) == 0)
}

@Test func fallsBackToResultTextWithoutMetadata() {
    let agent = json(["type": "user", "timestamp": "2026-10-04T11:00:00.000Z",
                      "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "toolu_1",
                                                               "content": [["type": "text", "text": "Async agent launched successfully.\nagentId: a3lu (internal ID)"]]]]]])
    let shell = json(["type": "user", "timestamp": "2026-10-04T11:00:00.000Z",
                      "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "toolu_2",
                                                               "content": "Command running in background with ID: b3lu. Output is being written to: /tmp/x"]]]])
    #expect(count(agent, shell) == 2)
    #expect(count(agent, shell, notified("a3lu"), notified("b3lu")) == 0)
}

// MARK: Status and "Now" line

private func idle(_ bg: Int, status: String = "idle", taskState: String? = nil) -> Session {
    Session(name: "lu.01", group: "lu", pid: 1, alive: true, status: status,
            task: taskState.map { Session.TaskLine(text: "x", state: $0, updatedAt: nil, stale: false) },
            lastAction: WorkAction(tool: "Agent", text: "Running agent: Review", detail: nil, at: "2026-10-04T11:00:00.000Z", pending: false),
            lastSentence: "Two reviewers are running.", backgroundTasks: bg)
}

@Test func idleSessionWithBackgroundTasksCountsAsWorking() {
    let st = SessionStatus(idle(2))
    #expect(st.rank == 1 && st.cls == "busy" && st.label == "background")
    #expect(SessionStatus(idle(0)).label == "ready")
}

@Test func backgroundTasksDoNotHideNeedsYouOrBusy() {
    #expect(SessionStatus(idle(1, status: "waiting")).rank == 0)
    #expect(SessionStatus(idle(1, taskState: "blocked")).rank == 0)
    #expect(SessionStatus(idle(1, status: "busy")).label == "working")
    #expect(SessionStatus(idle(1, taskState: "waiting")).label == "background")
}

@Test func nowLineWhileWorkingInBackgroundShowsLastSentence() throws {
    let n = try #require(NowLine(idle(2), rank: 1))
    #expect(n.kind == .done && n.text == "Two reviewers are running.")
    // the main loop working: still the work step
    #expect(NowLine(idle(2, status: "busy"), rank: 1)?.kind == .working)
}

// MARK: Session

@Test func sessionDecodesWithoutBackgroundTasks() throws {
    let data = Data(#"{"name":"or.02","project":"orbit","group":"or","isPm":false,"alive":true,"status":"idle","hasHandover":false,"errors":[]}"#.utf8)
    let s = try JSONDecoder().decode(Session.self, from: data)
    #expect(s.backgroundTasks == 0)
}

@Test func stateBuilderCountsOnlyForLiveSessions() {
    #expect(StateBuilder.backgroundTasks(alive: false, text: agentLaunched("a1fj"), now: now) == 0)
    #expect(StateBuilder.backgroundTasks(alive: true, text: agentLaunched("a1fj"), now: now) == 1)
}
