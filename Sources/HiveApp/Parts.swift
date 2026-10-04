import SwiftUI
import HiveCore

// MARK: Building blocks

struct Token: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.hiveMono(10.5, .bold))
            .foregroundStyle(.white)
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
            Circle().fill(loud ? Color.white : status.color).frame(width: 7, height: 7)
            Text(status.label).lineLimit(1).truncationMode(.tail)
            if !since.isEmpty { Text(since).foregroundStyle(loud ? Color.white.opacity(0.8) : Hive.muted).fixedSize() }
        }
        .font(.system(size: 12, weight: loud ? .semibold : .medium))
        .foregroundStyle(loud ? Color.white : Hive.ink2)
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
            Text(since.isEmpty ? label : "\(label) · \(since)")
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

/// Pill for running background agents/shell commands: green capsule, slowly turning arrows and the count.
/// Nothing when count is 0. Respects "Reduce motion".
struct BackgroundBadge: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        if count > 0 {
            let help = count == 1 ? "1 background task running" : "\(count) background tasks running"
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(turning ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 2).repeatForever(autoreverses: false), value: turning)
                Text("\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Hive.busy))
            .fixedSize()
            .onAppear { turning = true }
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
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
                .foregroundStyle(isOn ? Hive.ink : Hive.muted)
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

    /// Short line for Tiles and List: while working the work step, while waiting "Allow …?" or the question, otherwise nil
    /// (then the task).
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
