import Foundation
import Testing
@testable import HiveCore

private typealias L = DockLayout

private func group(_ p: DockPanel..., selected: DockPanel? = nil) -> L.Node { .group(L.Group(p, selected: selected)) }
private func row(_ c: L.Node..., f: [Double]) -> L.Node { .split(L.Split(.horizontal, c, fractions: f)) }
private func column(_ c: L.Node..., f: [Double]) -> L.Node { .split(L.Split(.vertical, c, fractions: f)) }

private func close(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

/// Same tree, fractions compared with a tolerance
private func same(_ a: L.Node, _ b: L.Node) -> Bool {
    switch (a, b) {
    case (.group(let x), .group(let y)): return x == y
    case (.split(let x), .split(let y)):
        return x.axis == y.axis && close(x.fractions, y.fractions) && x.children.count == y.children.count
            && zip(x.children, y.children).allSatisfy(same)
    default: return false
    }
}

private func same(_ a: L.Visible?, _ b: L.Visible?) -> Bool {
    switch (a, b) {
    case (.group, .group), (nil, nil): return a == b
    case (.split(let ax, let ap, let ac), .split(let bx, let bp, let bc)):
        return ax == bx && ap == bp && ac.count == bc.count
            && zip(ac, bc).allSatisfy { $0.index == $1.index && abs($0.share - $1.share) < 1e-9 && same($0.node, $1.node) }
    default: return false
    }
}

private func fractions(_ l: L) -> [Double] {
    if case .split(let s) = l.root { return s.fractions }
    return []
}

private let all = Set(DockPanel.allCases)

@Test func dockStartsWithTheOverviewBesideOneGroupOfTabs() {
    #expect(same(L.standard.root, row(group(.overview), group(.main, .handover, .project, .notes, selected: .main), f: [0.66, 0.34])))
}

@Test func dockMovesAPanelBesideItsGroup() {
    var l = L.standard
    // the row is divided by what each tile wants: overview and terminal more than the notes
    l.move(.notes, to: .main, zone: .right)
    #expect(same(l.root, row(group(.overview), group(.main, .handover, .project), group(.notes), f: [0.375, 0.375, 0.25])))

    // dropping it beside its own group works the same when dragged from the tabs
    var own = L.standard
    own.move(.notes, to: .notes, zone: .top)
    #expect(same(own.root, row(group(.overview), column(group(.notes), group(.main, .handover, .project), f: [0.4, 0.6]), f: [0.66, 0.34])))

    // a panel alone in its group stays where it is
    let before = l
    l.move(.notes, to: .notes, zone: .left)
    #expect(l == before)
}

@Test func dockStacksAndNestsTiles() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.project, to: .notes, zone: .bottom)
    #expect(same(l.root, row(group(.overview), group(.main, .handover),
                          column(group(.notes), group(.project), f: [0.5, 0.5]), f: [0.375, 0.375, 0.25])))
}

@Test func dockPutsAPanelBackIntoTabs() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.notes, to: .handover, zone: .center)
    // the tile that is left gets the room back
    #expect(same(l.root, row(group(.overview), group(.main, .handover, .project, .notes, selected: .notes), f: [0.375, 0.625])))
    l.move(.main, to: .notes, zone: .center)
    #expect(l.group(of: .main)?.selected == .main)
}

@Test func dockKeepsTheOverviewInATileOfItsOwn() {
    var l = L.standard
    let before = l
    // no tab on the overview, and the overview is no tab
    l.move(.notes, to: .overview, zone: .center)
    l.move(.overview, to: .main, zone: .center)
    #expect(l == before)
    // but it moves like any tile
    l.move(.overview, to: .main, zone: .right)
    #expect(same(l.root, row(group(.main, .handover, .project, .notes), group(.overview), f: [0.5, 0.5])))
    l.move(.notes, to: .overview, zone: .bottom)
    #expect(l.group(of: .overview)?.panels == [.overview])
    #expect(l.group(of: .notes)?.panels == [.notes])
}

@Test func dockMovesAPanelToAnEdgeOfTheWindow() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    // the overview as a strip across the top of everything; its neighbour takes the room it leaves
    l.move(.overview, toEdge: .top)
    #expect(same(l.root, column(group(.overview), row(group(.main, .handover, .project), group(.notes), f: [0.75, 0.25]), f: [0.3, 0.7])))
    // along the same axis it joins the column, which is divided anew
    l.move(.notes, toEdge: .bottom)
    guard case .split(let s) = l.root else { Issue.record("no split"); return }
    #expect(s.axis == .vertical && s.children.count == 3)
    #expect(close(s.fractions, [0.375, 0.375, 0.25]))
    #expect(s.children[2] == group(.notes))
    let before = l
    l.move(.notes, toEdge: .center)
    #expect(l == before)
}

@Test func dockSelectsWithinTheGroup() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.select(.project)
    #expect(l.group(of: .main)?.selected == .project)
    #expect(l.group(of: .notes)?.selected == .notes)
    // moving the selected panel away selects the first one left
    l.move(.project, to: .notes, zone: .center)
    #expect(l.group(of: .main)?.selected == .main)
}

@Test func dockResizesBetweenTwoTiles() {
    var l = L.standard
    l.resize(split: [], before: 0, after: 1, delta: -0.2)
    #expect(close(fractions(l), [0.46, 0.54]))
    // not below the smallest share
    l.resize(split: [], before: 0, after: 1, delta: 0.9)
    #expect(close(fractions(l), [1 - L.minFraction, L.minFraction]))
    // a nested split by its path
    l.move(.notes, to: .main, zone: .bottom)
    l.resize(split: [1], before: 0, after: 1, delta: 0.1)
    guard case .split(let s) = l.root, case .split(let inner) = s.children[1] else { Issue.record("no nested split"); return }
    #expect(close(inner.fractions, [0.7, 0.3]))
}

@Test func dockShowsOnlyWhatTheSessionHas() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.handover, to: .notes, zone: .bottom)
    l.select(.project)
    // no handover: its tile is gone, the column with the notes becomes a plain tile
    let v = l.visible(all.subtracting([.handover]))
    #expect(same(v, .split(axis: .horizontal, path: [], children: [
        .init(index: 0, share: 0.375, node: .group(panels: [.overview], selected: .overview, collapsed: false)),
        .init(index: 1, share: 0.375, node: .group(panels: [.main, .project], selected: .project, collapsed: false)),
        .init(index: 2, share: 0.25, node: .group(panels: [.notes], selected: .notes, collapsed: false)),
    ])))
    // offline with a handover: no terminal; the selected tab falls back to the first one
    guard case .split(_, _, let c) = L.standard.visible(all.subtracting([.main])) else { Issue.record("no split"); return }
    #expect(c[1].node == .group(panels: [.handover, .project, .notes], selected: .handover, collapsed: false))
    // a nested split keeps its path for resizing
    guard case .split(_, _, let d) = l.visible(all), case .split(let axis, let path, _) = d[2].node else {
        Issue.record("no nested split"); return
    }
    #expect(axis == .vertical && path == [2])
    // only the overview: it fills the window
    #expect(L.standard.visible([.overview]) == .group(panels: [.overview], selected: .overview, collapsed: false))
    #expect(L.standard.visible([]) == nil)
}

@Test func dockFindsTheDropZone() {
    let r = CGRect(x: 100, y: 50, width: 400, height: 300)
    #expect(L.zone(at: CGPoint(x: 300, y: 200), in: r) == .center)
    #expect(L.zone(at: CGPoint(x: 120, y: 200), in: r) == .left)
    #expect(L.zone(at: CGPoint(x: 480, y: 200), in: r) == .right)
    #expect(L.zone(at: CGPoint(x: 300, y: 60), in: r) == .top)
    #expect(L.zone(at: CGPoint(x: 300, y: 340), in: r) == .bottom)
    // in a corner the nearer edge wins
    #expect(L.zone(at: CGPoint(x: 110, y: 90), in: r) == .left)
    // without a middle (the overview) it is always the nearest edge
    #expect(L.zone(at: CGPoint(x: 310, y: 200), in: r, center: false) == .right)
    #expect(L.zone(at: CGPoint(x: 250, y: 190), in: r, center: false) == .left)

    #expect(L.windowEdge(at: CGPoint(x: 110, y: 200), in: r, margin: 24) == .left)
    #expect(L.windowEdge(at: CGPoint(x: 300, y: 340), in: r, margin: 24) == .bottom)
    #expect(L.windowEdge(at: CGPoint(x: 300, y: 200), in: r, margin: 24) == nil)
    #expect(L.windowEdge(at: CGPoint(x: 90, y: 200), in: r, margin: 24) == nil)
}

@Test func dockRepairsAStoredLayout() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .bottom)
    #expect(L(json: l.json) == l)
    #expect(L(json: "") == L.standard)
    #expect(L(json: "{\"root\":1}") == L.standard)
    // a panel twice, some missing, an empty group, fractions that don't fit
    let broken = L(root: row(group(.overview), group(.main, .notes), group(.notes), .group(L.Group([])), f: [3]))
    #expect(same(broken.root, row(group(.overview), group(.main, .notes, .handover, .project, selected: .main), f: [0.25, 0.75])))
    let uneven = L(root: column(group(.overview), group(.main, .handover, .project, .notes), f: [3, 1]))
    #expect(close(fractions(uneven), [0.75, 0.25]))
    // from before the overview was part of it: it goes back to the left
    let old = L(root: column(group(.main, .handover, .project), group(.notes), f: [0.5, 0.5]))
    #expect(same(old.root, row(group(.overview), column(group(.main, .handover, .project), group(.notes), f: [0.5, 0.5]), f: [0.66, 0.34])))
    // the overview pushed into tabs comes out again
    let tabbed = L(root: group(.overview, .main, .handover, .project, .notes))
    #expect(same(tabbed.root, row(group(.overview), group(.main, .handover, .project, .notes), f: [0.66, 0.34])))
    #expect(same(L(root: group(.overview)).root, L.standard.root))
}

@Test func dockCollapsesTilesButKeepsOneOpen() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.setCollapsed(true, groupOf: .notes)
    #expect(l.group(of: .notes)?.collapsed == true)
    guard case .split(_, _, let c) = l.visible(all) else { Issue.record("no split"); return }
    #expect(c[2].node == .group(panels: [.notes], selected: .notes, collapsed: true))
    // it survives storing; a layout stored without the flag reads as open
    #expect(L(json: l.json) == l)
    #expect(L(json: l.json.replacingOccurrences(of: "\"collapsed\":true", with: "\"x\":1")).group(of: .notes)?.collapsed == false)

    l.setCollapsed(true, groupOf: .overview)
    #expect(l.canCollapse(groupOf: .main) == false)
    // the last open tile stays open
    l.setCollapsed(true, groupOf: .main)
    #expect(l.group(of: .main)?.collapsed == false)
    l.setCollapsed(false, groupOf: .notes)
    #expect(l.group(of: .notes)?.collapsed == false)

    // a stored layout with everything collapsed opens the terminal's tile
    let shut = L(root: row(.group(L.Group([.overview], collapsed: true)),
                           .group(L.Group([.main, .handover, .project, .notes], collapsed: true)), f: [0.5, 0.5]))
    #expect(shut.group(of: .main)?.collapsed == false && shut.group(of: .overview)?.collapsed == true)
    // a panel that is dropped beside a collapsed tile opens in a tile of its own
    l.setCollapsed(true, groupOf: .notes)
    l.move(.project, to: .notes, zone: .bottom)
    #expect(l.group(of: .project)?.collapsed == false && l.group(of: .notes)?.collapsed == true)
}
