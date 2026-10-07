import SwiftUI
import HiveCore

/// "List" view: one row per session without sections, favorites first, offline collapsed at the end.
/// Workers are indented under their PM (SessionTree); favorites, active, and offline are each grouped separately.
/// Each group (a PM with its workers, or a single session) sits on one white card surface; rows inside are
/// separated by hairlines. ScrollView + LazyVStack instead of List, so surfaces, rings, and context menu stay
/// like in the cards.
struct SessionListView: View {
    @EnvironmentObject private var store: StateStore
    /// Favorites, already sorted (SessionOrder), including offline
    let favorites: [OverviewItem]
    /// Remaining sessions, already sorted (SessionOrder), without favorites
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        let top = Self.groups(SessionTree.grouped(favorites, session: \.session))
            + Self.groups(SessionTree.grouped(items.filter { $0.status.rank < 3 }, session: \.session))
        let offline = Self.groups(SessionTree.grouped(items.filter { $0.status.rank == 3 }, session: \.session))
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(top) { group($0) }
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.reduce(0) { $0 + $1.rows.count }, color: Hive.off,
                              expanded: $showOffline)
                    .padding(.top, 16).padding(.bottom, 2)
                if showOffline { ForEach(offline) { group($0) } }
            }
        }
    }

    /// A PM with its workers, or a single session
    struct Group: Identifiable {
        let rows: [SessionTree.Row<OverviewItem>]
        var id: String { rows[0].item.id }
    }

    /// Splits the tree rows into groups: each top-level row starts a new one.
    static func groups(_ rows: [SessionTree.Row<OverviewItem>]) -> [Group] {
        var out: [[SessionTree.Row<OverviewItem>]] = []
        for r in rows {
            if r.depth == 0 || out.isEmpty { out.append([r]) } else { out[out.count - 1].append(r) }
        }
        return out.map(Group.init)
    }

    static let radius: CGFloat = 14

    private func group(_ g: Group) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(g.rows.enumerated()), id: \.element.item.id) { i, r in
                row(r, index: i, last: i == g.rows.count - 1)
            }
        }
        // one surface per group, so the tree line never crosses a differently colored background;
        // a waiting row lets the whole group glow faintly red
        .background {
            CardSurface(shape: RoundedRectangle(cornerRadius: Self.radius),
                        glow: g.rows.contains { $0.item.status.rank == 0 })
        }
    }

    private func row(_ r: SessionTree.Row<OverviewItem>, index: Int, last: Bool) -> some View {
        let it = r.item
        let indent: CGFloat = r.depth > 0 ? Self.indent : 0
        return SessionRow(item: it, isSelected: it.name == store.selected, first: index == 0, last: last,
                          nameWidth: SessionRow.nameWidth - indent, indent: indent) { store.toggleFavorite(it.name) }
            .onTapGesture { store.selected = it.name }
            .sessionMenu(store, it.session)
            .navFrame(it.name)
            .overlay(alignment: .leading) {
                if r.depth > 0 {
                    // the worker right below the PM extends the line up to the PM's dot
                    TreeLine(isFirst: index == 1, isLast: r.isLastInGroup)
                        .stroke(Hive.hair, lineWidth: 1).frame(width: indent)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Indentation of workers under their PM
    static let indent: CGFloat = 28
}

/// Vertical line under the PM's status dot that connects its workers: the first worker extends it up to just
/// below the PM's dot, the last one ends it at its own middle. Rows have the same height and no spacing, so half
/// a row reaches the PM's dot.
private struct TreeLine: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        // same x as the status dot: row padding 14 + half of the 14 pt dot column
        let x = rect.minX + 21, dotGap: CGFloat = 9
        let top = isFirst ? rect.minY - rect.height / 2 + dotGap : rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x, y: top))
        p.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        return p
    }
}

/// One row on its group's surface. Rows below the first get a hairline on top that starts at the name column,
/// so it never touches the tree line. Waiting: red 1.5 pt ring, selected: dark 3 pt ring; the ring follows the
/// group's rounded corners where the row meets them.
struct SessionRow: View {
    let item: OverviewItem
    let isSelected: Bool
    /// first / last row of its group (rounded ring corners, hairline)
    var first = true
    var last = true
    /// Width of the name column; indented rows get it narrower by the indentation amount, so the remaining
    /// columns stay aligned
    var nameWidth: CGFloat = SessionRow.nameWidth
    /// Indentation of the content (workers); the row still spans the full width
    var indent: CGFloat = 0
    let toggleFavorite: () -> Void

    static let nameWidth: CGFloat = 140
    /// x of the name column (padding + dot column + spacing), where the hairline starts
    private static let textStart: CGFloat = 14 + 14 + 14

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        // working/waiting: the "Now" box briefly, instead of the task
        let now = item.now?.text
        let r = SessionListView.radius
        let shape = UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                           bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0)
        HStack(spacing: 14) {
            Circle().fill(st.color).frame(width: 9, height: 9).frame(width: 14)
            Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Hive.ink)
                .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 6) {
                // status as colored text like on the cards; the leading dot is the row's status dot
                if st.cls == "off" {
                    WakeUpButton(session: item.session)
                } else {
                    CardStatus(status: st, text: loud && now == nil ? [st.label, st.why].compactMap { $0 }.joined(separator: " · ") : nil,
                               size: 12.5, dot: false)
                }
                RemoteControlBadge(on: item.session.remoteControl)
                BackgroundBadge(count: item.session.backgroundTasks)
            }
            .frame(width: 210, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(item.color).frame(width: 6, height: 6)
                // the detail follows the task in gray, as far as the row has room
                let detail = now == nil && task != nil ? item.session.task?.detail : nil
                Text(now ?? task ?? "No task line").foregroundStyle(now == nil && task == nil ? Hive.muted : Hive.ink2)
                    + Text(detail.map { "  \($0)" } ?? "").foregroundStyle(Hive.muted)
            }
            .help(item.project)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.since).font(.system(size: 12)).foregroundStyle(Hive.muted).monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            StarButton(isOn: item.isFavorite, toggle: toggleFavorite)
                .padding(.leading, -4)
        }
        .font(.system(size: 13.5))
        .lineLimit(1).truncationMode(.tail)
        .padding(.leading, indent)
        .padding(.horizontal, 14).padding(.vertical, 15)
        .opacity(st.rank == 3 ? 0.55 : 1)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(Hive.hair).frame(height: 1).padding(.leading, Self.textStart + indent)
            }
        }
        .overlay { CardRing(shape: shape, status: st, isSelected: isSelected, working: false) }
        .contentShape(Rectangle())
    }
}
