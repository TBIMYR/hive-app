import Testing
@testable import HiveCore

private func s(_ status: String = "idle", alive: Bool = true, waitingFor: String? = nil,
               task: String? = nil, taskState: String? = nil) -> Session {
    Session(name: "al.01", group: "al", pid: 1, alive: alive, status: status, waitingFor: waitingFor,
            task: task.map { Session.TaskLine(text: $0, state: taskState, updatedAt: nil, stale: false) })
}

@Test func shellInTmuxWithoutRegister() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "zsh")
    #expect(st.rank == 2 && st.cls == "shell" && st.label == "Shell" && st.reason == nil)
}

@Test func claudeInTmuxWithoutRegisterWaitsAtStart() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "claude")
    #expect(st.rank == 0 && st.cls == "need" && st.label == "waiting at start")
    #expect(st.why == "Answer the start prompt in the terminal")
    #expect(st.reason == "Answer the start prompt in the terminal")
    #expect(st.waitsAtStart)
}

@Test func otherAgentInTmux() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "codex")
    #expect(st.rank == 2 && st.cls == "agent" && st.label == "codex")
}

@Test func liveSessionInTmuxFollowsRegister() {
    // if Claude is running and alive in the register, the register counts, not the tmux command
    let st = SessionStatus(s("waiting", waitingFor: "Freigabe Bash"), tmuxCommand: "claude")
    #expect(st.rank == 0 && st.label == "waiting for you" && st.reason == "Freigabe Bash" && !st.waitsAtStart)
}

@Test func offline() {
    let st = SessionStatus(s("offline", alive: false))
    #expect(st.rank == 3 && st.cls == "off" && st.label == "offline")
}

@Test func waitingForYouWithoutReason() {
    let st = SessionStatus(s("waiting"))
    #expect(st.rank == 0 && st.why == "Input needed" && st.reason == "Input needed")
}

@Test func workingBeatsBlockedTaskState() {
    let st = SessionStatus(s("busy", task: "x", taskState: "blocked"))
    #expect(st.rank == 1 && st.cls == "busy" && st.label == "working" && st.reason == nil)
}

@Test func blockedWithTaskLine() {
    let st = SessionStatus(s(task: "Entscheidung Spaltenlayout", taskState: "blocked"))
    #expect(st.rank == 0 && st.cls == "block" && st.label == "blocked")
    #expect(st.why == "Blocked – needs a decision")
    #expect(st.reason == "Entscheidung Spaltenlayout")
}

@Test func blockedWithEmptyTaskLine() {
    #expect(SessionStatus(s(task: " ", taskState: "blocked")).reason == "needs a decision")
}

@Test func waitingForReply() {
    let st = SessionStatus(s(task: "x", taskState: "waiting"))
    #expect(st.rank == 2 && st.cls == "wait" && st.label == "awaiting feedback")
}

@Test func shellInRegister() {
    #expect(SessionStatus(s("shell")).cls == "shell")
}

@Test func ready() {
    let st = SessionStatus(s())
    #expect(st.rank == 2 && st.cls == "idle" && st.label == "ready")
}

@Test func shellDetection() {
    #expect(SessionStatus.isShell("-zsh") && SessionStatus.isShell("login") && !SessionStatus.isShell("claude"))
}
