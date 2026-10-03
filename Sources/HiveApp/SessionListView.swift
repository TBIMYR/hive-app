import SwiftUI
import HiveCore

/// Ansicht „List“: eine Zeile je Session ohne Abschnitte, Offline eingeklappt am Ende.
/// ScrollView + LazyVStack statt List, damit Hintergründe, Auswahlrahmen und Kontextmenü wie in den Karten bleiben.
struct SessionListView: View {
    @EnvironmentObject private var store: StateStore
    /// schon sortiert (SessionOrder), ohne gepinnte
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        let active = items.filter { $0.status.rank < 3 }
        let offline = items.filter { $0.status.rank == 3 }
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(active.enumerated()), id: \.element.id) { i, it in row(it, index: i) }
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 8)
                if showOffline {
                    ForEach(Array(offline.enumerated()), id: \.element.id) { i, it in row(it, index: i) }
                }
            }
        }
    }

    private func row(_ it: OverviewItem, index: Int) -> some View {
        SessionRow(item: it, isSelected: it.name == store.selected, striped: index.isMultiple(of: 2))
            .onTapGesture { store.selected = it.name }
            .contextMenu { SessionMenu(store: store, session: it.session) }
    }
}

struct SessionRow: View {
    let item: OverviewItem
    let isSelected: Bool
    /// abwechselnder Hintergrund (jede zweite Zeile)
    let striped: Bool

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        HStack(spacing: 10) {
            Circle().fill(st.color).frame(width: 8, height: 8).frame(width: 14)
            Text(item.name).font(.hiveMono(12, .medium)).foregroundStyle(Hive.ink)
                .frame(width: 120, alignment: .leading)
            Text(loud ? [st.label, st.why].compactMap { $0 }.joined(separator: " · ") : st.label)
                .font(.system(size: 11.5, weight: loud ? .semibold : .regular))
                .foregroundStyle(loud ? st.color : Hive.ink2)
                .frame(width: 190, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(item.color).frame(width: 6, height: 6)
                Text(task ?? "No task line").foregroundStyle(task == nil ? Hive.muted : Hive.ink2)
            }
            .help(item.project)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.since).font(.system(size: 11)).foregroundStyle(Hive.muted).monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .lineLimit(1).truncationMode(.tail)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(loud || striped ? Hive.card : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Hive.ink : Color.clear, lineWidth: 2))
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
