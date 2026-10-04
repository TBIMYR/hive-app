import Foundation

/// Favoriten (nach Name gespeichert, Herz in Karte, Kachel und Zeile). Reine Funktionen, der Store speichert.
public enum Favorites {
    /// Nimmt den Namen auf (ans Ende) oder heraus.
    public static func toggling(_ name: String, in list: [String]) -> [String] {
        list.contains(name) ? list.filter { $0 != name } : list + [name]
    }

    /// Teilt schon sortierte Elemente in Favoriten und Rest, beide in Eingabereihenfolge.
    /// Je Favoritenname zählt nur der erste Eintrag (bei totem und lebendem der dringendere); weitere bleiben im Rest.
    public static func split<T>(_ sortedItems: [T], favorites: [String], name: (T) -> String)
        -> (favorites: [T], rest: [T]) {
        var open = Set(favorites)
        var fav: [T] = [], rest: [T] = []
        for item in sortedItems {
            if open.remove(name(item)) != nil { fav.append(item) } else { rest.append(item) }
        }
        return (fav, rest)
    }
}
