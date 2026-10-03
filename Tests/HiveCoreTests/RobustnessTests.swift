import Foundation
import Testing
@testable import HiveCore

/// Leerer Ordner unter tmp, wird nach dem Test gelöscht.
private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hive-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func pidAusserhalbDesZahlenbereichsWirdUebersprungen() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try #"{"pid":1e20,"name":"x"}"#.write(to: dir.appending(path: "a.json"), atomically: true, encoding: .utf8)
    try #"{"pid":42,"name":"y"}"#.write(to: dir.appending(path: "b.json"), atomically: true, encoding: .utf8)
    let r = Registry.read(dir.path, isAlive: { _ in true })
    #expect(r.entries.map(\.name) == ["y"])
}

@Test func ungueltigesUtf8ImHandoverWieNode() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    var data = Data("---\ntask: Aufgabe \u{FF}\n---\nText ".utf8)
    data.append(0xFF)   // kaputtes Byte: Node ersetzt es durch U+FFFD statt die Datei zu verwerfen
    data.append(contentsOf: Array("\n".utf8))
    try data.write(to: dir.appending(path: "x.md"))
    let e = Handover.readDir(dir.path)["x"]
    #expect(e?.error == nil)
    #expect(e?.task == "Aufgabe \u{FF}")
    #expect(Handover.body("x", dir: dir.path) == "Text \u{FFFD}\n")
}

@Test func idIstEindeutigAuchBeiGleichemNamen() {
    let dead = Session(name: "al.01", group: "al", pid: 7)
    let live = Session(name: "al.01", group: "al", pid: 8, alive: true)
    let offline = Session(name: "al.01", group: "al")
    #expect(Set([dead.id, live.id, offline.id]).count == 3)
}
