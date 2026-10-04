import SwiftUI
import HiveCore

/// "List" view: one row per session without sections, favorites first, offline collapsed at the end.
/// Workers are indented under their PM (SessionTree); favorites, active, and offline are each grouped separately.
/// ScrollView + LazyVStack instead of List, so backgrounds, selection border, and context menu stay like in the cards.
struct SessionListView: View {
    @EnvironmentObject private var store: StateStore
    /// Favorites, already sorted (SessionOrder), including offline
    let favorites: [OverviewItem]
    /// Remaining sessions, already sorted (SessionOrder), without favorites
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        // favorites and active grouped separately, but one continuous stripe sequence
        let top = SessionTree.grouped(favorites, session: \.session)
            + SessionTree.grouped(items.filter { $0.status.rank < 3 }, session: \.session)
        let offline = SessionTree.grouped(items.filter { $0.status.rank == 3 }, session: \.session)
        LazyVStack(alignment: .leading, spacing: 4) {
            let topStripes = Self.groupStripes(top)
            ForEach(Array(top.enumerated()), id: \.element.item.id) { i, r in row(r, striped: topStripes[i], isFirst: i == 0 || top[i - 1].depth == 0) }
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 8)
                if showOffline {
                    let offStripes = Self.groupStripes(offline)
                    ForEach(Array(offline.enumerated()), id: \.element.item.id) { i, r in row(r, striped: offStripes[i], isFirst: i == 0 || offline[i - 1].depth == 0) }
                }
            }
        }
    }

    private func row(_ r: SessionTree.Row<OverviewItem>, striped: Bool, isFirst: Bool) -> some View {
        let it = r.item
        let indent: CGFloat = r.depth > 0 ? Self.indent : 0
        return SessionRow(item: it, isSelected: it.name == store.selected, striped: striped,
                          nameWidth: SessionRow.nameWidth - indent, indent: indent) { store.toggleFavorite(it.name) }
            .onTapGesture { store.selected = it.name }
            .contextMenu { SessionMenu(store: store, session: it.session) }
            // full-width row background, so the line sits on one surface per group
            .overlay(alignment: .leading) {
                if r.depth > 0 {
                    TreeLine(isFirst: isFirst, isLast: r.isLastInGroup).stroke(Hive.hair2, lineWidth: 1.5).frame(width: indent)
                }
            }
    }

    /// Indentation of workers under their PM
    static let indent: CGFloat = 28

    /// Stripes alternate per group, not per row: a PM and its workers share one background, so the tree line
    /// never runs across a differently colored row.
    static func groupStripes(_ rows: [SessionTree.Row<OverviewItem>]) -> [Bool] {
        var group = -1
        return rows.map { r in
            if r.depth == 0 { group += 1 }
            return group.isMultiple(of: 2)
        }
    }
}

/// Vertical line under the PM's status dot that connects its workers: the first worker extends it up to just
/// below the PM's dot, the last one ends it at its own middle. Rows have the same height, so half a row plus the
/// row spacing reaches the PM's dot.
private struct TreeLine: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        // same x as the status dot: row padding 14 + half of the 14 pt dot column
        let x = rect.minX + 21, spacing: CGFloat = 4, dotGap: CGFloat = 9
        let top = isFirst ? rect.minY - spacing - rect.height / 2 + dotGap : rect.minY - spacing
        var p = Path()
        p.move(to: CGPoint(x: x, y: top))
        p.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        return p
    }
}

struct SessionRow: View {
    let item: OverviewItem
    let isSelected: Bool
    /// alternating background (every other row)
    let striped: Bool
    /// Width of the name column; indented rows get it narrower by the indentation amount, so the remaining
    /// columns stay aligned
    var nameWidth: CGFloat = SessionRow.nameWidth
    /// Indentation of the content (workers); the background still spans the full width
    var indent: CGFloat = 0
    let toggleFavorite: () -> Void

    static let nameWidth: CGFloat = 140

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        // working/waiting: the "Now" box briefly, instead of the task
        let now = item.now?.text
        HStack(spacing: 14) {
            Circle().fill(st.color).frame(width: 9, height: 9).frame(width: 14)
            Text(item.name).font(.hiveMono(14, .medium)).foregroundStyle(Hive.ink)
                .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 6) {
                Text(loud && now == nil ? [st.label, st.why].compactMap { $0 }.joined(separator: " · ") : st.label)
                    .font(.system(size: 12.5, weight: loud ? .semibold : .regular))
                    .foregroundStyle(loud ? st.color : Hive.ink2)
                BackgroundBadge(count: item.session.backgroundTasks)
            }
            .frame(width: 210, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(item.color).frame(width: 6, height: 6)
                Text(now ?? task ?? "No task line").foregroundStyle(now == nil && task == nil ? Hive.muted : Hive.ink2)
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
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(loud || striped ? Hive.card : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Hive.ink : Color.clear, lineWidth: 3))
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
