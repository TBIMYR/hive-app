import Foundation
import Testing
@testable import HiveCore

private let now = parseISO("2026-09-30T16:00:00Z")!

private func build(now: Date = now, alive: @escaping (Int) -> Bool = { _ in true }) -> HiveState {
    StateBuilder.build(claudeHome: fixtures, devRoot: dev, now: now, isAlive: alive)
}
private func session(_ name: String, _ s: HiveState = build()) -> Session? { s.sessions.first { $0.name == name } }

@Test func lebendeSessionsUndOfflineZeileAusHandover() throws {
    let s = build()
    #expect(s.sessions.map(\.name).sorted() == ["al.01", "al.01#101", "al.pm", "al.pm#103", "be.pm"])
    let off = try #require(session("be.pm", s))
    #expect(off.alive == false)
    #expect(off.status == "offline")
    #expect(off.task?.text == "Handover geschrieben, wartet auf Neustart")
    #expect(off.project == "beta")
    #expect(off.cwd == nil)
    #expect(off.pid == nil)
}

@Test func transkriptUndHandoverWerdenVerknuepft() throws {
    let pm = try #require(session("al.pm"))
    #expect(pm.lastAssistant?.text == "Ich fange mit dem Layout an.")
    #expect(pm.lastUser?.text == "Bitte die Startseite umbauen")
    #expect(pm.branch == "feat/startseite")
    #expect(pm.project == "alpha")
    #expect(pm.group == "al")
    #expect(pm.isPm)
    #expect(pm.hasHandover == false)
    #expect(pm.task == nil)
    let w = try #require(session("al.01"))
    #expect(w.hasHandover)
    #expect(w.task?.state == "working")
    #expect(w.lastAssistant == nil, "kein Transkript für sid-102 → nil, kein Fehler")
    #expect(w.errors.isEmpty)
}

@Test func staleWennBusyUndAufgabeAelterAlsEineStunde() {
    let late = build(now: parseISO("2026-09-30T18:00:00+02:00")!)
    #expect(session("al.01", late)?.status == "busy")
    #expect(session("al.01", late)?.task?.stale == true)
    let early = build(now: parseISO("2026-09-30T16:30:00+02:00")!)
    #expect(session("al.01", early)?.task?.stale == false)
}

@Test func sortierungGruppePmZuerstDannName() {
    #expect(build().sessions.map(\.name) == ["al.pm", "al.01", "al.01#101", "al.pm#103", "be.pm"])
}

@Test func toteRegisterEintraegeOhneHandoverFallenWeg() {
    let s = build(alive: { $0 != 100 && $0 != 103 })
    #expect(!s.sessions.contains { $0.name.hasPrefix("al.pm") })
}

@Test func kindWirdDurchgereichtOfflineHatKeins() {
    #expect(session("al.pm")?.kind == "interactive")
    #expect(session("al.pm#103")?.kind == "bg")
    #expect(session("be.pm")?.kind == nil)
}

@Test func langeTexteWerdenGekuerzt() {
    let long = String(repeating: "a", count: 700)
    let c = StateBuilder.clip(Said(text: long, at: nil))
    #expect(c?.text == String(repeating: "a", count: 600) + "…")
    #expect(StateBuilder.clip(Said(text: "kurz", at: "x")) == Said(text: "kurz", at: "x"))
}

@Test func registerFehlerLandenImZustand() {
    #expect(build().errors.count == 1)
    #expect(build().generatedAt == "2026-09-30T16:00:00.000Z")
}
