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
            Picker("View", selection: $mode) {
                ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 14)

            if !pins.isEmpty {
                PinBar(items: pins, dragging: $dragging)
                    .padding(.horizontal, 26).padding(.bottom, 14)
                Rectangle().fill(Hive.hair).frame(height: 1).padding(.horizontal, 26)
            }

            ScrollView {
                content(items)
                    .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func content(_ items: [OverviewItem]) -> some View {
        switch mode {
        case .list: SessionListView(items: items, showOffline: $showOffline)
        // Tiles kommt in der nächsten Aufgabe dazu
        case .tiles, .cards: SessionCardsView(items: items, showOffline: $showOffline)
        }
    }
}
