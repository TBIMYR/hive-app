import Foundation

/// Gruppierung der Ansicht „List“: Worker stehen eingerückt direkt unter ihrem PM.
public enum SessionTree {
    public struct Row<T> {
        public let item: T
        /// 0 = normale Zeile oder PM, 1 = eingerückt unter dem PM
        public let depth: Int
        /// letzte Zeile ihrer Gruppe (Linie endet hier in der Zeilenmitte)
        public let isLastInGroup: Bool
    }

    /// `sortedItems`: schon nach `SessionOrder` sortiert. Eine Gruppe (gleicher `groupKey` mit mindestens einem PM)
    /// steht dort, wo ihr erstes (dringendstes) Mitglied steht: erst der erste PM als Kopf, dann alle übrigen
    /// Mitglieder (auch weitere PMs) eingerückt in Eingabereihenfolge. Ohne PM bleiben Sessions flach an ihrer Stelle.
    public static func grouped<T>(_ sortedItems: [T], session: (T) -> Session) -> [Row<T>] {
        let sessions = sortedItems.map(session)
        let withPm = Set(sessions.filter(\.isPm).map(\.groupKey))
        var members: [String: [Int]] = [:]
        for (i, s) in sessions.enumerated() where withPm.contains(s.groupKey) {
            members[s.groupKey, default: []].append(i)
        }
        var rows: [Row<T>] = []
        var done = Set<String>()
        for (i, s) in sessions.enumerated() {
            let key = s.groupKey
            guard withPm.contains(key) else {
                rows.append(Row(item: sortedItems[i], depth: 0, isLastInGroup: true))
                continue
            }
            guard done.insert(key).inserted, let idx = members[key],
                  let head = idx.first(where: { sessions[$0].isPm }) else { continue }
            let rest = idx.filter { $0 != head }
            rows.append(Row(item: sortedItems[head], depth: 0, isLastInGroup: rest.isEmpty))
            for (n, j) in rest.enumerated() {
                rows.append(Row(item: sortedItems[j], depth: 1, isLastInGroup: n == rest.count - 1))
            }
        }
        return rows
    }
}
