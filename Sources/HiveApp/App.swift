import AppKit
import SwiftUI
import HiveCore

// Without an app bundle (swift run) the window would otherwise have no keyboard focus and no menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The store belongs to the AppDelegate so the notification delegate is set up before the first window appears.
    let store = StateStore()
    let notes = NotesStore()
    let usage = UsageStore()
    let projects = ProjectInfoStore()

    let dock = DockStore()

    /// ⌘T: brings the selected session's notepad to the front with the cursor in it; once more goes back
    /// to what shares its tile (the terminal). In a collapsed tile it shows and hides the notepad on top.
    func toggleNotes() {
        guard let name = store.selected, let group = dock.layout.group(of: .notes) else { return }
        // collapsed: on top of the rest for the moment
        if group.collapsed {
            dock.peek = dock.peek == .notes ? nil : .notes
            if dock.peek == .notes { notes.focusRequest = name }
            return
        }
        if group.selected == .notes, let other = group.panels.first(where: { $0 != .notes }) {
            dock.change { $0.select(other) }
        } else {
            dock.change { $0.select(.notes) }
            notes.focusRequest = name
        }
    }

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

    var body: some Scene {
        WindowGroup("Hive") {
            ContentView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.notes)
                .environmentObject(delegate.dock)
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
            CommandGroup(after: .toolbar) {
                Button("Find Session") { NotificationCenter.default.post(name: .findSession, object: nil) }
                    .keyboardShortcut("f")
                Button("Notes") { delegate.toggleNotes() }
                    .keyboardShortcut("t")
                Button("Reset Window Layout") { delegate.dock.reset() }
            }
        }
        // Hive → Settings… (⌘,)
        Settings {
            SettingsView().environmentObject(delegate.store)
        }
    }
}

/// Grace period before the Mac sleeps: counts down, Cancel turns Sleep When Done off.
struct SleepCountdown: View {
    @EnvironmentObject private var store: StateStore
    let deadline: Date

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("No session is working any more").font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text("The Mac goes to sleep in \(max(0, Int(deadline.timeIntervalSince(t.date).rounded(.up)))) s.")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Button("Sleep Now") { store.sleepNow() }
                Button("Cancel") { store.setSleepWhenDone(false) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

/// Options of the app.
struct SettingsView: View {
    @EnvironmentObject private var store: StateStore
    @AppStorage(Notifier.soundKey) private var notifySound = true
    @AppStorage(Notifier.phoneKey) private var phonePush = false
    @AppStorage(Notifier.topicKey) private var topic = ""
    @AppStorage(Notifier.awayKey) private var awayMinutes = 5
    @AppStorage(Hive.monoKey) private var mono = false
    private var show = Show()

    var body: some View {
        TabView {
            page { general }.tabItem { Label("General", systemImage: "gearshape") }
            page { notifications }.tabItem { Label("Notifications", systemImage: "bell") }
            page { display }.tabItem { Label("Display", systemImage: "eye") }
        }
    }

    /// One tab: grouped form, as tall as its content
    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .frame(width: 460)
            .fixedSize()
    }

    @ViewBuilder
    private var general: some View {
        Section {
            Picker(selection: $store.keepAwake) {
                Text("Off").tag(KeepAwake.Mode.off)
                Text("While sessions work").tag(KeepAwake.Mode.whileWorking)
                Text("Always").tag(KeepAwake.Mode.always)
            } label: {
                Text("Keep the Mac awake")
                Text("Like Amphetamine: no idle sleep while at least one session is working (also in the background), or always, without a limit. The display may still turn off.")
            }
        }
    }

    @ViewBuilder
    private var notifications: some View {
        Section {
            Toggle(isOn: $notifySound) {
                Text("Ping when a session needs you")
                Text("Plays a sound with the notification. Banner style and badge are set in System Settings → Notifications → Hive.")
            }
        }
        Section {
            Toggle(isOn: $phonePush) {
                Text("Push to the phone when I'm away")
                Text("Sends \"needs you\" via ntfy once the Mac has had no mouse or keyboard input for a while. Install the ntfy app and subscribe to the topic below.")
            }
            if phonePush {
                Stepper("Away after \(awayMinutes) min without input", value: $awayMinutes, in: 1...60)
                LabeledContent("Topic") {
                    HStack(spacing: 8) {
                        Text(topic).font(.hiveMono(12)).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(topic, forType: .string)
                        }
                        Button("Send test") {
                            Notifier.sendToPhone(topic: topic, title: "Hive", body: "Test: phone notifications work.")
                        }
                    }
                }
            }
        }
        .onChange(of: phonePush) { _, on in if on && topic.isEmpty { topic = Notifier.newTopic() } }
    }

    @ViewBuilder
    private var display: some View {
        Section {
            Toggle(isOn: $mono) {
                Text("Monochrome")
                Text("Black, white and gray instead of status and project colors. The terminal keeps its colors.")
            }
        }
        Section("Shown on the sessions") {
            Toggle("Status", isOn: show.$status)
            Toggle("Time in status", isOn: show.$since)
            Toggle("Detail line under the task", isOn: show.$detail)
            Toggle(isOn: show.$now) {
                Text("\"Now\" line")
                Text("Last step, question or result. An open question keeps its answer buttons.")
            }
            Toggle("Context usage", isOn: show.$context)
            Toggle("CPU load", isOn: show.$load)
            Toggle(isOn: show.$badges) {
                Text("Badges")
                Text("Background tasks, notes and Remote Control.")
            }
            Toggle("Project and branch", isOn: show.$project)
            Toggle(isOn: show.$model) {
                Text("Model")
                Text("The model of the last answer, e.g. Opus 5.5.")
            }
            Toggle(isOn: show.$place) {
                Text("Where the session runs")
                Text("Terminal icon (in Hive) or \"iTerm\" at the bottom right of a card.")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var usage: UsageStore
    /// Settings → Monochrome; the whole window content is rebuilt so every color is read again
    @AppStorage(Hive.monoKey) private var mono = false
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

    /// Keep-awake switch, clicks through while working → always → off: cup with steam while it holds the Mac
    /// awake for working sessions, empty cup while nothing works, sun while it stays awake without a limit.
    private var awakeButton: some View {
        let mode = store.keepAwake
        let armed = store.sleepWhenDone.armed
        return Button { store.keepAwake = mode.next } label: {
            Label("Keep Awake", systemImage: mode == .always && !armed ? "sun.max.fill"
                  : store.holdingAwake ? "cup.and.heat.waves.fill" : mode == .whileWorking ? "cup.and.saucer" : "moon.zzz")
        }
        .help(armed && store.holdingAwake ? "Awake until the sessions are done, then the Mac sleeps (Sleep When Done). Click to change Keep Awake."
              : mode == .always ? "Keeping the Mac awake, without a limit. Click to turn off."
              : mode == .off ? "Mac may sleep while sessions work. Click to keep it awake while sessions work."
              : store.holdingAwake ? "Keeping the Mac awake while sessions work. Click to keep it awake always."
              : "Keeps the Mac awake as soon as a session works. Click to keep it awake always.")
    }

    /// Sleep When Done: armed once, off again after the Mac slept or the grace period was cancelled.
    private var sleepButton: some View {
        Button { store.setSleepWhenDone(!store.sleepWhenDone.armed) } label: {
            Label("Sleep When Done", systemImage: store.sleepWhenDone.armed ? "moon.stars.fill" : "moon.stars")
                .foregroundStyle(store.sleepWhenDone.armed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .help(store.sleepWhenDone.armed ? "The Mac goes to sleep once no session works any more. Click to turn off."
              : "Put the Mac to sleep once no session works any more (once, with 60 s to cancel).")
    }

    /// Plan usage, then Keep Awake, Sleep When Done and New Session at the right edge of the title bar; from macOS 26 a
    /// flexible spacer pushes them there. Without usage data the usage item is left out.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        let hasUsage = usage.current(now: store.now) != nil
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
            // usage forms its own section, apart from the session buttons
            if hasUsage {
                ToolbarItem(placement: .automatic) { UsageButton() }
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(placement: .automatic) { awakeButton }
            ToolbarItem(placement: .automatic) { sleepButton }
            ToolbarItem(placement: .automatic) { newSessionButton }
        } else {
            if hasUsage { ToolbarItem(placement: .primaryAction) { UsageButton() } }
            ToolbarItem(placement: .primaryAction) { awakeButton }
            ToolbarItem(placement: .primaryAction) { sleepButton }
            ToolbarItem(placement: .primaryAction) { newSessionButton }
        }
    }

    var body: some View {
        Workspace()
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
        // grace period of Sleep When Done
        .sheet(isPresented: Binding(get: { store.sleepWhenDone.deadline != nil },
                                    set: { if !$0 { store.setSleepWhenDone(false) } })) {
            if let deadline = store.sleepWhenDone.deadline { SleepCountdown(deadline: deadline) }
        }
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
        .tint(mono ? Hive.ink : nil)
        .id(mono)
        #if DEBUG
        // for checking the look without screen recording: HIVE_SNAPSHOT=<file.png> saves the window content
        // a few seconds after launch (drawn by the app itself, so the title bar is missing)
        .task {
            guard let path = ProcessInfo.processInfo.environment["HIVE_SNAPSHOT"] else { return }
            try? await Task.sleep(for: .seconds(5))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        #endif
    }
}
