import Foundation

/// The views of the window: the overview of all sessions and the views of the selected one.
public enum DockPanel: String, Codable, CaseIterable, Sendable {
    case overview, main, handover, project, notes

    /// The views of the selected session, which may share a tile as tabs
    public static let session: [DockPanel] = [.main, .handover, .project, .notes]
}

/// How the window is divided: a tree of splits (side by side or stacked) whose leaves are groups of
/// panels on top of each other with tabs. Every panel sits in exactly one group; the overview always has
/// a tile of its own, so the sessions never hide behind a tab. The layout is the same for all sessions;
/// panels a session doesn't have are left out when it is shown (`visible`).
public struct DockLayout: Codable, Equatable, Sendable {
    public enum Axis: String, Codable, Sendable { case horizontal, vertical }

    /// Where a dragged panel is dropped on a group: onto its tabs, or beside it
    public enum Zone: String, Sendable { case center, left, right, top, bottom }

    public struct Group: Codable, Equatable, Sendable {
        public var panels: [DockPanel]
        public var selected: DockPanel
        /// Folded to a bar of icons; a click on one shows its panel on top of the rest for a moment
        public var collapsed: Bool

        public init(_ panels: [DockPanel], selected: DockPanel? = nil, collapsed: Bool = false) {
            self.panels = panels
            self.selected = selected ?? panels.first ?? .main
            self.collapsed = collapsed
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            panels = try c.decode([DockPanel].self, forKey: .panels)
            selected = try c.decode(DockPanel.self, forKey: .selected)
            collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
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

    /// The overview on the left, the session's views beside it in one group with tabs, the terminal in front.
    public static let standard = DockLayout(root: .split(Split(.horizontal, [
        .group(Group([.overview])), .group(Group(DockPanel.session, selected: .main)),
    ], fractions: [1 - sessionShare, sessionShare])))

    /// Room the session's views get next to the overview by default
    public static let sessionShare = 0.34
    /// Room a panel gets that is dropped at an edge of the window
    public static let edgeShare = 0.3

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

    /// Folds the panel's tile to a bar of icons, or opens it again. The last open tile stays open.
    public mutating func setCollapsed(_ collapsed: Bool, groupOf panel: DockPanel) {
        guard !collapsed || canCollapse(groupOf: panel) else { return }
        root = Self.map(root) { g in
            var g = g
            if g.panels.contains(panel) { g.collapsed = collapsed }
            return g
        }
    }

    public func canCollapse(groupOf panel: DockPanel) -> Bool {
        groups.contains { !$0.collapsed && !$0.panels.contains(panel) }
    }

    /// Moves `panel` onto the group that holds `target`: `.center` adds it to that group's tabs, an edge
    /// puts it in a tile of its own on that side and divides that row or column anew (`rebalance`). Dropping a panel beside its own group pulls it out of the
    /// tabs; with nothing else in the group there is nothing to do.
    public mutating func move(_ panel: DockPanel, to target: DockPanel, zone: Zone) {
        guard let from = group(of: panel), let to = group(of: target) else { return }
        // the overview takes no tabs and is no tab
        if zone == .center, panel == .overview || target == .overview { return }
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
        if zone != .center { rebalance(around: panel) }
    }

    /// How much room a panel wants compared with the others: the terminal and the overview the most.
    public static func weight(_ panel: DockPanel) -> Double {
        switch panel {
        case .overview, .main: 3
        case .handover, .project, .notes: 2
        }
    }

    /// A tile wants what its most demanding tab wants; tiles stacked across the axis want what the most
    /// demanding of them wants.
    private static func weight(_ n: Node) -> Double {
        switch n {
        case .group(let g): g.panels.map(weight).max() ?? 1
        case .split(let s): s.children.map(weight).max() ?? 1
        }
    }

    /// Divides the row or column that holds the panel's tile by what each tile in it wants. Done after a
    /// panel was dropped there; what is dragged by hand afterwards stays until the next drop.
    private mutating func rebalance(around panel: DockPanel) {
        func path(_ n: Node, _ at: [Int]) -> [Int]? {
            guard case .split(let s) = n else { return nil }
            for (i, c) in s.children.enumerated() {
                if case .group(let g) = c, g.panels.contains(panel) { return at }
                if let p = path(c, at + [i]) { return p }
            }
            return nil
        }
        guard let p = path(root, []) else { return }
        root = Self.update(root, path: p[...]) { s in
            var s = s
            let w = s.children.map(Self.weight)
            let sum = w.reduce(0, +)
            s.fractions = w.map { $0 / sum }
            return s
        }
    }

    /// Moves `panel` to an edge of the window, across everything else.
    public mutating func move(_ panel: DockPanel, toEdge zone: Zone) {
        guard zone != .center, group(of: panel) != nil else { return }
        root = Self.map(root) { g in
            var g = g
            g.panels.removeAll { $0 == panel }
            if g.selected == panel, let first = g.panels.first { g.selected = first }
            return g
        }
        guard let rest = Self.tidy(root) else { return }
        let new = Node.group(Group([panel]))
        let (a, b) = (Self.edgeShare, 1 - Self.edgeShare)
        switch zone {
        case .left: root = .split(Split(.horizontal, [new, rest], fractions: [a, b]))
        case .right: root = .split(Split(.horizontal, [rest, new], fractions: [b, a]))
        case .top: root = .split(Split(.vertical, [new, rest], fractions: [a, b]))
        default: root = .split(Split(.vertical, [rest, new], fractions: [b, a]))
        }
        normalize()
        // joined an existing row or column: divide it anew; alone across the window it keeps `edgeShare`
        if case .split(let s) = root, s.children.count > 2 { rebalance(around: panel) }
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
        case group(panels: [DockPanel], selected: DockPanel, collapsed: Bool)
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
            return .group(panels: panels, selected: panels.contains(g.selected) ? g.selected : first, collapsed: g.collapsed)
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
    /// With `center: false` (the overview is involved) it is always the nearest edge.
    public static func zone(at p: CGPoint, in r: CGRect, center: Bool = true) -> Zone {
        guard r.width > 0, r.height > 0 else { return center ? .center : .right }
        let x = (p.x - r.minX) / r.width, y = (p.y - r.minY) / r.height
        let nearest = [(x, Zone.left), (1 - x, .right), (y, .top), (1 - y, .bottom)].min { $0.0 < $1.0 }!
        return nearest.0 < edge || !center ? nearest.1 : .center
    }

    /// The edge of the window (`area`) a point is at, within `margin` points; nil further inside.
    public static func windowEdge(at p: CGPoint, in area: CGRect, margin: CGFloat) -> Zone? {
        guard area.contains(p) else { return nil }
        let nearest = [(p.x - area.minX, Zone.left), (area.maxX - p.x, .right), (p.y - area.minY, .top), (area.maxY - p.y, .bottom)]
            .min { $0.0 < $1.0 }!
        return nearest.0 < margin ? nearest.1 : nil
    }

    // MARK: Keeping it valid

    /// Every panel exactly once, the overview alone in its group, no empty groups, no splits with one child
    /// or nested along the same axis, fractions that fit. Also repairs a stored layout from an older version.
    public mutating func normalize() {
        var seen: Set<DockPanel> = []
        var node = Self.map(root) { g in
            var g = g
            g.panels = g.panels.filter { seen.insert($0).inserted }
            // the overview shares no tile; it is put back beside everything below
            if g.panels.count > 1, g.panels.contains(.overview) {
                g.panels.removeAll { $0 == .overview }
                seen.remove(.overview)
            }
            return g
        }
        let missing = DockPanel.session.filter { !seen.contains($0) }
        if !missing.isEmpty {
            // new panels join the terminal's group (or the first one with session views)
            let groups = Self.groups(node).filter { !$0.panels.isEmpty && !$0.panels.contains(.overview) }
            let home = (groups.first { $0.panels.contains(.main) } ?? groups.first)?.panels.first
            var added = false
            node = Self.map(node) { g in
                guard !added, let home, g.panels.contains(home) else { return g }
                added = true
                var g = g
                g.panels += missing
                return g
            }
            if !added { node = .split(Split(.horizontal, [node, .group(Group(missing))], fractions: [1 - Self.sessionShare, Self.sessionShare])) }
        }
        guard var tidy = Self.tidy(node) else { root = Self.standard.root; return }
        if !seen.contains(.overview) {
            tidy = Self.tidy(.split(Split(.horizontal, [.group(Group([.overview])), tidy],
                                          fractions: [1 - Self.sessionShare, Self.sessionShare]))) ?? tidy
        }
        // something stays open: the terminal's tile, or the first one
        let all = Self.groups(tidy)
        if all.allSatisfy(\.collapsed), let open = (all.first { $0.panels.contains(.main) } ?? all.first)?.panels.first {
            tidy = Self.map(tidy) { g in
                var g = g
                if g.panels.contains(open) { g.collapsed = false }
                return g
            }
        }
        root = tidy
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
            // room of a tile that is gone, waiting for the next one (if there was none before it)
            var freed = 0.0
            for (i, c) in s.children.enumerated() {
                var f = s.fractions.count == s.children.count && s.fractions[i] > 0 ? s.fractions[i] : even
                guard let t = tidy(c) else {
                    // its neighbour gets the room, not everyone a bit
                    if fractions.isEmpty { freed += f } else { fractions[fractions.count - 1] += f }
                    continue
                }
                f += freed
                freed = 0
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
