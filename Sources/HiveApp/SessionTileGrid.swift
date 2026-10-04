import SwiftUI
import HiveCore

/// "Tiles" view: small tiles without sections, same order as the list: favorites first,
/// offline collapsed at the end.
struct SessionTileGrid: View {
    @EnvironmentObject private var store: StateStore
    /// Favorites, already sorted (SessionOrder), including offline
    let favorites: [OverviewItem]
    /// Remaining sessions, already sorted (SessionOrder), without favorites
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        let active = items.filter { $0.status.rank < 3 }
        let offline = items.filter { $0.status.rank == 3 }
        VStack(alignment: .leading, spacing: 0) {
            // one grid for favorites and active, so there's no gap between the two
            grid(favorites + active)
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 26).padding(.bottom, 12)
                if showOffline { grid(offline) }
            }
        }
    }

    private func grid(_ part: [OverviewItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 16) {
            ForEach(part) { it in
                SmallTile(item: it, isSelected: it.name == store.selected) { store.toggleFavorite(it.name) }
                    .onTapGesture { store.selected = it.name }
                    .contextMenu { SessionMenu(store: store, session: it.session) }
            }
        }
    }
}

/// Small card in the same calm style as the cards: white surface, soft shadow, rings for selected/waiting/working.
struct SmallTile: View {
    let item: OverviewItem
    let isSelected: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        let now = item.now
        // working/waiting: briefly the content of "Now", otherwise for "needs you" first the reason, then the task
        let text = loud ? [st.why, task].compactMap { $0 }.joined(separator: " – ") : (task ?? "No task line")
        VStack(alignment: .leading, spacing: 8) {
            // name, then the status as dot + colored text like on the cards; the status gives way first
            HStack(spacing: 8) {
                Text(item.name).font(.hiveMono(14, .medium)).foregroundStyle(Hive.ink).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                CardStatus(status: st, size: 11.5).layoutPriority(-1)
                BackgroundBadge(count: item.session.backgroundTasks)
                StarButton(isOn: item.isFavorite, toggle: toggleFavorite)
                    .padding(.trailing, -4)
            }
            if let now {
                // one line of text, below it command/file; together as tall as two lines of task
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.text)
                        .font(.system(size: 13, weight: now.kind == .permission ? .semibold : .regular))
                        .foregroundStyle(now.kind == .permission ? Hive.ink : Hive.ink2)
                    Text(now.detail ?? " ").font(.hiveMono(11.5)).foregroundStyle(Hive.muted).truncationMode(.middle)
                }
                .lineLimit(1)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(!loud && task == nil ? Hive.muted : Hive.ink2)
                    .lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 6) {
                Circle().fill(item.color).frame(width: 6, height: 6)
                Text(item.since.isEmpty ? item.project : "\(item.project) · \(item.since)")
            }
            .font(.system(size: 11.5)).foregroundStyle(Hive.muted).lineLimit(1)
            .padding(.top, 2)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(status: st, isSelected: isSelected, radius: 14)
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
