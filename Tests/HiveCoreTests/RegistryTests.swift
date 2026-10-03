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

@Test func liestEintraegeUndUeberspringtKaputteDateien() {
    let r = read()
    #expect(r.entries.count == 4)
    #expect(r.errors.count == 1)
    #expect(r.errors.first?.contains("broken.json") == true)
}

@Test func felderWerdenUebernommen() {
    let r = read()
    let pm = entry(pid: 100, r)
    #expect(pm?.name == "al.pm")
    #expect(pm?.sessionId == "sid-100")
    #expect(pm?.status == "idle")
    #expect(pm?.waitingFor == nil)
    #expect(pm?.alive == true)
    #expect(pm?.statusUpdatedAt == "1970-01-01T00:00:05.000Z")
    #expect(entry(pid: 101, r)?.waitingFor == "input needed")
}

@Test func statusUpdatedAtFaelltAufUpdatedAtZurueck() {
    #expect(entry(pid: 103, read())?.statusUpdatedAt == "1970-01-01T00:00:09.000Z")
}

@Test func duplikatJuengsterStartBehaeltDenNamen() {
    let r = read()
    #expect(r.entries.map(\.name).sorted() == ["al.01", "al.01#101", "al.pm", "al.pm#103"])
    #expect(r.entries.first { $0.name == "al.01" }?.pid == 102)
}

@Test func duplikatSessionMitFensterSchlaegtHintergrund() {
    let r = read()
    #expect(r.entries.first { $0.name == "al.pm" }?.pid == 100)
    #expect(entry(pid: 103, r)?.name == "al.pm#103")
    #expect(entry(pid: 103, r)?.kind == "bg")
    #expect(entry(pid: 100, r)?.kind == "interactive")
}

@Test func toteEintraegeZaehlenNichtBeiDuplikaten() {
    #expect(entry(pid: 101, read(alive: { $0 != 102 }))?.name == "al.01")
}

@Test func toteProzesseSindNichtAlive() {
    #expect(entry(pid: 101, read(alive: { $0 != 101 }))?.alive == false)
}

@Test func fehlenderOrdnerIstLeerOhneFehler() {
    let r = Registry.read("/nonexistent/dir", isAlive: { _ in true })
    #expect(r.entries.isEmpty)
    #expect(r.errors.isEmpty)
}

@Test func eigenerProzessLebtUnbekannterNicht() {
    #expect(Registry.isAlive(Int(getpid())))
    #expect(!Registry.isAlive(999_999))
}
