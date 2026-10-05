import AppKit
import SwiftUI
import HiveCore

extension View {
    /// Right-click opens the session menu in the Hive style (a floating card at the pointer)
    /// instead of the system context menu. SwiftUI's own hover decides which row is under the
    /// pointer, so the menu always belongs to the row that was clicked.
    func sessionMenu(_ store: StateStore, _ session: Session) -> some View {
        onHover { inside in SessionMenuPresenter.shared.hover(inside, store: store, session: session) }
    }
}

/// One menu open at a time; one right-click monitor for the whole app.
@MainActor
final class SessionMenuPresenter {
    static let shared = SessionMenuPresenter()
    private let card = FloatingCard()
    private var hovered: (store: StateStore, session: Session)?
    private var monitor: Any?

    func hover(_ inside: Bool, store: StateStore, session: Session) {
        if inside {
            hovered = (store, session)
            installMonitor()
        } else if hovered?.session.id == session.id {
            // leaving a row may arrive after entering the next one: only clear our own
            hovered = nil
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] e in
            guard let self, let (store, session) = self.hovered, let w = e.window, !(w is NSPanel) else { return e }
            // the row may be gone since (refresh): only open for a session that still exists
            guard let current = store.displaySessions.first(where: { $0.id == session.id }) else {
                self.hovered = nil
                return e
            }
            self.show(at: w.convertPoint(toScreen: e.locationInWindow), in: w, store: store, session: current)
            return nil
        }
    }

    func show(at point: NSPoint, in window: NSWindow? = nil, store: StateStore, session: Session) {
        guard let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        card.show(at: point, in: window) {
            SessionMenu(store: store, session: session) { [weak self] in self?.card.close() }
        }
    }
}

/// Session menu, in three parts: control the running session, organize, end it.
struct SessionMenu: View {
    @ObservedObject var store: StateStore
    let session: Session
    let dismiss: () -> Void

    var body: some View {
        // control only works via tmux, so only for sessions running in hive
        let inHive = store.tmux(session) != nil
        let notInHive = inHive ? nil : "Only for sessions running in Hive"
        VStack(alignment: .leading, spacing: 0) {
            Text(session.name)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Hive.muted)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            if !session.alive {
                item("Wake Up", "power") { store.wakeUp(session) }
            }
            item("Remote Control", "iphone.radiowaves.left.and.right", disabled: notInHive) { store.remoteControl(session) }
            item("Write Handover", "doc.text", disabled: notInHive) { store.writeHandover(session) }
            separator
            let fav = store.isFavorite(session.name)
            item(fav ? "Remove from Favorites" : "Favorite", fav ? "star.slash" : "star") { store.toggleFavorite(session.name) }
            if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == session.groupKey }) {
                item("Start \(next) in the same project", "plus") {
                    store.newPreset = NewSessionPreset(name: next, dir: session.cwd)
                }
            }
            separator
            // ending: a running session is ended, an offline one only taken off the list
            if session.alive || inHive {
                item("Restart…", "arrow.clockwise", disabled: notInHive) { store.requestClose(session, restart: true) }
                item("Close…", "xmark", disabled: notInHive) { store.requestClose(session, restart: false) }
                item("Force Quit…", "bolt.fill", destructive: true,
                     disabled: session.alive && session.pid != nil ? nil : "Not running") { store.requestForceQuit(session) }
            } else if session.hasHandover {
                item("Remove from List…", "trash", destructive: true) { store.removeRequest = session }
            }
        }
        .padding(6)
        .frame(minWidth: 240, alignment: .leading)
    }

    private var separator: some View {
        Rectangle().fill(Hive.hair).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 5)
    }

    /// `disabled`: reason shown as help, nil = enabled
    private func item(_ title: String, _ icon: String, destructive: Bool = false, disabled: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(MenuItemStyle(destructive: destructive))
        .disabled(disabled != nil)
        .help(disabled ?? "")
    }
}

/// Menu row: full width, light hover surface, red for destructive actions.
struct MenuItemStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? Hive.need : Hive.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(hover && enabled ? Hive.soft : Color.clear))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}
