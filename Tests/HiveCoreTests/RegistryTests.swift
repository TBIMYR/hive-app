import Foundation
import Testing
@testable import HiveCore

private let dir = fixture("sessions")
private func read(alive: @escaping (Int) -> Bool = { _ in true }) -> (entries: [RegistryEntry], errors: [String]) {
    Registry.read(dir, isAlive: alive)
}
private func entry(pid: Int, _ r: (entries: [RegistryEntry], errors: [String])) -> RegistryEntry? {
    r.entries.first { $0.pid == pid }
}

@Test func readsEntriesAndSkipsBrokenFiles() {
    let r = read()
    #expect(r.entries.count == 4)
    #expect(r.errors.count == 1)
    #expect(r.errors.first?.contains("broken.json") == true)
}

@Test func fieldsArePopulated() {
    let r = read()
    let pm = entry(pid: 100, r)
    #expect(pm?.name == "al.pm")
    #expect(pm?.sessionId == "sid-100")
    #expect(pm?.status == "idle")
    #expect(pm?.waitingFor == nil)
    #expect(pm?.alive == true)
    #expect(pm?.statusUpdatedAt == "1970-01-01T00:00:05.000Z")
    #expect(entry(pid: 101, r)?.waitingFor == "input needed")
    #expect(pm?.remoteControl == false)
    #expect(entry(pid: 101, r)?.remoteControl == true)
}

@Test func standbyProcessesAreNotSessions() {
    #expect(entry(pid: 104, read()) == nil)
}

@Test func tmuxPaneFromTmuxField() {
    let r = read()
    #expect(entry(pid: 100, r)?.tmuxPane == "%1")
    #expect(entry(pid: 101, r)?.tmuxPane == nil)
    #expect(Registry.paneOf("keeper.01:@13.%13") == "%13")
    #expect(Registry.paneOf("broken") == nil)
}

@Test func statusUpdatedAtFallsBackToUpdatedAt() {
    #expect(entry(pid: 103, read())?.statusUpdatedAt == "1970-01-01T00:00:09.000Z")
}

@Test func duplicateMostRecentlyStartedKeepsTheName() {
    let r = read()
    #expect(r.entries.map(\.name).sorted() == ["al.01", "al.01#101", "al.pm", "al.pm#103"])
    #expect(r.entries.first { $0.name == "al.01" }?.pid == 102)
}

@Test func duplicateSessionWithWindowBeatsBackground() {
    let r = read()
    #expect(r.entries.first { $0.name == "al.pm" }?.pid == 100)
    #expect(entry(pid: 103, r)?.name == "al.pm#103")
    #expect(entry(pid: 103, r)?.kind == "bg")
    #expect(entry(pid: 100, r)?.kind == "interactive")
}

@Test func deadEntriesDontCountForDuplicates() {
    #expect(entry(pid: 101, read(alive: { $0 != 102 }))?.name == "al.01")
}

@Test func deadProcessesAreNotAlive() {
    #expect(entry(pid: 101, read(alive: { $0 != 101 }))?.alive == false)
}

@Test func missingFolderIsEmptyWithoutError() {
    let r = Registry.read("/nonexistent/dir", isAlive: { _ in true })
    #expect(r.entries.isEmpty)
    #expect(r.errors.isEmpty)
}

@Test func ownProcessIsAliveUnknownOneIsNot() {
    #expect(Registry.isAlive(Int(getpid())))
    #expect(!Registry.isAlive(999_999))
}

@Test func windowWithHandedOverConversationBecomesASession() {
    let r = Registry.read(fixture("sessions-parked"), isAlive: { _ in true })
    #expect(r.entries.count == 1)
    let e = r.entries.first
    #expect(e?.name == "x.01")
    #expect(e?.pid == 105)
    #expect(e?.tmuxPane == "%5")
    #expect(e?.status == "waiting")
    #expect(e?.waitingFor == "input needed")
    #expect(e?.statusUpdatedAt == "1970-01-01T00:00:02.000Z")
}
