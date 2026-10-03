import Testing
@testable import HiveCore

@Test func anpinnenHaengtAnsEndeOhneDoppelte() {
    #expect(Pins.pinning("c", in: ["a", "b"]) == ["a", "b", "c"])
    #expect(Pins.pinning("a", in: ["a", "b"]) == ["a", "b"])
}

@Test func nachRechtsZiehenNimmtDenPlatzDesZiels() {
    #expect(Pins.moving("a", to: "c", in: ["a", "b", "c"]) == ["b", "c", "a"])
    #expect(Pins.moving("a", to: "b", in: ["a", "b", "c"]) == ["b", "a", "c"])
}

@Test func nachLinksZiehenNimmtDenPlatzDesZiels() {
    #expect(Pins.moving("c", to: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
}

@Test func unbekannteNamenAendernNichts() {
    #expect(Pins.moving("x", to: "a", in: ["a", "b"]) == ["a", "b"])
    #expect(Pins.moving("a", to: "x", in: ["a", "b"]) == ["a", "b"])
    #expect(Pins.moving("a", to: "a", in: ["a", "b"]) == ["a", "b"])
}

@Test func aufloesenUeberspringtFehlendeUndBehaeltDieReihenfolge() {
    let items = [("a", 2), ("b", 1)]
    let r = Pins.resolve(["b", "x", "a"], in: items, name: { $0.0 }, rank: { $0.1 })
    #expect(r.map(\.0) == ["b", "a"])
}

@Test func aufloesenNimmtDenKleinstenRangSonstDenErsten() {
    let items = [("a", 3, "tot"), ("a", 0, "lebt"), ("b", 2, "erster"), ("b", 2, "zweiter")]
    let r = Pins.resolve(["a", "b"], in: items, name: { $0.0 }, rank: { $0.1 })
    #expect(r.map(\.2) == ["lebt", "erster"])
}
