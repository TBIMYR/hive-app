import Foundation

/// Grouping for the "List" view: workers are indented directly under their PM.
public enum SessionTree {
    public struct Row<T> {
        public let item: T
        /// 0 = normal row or PM, 1 = indented under the PM
        public let depth: Int
        /// last row of its group (line ends here at the row's middle)
        public let isLastInGroup: Bool
    }

    /// `sortedItems`: already sorted by `SessionOrder`. A group (same `groupKey` with at least one PM) sits where
    /// its first (most urgent) member sits: the first PM comes first as head, then all remaining members
    /// (including further PMs) indented in input order. Without a PM, sessions stay flat in their place.
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
