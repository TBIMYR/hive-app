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
