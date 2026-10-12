import AppKit
import SwiftUI
import HiveCore

/// The text of a note: always editable, and styled as Markdown while one types (see NoteMarkdown). The
/// markup characters (`#`, `**`, backticks, fences) shrink away on every line the cursor is not on, so a
/// note reads like rendered Markdown and there is no separate edit mode. A click outside ends the editing.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    /// true = take the keyboard focus now (a fresh note); reset through `onFocus`
    var wantsFocus: Bool
    let onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let tv = NoteTextView()
        tv.delegate = context.coordinator
        tv.onFocus = { [weak coordinator = context.coordinator] focused in coordinator?.focusChanged(focused) }
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 11, height: 2)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.insertionPointColor = .labelColor
        tv.string = text
        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.string != text {
            tv.string = text
            c.restyle()
        }
        if wantsFocus, tv.window?.firstResponder !== tv {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.stopWatchingClicks() }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NoteTextView?
        private var focused = false
        private var clickMonitor: Any?

        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            restyle()
        }

        func textViewDidChangeSelection(_ notification: Notification) { restyle() }

        func focusChanged(_ now: Bool) {
            focused = now
            if now { watchClicks() } else { stopWatchingClicks() }
            restyle()
            parent.onFocus(now)
        }

        /// A click anywhere else in the window (also on plain background, which takes no focus itself)
        /// ends the editing.
        private func watchClicks() {
            guard clickMonitor == nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView, let w = tv.window, e.window === w, w.firstResponder === tv else { return }
                    if !tv.bounds.contains(tv.convert(e.locationInWindow, from: nil)) { w.makeFirstResponder(nil) }
                }
                return e
            }
        }

        func stopWatchingClicks() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }

        // MARK: Look

        private static let size: CGFloat = 15
        private static let body = NSFont.systemFont(ofSize: size)
        private static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        /// markup off the cursor line: too small to see or to take room
        private static let hidden = NSFont.systemFont(ofSize: 0.1)

        private static var base: [NSAttributedString.Key: Any] {
            [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph(indent: 0)]
        }

        /// Line and paragraph spacing; `indent` is where wrapped lines continue (list items hang under their text).
        private static func paragraph(indent: CGFloat) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 4
            p.paragraphSpacing = 4
            p.headIndent = indent
            return p
        }

        /// Applies the Markdown look to the whole text. Only attributes change, never characters.
        func restyle() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            let selection = focused ? tv.selectedRange() : nil
            storage.beginEditing()
            storage.setAttributes(Self.base, range: all)
            for span in NoteMarkdown.spans(storage.string) where NSMaxRange(span.range) <= storage.length {
                switch span.kind {
                case .heading(let level):
                    let s: CGFloat = level == 1 ? 20 : level == 2 ? 17.5 : Self.size
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: s, weight: .semibold), range: span.range)
                case .bold:
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: Self.size, weight: .semibold), range: span.range)
                case .code:
                    storage.addAttributes([.font: Self.mono, .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07)], range: span.range)
                case .codeBlock:
                    storage.addAttributes([.font: Self.mono, .foregroundColor: NSColor.secondaryLabelColor], range: span.range)
                case .listItem(let prefix):
                    let lead = (storage.string as NSString).substring(with: prefix).replacingOccurrences(of: "\t", with: "    ")
                    let width = (lead as NSString).size(withAttributes: [.font: Self.body]).width
                    storage.addAttribute(.paragraphStyle, value: Self.paragraph(indent: width.rounded(.up)), range: span.range)
                case .listMarker:
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                case .markup(let scope):
                    if NoteMarkdown.showsMarkup(scope: scope, selection: selection) {
                        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: span.range)
                    } else {
                        storage.addAttributes([.font: Self.hidden, .foregroundColor: NSColor.clear, .backgroundColor: NSColor.clear],
                                              range: span.range)
                    }
                }
            }
            storage.endEditing()
            tv.typingAttributes = Self.base
        }
    }
}

/// Text view that reports gaining and losing the keyboard focus.
final class NoteTextView: NSTextView {
    var onFocus: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocus?(false) }
        return ok
    }

    // Esc leaves the note
    override func cancelOperation(_ sender: Any?) { window?.makeFirstResponder(nil) }
}
