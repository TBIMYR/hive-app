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

/// Umschalter der Ansichten: Schiene mit hellem, mitgleitendem Feld für die gewählte Ansicht.
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
                    .foregroundStyle(on ? Hive.ink : (hover == m ? Hive.ink2 : Hive.muted))
                    .padding(.horizontal, 14).frame(height: 30)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8).fill(Hive.card)
                                .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
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
        .background(RoundedRectangle(cornerRadius: 11).fill(Hive.hair))
    }
}

/// Rahmen der Übersicht: Umschalter, Leiste „Pinned“ fest oben, darunter die gewählte Ansicht.
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @AppStorage("view") private var mode: ViewMode = .cards
    /// Offline-Sessions aufgeklappt (geteilt von allen Ansichten, nicht über Neustart gemerkt)
    @State private var showOffline = false
    /// Name des Pins, der gerade gezogen wird (siehe PinDropDelegate)
    @State private var dragging: String?

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
                         since: s.alive ? dur(s.statusUpdatedAt, now: now) : "")
        }
        let pins = store.pinnedSessions.map(item)
        let items = SessionOrder.sorted(store.unpinnedSessions.map(item), session: { $0.session },
                                        status: { $0.status.core }, labels: labels)
        return VStack(alignment: .leading, spacing: 0) {
            // Kopfzeile: Umschalter links, Pins rechts auf gleicher Höhe
            HStack(alignment: .top, spacing: 24) {
                ViewSwitcher(mode: $mode).fixedSize()
                if !pins.isEmpty {
                    PinBar(items: pins, dragging: $dragging)
                }
            }
            .padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 4)

            ScrollView {
                content(items)
                    .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 60)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder
    private func content(_ items: [OverviewItem]) -> some View {
        switch mode {
        case .list: SessionListView(items: items, showOffline: $showOffline)
        case .tiles: SessionTileGrid(items: items, showOffline: $showOffline)
        case .cards: SessionCardsView(items: items, showOffline: $showOffline)
        }
    }
}
