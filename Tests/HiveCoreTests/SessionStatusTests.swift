import Testing
@testable import HiveCore

private func s(_ status: String = "idle", alive: Bool = true, waitingFor: String? = nil,
               task: String? = nil, taskState: String? = nil) -> Session {
    Session(name: "al.01", group: "al", pid: 1, alive: alive, status: status, waitingFor: waitingFor,
            task: task.map { Session.TaskLine(text: $0, state: taskState, updatedAt: nil, stale: false) })
}

@Test func shellInTmuxOhneRegister() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "zsh")
    #expect(st.rank == 2 && st.cls == "shell" && st.label == "Shell" && st.reason == nil)
}

@Test func claudeInTmuxOhneRegisterWartetBeimStart() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "claude")
    #expect(st.rank == 0 && st.cls == "need" && st.label == "waiting at start")
    #expect(st.why == "Answer the start prompt in the terminal")
    #expect(st.reason == "Answer the start prompt in the terminal")
    #expect(st.waitsAtStart)
}

@Test func andererAgentInTmux() {
    let st = SessionStatus(s(alive: false), tmuxCommand: "codex")
    #expect(st.rank == 2 && st.cls == "agent" && st.label == "codex")
}

@Test func lebendeSessionInTmuxNachRegister() {
    // läuft Claude und steht lebend im Register, zählt das Register, nicht der tmux-Befehl
    let st = SessionStatus(s("waiting", waitingFor: "Freigabe Bash"), tmuxCommand: "claude")
    #expect(st.rank == 0 && st.label == "waiting for you" && st.reason == "Freigabe Bash" && !st.waitsAtStart)
}

@Test func offline() {
    let st = SessionStatus(s("offline", alive: false))
    #expect(st.rank == 3 && st.cls == "off" && st.label == "offline")
}

@Test func wartetAufDichOhneGrund() {
    let st = SessionStatus(s("waiting"))
    #expect(st.rank == 0 && st.why == "Input needed" && st.reason == "Input needed")
}

@Test func arbeitetSchlaegtBlockiert() {
    let st = SessionStatus(s("busy", task: "x", taskState: "blocked"))
    #expect(st.rank == 1 && st.cls == "busy" && st.label == "working" && st.reason == nil)
}

@Test func blockiertMitAufgabenZeile() {
    let st = SessionStatus(s(task: "Entscheidung Spaltenlayout", taskState: "blocked"))
    #expect(st.rank == 0 && st.cls == "block" && st.label == "blocked")
    #expect(st.why == "Blocked – needs a decision")
    #expect(st.reason == "Entscheidung Spaltenlayout")
}

@Test func blockiertMitLeererAufgabenZeile() {
    #expect(SessionStatus(s(task: " ", taskState: "blocked")).reason == "needs a decision")
}

@Test func wartetAufRueckmeldung() {
    let st = SessionStatus(s(task: "x", taskState: "waiting"))
    #expect(st.rank == 2 && st.cls == "wait" && st.label == "waiting for reply")
}

@Test func shellImRegister() {
    #expect(SessionStatus(s("shell")).cls == "shell")
}

@Test func bereit() {
    let st = SessionStatus(s())
    #expect(st.rank == 2 && st.cls == "idle" && st.label == "ready")
}

@Test func shellErkennung() {
    #expect(SessionStatus.isShell("-zsh") && SessionStatus.isShell("login") && !SessionStatus.isShell("claude"))
}
