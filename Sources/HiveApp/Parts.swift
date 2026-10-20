import SwiftUI
import HiveCore

// MARK: Building blocks

struct Token: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.hiveMono(10.5, .bold))
            .foregroundStyle(Hive.onColor)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}

/// Status as dot + text; only "needs you" becomes a filled pill.
struct StatusLabel: View {
    let status: Status
    var since: String = ""

    var body: some View {
        let loud = status.rank == 0
        HStack(spacing: 5) {
            Circle().fill(loud ? Hive.onColor : status.color).frame(width: 7, height: 7)
            Text(status.label).lineLimit(1).truncationMode(.tail)
            if !since.isEmpty { Text(since).foregroundStyle(loud ? Hive.onColor.opacity(0.8) : Hive.muted).fixedSize() }
        }
        .font(.system(size: 12, weight: loud ? .semibold : .medium))
        .foregroundStyle(loud ? Hive.onColor : Hive.ink2)
        .padding(.horizontal, loud ? 9 : 0).padding(.vertical, loud ? 3 : 0)
        .background(loud ? status.color : Color.clear)
        .clipShape(Capsule())
    }
}

/// Card status without a pill: dot and text, "waiting for you · 4 min". Semibold in the status color while
/// waiting or working, muted otherwise. `text` replaces the label (List: "waiting for you · reason").
struct CardStatus: View {
    let status: Status
    var since: String = ""
    var text: String? = nil
    var size: CGFloat = 12
    /// false: text only (List, where the row's leading dot already shows the status)
    var dot = true

    var body: some View {
        let loud = status.rank <= 1
        let label = text ?? status.label
        HStack(spacing: 6) {
            if dot { Circle().fill(status.color).frame(width: 8, height: 8) }
            Text(since.isEmpty ? label : label.isEmpty ? since : "\(label) · \(since)")
                .lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: size, weight: loud ? .semibold : .medium))
        .foregroundStyle(loud ? status.color : Hive.muted)
    }
}

// MARK: Card look (Cards, Tiles, List)

/// The calm card surface: white, borderless, soft two-layer shadow; on dark, where shadows vanish, a hairline
/// instead. `glow`: waiting for you – a faint red glow replaces the gray shadow.
struct CardSurface<S: InsettableShape>: View {
    let shape: S
    var glow = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        shape.fill(Hive.card)
            .shadow(color: dark ? .clear : .black.opacity(glow ? 0.03 : 0.05), radius: 1, y: 1)
            .shadow(color: glow ? Hive.need.opacity(dark ? 0.25 : 0.14) : (dark ? .clear : .black.opacity(0.04)),
                    radius: 9, y: 6)
            .overlay { if dark && !glow { shape.strokeBorder(Hive.hair, lineWidth: 1) } }
    }
}

/// Ring on top of a card: selected = dark 3 pt, waiting for you = red 1.5 pt, working = a quiet green 1 pt
/// (static, no pulsing; `working: false` leaves it out).
struct CardRing<S: InsettableShape>: View {
    let shape: S
    let status: Status
    let isSelected: Bool
    var working = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if isSelected {
                shape.strokeBorder(Hive.ink, lineWidth: 3)
            } else if status.rank == 0 {
                shape.strokeBorder(Hive.need, lineWidth: 1.5)
            } else if status.rank == 1 && working {
                shape.strokeBorder(Hive.busy.opacity(scheme == .dark ? 0.45 : 0.35), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Card surface plus status ring, shared by the cards and the tiles.
struct CardBackground: ViewModifier {
    let status: Status
    let isSelected: Bool
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background { CardSurface(shape: shape, glow: status.rank == 0) }
            .overlay { CardRing(shape: shape, status: status, isSelected: isSelected) }
    }
}

extension View {
    func cardBackground(status: Status, isSelected: Bool, radius: CGFloat = 16) -> some View {
        modifier(CardBackground(status: status, isSelected: isSelected, radius: radius))
    }
}

// MARK: Equal heights in a grid

/// Natural height of the tallest view in a grid that uses `matchTallest`.
struct TallestKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Reports its natural height (measured before growing, so it can shrink again) and grows to `height`,
    /// the tallest of its grid, with the content on top. The grid reads it with `onPreferenceChange(TallestKey.self)`.
    func matchTallest(_ height: CGFloat) -> some View {
        background { GeometryReader { g in Color.clear.preference(key: TallestKey.self, value: g.size.height) } }
            .frame(minHeight: height, alignment: .topLeading)
    }
}

// MARK: ⌥ + arrow keys

/// Frames of the drawn sessions (by name) in the overview's scroll content, for SessionNav.
struct NavFrameKey: PreferenceKey {
    static let space = "overview"
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

extension View {
    /// Reports where this session is drawn, so ⌥ + arrow keys can find its neighbors.
    func navFrame(_ name: String) -> some View {
        background {
            GeometryReader { g in
                Color.clear.preference(key: NavFrameKey.self, value: [name: g.frame(in: .named(NavFrameKey.space))])
            }
        }
    }
}

/// CPU load of a session's processes (tests, builds, servers) as a share of the whole Mac: "29 %" = four of
/// fourteen cores busy. Nothing while the load is small; orange once it takes a quarter of the Mac.
struct LoadBadge: View {
    let session: Session
    @EnvironmentObject private var store: StateStore

    var body: some View {
        if let cpu = store.load[session.id], let share = ProcessLoad.share(cpu, cores: StateStore.cores) {
            let warn = share >= ProcessLoad.warnFrom
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 10.5, weight: .semibold))
                Text("\(share) %").font(.system(size: 12, weight: warn ? .semibold : .regular)).monospacedDigit()
            }
            .foregroundStyle(warn ? Hive.block : Hive.muted)
            .fixedSize()
            .help("This session's processes use \(share) % of the Mac (\(ProcessLoad.coresText(cpu)) of \(StateStore.cores) cores)")
        }
    }
}

/// Pill for running background agents/shell commands: green capsule, slowly turning arrows and the count.
/// Nothing when count is 0. Respects "Reduce motion".
struct BackgroundBadge: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > 0 {
            let help = count == 1 ? "1 background task running" : "\(count) background tasks running"
            HStack(spacing: 4) {
                TurningArrows(color: NSColor(Hive.onColor), turning: !reduceMotion)
                Text("\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Hive.onColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Hive.busy))
            .fixedSize()
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
        }
    }
}

/// The badge's arrows, turned by Core Animation on a layer of their own: the render server turns them and the app
/// does nothing per frame. SwiftUI redraws the whole window on every frame for a TimelineView or a repeating
/// symbol effect (measured with the symbol effect: about 16 % CPU against under 2 % without it), and a repeating
/// SwiftUI animation drifts with layout moves.
private struct TurningArrows: NSViewRepresentable {
    let color: NSColor
    let turning: Bool

    final class View: NSView {
        private let arrows = CALayer()
        private var color: NSColor?
        private var image: NSImage?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arrows.contentsGravity = .resizeAspect
            layer?.addSublayer(arrows)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var intrinsicContentSize: NSSize { image?.size ?? NSSize(width: 13, height: 12) }

        func set(color: NSColor, turning: Bool) {
            if color != self.color {
                self.color = color
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
                image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                arrows.contents = image
                invalidateIntrinsicContentSize()
            }
            if turning, arrows.animation(forKey: "turn") == nil {
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0
                turn.toValue = -2 * Double.pi   // clockwise
                turn.duration = 2
                turn.repeatCount = .infinity
                // keeps turning when the window is hidden and shown again
                turn.isRemovedOnCompletion = false
                arrows.add(turn, forKey: "turn")
            } else if !turning {
                arrows.removeAnimation(forKey: "turn")
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // turns around its center: anchor in the middle, position at the middle of the view
            arrows.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            arrows.bounds = bounds
            arrows.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            arrows.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    func makeNSView(context: Context) -> View {
        let v = View(frame: .zero)
        v.set(color: color, turning: turning)
        return v
    }

    func updateNSView(_ v: View, context: Context) { v.set(color: color, turning: turning) }
}

/// Phone icon while Remote Control is connected (the session can be continued on claude.ai or the phone).
struct RemoteControlBadge: View {
    let on: Bool

    var body: some View {
        if on {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Hive.shell)
                .help("Remote Control is on")
                .accessibilityLabel("Remote Control is on")
        }
    }
}

/// Star for favorites: filled in Hive.ink while a favorite, otherwise a gray outline. Always visible so nothing jumps around.
/// As a button it intercepts the click; the session selection (onTapGesture below it) stays untouched.
struct StarButton: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Hive.ink)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove from favorites" : "Favorite")
        .accessibilityLabel(isOn ? "Remove from favorites" : "Favorite")
    }
}

/// A session with everything the views show; the frame (OverviewView) computes this once per pass.
struct OverviewItem: Identifiable {
    let session: Session
    let status: Status
    /// Project name (labels[groupKey] ?? groupKey)
    let project: String
    let color: Color
    let inTmux: Bool
    /// "<1 min", "12 min" since the last status change, only for live sessions
    let since: String
    /// Favorite (star filled, listed first)
    let isFavorite: Bool

    var id: String { session.id }
    var name: String { session.name }

    /// Short line for Tiles and List: while working the work step, while waiting "Allow …?" or the question, otherwise nil.
    /// The List shows it after the task, Tiles only when there is no task.
    var now: NowLine? { status.rank <= 1 ? NowLine(session, rank: status.rank) : nil }
}

/// Section header: dot, title, count, line. Collapsible with `expanded` (Offline).
struct SectionHeader: View {
    let title: String
    let count: Int
    let color: Color
    var expanded: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
            Text("\(count)").font(.system(size: 13)).foregroundStyle(Hive.muted).monospacedDigit()
            if let expanded {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Hive.muted)
            }
            Rectangle().fill(Hive.hair).frame(height: 1).padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}

/// hive's mark: a honeycomb cell (pointed side up), like the app icon. Rounded corners come from
/// drawing an extra line with a rounded join.
struct HiveMark: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / sqrt(3), rect.height / 2)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<6 {
            let a = CGFloat.pi / 3 * CGFloat(i) - .pi / 2
            let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}

/// Row that wraps to the next line when space runs short (reply buttons).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(size.width, width)
            if !row.items.isEmpty && row.width + spacing + w > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + w
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// Empty state of a tile in Hive's calm style, centered in the room it gets: icon on a soft disc, a short
/// title, one or two gray lines and optionally a button.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var action: (title: String, enabled: Bool, run: () -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(Hive.ink2)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Hive.soft))
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Hive.ink)
                .padding(.top, 16)
            Text(text).font(.system(size: 13)).foregroundStyle(Hive.muted)
                .multilineTextAlignment(.center).lineSpacing(3)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let action {
                Button(action: action.run) {
                    Text(action.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.bg)
                        .padding(.horizontal, 18).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Hive.ink))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!action.enabled).opacity(action.enabled ? 1 : 0.4)
                .padding(.top, 18)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Display options

/// Settings → Display: which details the overview and the terminal header show. All on by default; the
/// task (title) and the status dot always stay.
struct Show: DynamicProperty {
    @AppStorage("show.status") var status = true
    @AppStorage("show.since") var since = true
    @AppStorage("show.detail") var detail = true
    @AppStorage("show.now") var now = true
    @AppStorage("show.context") var context = true
    @AppStorage("show.load") var load = true
    @AppStorage("show.badges") var badges = true
    @AppStorage("show.project") var project = true
    @AppStorage("show.place") var place = true
    @AppStorage("show.model") var model = true
}
