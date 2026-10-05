import AppKit
import SwiftUI

/// Hands out the NSView behind a SwiftUI view, so a floating card can be anchored to it.
struct AnchorReader: NSViewRepresentable {
    let onView: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onView(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A calm card (white, radius 16, soft shadow, no border) floating below an anchor view, in place of a
/// popover: from macOS 26 the system draws a dark outline around every popover that cannot be turned off.
/// Closes on a click outside (also in other apps), on Esc, when hive is deactivated and when the window
/// is resized or closed.
@MainActor
final class FloatingCard {
    /// room around the card for its shadow
    private static let margin: CGFloat = 24
    /// gap between the anchor and the top of the card
    private static let gap: CGFloat = 6

    private var panel: NSPanel?
    private weak var anchor: NSView?
    /// Pointer in screen coordinates for a card opened at the pointer (menu); nil = below the anchor
    private var point: NSPoint?
    private weak var window: NSWindow?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    var isOpen: Bool { panel != nil }

    func toggle(below anchor: NSView?, content: @escaping () -> some View) {
        if isOpen { close() } else if let anchor { show(below: anchor, content: content) }
    }

    func show(below anchor: NSView, content: () -> some View) {
        close()
        guard let window = anchor.window else { return }
        self.anchor = anchor
        open(in: window, content: content)
    }

    /// Top left corner at the pointer, like a menu; flips up or left where the window ends.
    func show(at point: NSPoint, in window: NSWindow, content: () -> some View) {
        close()
        self.point = point
        open(in: window, content: content)
    }

    private func open(in window: NSWindow, content: () -> some View) {
        self.window = window
        let p = CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        let host = NSHostingView(rootView: CardContainer(margin: Self.margin, content: AnyView(content())) { [weak self] size in
            self?.place(size)
        })
        p.contentView = host
        panel = p
        place(host.fittingSize)
        window.addChildWindow(p, ordered: .above)
        watch(window)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        panel = nil
        point = nil
    }

    /// Centered below the anchor and below the title bar (on macOS 26 the item's glass capsule is taller
    /// than the item itself), kept inside the window.
    private func place(_ size: CGSize) {
        guard let p = panel, let window, size.width > 0, size.height > 0 else { return }
        let m = Self.margin
        if let point {
            let f = window.frame
            var x = point.x - m
            if x + size.width - m > f.maxX - 8 { x = point.x - size.width + m }
            var y = point.y + m - size.height
            if y + m < f.minY + 8 { y = point.y - m }
            p.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
            return
        }
        guard let anchor else { return }
        let a = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var x = a.midX - size.width / 2
        x = min(x, window.frame.maxX - 8 + m - size.width)
        x = max(x, window.frame.minX + 8 - m)
        let titleBarBottom = window.frame.minY + window.contentLayoutRect.maxY
        let top = min(a.minY - Self.gap, titleBarBottom) + m
        p.setFrame(NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height),
                   display: true)
    }

    private func watch(_ window: NSWindow) {
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self, let p = self.panel else { return e }
            if e.type == .keyDown {
                guard e.keyCode == 53 else { return e }  // Esc
                self.close()
                return nil
            }
            if e.window === p { return e }
            // a click on the anchor itself is left to its button, which toggles the card
            if let anchor = self.anchor, e.window === anchor.window,
               anchor.bounds.contains(anchor.convert(e.locationInWindow, from: nil)) { return e }
            self.close()
            return e
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        monitors = [local, global].compactMap { $0 }
        let nc = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in Task { @MainActor in self?.close() } }
        observers = [
            nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: close),
            nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: close),
            nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: close),
        ]
    }
}

/// Borderless panels can't become key by default; the card's controls need it for keyboard focus.
private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The card surface with room for its shadow; reports its size so the panel can follow it.
private struct CardContainer: View {
    let margin: CGFloat
    let content: AnyView
    let onSize: (CGSize) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        content
            .clipShape(shape)
            .background { CardSurface(shape: shape) }
            .padding(margin)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}
