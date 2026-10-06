import CoreGraphics
import Foundation

/// Keyboard navigation through the overview (⌘ + arrow keys): spatial, based on where the sessions are drawn.
public enum SessionNav {
    public enum Direction: Sendable { case up, down, left, right }

    /// Session to select after pressing ⌘ + `direction`.
    /// - `frames`: frame of each drawn session (by name) in one coordinate space. Lazy stacks only draw what's near
    ///   the visible area, so sessions further away may be missing.
    /// - `order`: all shown sessions in overview order; reaches sessions that aren't drawn yet.
    ///
    /// ↑/↓ go to the nearest row above/below, there to the session closest in x. ←/→ go to the previous/next
    /// session in reading order (in a grid the neighbor in the row, at the row's end on to the next row).
    /// Without a drawn selection: the first session (↓/→) or the last one (↑/←). At the edge the selection stays.
    public static func target(from selected: String?, _ direction: Direction,
                              frames: [String: CGRect], order: [String]) -> String? {
        let rows = Self.rows(frames)
        let reading = rows.flatMap { $0 }
        guard let sel = selected, let cur = frames[sel] else {
            let all = reading.isEmpty ? order : reading
            return direction == .up || direction == .left ? all.last : all.first
        }
        let r = rows.firstIndex { $0.contains(sel) }!
        let found: String?
        switch direction {
        case .left, .right:
            let i = reading.firstIndex(of: sel)! + (direction == .right ? 1 : -1)
            found = reading.indices.contains(i) ? reading[i] : nil
        case .up, .down:
            let t = r + (direction == .down ? 1 : -1)
            found = rows.indices.contains(t)
                ? rows[t].min { abs(frames[$0]!.midX - cur.midX) < abs(frames[$1]!.midX - cur.midX) }
                : nil
        }
        return found ?? undrawnNeighbor(of: sel, direction, frames: frames, order: order) ?? sel
    }

    /// Names grouped into rows (same top edge), top to bottom, each row left to right.
    static func rows(_ frames: [String: CGRect]) -> [[String]] {
        let sorted = frames.sorted { a, b in
            a.value.minY != b.value.minY ? a.value.minY < b.value.minY : a.value.minX < b.value.minX
        }
        var rows: [[String]] = []
        var top = -CGFloat.infinity
        for (name, f) in sorted {
            if f.minY - top > 4 || rows.isEmpty { rows.append([]); top = f.minY }
            rows[rows.count - 1].append(name)
        }
        return rows.map { $0.sorted { frames[$0]!.minX < frames[$1]!.minX } }
    }

    /// Past the drawn sessions: the neighbor in `order`, if it isn't drawn (otherwise it lies elsewhere on screen).
    private static func undrawnNeighbor(of sel: String, _ direction: Direction,
                                        frames: [String: CGRect], order: [String]) -> String? {
        guard let i = order.firstIndex(of: sel) else { return nil }
        let j = i + (direction == .down || direction == .right ? 1 : -1)
        guard order.indices.contains(j), frames[order[j]] == nil else { return nil }
        return order[j]
    }
}
