import AppKit
import SwiftUI
import HiveCore

extension View {
    /// Right-click opens the session menu in the Hive style (a floating card at the pointer)
    /// instead of the system context menu.
    func sessionMenu(_ store: StateStore, _ session: Session) -> some View {
        background {
            RightClickCatcher { point in
                SessionMenuPresenter.shared.show(at: point, store: store, session: session)
            }
        }
    }
}

/// Catches right-clicks inside the bounds of its view (a background, so left clicks and
/// hit testing stay untouched) and reports the pointer in screen coordinates.
private struct RightClickCatcher: NSViewRepresentable {
    let onClick: (NSPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onClick = onClick
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onClick = onClick }

    final class CatcherView: NSView {
        var onClick: ((NSPoint) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] e in
                guard let self, let w = self.window, e.window === w,
                      self.visibleRect.contains(self.convert(e.locationInWindow, from: nil)) else { return e }
                self.onClick?(w.convertPoint(toScreen: e.locationInWindow))
                return nil
            }
        }
    }
}

/// One menu open at a time.
@MainActor
final class SessionMenuPresenter {
    static let shared = SessionMenuPresenter()
    private let card = FloatingCard()

    func show(at point: NSPoint, store: StateStore, session: Session) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
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
            item("Restart…", "arrow.clockwise", disabled: notInHive) { store.requestClose(session, restart: true) }
            item("Close…", "xmark", disabled: notInHive) { store.requestClose(session, restart: false) }
            item("Force Quit…", "bolt.fill", destructive: true,
                 disabled: session.alive && session.pid != nil ? nil : "Not running") { store.requestForceQuit(session) }
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
