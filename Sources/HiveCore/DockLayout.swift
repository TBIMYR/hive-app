import Foundation

/// The views of the session area next to the overview.
public enum DockPanel: String, Codable, CaseIterable, Sendable {
    case main, handover, project, notes
}

/// How the session area is divided: a tree of splits (side by side or stacked) whose leaves are groups of
/// panels on top of each other with tabs. Every panel sits in exactly one group. The layout is the same
/// for all sessions; panels a session doesn't have are left out when it is shown (`visible`).
public struct DockLayout: Codable, Equatable, Sendable {
    public enum Axis: String, Codable, Sendable { case horizontal, vertical }

    /// Where a dragged panel is dropped on a group: onto its tabs, or beside it
    public enum Zone: String, Sendable { case center, left, right, top, bottom }

    public struct Group: Codable, Equatable, Sendable {
        public var panels: [DockPanel]
        public var selected: DockPanel

        public init(_ panels: [DockPanel], selected: DockPanel? = nil) {
            self.panels = panels
            self.selected = selected ?? panels.first ?? .main
        }
    }

    public struct Split: Codable, Equatable, Sendable {
        public var axis: Axis
        public var children: [Node]
        /// share of each child along the axis, summing up to 1
        public var fractions: [Double]

        public init(_ axis: Axis, _ children: [Node], fractions: [Double]? = nil) {
            self.axis = axis
            self.children = children
            self.fractions = fractions ?? []
        }
    }

    public indirect enum Node: Codable, Equatable, Sendable {
        case group(Group)
        case split(Split)
    }

    public var root: Node

    public init(root: Node) {
        self.root = root
        normalize()
    }

    /// Everything in one group with tabs, the session's terminal in front.
    public static let standard = DockLayout(root: .group(Group(DockPanel.allCases, selected: .main)))

    /// Smallest share a tile can be dragged to
    public static let minFraction = 0.12
    /// Part of a group's width or height at each edge that counts as "beside it" when dropping
    public static let edge = 0.28

    // MARK: Reading

    public var groups: [Group] { Self.groups(root) }

    private static func groups(_ n: Node) -> [Group] {
        switch n {
        case .group(let g): [g]
        case .split(let s): s.children.flatMap(groups)
        }
    }

    public func group(of panel: DockPanel) -> Group? { groups.first { $0.panels.contains(panel) } }

    // MARK: Changing

    /// Brings the panel to the front of its group.
    public mutating func select(_ panel: DockPanel) {
        root = Self.map(root) { g in
            var g = g
            if g.panels.contains(panel) { g.selected = panel }
            return g
        }
    }

    /// Moves `panel` onto the group that holds `target`: `.center` adds it to that group's tabs, an edge
    /// puts it in a tile of its own on that side. Dropping a panel beside its own group pulls it out of the
    /// tabs; with nothing else in the group there is nothing to do.
    public mutating func move(_ panel: DockPanel, to target: DockPanel, zone: Zone) {
        guard let from = group(of: panel), let to = group(of: target) else { return }
        // the group stays identifiable after the panel left it
        var anchor = target
        if from == to {
            if zone == .center { select(panel); return }
            guard let other = from.panels.first(where: { $0 != panel }) else { return }
            anchor = other
        }
        root = Self.map(root) { g in
            guard g.panels.contains(panel) else { return g }
            var g = g
            g.panels.removeAll { $0 == panel }
            if g.selected == panel, let first = g.panels.first { g.selected = first }
            return g
        }
        root = Self.replace(root) { g in
            guard g.panels.contains(anchor) else { return nil }
            var g = g
            let new = Node.group(Group([panel]))
            switch zone {
            case .center:
                g.panels.append(panel)
                g.selected = panel
                return .group(g)
            case .left: return .split(Split(.horizontal, [new, .group(g)]))
            case .right: return .split(Split(.horizontal, [.group(g), new]))
            case .top: return .split(Split(.vertical, [new, .group(g)]))
            case .bottom: return .split(Split(.vertical, [.group(g), new]))
            }
        }
        normalize()
    }

    /// Shifts `delta` (a share of the split at `path`) from the child at `after` to the one at `before`;
    /// neither gets smaller than `minFraction` of the split.
    public mutating func resize(split path: [Int], before: Int, after: Int, delta: Double) {
        root = Self.update(root, path: path[...]) { s in
            guard s.fractions.indices.contains(before), s.fractions.indices.contains(after), before != after else { return s }
            var s = s
            let pair = s.fractions[before] + s.fractions[after]
            let floor = min(Self.minFraction, pair / 2)
            let a = min(max(s.fractions[before] + delta, floor), pair - floor)
            s.fractions[before] = a
            s.fractions[after] = pair - a
            return s
        }
    }

    // MARK: Shown for a session

    public indirect enum Visible: Equatable, Sendable {
        /// `panels` in tab order, `selected` is one of them
        case group(panels: [DockPanel], selected: DockPanel)
        /// `path` leads to the split in the layout; each child knows its index there and its share
        case split(axis: Axis, path: [Int], children: [Child])

        public struct Child: Equatable, Sendable {
            public let index: Int
            public let share: Double
            public let node: Visible
        }
    }

    /// The layout with only the panels this session has. Groups without any are left out, a split with a
    /// single tile left becomes that tile. nil if nothing is available.
    public func visible(_ available: Set<DockPanel>) -> Visible? { Self.visible(root, available, path: []) }

    private static func visible(_ n: Node, _ available: Set<DockPanel>, path: [Int]) -> Visible? {
        switch n {
        case .group(let g):
            let panels = g.panels.filter(available.contains)
            guard let first = panels.first else { return nil }
            return .group(panels: panels, selected: panels.contains(g.selected) ? g.selected : first)
        case .split(let s):
            let children = s.children.enumerated().compactMap { i, c in
                visible(c, available, path: path + [i]).map { Visible.Child(index: i, share: s.fractions[i], node: $0) }
            }
            if children.count == 1 { return children[0].node }
            return children.isEmpty ? nil : .split(axis: s.axis, path: path, children: children)
        }
    }

    /// Drop zone for a point in a group's rectangle (both in the same coordinates): the nearest edge within
    /// `edge` of the size, otherwise the middle.
    public static func zone(at p: CGPoint, in r: CGRect) -> Zone {
        guard r.width > 0, r.height > 0 else { return .center }
        let x = (p.x - r.minX) / r.width, y = (p.y - r.minY) / r.height
        let nearest = [(x, Zone.left), (1 - x, .right), (y, .top), (1 - y, .bottom)].min { $0.0 < $1.0 }!
        return nearest.0 < edge ? nearest.1 : .center
    }

    // MARK: Keeping it valid

    /// Every panel exactly once, no empty groups, no splits with one child or nested along the same axis,
    /// fractions that fit. Also repairs a stored layout from an older version.
    public mutating func normalize() {
        var seen: Set<DockPanel> = []
        var node = Self.map(root) { g in
            var g = g
            g.panels = g.panels.filter { seen.insert($0).inserted }
            return g
        }
        let missing = DockPanel.allCases.filter { !seen.contains($0) }
        if !missing.isEmpty {
            // new panels join the terminal's group (or the first one)
            let home = Self.groups(node).first { $0.panels.contains(.main) }?.panels.first
                ?? Self.groups(node).first { !$0.panels.isEmpty }?.panels.first
            var added = false
            node = Self.map(node) { g in
                guard !added, let home, g.panels.contains(home) else { return g }
                added = true
                var g = g
                g.panels += missing
                return g
            }
            if !added { node = .group(Group(missing)) }
        }
        root = Self.tidy(node) ?? Self.standard.root
    }

    private static func tidy(_ n: Node) -> Node? {
        switch n {
        case .group(var g):
            guard let first = g.panels.first else { return nil }
            if !g.panels.contains(g.selected) { g.selected = first }
            return .group(g)
        case .split(let s):
            var children: [Node] = [], fractions: [Double] = []
            let even = 1 / Double(max(s.children.count, 1))
            for (i, c) in s.children.enumerated() {
                guard let t = tidy(c) else { continue }
                let f = s.fractions.count == s.children.count && s.fractions[i] > 0 ? s.fractions[i] : even
                // a split along the same axis dissolves into its parent
                if case .split(let inner) = t, inner.axis == s.axis {
                    children += inner.children
                    fractions += inner.fractions.map { $0 * f }
                } else {
                    children.append(t)
                    fractions.append(f)
                }
            }
            if children.count <= 1 { return children.first }
            let sum = fractions.reduce(0, +)
            return .split(Split(s.axis, children, fractions: fractions.map { $0 / sum }))
        }
    }

    private static func map(_ n: Node, _ f: (Group) -> Group) -> Node {
        switch n {
        case .group(let g): return .group(f(g))
        case .split(var s):
            s.children = s.children.map { map($0, f) }
            return .split(s)
        }
    }

    /// Replaces the groups for which `f` returns a node.
    private static func replace(_ n: Node, _ f: (Group) -> Node?) -> Node {
        switch n {
        case .group(let g): return f(g) ?? n
        case .split(var s):
            s.children = s.children.map { replace($0, f) }
            return .split(s)
        }
    }

    private static func update(_ n: Node, path: ArraySlice<Int>, _ f: (Split) -> Split) -> Node {
        guard case .split(var s) = n else { return n }
        guard let i = path.first else { return .split(f(s)) }
        guard s.children.indices.contains(i) else { return n }
        s.children[i] = update(s.children[i], path: path.dropFirst(), f)
        return .split(s)
    }

    // MARK: Storing

    public var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The stored layout, repaired if needed; the standard one for anything unreadable.
    public init(json: String) {
        if let l = try? JSONDecoder().decode(DockLayout.self, from: Data(json.utf8)) {
            self.init(root: l.root)
        } else {
            self = Self.standard
        }
    }
}
