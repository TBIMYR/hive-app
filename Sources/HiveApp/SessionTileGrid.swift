import SwiftUI
import HiveCore

/// Ansicht „Tiles“: kleine Kacheln ohne Abschnitte, gleiche Reihenfolge wie die Liste: Favoriten zuerst,
/// Offline eingeklappt am Ende.
struct SessionTileGrid: View {
    @EnvironmentObject private var store: StateStore
    /// Favoriten, schon sortiert (SessionOrder), auch offline
    let favorites: [OverviewItem]
    /// übrige Sessions, schon sortiert (SessionOrder), ohne Favoriten
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        let active = items.filter { $0.status.rank < 3 }
        let offline = items.filter { $0.status.rank == 3 }
        VStack(alignment: .leading, spacing: 0) {
            // ein Raster für Favoriten und aktive, damit keine Lücke zwischen beiden entsteht
            grid(favorites + active)
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 10)
                if showOffline { grid(offline) }
            }
        }
    }

    private func grid(_ part: [OverviewItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)],
                  alignment: .leading, spacing: 14) {
            ForEach(part) { it in
                SmallTile(item: it, isSelected: it.name == store.selected) { store.toggleFavorite(it.name) }
                    .onTapGesture { store.selected = it.name }
                    .contextMenu { SessionMenu(store: store, session: it.session) }
            }
        }
    }
}

struct SmallTile: View {
    let item: OverviewItem
    let isSelected: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        // bei „braucht dich“ zuerst der Grund, dann die Aufgabe
        let text = loud ? [st.why, task].compactMap { $0 }.joined(separator: " – ") : (task ?? "No task line")
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(st.color).frame(width: 9, height: 9)
                Text(item.name).font(.hiveMono(14, .medium)).foregroundStyle(Hive.ink).lineLimit(1)
                Spacer(minLength: 4)
                StarButton(isOn: item.isFavorite, toggle: toggleFavorite)
                    .padding(.trailing, -4)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(!loud && task == nil ? Hive.muted : Hive.ink2)
                .lineLimit(2, reservesSpace: true)
            Text(item.since.isEmpty ? item.project : "\(item.project) · \(item.since)")
                .font(.system(size: 11.5)).foregroundStyle(Hive.muted).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            // arbeitend: ruhiger grünlicher Rahmen (kein Pulsieren, bei vielen Kacheln zu unruhig)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Hive.ink : (loud ? st.color.opacity(0.5) : (st.rank == 1 ? st.color.opacity(0.4) : Hive.hair)),
                              lineWidth: isSelected ? 3 : 1)
        )
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
