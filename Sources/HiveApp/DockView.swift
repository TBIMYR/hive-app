import AppKit
import SwiftUI
import HiveCore

/// How the session area is divided (see DockLayout), the same for every session and remembered under
/// `dockLayout`.
@MainActor
final class DockStore: ObservableObject {
    @Published private(set) var layout: DockLayout
    /// Panel of a collapsed tile that is shown on top of the rest for the moment
    @Published var peek: DockPanel?
    /// Own width (or height) of the layer per collapsed tile, keyed by the tile's first panel; without an
    /// entry the layer is a tenth smaller than the tile beneath it
    @Published private(set) var peekSizes: [String: Double]
    private static let key = "dockLayout"
    private static let peekKey = "dockPeekSizes"

    init() {
        layout = DockLayout(json: UserDefaults.standard.string(forKey: Self.key) ?? "")
        peekSizes = UserDefaults.standard.dictionary(forKey: Self.peekKey) as? [String: Double] ?? [:]
    }

    /// nil = back to the default size. `persist: false` while dragging.
    func setPeekSize(_ size: CGFloat?, for anchor: DockPanel, persist: Bool = true) {
        peekSizes[anchor.rawValue] = size.map(Double.init)
        if persist { savePeekSizes() }
    }

    func savePeekSizes() { UserDefaults.standard.set(peekSizes, forKey: Self.peekKey) }

    /// `persist: false` while dragging a divider; `save()` when the gesture ends.
    func change(persist: Bool = true, _ f: (inout DockLayout) -> Void) {
        var l = layout
        f(&l)
        guard l != layout else { return }
        layout = l
        if persist { save() }
    }

    func save() { UserDefaults.standard.set(layout.json, forKey: Self.key) }

    func reset() {
        change { $0 = .standard }
        peekSizes = [:]
        savePeekSizes()
    }
}

enum Dock {
    /// Coordinate space of the window's content; tab drags and group frames are measured in it
    static let space = "dock"
    /// Distance from the window's edge within which a drop goes across everything
    static let windowEdge: CGFloat = 28
    /// Height of a tile's top row: the tabs, in the terminal's tile also the session's name and status
    static let strip: CGFloat = 54
    /// Thickness of a collapsed tile's bar of icons
    static let bar: CGFloat = 44
}

/// A tab that is being dragged, with the pointer's place in the window's content
struct DockDrag: Equatable {
    let panel: DockPanel
    let title: String
    let symbol: String
    var location: CGPoint
}

/// Frames of the groups in the window's content, keyed by each group's first panel
struct DockFrames: PreferenceKey {
    static let defaultValue: [DockPanel: CGRect] = [:]
    static func reduce(value: inout [DockPanel: CGRect], nextValue: () -> [DockPanel: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Room a collapsed tile would take along its split if it were open, keyed by its first panel. The layer
/// that shows one of its panels for a moment is made as large.
struct DockOpenSizes: PreferenceKey {
    static let defaultValue: [DockPanel: CGFloat] = [:]
    static func reduce(value: inout [DockPanel: CGFloat], nextValue: () -> [DockPanel: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The tabs of one group in the look of RailSwitcher. A click brings a panel to the front; dragging a tab
/// onto a tile moves the panel there (onto the tabs, or beside the tile at its edges).
struct DockTabs: View {
    struct Item: Identifiable {
        let panel: DockPanel
        let title: String
        let symbol: String
        let help: String
        var id: DockPanel { panel }
    }

    let items: [Item]
    let selected: DockPanel
    /// false = icons only (a narrow tile)
    var titles = true
    @Binding var drag: DockDrag?
    let select: (DockPanel) -> Void
    let drop: (DockDrag) -> Void
    /// "Move right / below / back" from the right-click menu, for those who don't drag
    let move: (DockPanel, DockLayout.Zone?) -> Void
    @Namespace private var ns
    @State private var hover: DockPanel?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item.panel == selected
                HStack(spacing: 7) {
                    Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                    if titles { Text(item.title).font(.system(size: 13, weight: on ? .semibold : .medium)).fixedSize() }
                }
                .foregroundStyle(on ? Hive.bg : (hover == item.panel ? Hive.ink2 : Hive.muted))
                .padding(.horizontal, titles ? 14 : 11).frame(height: 36)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 9).fill(Hive.ink)
                            .matchedGeometryEffect(id: "on", in: ns)
                    }
                }
                .opacity(drag?.panel == item.panel ? 0.4 : 1)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { select(item.panel) } }
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(Dock.space))
                        .onChanged { v in
                            drag = DockDrag(panel: item.panel, title: item.title, symbol: item.symbol, location: v.location)
                        }
                        .onEnded { v in
                            drop(DockDrag(panel: item.panel, title: item.title, symbol: item.symbol, location: v.location))
                            drag = nil
                        }
                )
                .onHover { hover = $0 ? item.panel : (hover == item.panel ? nil : hover) }
                .help("\(item.help). Drag it onto the area to place it beside or below.")
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(.isButton)
                .contextMenu {
                    Button("Show \(item.title) on the Right") { move(item.panel, .right) }
                    Button("Show \(item.title) Below") { move(item.panel, .bottom) }
                    Divider()
                    Button("Reset Layout") { move(item.panel, nil) }
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Hive.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Hive.hair))
    }
}

/// Tiles side by side or stacked; dragging the gap between two shifts room between them. Collapsed tiles
/// have a fixed size, the others share the rest. Sizes are whole points, otherwise the terminal text gets blurry.
struct DockSplit: View {
    let axis: DockLayout.Axis
    let shares: [Double]
    /// size of the tiles that don't take part in the sharing (collapsed), nil for the others
    let fixed: [CGFloat?]
    /// first panel of each collapsed tile (nil for the others), to report its open size
    let anchors: [DockPanel?]
    /// the two tiles (indices) a dragged boundary shifts room between, and the change as a share of the split
    let onResize: (Int, Int, Double) -> Void
    let onEnd: () -> Void
    let content: (Int) -> AnyView
    @State private var last: CGFloat = 0
    /// Boundary under the pointer / being dragged
    @State private var hover: Int?
    @State private var dragging: Int?

    /// Share of the tiles that are sized by their share
    private var flexible: Double { zip(shares, fixed).reduce(0) { $0 + ($1.1 == nil ? $1.0 : 0) } }

    static func sizes(_ shares: [Double], fixed: [CGFloat?], total: CGFloat) -> [CGFloat] {
        let room = max(0, total - fixed.compactMap { $0 }.reduce(0, +))
        let sum = zip(shares, fixed).reduce(0) { $0 + ($1.1 == nil ? $1.0 : 0) }
        let lastFlexible = fixed.lastIndex { $0 == nil }
        var out: [CGFloat] = [], used: CGFloat = 0
        for (i, s) in shares.enumerated() {
            if let f = fixed[i] { out.append(f); continue }
            let w = i == lastFlexible ? room - used : (sum > 0 ? (room * s / sum).rounded() : 0)
            out.append(max(0, w))
            used += w
        }
        return out
    }

    /// Size the collapsed tile `i` would have if it shared the room like the open ones; nil for an open tile.
    static func openSize(_ i: Int, shares: [Double], fixed: [CGFloat?], total: CGFloat) -> CGFloat? {
        guard let own = fixed[i] else { return nil }
        let room = max(0, total - fixed.compactMap { $0 }.reduce(0, +) + own)
        let sum = zip(shares, fixed).reduce(shares[i]) { $0 + ($1.1 == nil ? $1.0 : 0) }
        return sum > 0 ? (room * shares[i] / sum).rounded() : nil
    }

    var body: some View {
        GeometryReader { geo in
            let horizontal = axis == .horizontal
            let n = shares.count
            let total = max(0, horizontal ? geo.size.width : geo.size.height)
            let sizes = Self.sizes(shares, fixed: fixed, total: total)
            let room = max(0, total - fixed.compactMap { $0 }.reduce(0, +))
            let stack = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            stack {
                ForEach(0..<n, id: \.self) { i in
                    content(i)
                        .frame(width: horizontal ? sizes[i] : nil, height: horizontal ? nil : sizes[i])
                        .clipped()
                        .preference(key: DockOpenSizes.self, value: Self.openSize(i, shares: shares, fixed: fixed, total: total)
                            .flatMap { size in anchors[i].map { [$0: size] } } ?? [:])
                    // a boundary moves the nearest tiles on both sides that can change their size
                    if i < n - 1, let a = (0...i).last(where: { fixed[$0] == nil }),
                       let b = ((i + 1)..<n).first(where: { fixed[$0] == nil }) {
                        divider(i, between: a, and: b, room: room)
                    }
                }
            }
        }
    }

    /// The boundary between two tiles takes no room itself; its handle spans the gap between them up to
    /// both edges. Hovering or dragging shows a blue bar in the gap, in the style of the drop target.
    private func divider(_ i: Int, between a: Int, and b: Int, room: CGFloat) -> some View {
        let horizontal = axis == .horizontal
        let thickness = Hive.margin + 4
        let on = hover == i || dragging == i
        return Color.clear
            .frame(width: horizontal ? 0 : nil, height: horizontal ? nil : 0)
            .overlay {
                Color.clear
                    .frame(width: horizontal ? thickness : nil, height: horizontal ? nil : thickness)
                    .overlay {
                        if on {
                            RoundedRectangle(cornerRadius: 5).fill(Hive.shell.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Hive.shell.opacity(0.7), lineWidth: 1.5))
                                .frame(width: horizontal ? 10 : nil, height: horizontal ? nil : 10)
                                .padding(horizontal ? .vertical : .horizontal, Hive.margin)
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            hover = i
                            (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            if hover == i { hover = nil }
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                dragging = i
                                let t = horizontal ? v.translation.width : v.translation.height
                                if room > 0 { onResize(a, b, Double((t - last) / room) * flexible) }
                                last = t
                            }
                            .onEnded { _ in
                                dragging = nil
                                last = 0
                                onEnd()
                            }
                    )
            }
            // above the tiles, so the handle catches the pointer in the gap between them
            .zIndex(1)
    }
}

/// While a tab is dragged: the place it would land in, and a small label at the pointer.
struct DockDropOverlay: View {
    let drag: DockDrag
    /// nil = nothing happens here
    let target: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let r = target {
                RoundedRectangle(cornerRadius: 10).fill(Hive.shell.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Hive.shell.opacity(0.7), lineWidth: 1.5))
                    .frame(width: max(0, r.width - 8), height: max(0, r.height - 8))
                    .offset(x: r.minX + 4, y: r.minY + 4)
            }
            HStack(spacing: 7) {
                Image(systemName: drag.symbol).font(.system(size: 12, weight: .semibold))
                Text(drag.title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Hive.bg)
            .padding(.horizontal, 14).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(Hive.ink))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .fixedSize()
            .position(x: drag.location.x, y: drag.location.y + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
