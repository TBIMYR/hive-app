import Foundation
import Testing
@testable import HiveCore

private let now = parseISO("2026-09-30T16:00:00Z")!

private func build(now: Date = now, alive: @escaping (Int) -> Bool = { _ in true }) -> HiveState {
    StateBuilder.build(claudeHome: fixtures, devRoot: dev, now: now, isAlive: alive)
}
private func session(_ name: String, _ s: HiveState = build()) -> Session? { s.sessions.first { $0.name == name } }

@Test func livingSessionsAndOfflineLineFromHandover() throws {
    let s = build()
    #expect(s.sessions.map(\.name).sorted() == ["al.01", "al.01#101", "al.pm", "al.pm#103", "be.pm"])
    let off = try #require(session("be.pm", s))
    #expect(off.alive == false)
    #expect(off.status == "offline")
    #expect(off.task?.text == "Handover written, waiting for restart")
    #expect(off.project == "beta")
    #expect(off.cwd == nil)
    #expect(off.pid == nil)
}

@Test func transcriptAndHandoverAreLinked() throws {
    let pm = try #require(session("al.pm"))
    #expect(pm.lastAssistant?.text == "I will start with the layout.")
    #expect(pm.lastUser?.text == "Please rebuild the home page")
    #expect(pm.branch == "feat/home-page")
    #expect(pm.lastSentence == "I will start with the layout.")
    #expect(pm.lastAction?.tool == "Bash")
    #expect(pm.project == "alpha")
    #expect(pm.group == "al")
    #expect(pm.isPm)
    #expect(pm.hasHandover == false)
    #expect(pm.task == nil)
    let w = try #require(session("al.01"))
    #expect(w.hasHandover)
    #expect(w.task?.state == "working")
    #expect(w.lastAssistant == nil, "no transcript for sid-102 → nil, no error")
    #expect(w.errors.isEmpty)
}

@Test func staleWhenBusyAndTaskOlderThanOneHour() {
    let late = build(now: parseISO("2026-09-30T18:00:00+02:00")!)
    #expect(session("al.01", late)?.status == "busy")
    #expect(session("al.01", late)?.task?.stale == true)
    let early = build(now: parseISO("2026-09-30T16:30:00+02:00")!)
    #expect(session("al.01", early)?.task?.stale == false)
}

@Test func sortingGroupPmFirstThenName() {
    #expect(build().sessions.map(\.name) == ["al.pm", "al.01", "al.01#101", "al.pm#103", "be.pm"])
}

@Test func deadRegisterEntriesWithoutHandoverAreDropped() {
    let s = build(alive: { $0 != 100 && $0 != 103 })
    #expect(!s.sessions.contains { $0.name.hasPrefix("al.pm") })
}

@Test func kindIsPassedThroughOfflineHasNone() {
    #expect(session("al.pm")?.kind == "interactive")
    #expect(session("al.pm#103")?.kind == "bg")
    #expect(session("be.pm")?.kind == nil)
}

@Test func longTextsAreTruncated() {
    let long = String(repeating: "a", count: 700)
    let c = StateBuilder.clip(Said(text: long, at: nil))
    #expect(c?.text == String(repeating: "a", count: 600) + "…")
    #expect(StateBuilder.clip(Said(text: "short", at: "x")) == Said(text: "short", at: "x"))
}

@Test func registerErrorsEndUpInState() {
    #expect(build().errors.count == 1)
    #expect(build().generatedAt == "2026-09-30T16:00:00.000Z")
}
