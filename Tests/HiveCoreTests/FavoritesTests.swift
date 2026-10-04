import Testing
@testable import HiveCore

@Test func favoritUmschaltenHaengtAnOderNimmtRaus() {
    #expect(Favorites.toggling("c", in: ["a", "b"]) == ["a", "b", "c"])
    #expect(Favorites.toggling("a", in: ["a", "b"]) == ["b"])
}

/// Elemente als (Name, Kennung), schon sortiert
private func split(_ items: [(String, String)], _ favs: [String]) -> (fav: [String], rest: [String]) {
    let r = Favorites.split(items, favorites: favs, name: { $0.0 })
    return (r.favorites.map(\.1), r.rest.map(\.1))
}

@Test func favoritenZuerstInEingabereihenfolge() {
    let items = [("a", "a"), ("b", "b"), ("c", "c"), ("d", "d")]
    let r = split(items, ["d", "b"])
    // Reihenfolge der Eingabe (SessionOrder), nicht der Favoritenliste
    #expect(r.fav == ["b", "d"])
    #expect(r.rest == ["a", "c"])
}

@Test func favoritenOhneTrefferUndLeer() {
    let items = [("a", "a"), ("b", "b")]
    #expect(split(items, ["x"]).fav.isEmpty)
    #expect(split(items, ["x"]).rest == ["a", "b"])
    #expect(split(items, []).rest == ["a", "b"])
    #expect(split([], ["a"]).fav.isEmpty)
}

@Test func favoritDoppelterNameNurErsterEintragOben() {
    // sortiert: lebender Eintrag vor dem toten; nur der erste wird Favorit, der tote bleibt im Rest
    let items = [("a", "lebt"), ("b", "b"), ("a", "tot")]
    let r = split(items, ["a"])
    #expect(r.fav == ["lebt"])
    #expect(r.rest == ["b", "tot"])
}
