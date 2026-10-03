import SwiftUI
import HiveCore

/// Ansicht „Tiles“: kleine Kacheln ohne Abschnitte, gleiche Reihenfolge wie die Liste, Offline eingeklappt am Ende.
struct SessionTileGrid: View {
    @EnvironmentObject private var store: StateStore
    /// schon sortiert (SessionOrder), ohne gepinnte
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        let active = items.filter { $0.status.rank < 3 }
        let offline = items.filter { $0.status.rank == 3 }
        VStack(alignment: .leading, spacing: 0) {
            grid(active)
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 10)
                if showOffline { grid(offline) }
            }
        }
    }

    private func grid(_ part: [OverviewItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10, alignment: .top)],
                  alignment: .leading, spacing: 10) {
            ForEach(part) { it in
                SmallTile(item: it, isSelected: it.name == store.selected)
                    .onTapGesture { store.selected = it.name }
                    .contextMenu { SessionMenu(store: store, session: it.session) }
            }
        }
    }
}

struct SmallTile: View {
    let item: OverviewItem
    let isSelected: Bool

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        // bei „braucht dich“ zuerst der Grund, dann die Aufgabe
        let text = loud ? [st.why, task].compactMap { $0 }.joined(separator: " – ") : (task ?? "No task line")
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(st.color).frame(width: 8, height: 8)
                Text(item.name).font(.hiveMono(12, .medium)).foregroundStyle(Hive.ink).lineLimit(1)
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(!loud && task == nil ? Hive.muted : Hive.ink2)
                .lineLimit(2, reservesSpace: true)
            Text(item.since.isEmpty ? item.project : "\(item.project) · \(item.since)")
                .font(.system(size: 10.5)).foregroundStyle(Hive.muted).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            // arbeitend: ruhiger grünlicher Rahmen (kein Pulsieren, bei vielen Kacheln zu unruhig)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Hive.ink : (loud ? st.color.opacity(0.5) : (st.rank == 1 ? st.color.opacity(0.4) : Hive.hair)),
                              lineWidth: isSelected ? 2 : 1)
        )
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
