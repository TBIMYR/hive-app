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
        // TextKit 1: the checkboxes are placed with the layout manager
        let tv = NoteTextView(usingTextLayoutManager: false)
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
            var items: [NSRange] = []
            var boxes: [NoteTextView.Box] = []
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
                    items.append(prefix)
                    storage.addAttribute(.paragraphStyle, value: Self.paragraph(indent: 0), range: span.range)
                case .listMarker:
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                case .checkbox(let checked, let scope):
                    if NoteMarkdown.showsMarkup(scope: scope, selection: selection) {
                        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                    } else {
                        // the brackets keep their place but turn invisible; the text view draws the box over them
                        storage.addAttributes([.foregroundColor: NSColor.clear, .kern: 1.5], range: span.range)
                        boxes.append(.init(range: span.range, checked: checked))
                    }
                case .done:
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: span.range)
                case .markup(let scope):
                    if NoteMarkdown.showsMarkup(scope: scope, selection: selection) {
                        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: span.range)
                    } else {
                        storage.addAttributes([.font: Self.hidden, .foregroundColor: NSColor.clear, .backgroundColor: NSColor.clear],
                                              range: span.range)
                    }
                }
            }
            // wrapped lines of a list item continue under its text, measured with the look it has right now
            for prefix in items {
                let width = storage.attributedSubstring(from: prefix).size().width
                let line = (storage.string as NSString).paragraphRange(for: prefix)
                storage.addAttribute(.paragraphStyle, value: Self.paragraph(indent: width.rounded(.up)), range: line)
            }
            storage.endEditing()
            tv.typingAttributes = Self.base
            tv.boxes = boxes
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

    // MARK: Task checkboxes

    struct Box: Equatable {
        let range: NSRange
        let checked: Bool
    }

    /// Checkboxes to draw: task items off the cursor line.
    var boxes: [Box] = [] {
        didSet {
            guard boxes != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private func rect(of box: Box) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer, NSMaxRange(box.range) <= (textStorage?.length ?? 0) else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: box.range, actualCharacterRange: nil)
        let line = lm.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let chars = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        let side: CGFloat = 15
        let origin = textContainerOrigin
        return NSRect(x: chars.minX + origin.x + (chars.width - side) / 2,
                      y: line.minY + origin.y + (line.height - side) / 2, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for box in boxes {
            guard let r = rect(of: box), r.intersects(dirtyRect) else { continue }
            // checked: a check in the background color on a filled box, so it stays visible in light and dark mode
            let colors: [NSColor] = box.checked ? [.textBackgroundColor, .labelColor] : [.secondaryLabelColor]
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(.init(paletteColors: colors))
            guard let image = NSImage(systemSymbolName: box.checked ? "checkmark.square.fill" : "square",
                                      accessibilityDescription: box.checked ? "Done" : "Open")?
                .withSymbolConfiguration(config) else { continue }
            let size = image.size
            image.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height))
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for box in boxes { if let r = rect(of: box) { addCursorRect(r.insetBy(dx: -3, dy: -3), cursor: .pointingHand) } }
    }

    /// A click on a checkbox flips it (undoable) without moving the cursor or starting to edit.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let box = boxes.first(where: { rect(of: $0)?.insetBy(dx: -3, dy: -3).contains(p) == true }),
           let edit = NoteMarkdown.toggle(string, box: box.range),
           shouldChangeText(in: edit.range, replacementString: edit.with) {
            textStorage?.replaceCharacters(in: edit.range, with: edit.with)
            didChangeText()
            return
        }
        super.mouseDown(with: event)
    }
}
