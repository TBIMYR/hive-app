import SwiftUI
import HiveCore

/// Overview view mode, remembered under `view`; unknown values default to Cards.
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

/// View switcher: white rail with a black, sliding field for the selected view.
struct ViewSwitcher: View {
    @Binding var mode: ViewMode

    var body: some View {
        RailSwitcher(selection: $mode, items: ViewMode.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) },
                     help: { "\($0.title) view" })
    }
}

/// Segmented switch in Hive's style: white rail, the selected item on a black field that slides over.
/// Used for the overview's view mode and the terminal card's Terminal · Handover · Project.
struct RailSwitcher<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        let symbol: String
    }

    @Binding var selection: Value
    let items: [Item]
    var help: (Item) -> String = { $0.title }
    @Namespace private var ns
    @State private var hover: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let on = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = item.value }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                        Text(item.title).font(.system(size: 13, weight: on ? .semibold : .medium))
                    }
                    .foregroundStyle(on ? Hive.bg : (hover == item.value ? Hive.ink2 : Hive.muted))
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
                .onHover { hover = $0 ? item.value : (hover == item.value ? nil : hover) }
                .help(help(item))
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11).fill(Hive.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Hive.hair))
    }
}

/// Frame of the overview: switcher fixed at the top, below it the selected view (favorites first).
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("view") private var mode: ViewMode = .cards
    /// Offline sessions expanded (shared by all views, not remembered across restarts)
    @State private var showOffline = Self.offlineAtLaunch
    @State private var nav = SessionNavigator()
    #if DEBUG
    /// for screenshots of a test instance: HIVE_SHOW_OFFLINE=1 starts with offline sessions expanded
    private static let offlineAtLaunch = ProcessInfo.processInfo.environment["HIVE_SHOW_OFFLINE"] != nil
    #else
    private static let offlineAtLaunch = false
    #endif

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
        // finds the window for ⌥ + arrow keys (only this one, not Settings or the floating cards)
        .background(AnchorReader { nav.anchor = $0 })
        .onAppear { nav.start(store) }
        .onDisappear { nav.stop() }
        #if DEBUG
        // for screenshots of a test instance: HIVE_OPEN_MENU=<name> opens that session's menu at launch
        // HIVE_OPEN_SETTINGS=1 opens the settings window at launch
        .task {
            guard ProcessInfo.processInfo.environment["HIVE_OPEN_SETTINGS"] != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .task {
            guard let name = ProcessInfo.processInfo.environment["HIVE_OPEN_MENU"] else { return }
            try? await Task.sleep(for: .seconds(3))
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(1))
            guard let s = store.displaySessions.first(where: { $0.name == name }),
                  let w = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            SessionMenuPresenter.shared.show(at: NSPoint(x: w.frame.minX + 300, y: w.frame.maxY - 200), store: store, session: s)
        }
        #endif
    }

    private var board: some View {
        // once per pass: project names, colors, status
        let labels = store.labels
        let colors = store.groupColors(labels)
        let now = store.now
        func item(_ s: Session) -> OverviewItem {
            OverviewItem(session: s, status: store.status(s), project: labels[s.groupKey] ?? s.groupKey,
                         color: colors[s.groupKey] ?? StateStore.fallbackColor, inTmux: store.tmux(s) != nil,
                         since: s.alive ? dur(s.statusUpdatedAt, now: now) : "", isFavorite: store.isFavorite(s.name))
        }
        let sorted = SessionOrder.sorted(store.displaySessions.map(item), session: { $0.session },
                                         status: { $0.status.core }, labels: labels, activity: store.sortActivity.times)
        var parts = Favorites.split(sorted, favorites: store.favorites, name: \.name)
        // the list nests workers under their PM, so a favorite PM takes its workers along
        if mode == .list {
            parts = Favorites.withWorkers(favorites: parts.favorites, rest: parts.rest, session: \.session,
                                          active: { $0.status.rank < 3 })
        }
        let shown = shownOrder(favorites: parts.favorites, rest: parts.rest)
        nav.order = shown.map(\.name)
        return VStack(alignment: .leading, spacing: 0) {
            ViewSwitcher(mode: $mode).fixedSize()
                .padding(.leading, Hive.margin).padding(.trailing, Hive.margin / 2).padding(.top, Hive.margin).padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    content(favorites: parts.favorites, rest: parts.rest)
                        .coordinateSpace(.named(NavFrameKey.space))
                        .onPreferenceChange(NavFrameKey.self) { nav.frames = $0 }
                        .padding(.leading, Hive.margin).padding(.trailing, Hive.margin / 2).padding(.top, 20).padding(.bottom, 60)
                }
                .scrollIndicators(.never)
                // keeps the selection in view (arrow keys, ⌘H, notifications); nil anchor = scroll as little as needed
                .onChange(of: store.selected) { _, name in
                    guard let id = shown.first(where: { $0.name == name })?.id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id, anchor: nil) }
                }
            }
        }
    }

    /// Sessions in the order the current view shows them (the list puts workers under their PM),
    /// offline only while expanded. Lets the arrow keys reach sessions a lazy stack hasn't drawn yet.
    private func shownOrder(favorites: [OverviewItem], rest: [OverviewItem]) -> [OverviewItem] {
        let active = rest.filter { $0.status.rank < 3 }
        let offline = showOffline ? rest.filter { $0.status.rank == 3 } : []
        guard mode == .list else { return favorites + active + offline }
        return [favorites, active, offline].flatMap { SessionTree.grouped($0, session: \.session).map(\.item) }
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

/// ⌥ + arrow keys in the main window: moves the selection spatially through the overview (SessionNav) and puts
/// the cursor into the terminal. ⌥ + arrows reach hive even while the terminal has focus (there they would jump by word).
@MainActor
final class SessionNavigator {
    /// where the sessions are drawn right now (scroll content coordinates)
    var frames: [String: CGRect] = [:]
    /// all shown sessions in view order
    var order: [String] = []
    /// any view in the main window
    weak var anchor: NSView?
    private var monitor: Any?

    func start(_ store: StateStore) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak store] e in
            guard let self, let store, let dir = Self.direction(e),
                  let w = e.window, w === self.anchor?.window, w.attachedSheet == nil,
                  // text fields (reply, todo list) keep ⌥ + arrows for moving by word or paragraph
                  !(w.firstResponder is NSTextView) else { return e }
            if let name = SessionNav.target(from: store.selected, dir, frames: self.frames, order: self.order) {
                store.selectAndFocus(name)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func direction(_ e: NSEvent) -> SessionNav.Direction? {
        guard e.modifierFlags.intersection([.shift, .control, .option, .command]) == .option else { return nil }
        switch e.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }
}
