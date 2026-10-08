import AppKit
import SwiftUI
import HiveCore

// Without an app bundle (swift run) the window would otherwise have no keyboard focus and no menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The store belongs to the AppDelegate so the notification delegate is set up before the first window appears.
    let store = StateStore()
    let todos = TodoStore()
    let usage = UsageStore()
    let projects = ProjectInfoStore()

    func applicationWillFinishLaunching(_ notification: Notification) {
        store.notifier.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("todoVisible") private var todoVisible = false

    var body: some Scene {
        WindowGroup("Hive") {
            ContentView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.todos)
                .environmentObject(delegate.usage)
                .environmentObject(delegate.projects)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            // shortcuts here, not on the toolbar menu (those don't fire while the menu is closed)
            CommandGroup(replacing: .newItem) {
                Button("New Session") { delegate.store.newPreset = NewSessionPreset() }
                    .keyboardShortcut("n").disabled(Tmux.path == nil)
                Button("New Project…") { delegate.store.newProjectOpen = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // ⌘H only in hive: replaces "Hide hive" (this also drops "Hide Others" and "Show All")
            CommandGroup(replacing: .appVisibility) {
                Button("Jump to Waiting Session") { delegate.store.jumpToWaiting() }
                    .keyboardShortcut("h")
            }
            // in the View menu, checked as long as the card is visible
            CommandGroup(after: .toolbar) {
                Toggle("Todo List", isOn: $todoVisible)
                    .keyboardShortcut("t")
            }
        }
        // Hive → Settings… (⌘,)
        Settings {
            SettingsView().environmentObject(delegate.store)
        }
    }
}

/// Options of the app.
struct SettingsView: View {
    @EnvironmentObject private var store: StateStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.keepAwake) {
                    Text("Keep the Mac awake while sessions work")
                    Text("Like Amphetamine: no idle sleep as long as at least one session is working, also in the background. The display may still turn off.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var usage: UsageStore
    /// Width of the terminal in points, changed by dragging the divider; 0 = default (⅓ of the window)
    @AppStorage("terminalWidth") private var terminalWidth: Double = 0
    @AppStorage("todoVisible") private var todoVisible = false
    @State private var dragStart: Double?

    private static let minTerminal: Double = 340
    private static let minOverview: Double = 420

    /// Terminal width for the window width, clamped and rounded to whole points
    /// (otherwise the terminal sits between two pixels and the text gets blurry).
    private func width(for total: Double, wanted: Double) -> Double {
        let w = wanted > 0 ? wanted : total / 3
        return min(max(w, Self.minTerminal), max(Self.minTerminal, total - Self.minOverview)).rounded()
    }

    /// Mark and wordmark on the left of the title bar
    private var brandLabel: some View {
        HStack(spacing: 8) {
            ZStack {
                HiveMark().fill(Hive.ink)
                HiveMark().stroke(Hive.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            .frame(width: 15, height: 17)
            Text("Hive").font(.system(size: 15, weight: .medium)).kerning(-0.1).foregroundStyle(Hive.ink)
        }
        .padding(.leading, 4)
    }

    @ToolbarContentBuilder
    private var brand: some ToolbarContent {
        // from macOS 26 toolbar items otherwise get a glass background; the logo stands free
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { brandLabel }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { brandLabel }
        }
    }

    private var todoButton: some View {
        Button { todoVisible.toggle() } label: { Label("Todo List", systemImage: "checklist") }
            .help(todoVisible ? "Hide the todo list (⌘T)" : "Show the todo list (⌘T)")
    }

    /// Click: New Session; the arrow opens the menu with New Project.
    private var newSessionButton: some View {
        Menu {
            Button("New Session") { store.newPreset = NewSessionPreset() }.disabled(Tmux.path == nil)
            Button("New Project…") { store.newProjectOpen = true }
        } label: {
            Label("New", systemImage: "plus")
        } primaryAction: {
            if Tmux.path != nil { store.newPreset = NewSessionPreset() } else { store.newProjectOpen = true }
        }
        .help("New session in tmux (⌘N); the menu also has New Project (⇧⌘N)")
    }

    /// Keep-awake switch: cup with steam while it holds the Mac awake, empty cup while on but nothing works.
    private var awakeButton: some View {
        Button { store.keepAwake.toggle() } label: {
            Label("Keep Awake", systemImage: !store.keepAwake ? "moon.zzz" : store.holdingAwake ? "cup.and.heat.waves.fill" : "cup.and.saucer")
        }
        .help(!store.keepAwake ? "Mac may sleep while sessions work. Click to keep it awake."
              : store.holdingAwake ? "Keeping the Mac awake while sessions work. Click to turn off."
              : "Keeps the Mac awake as soon as a session works. Click to turn off.")
    }

    /// Plan usage, Todo and New Session at the right edge of the title bar; from macOS 26 a flexible spacer
    /// pushes them there. Without usage data the usage item is left out.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        let hasUsage = usage.current(now: store.now) != nil
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
            if hasUsage { ToolbarItem(placement: .automatic) { UsageButton() } }
            ToolbarItem(placement: .automatic) { awakeButton }
            ToolbarItem(placement: .automatic) { todoButton }
            ToolbarItem(placement: .automatic) { newSessionButton }
        } else {
            if hasUsage { ToolbarItem(placement: .primaryAction) { UsageButton() } }
            ToolbarItem(placement: .primaryAction) { awakeButton }
            ToolbarItem(placement: .primaryAction) { todoButton }
            ToolbarItem(placement: .primaryAction) { newSessionButton }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let total = Double(geo.size.width)
            let w = width(for: total, wanted: terminalWidth)
            HStack(spacing: 0) {
                OverviewView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TerminalPane(session: store.displaySessions.first { $0.name == store.selected })
                    // whole points on all sides, otherwise the terminal text gets blurry
                    .padding(.vertical, Hive.margin).padding(.trailing, Hive.margin).padding(.leading, Hive.margin / 2)
                    .frame(width: w)
                    .frame(maxHeight: .infinity)
                    .background(Hive.bg)
            }
            // invisible handle on the divider: dragging changes the terminal's width
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 9).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .offset(x: total - w + Hive.margin / 2 - 4.5)  // centered on the left edge of the terminal card
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let start = dragStart ?? w
                                dragStart = start
                                terminalWidth = width(for: total, wanted: start - Double(v.translation.width))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            // floating todo card, by default top right in the overview
            .overlay(alignment: .topLeading) {
                if todoVisible {
                    TodoPanel(bounds: geo.size,
                              defaultOrigin: CGPoint(x: total - w - TodoPanel.defaultSize.width - 26, y: 64),
                              visible: $todoVisible)
                }
            }
        }
        // instead of the window title: mark and wordmark on the left of the title bar
        .onAppear { NSApp.windows.forEach { $0.titleVisibility = .hidden } }
        .toolbar {
            brand
            actions
        }
        .sheet(item: $store.newPreset) { preset in
            NewSessionSheet(preset: preset) { name in
                store.selected = name
                store.refreshSoon()
            }
        }
        .sheet(isPresented: $store.newProjectOpen) { NewProjectSheet() }
        // confirmation for Close…/Restart… from the right-click menu
        .alert(store.closeRequest?.title ?? "",
               isPresented: Binding(get: { store.closeRequest != nil },
                                    set: { if !$0 { store.closeRequest = nil } }),
               presenting: store.closeRequest) { r in
            Button(r.restart ? "Restart" : "Close", role: .destructive) { store.close(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text(r.message)
        }
        .alert(store.forceQuitRequest?.title ?? "",
               isPresented: Binding(get: { store.forceQuitRequest != nil },
                                    set: { if !$0 { store.forceQuitRequest = nil } }),
               presenting: store.forceQuitRequest) { r in
            Button("Force Quit", role: .destructive) { store.forceQuit(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text(r.message)
        }
        .alert("Remove \(store.removeRequest?.name ?? "") from the list?",
               isPresented: Binding(get: { store.removeRequest != nil },
                                    set: { if !$0 { store.removeRequest = nil } }),
               presenting: store.removeRequest) { s in
            Button("Remove", role: .destructive) { store.remove(s) }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            Text("Moves its handover to ~/.claude/handover/archive/\(s.name)/. Nothing is deleted; moving the file back brings the session back.")
        }
        .alert("Hive",
               isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.notice ?? "")
        }
    }
}
