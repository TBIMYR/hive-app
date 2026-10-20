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

    private func grid(_ part: [OverviewItem]) -> some View { TileGrid(part: part) }
}

/// Grid of tiles, all as tall as the tallest one.
private struct TileGrid: View {
    @EnvironmentObject private var store: StateStore
    let part: [OverviewItem]
    @State private var tallest: CGFloat = 0

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 16) {
            ForEach(part) { it in
                SmallTile(item: it, isSelected: it.name == store.selected, minBody: tallest) { store.toggleFavorite(it.name) }
                    .onTapGesture { store.selected = it.name }
                    .sessionMenu(store, it.session)
                    .navFrame(it.name)
            }
        }
        .onPreferenceChange(TallestKey.self) { tallest = $0 }
    }
}

/// Small card in the same calm style as the cards: white surface, soft shadow, rings for selected/waiting/working.
struct SmallTile: View {
    let item: OverviewItem
    let isSelected: Bool
    /// Height of the tallest middle part (the title) in the grid; this one grows to it
    var minBody: CGFloat = 0
    let toggleFavorite: () -> Void
    private var show = Show()

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        // only the title (the task) like on the cards; without one the content of "Now" or the reason
        let text = task ?? (show.now ? item.now?.text : nil) ?? (loud ? st.why : nil)
        VStack(alignment: .leading, spacing: 8) {
            // name, then the status as dot + colored text like on the cards; the status gives way first
            HStack(spacing: 8) {
                Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Hive.ink).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if st.cls == "off" {
                    WakeUpButton(session: item.session)
                } else if show.status {
                    CardStatus(status: st, size: 11.5).layoutPriority(-1)
                }
                if show.badges {
                    RemoteControlBadge(on: item.session.remoteControl)
                    BackgroundBadge(count: item.session.backgroundTasks)
                }
                if show.load { LoadBadge(session: item.session) }
                if show.badges { NoteBadge(name: item.session.name) }
                StarButton(isOn: item.isFavorite, toggle: toggleFavorite)
                    .padding(.trailing, -4)
            }
            Text(text ?? "No task line")
                .font(.system(size: 13, weight: task == nil ? .regular : .medium))
                .foregroundStyle(text == nil ? Hive.muted : task == nil ? Hive.ink2 : Hive.ink)
                .lineLimit(2, reservesSpace: true)
            .matchTallest(minBody)
            let meta = [show.project ? item.project : nil, show.model ? item.session.model.map(ModelName.short) : nil,
                        show.since ? item.since : nil].compactMap { $0 }.filter { !$0.isEmpty }
            if !meta.isEmpty {
                HStack(spacing: 6) {
                    if show.project { Circle().fill(item.color).frame(width: 6, height: 6) }
                    Text(meta.joined(separator: " · "))
                }
                .font(.system(size: 11.5)).foregroundStyle(Hive.muted).lineLimit(1)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // below the ring, so a selected tile's ring covers it
        .overlay { if show.context { ContextEdge(percent: item.session.contextPercent, radius: 14) } }
        .cardBackground(status: st, isSelected: isSelected, radius: 14)
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}
