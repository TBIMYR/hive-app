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
            ForEach(Array(top.enumerated()), id: \.element.item.id) { i, r in row(r, index: i) }
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 8)
                if showOffline {
                    ForEach(Array(offline.enumerated()), id: \.element.item.id) { i, r in row(r, index: i) }
                }
            }
        }
    }

    private func row(_ r: SessionTree.Row<OverviewItem>, index: Int) -> some View {
        let it = r.item
        let indent: CGFloat = r.depth > 0 ? Self.indent : 0
        return SessionRow(item: it, isSelected: it.name == store.selected, striped: index.isMultiple(of: 2),
                          nameWidth: SessionRow.nameWidth - indent) { store.toggleFavorite(it.name) }
            .onTapGesture { store.selected = it.name }
            .contextMenu { SessionMenu(store: store, session: it.session) }
            .padding(.leading, indent)
            .background(alignment: .leading) {
                if r.depth > 0 {
                    TreeLine(isLast: r.isLastInGroup).stroke(Hive.hair2, lineWidth: 1.5).frame(width: indent)
                }
            }
    }

    /// Indentation of workers under their PM
    static let indent: CGFloat = 28
}

/// Thin line to the left of an indented worker: vertical (for the last one only down to the middle), plus a short
/// horizontal stroke to the row. Extends beyond the row spacing above and below so the line stays continuous.
private struct TreeLine: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + 13, gap: CGFloat = 4
        var p = Path()
        p.move(to: CGPoint(x: x, y: rect.minY - gap))
        p.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY + gap))
        p.move(to: CGPoint(x: x, y: rect.midY))
        p.addLine(to: CGPoint(x: x + 9, y: rect.midY))
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
            Text(loud && now == nil ? [st.label, st.why].compactMap { $0 }.joined(separator: " · ") : st.label)
                .font(.system(size: 12.5, weight: loud ? .semibold : .regular))
                .foregroundStyle(loud ? st.color : Hive.ink2)
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
        .padding(.horizontal, 14).padding(.vertical, 15)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(loud || striped ? Hive.card : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Hive.ink : Color.clear, lineWidth: 3))
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
