import Testing
@testable import HiveCore

@Test func toggleFavoriteAppendsOrRemoves() {
    #expect(Favorites.toggling("c", in: ["a", "b"]) == ["a", "b", "c"])
    #expect(Favorites.toggling("a", in: ["a", "b"]) == ["b"])
}

/// Items as (name, identifier), already sorted
private func split(_ items: [(String, String)], _ favs: [String]) -> (fav: [String], rest: [String]) {
    let r = Favorites.split(items, favorites: favs, name: { $0.0 })
    return (r.favorites.map(\.1), r.rest.map(\.1))
}

@Test func favoritesFirstInInputOrder() {
    let items = [("a", "a"), ("b", "b"), ("c", "c"), ("d", "d")]
    let r = split(items, ["d", "b"])
    // Order of input (SessionOrder), not of the favorites list
    #expect(r.fav == ["b", "d"])
    #expect(r.rest == ["a", "c"])
}

@Test func favoritesWithNoMatchAndEmpty() {
    let items = [("a", "a"), ("b", "b")]
    #expect(split(items, ["x"]).fav.isEmpty)
    #expect(split(items, ["x"]).rest == ["a", "b"])
    #expect(split(items, []).rest == ["a", "b"])
    #expect(split([], ["a"]).fav.isEmpty)
}

@Test func favoriteDuplicateNameOnlyFirstEntryOnTop() {
    // sorted: live entry before the dead one; only the first becomes a favorite, the dead one stays in the rest
    let items = [("a", "lebt"), ("b", "b"), ("a", "tot")]
    let r = split(items, ["a"])
    #expect(r.fav == ["lebt"])
    #expect(r.rest == ["b", "tot"])
}

private func session(_ name: String, alive: Bool = true) -> Session {
    Session(name: name, group: Project.groupKey(name, project: ""), isPm: Project.isPm(name), alive: alive,
            status: alive ? "idle" : "offline")
}

@Test func favoritePmTakesItsActiveWorkersAlong() {
    let fav = [session("lu.pm")]
    let rest = [session("or.01"), session("lu.01"), session("lu.02", alive: false), session("lu.03")]
    let r = Favorites.withWorkers(favorites: fav, rest: rest, session: { $0 }, active: { $0.alive == true })
    #expect(r.favorites.map(\.name) == ["lu.pm", "lu.01", "lu.03"])
    // offline workers stay in the offline section
    #expect(r.rest.map(\.name) == ["or.01", "lu.02"])
}

@Test func favoriteWorkerWithoutPmTakesNothing() {
    let r = Favorites.withWorkers(favorites: [session("lu.01")], rest: [session("lu.02")], session: { $0 }, active: { _ in true })
    #expect(r.favorites.map(\.name) == ["lu.01"])
    #expect(r.rest.map(\.name) == ["lu.02"])
}
