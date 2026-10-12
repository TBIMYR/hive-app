import Foundation
import Testing
@testable import HiveCore

private typealias L = DockLayout

private func group(_ p: DockPanel..., selected: DockPanel? = nil) -> L.Node { .group(L.Group(p, selected: selected)) }

@Test func dockStartsAsOneGroupWithTabs() {
    #expect(L.standard.root == group(.main, .handover, .project, .notes, selected: .main))
}

@Test func dockMovesAPanelBesideItsGroup() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    #expect(l.root == .split(L.Split(.horizontal, [group(.main, .handover, .project), group(.notes)], fractions: [0.5, 0.5])))

    // dropping it beside its own group works the same when dragged from the tabs
    var own = L.standard
    own.move(.notes, to: .notes, zone: .top)
    #expect(own.root == .split(L.Split(.vertical, [group(.notes), group(.main, .handover, .project)], fractions: [0.5, 0.5])))

    // a panel alone in its group stays where it is
    let before = l
    l.move(.notes, to: .notes, zone: .left)
    #expect(l == before)
}

@Test func dockStacksAndNestsTiles() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.project, to: .notes, zone: .bottom)
    #expect(l.root == .split(L.Split(.horizontal, [
        group(.main, .handover),
        .split(L.Split(.vertical, [group(.notes), group(.project)], fractions: [0.5, 0.5])),
    ], fractions: [0.5, 0.5])))

    // a third tile along the same axis joins the row and halves its neighbour
    l.move(.handover, to: .main, zone: .left)
    guard case .split(let s) = l.root else { Issue.record("no split"); return }
    #expect(s.children.count == 3)
    #expect(s.fractions == [0.25, 0.25, 0.5])
    #expect(s.children[0] == group(.handover) && s.children[1] == group(.main))
}

@Test func dockPutsAPanelBackIntoTabs() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.notes, to: .handover, zone: .center)
    // the split with one tile left dissolves
    #expect(l.root == group(.main, .handover, .project, .notes, selected: .notes))
    l.move(.main, to: .notes, zone: .center)
    #expect(l.group(of: .main)?.selected == .main)
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
    l.move(.notes, to: .main, zone: .right)
    l.resize(split: [], before: 0, after: 1, delta: 0.2)
    guard case .split(let s) = l.root else { Issue.record("no split"); return }
    #expect(abs(s.fractions[0] - 0.7) < 1e-9 && abs(s.fractions[1] - 0.3) < 1e-9)
    // not below the smallest share
    l.resize(split: [], before: 0, after: 1, delta: 0.9)
    guard case .split(let t) = l.root else { Issue.record("no split"); return }
    #expect(abs(t.fractions[1] - L.minFraction) < 1e-9)
    #expect(abs(t.fractions.reduce(0, +) - 1) < 1e-9)
}

@Test func dockShowsOnlyWhatTheSessionHas() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .right)
    l.move(.handover, to: .notes, zone: .bottom)
    l.select(.project)
    // no handover: its tile is gone, the column with the notes becomes a plain tile
    let v = l.visible([.main, .project, .notes])
    #expect(v == .split(axis: .horizontal, path: [], children: [
        .init(index: 0, share: 0.5, node: .group(panels: [.main, .project], selected: .project)),
        .init(index: 1, share: 0.5, node: .group(panels: [.notes], selected: .notes)),
    ]))
    // offline with a handover: no terminal; the selected tab falls back to the first one
    var o = L.standard
    #expect(o.visible([.handover, .project, .notes]) == .group(panels: [.handover, .project, .notes], selected: .handover))
    // a nested split keeps its path for resizing
    o.move(.notes, to: .main, zone: .right)
    o.move(.project, to: .notes, zone: .bottom)
    guard case .split(_, _, let c) = o.visible(Set(DockPanel.allCases)), case .split(let axis, let path, _) = c[1].node else {
        Issue.record("no nested split"); return
    }
    #expect(axis == .vertical && path == [1])
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
}

@Test func dockRepairsAStoredLayout() {
    var l = L.standard
    l.move(.notes, to: .main, zone: .bottom)
    #expect(L(json: l.json) == l)
    #expect(L(json: "") == L.standard)
    #expect(L(json: "{\"root\":1}") == L.standard)
    // a panel twice, one missing, an empty group, fractions that don't fit
    let broken = L(root: .split(L.Split(.horizontal, [group(.main, .notes), group(.notes), .group(L.Group([]))], fractions: [3])))
    #expect(broken.root == group(.main, .notes, .handover, .project, selected: .main))
    let uneven = L(root: .split(L.Split(.vertical, [group(.main, .handover, .project), group(.notes)], fractions: [3, 1])))
    guard case .split(let s) = uneven.root else { Issue.record("no split"); return }
    #expect(s.fractions == [0.75, 0.25])
}
