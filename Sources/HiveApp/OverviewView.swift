import SwiftUI
import HiveCore

/// Ansicht der Übersicht, gemerkt unter `view`; unbekannte Werte ergeben Cards.
enum ViewMode: String, CaseIterable, Identifiable {
    case list, tiles, cards

    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "List"
        case .tiles: "Tiles"
        case .cards: "Cards"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .tiles: "square.grid.2x2"
        case .cards: "rectangle.grid.2x2"
        }
    }
}

/// Umschalter der Ansichten: weiße Schiene mit schwarzem, mitgleitendem Feld für die gewählte Ansicht.
struct ViewSwitcher: View {
    @Binding var mode: ViewMode
    @Namespace private var ns
    @State private var hover: ViewMode?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { m in
                let on = m == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) { mode = m }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: m.symbol).font(.system(size: 12, weight: .semibold))
                        Text(m.title).font(.system(size: 13, weight: on ? .semibold : .medium))
                    }
                    .foregroundStyle(on ? Hive.bg : (hover == m ? Hive.ink2 : Hive.muted))
                    .padding(.horizontal, 14).frame(height: 30)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8).fill(Hive.ink)
                                .matchedGeometryEffect(id: "on", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 ? m : (hover == m ? nil : hover) }
                .help("\(m.title) view")
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11).fill(Hive.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Hive.hair))
    }
}

/// Rahmen der Übersicht: Umschalter fest oben, darunter die gewählte Ansicht (Favoriten zuerst).
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @AppStorage("view") private var mode: ViewMode = .cards
    /// Offline-Sessions aufgeklappt (geteilt von allen Ansichten, nicht über Neustart gemerkt)
    @State private var showOffline = false

    var body: some View {
        Group {
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("No sessions readable", systemImage: "hexagon", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .background(Hive.bg)
    }

    private var board: some View {
        // einmal je Durchlauf: Projektnamen, Farben, Status
        let labels = store.labels
        let colors = store.groupColors(labels)
        let now = store.now
        func item(_ s: Session) -> OverviewItem {
            OverviewItem(session: s, status: store.status(s), project: labels[s.groupKey] ?? s.groupKey,
                         color: colors[s.groupKey] ?? StateStore.fallbackColor, inTmux: store.tmux(s) != nil,
                         since: s.alive ? dur(s.statusUpdatedAt, now: now) : "", isFavorite: store.isFavorite(s.name))
        }
        let sorted = SessionOrder.sorted(store.displaySessions.map(item), session: { $0.session },
                                         status: { $0.status.core }, labels: labels)
        let parts = Favorites.split(sorted, favorites: store.favorites, name: \.name)
        return VStack(alignment: .leading, spacing: 0) {
            ViewSwitcher(mode: $mode).fixedSize()
                .padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 4)

            ScrollView {
                content(favorites: parts.favorites, rest: parts.rest)
                    .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 60)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder
    private func content(favorites: [OverviewItem], rest: [OverviewItem]) -> some View {
        switch mode {
        case .list: SessionListView(favorites: favorites, items: rest, showOffline: $showOffline)
        case .tiles: SessionTileGrid(favorites: favorites, items: rest, showOffline: $showOffline)
        case .cards: SessionCardsView(favorites: favorites, items: rest, showOffline: $showOffline)
        }
    }
}
