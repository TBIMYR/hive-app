import AppKit
import SwiftUI
import HiveCore

/// How the session area is divided (see DockLayout), the same for every session and remembered under
/// `dockLayout`.
@MainActor
final class DockStore: ObservableObject {
    @Published private(set) var layout: DockLayout
    private static let key = "dockLayout"

    init() {
        layout = DockLayout(json: UserDefaults.standard.string(forKey: Self.key) ?? "")
    }

    /// `persist: false` while dragging a divider; `save()` when the gesture ends.
    func change(persist: Bool = true, _ f: (inout DockLayout) -> Void) {
        var l = layout
        f(&l)
        guard l != layout else { return }
        layout = l
        if persist { save() }
    }

    func save() { UserDefaults.standard.set(layout.json, forKey: Self.key) }

    func reset() { change { $0 = .standard } }
}

enum Dock {
    /// Coordinate space of the window's content; tab drags and group frames are measured in it
    static let space = "dock"
    /// Distance from the window's edge within which a drop goes across everything
    static let windowEdge: CGFloat = 28
    /// Height of a tile's top row: the tabs, in the terminal's tile also the session's name and status
    static let strip: CGFloat = 54
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
                .padding(.horizontal, titles ? 14 : 11).frame(height: 30)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 8).fill(Hive.ink)
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
        .background(RoundedRectangle(cornerRadius: 11).fill(Hive.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Hive.hair))
    }
}

/// Tiles side by side or stacked; dragging the gap between two shifts room between them. Sizes are whole
/// points, otherwise the terminal text gets blurry.
struct DockSplit: View {
    let axis: DockLayout.Axis
    let shares: [Double]
    /// boundary index (between tile i and i+1) and the change as a share of the split
    let onResize: (Int, Double) -> Void
    let onEnd: () -> Void
    let content: (Int) -> AnyView
    @State private var last: CGFloat = 0

    static func sizes(_ shares: [Double], total: CGFloat) -> [CGFloat] {
        let sum = shares.reduce(0, +)
        guard sum > 0, total > 0 else { return shares.map { _ in 0 } }
        var out: [CGFloat] = [], used: CGFloat = 0
        for (i, s) in shares.enumerated() {
            let w = i == shares.count - 1 ? total - used : (total * s / sum).rounded()
            out.append(max(0, w))
            used += w
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let horizontal = axis == .horizontal
            let n = shares.count
            let room = max(0, horizontal ? geo.size.width : geo.size.height)
            let sizes = Self.sizes(shares, total: room)
            let stack = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            stack {
                ForEach(0..<n, id: \.self) { i in
                    content(i)
                        .frame(width: horizontal ? sizes[i] : nil, height: horizontal ? nil : sizes[i])
                        .clipped()
                    if i < n - 1 { divider(i, room: room) }
                }
            }
        }
    }

    private func divider(_ i: Int, room: CGFloat) -> some View {
        let horizontal = axis == .horizontal
        return Color.clear
            .frame(width: horizontal ? 0 : nil, height: horizontal ? nil : 0)
            .overlay {
                Color.clear
                    .frame(width: horizontal ? 9 : nil, height: horizontal ? nil : 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                let t = horizontal ? v.translation.width : v.translation.height
                                if room > 0 { onResize(i, Double((t - last) / room) * shares.reduce(0, +)) }
                                last = t
                            }
                            .onEnded { _ in
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
            .padding(.horizontal, 14).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Hive.ink))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .fixedSize()
            .position(x: drag.location.x, y: drag.location.y + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
