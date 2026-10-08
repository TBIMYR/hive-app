import Foundation

/// Favorites (stored by name, heart icon in card, tile and row). Pure functions, the store does the persisting.
public enum Favorites {
    /// Adds the name (at the end) or removes it.
    public static func toggling(_ name: String, in list: [String]) -> [String] {
        list.contains(name) ? list.filter { $0 != name } : list + [name]
    }

    /// Splits already-sorted items into favorites and the rest, both in input order.
    /// For each favorite name only the first entry counts (for a dead and a live one, the more urgent one); further ones stay in the rest.
    public static func split<T>(_ sortedItems: [T], favorites: [String], name: (T) -> String)
        -> (favorites: [T], rest: [T]) {
        var open = Set(favorites)
        var fav: [T] = [], rest: [T] = []
        for item in sortedItems {
            if open.remove(name(item)) != nil { fav.append(item) } else { rest.append(item) }
        }
        return (fav, rest)
    }

    /// For the list: a favorite PM takes the active workers of its group along into the favorites, so they stay
    /// indented under it. Workers keep their order and follow the favorites; offline ones stay in the rest.
    public static func withWorkers<T>(favorites: [T], rest: [T], session: (T) -> Session, active: (T) -> Bool)
        -> (favorites: [T], rest: [T]) {
        let pms = Set(favorites.map(session).filter(\.isPm).map(\.groupKey))
        let along = rest.map { active($0) && pms.contains(session($0).groupKey) }
        return (favorites + rest.indices.filter { along[$0] }.map { rest[$0] },
                rest.indices.filter { !along[$0] }.map { rest[$0] })
    }
}
