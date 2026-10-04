import AppKit
import SwiftUI
import HiveCore

/// Todo-Liste aus `~/.claude/hive/todos.md` (zum Ausprobieren: `HIVE_TODOS=<pfad>`).
/// Schreibt atomar und übernimmt Änderungen von außen; nach dem eigenen Schreiben ist der gelesene
/// Stand gleich dem eigenen, darum flackert nichts.
@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var list = TodoList.parse("")
    let url: URL
    /// zuletzt gelesener oder geschriebener Dateiinhalt
    private var text = ""
    private var watcher: Watcher?

    init(path: String = ProcessInfo.processInfo.environment["HIVE_TODOS"]
            ?? "\(StateBuilder.defaultClaudeHome)/hive/todos.md") {
        url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        watcher = Watcher(paths: [dir.path]) { [weak self] in
            Task { @MainActor in self?.load() }
        }
    }

    /// Liest die Datei neu; fehlt sie, ist die Liste leer.
    func load() {
        let now = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard now != text else { return }
        text = now
        list = TodoList.parse(now)
    }

    func add(_ text: String) { change { $0.add(text) } }
    func toggle(_ id: Int) { change { $0.toggle(id) } }
    func edit(_ id: Int, _ text: String) { change { $0.edit(id, text) } }
    func remove(_ id: Int) { change { $0.remove(id) } }
    func clearDone() { change { $0.clearDone() } }

    private func change(_ f: (inout TodoList) -> Void) {
        var next = list
        f(&next)
        let rendered = next.render()
        list = next
        guard rendered != text else { return }
        text = rendered
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(rendered.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("hive: todos not saved: \(error.localizedDescription)")
        }
    }

    /// Öffnet die Datei im Standard-Editor (legt sie leer an, wenn es sie noch nicht gibt).
    func openInEditor() {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// Schwebende Todo-Karte im Hive-Fenster. Lage und Größe liegen in @AppStorage; angezeigt wird sie
/// immer innerhalb von `bounds` (kleineres Fenster schiebt sie zurück, ohne den gemerkten Wert zu ändern).
struct TodoPanel: View {
    @EnvironmentObject private var todos: TodoStore
    /// Fenstergröße, in die die Karte passen muss
    let bounds: CGSize
    /// Lage, falls noch keine gemerkt ist
    let defaultOrigin: CGPoint
    @Binding var visible: Bool

    @AppStorage("todoX") private var storedX: Double = -1
    @AppStorage("todoY") private var storedY: Double = -1
    @AppStorage("todoW") private var storedW: Double = TodoPanel.defaultSize.width
    @AppStorage("todoH") private var storedH: Double = TodoPanel.defaultSize.height

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?
    @State private var editing: Int?
    @State private var draft = ""
    @State private var newText = ""
    @State private var hovered: Int?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case add, item(Int) }

    static let minSize = CGSize(width: 260, height: 220)
    /// Größe beim ersten Öffnen und nach dem Zurücksetzen (Doppelklick auf die Kopfzeile)
    static let defaultSize = CGSize(width: 380, height: 460)

    private var size: CGSize {
        CGSize(width: min(max(storedW, Self.minSize.width), max(Self.minSize.width, bounds.width)).rounded(),
               height: min(max(storedH, Self.minSize.height), max(Self.minSize.height, bounds.height)).rounded())
    }

    private var origin: CGPoint {
        let s = size
        let x = storedX < 0 ? defaultOrigin.x : storedX
        let y = storedY < 0 ? defaultOrigin.y : storedY
        return CGPoint(x: min(max(x, 0), max(0, bounds.width - s.width)).rounded(),
                       y: min(max(y, 0), max(0, bounds.height - s.height)).rounded())
    }

    var body: some View {
        let s = size, o = origin
        VStack(spacing: 0) {
            header
            Rectangle().fill(Hive.hair).frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(todos.list.ordered) { row($0) }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            addField
            footer
        }
        .frame(width: s.width, height: s.height)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Hive.hair, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 14)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        .offset(x: o.x, y: o.y)
        .onChange(of: focus) { old, new in
            // Fokus verlassen speichert die Bearbeitung
            if case .item(let id) = old, new != old, editing == id { commit() }
        }
    }

    // MARK: Teile

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Hive.hair2)
            Text("Todo").font(.system(size: 14, weight: .semibold)).foregroundStyle(Hive.ink)
            Text("\(todos.list.open.count) open").font(.system(size: 13)).foregroundStyle(Hive.muted).monospacedDigit()
            Spacer(minLength: 4)
            Button { visible = false } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Hive.muted)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide (⌘T)")
        }
        .padding(.leading, 16).padding(.trailing, 10).frame(height: 44)
        .contentShape(Rectangle())
        // Doppelklick: Standardgröße, mittig im Fenster
        .onTapGesture(count: 2) { reset() }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    let start = dragStart ?? origin
                    dragStart = start
                    storedX = Double(start.x + v.translation.width).rounded()
                    storedY = Double(start.y + v.translation.height).rounded()
                }
                .onEnded { _ in
                    // gemerkt wird, wo die Karte wirklich steht
                    let o = origin
                    storedX = o.x; storedY = o.y
                    dragStart = nil
                }
        )
    }

    private func row(_ item: TodoList.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Button { todos.toggle(item.id) } label: { checkbox(item.done) }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            if editing == item.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Hive.ink)
                    .focused($focus, equals: .item(item.id))
                    .onSubmit { commit(); focus = nil }
                    .onExitCommand { editing = nil; focus = nil }
            } else {
                Text(item.text)
                    .font(.system(size: 14))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Hive.muted : Hive.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEditing(item) }
            }
            if hovered == item.id && editing != item.id {
                Button { todos.remove(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Hive.muted)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(hovered == item.id ? Hive.bg : Color.clear)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
    }

    private func checkbox(_ done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(done ? Hive.ink : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(done ? Hive.ink : Hive.idle, lineWidth: 1.5))
            .overlay {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Hive.card)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }

    private var addField: some View {
        TextField("Add a todo…", text: $newText)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($focus, equals: .add)
            .onSubmit {
                todos.add(newText)
                newText = ""
                focus = .add   // bleibt für den nächsten Eintrag
            }
            .onExitCommand { focus = nil }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Hive.hair, lineWidth: 1))
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
    }

    private var footer: some View {
        HStack {
            Button { todos.openInEditor() } label: {
                Text(todos.displayPath).lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("Open in the default editor")
            Spacer(minLength: 8)
            if !todos.list.done.isEmpty {
                Button("Clear done") { todos.clearDone() }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Hive.muted)
        .padding(.leading, 16).padding(.trailing, 24).padding(.top, 8).padding(.bottom, 14)
    }

    private var resizeGrip: some View {
        Color.clear
            .overlay(alignment: .bottomTrailing) {
                Path { p in
                    p.move(to: CGPoint(x: 10, y: 0))
                    p.addLine(to: CGPoint(x: 10, y: 7))
                    p.addQuadCurve(to: CGPoint(x: 7, y: 10), control: CGPoint(x: 10, y: 10))
                    p.addLine(to: CGPoint(x: 0, y: 10))
                }
                .stroke(Hive.hair2, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 10, height: 10)
                .padding(5)
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let start = resizeStart ?? size
                        resizeStart = start
                        // nicht über den Fensterrand hinaus
                        let o = origin
                        storedW = min(max(Double(start.width + v.translation.width), Self.minSize.width),
                                      max(Self.minSize.width, bounds.width - o.x)).rounded()
                        storedH = min(max(Double(start.height + v.translation.height), Self.minSize.height),
                                      max(Self.minSize.height, bounds.height - o.y)).rounded()
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .help("Resize")
    }

    /// Zurück auf Standardgröße, mittig im Fenster (gemerkte Werte werden überschrieben).
    private func reset() {
        let w = min(Self.defaultSize.width, max(Self.minSize.width, bounds.width))
        let h = min(Self.defaultSize.height, max(Self.minSize.height, bounds.height))
        storedW = Double(w); storedH = Double(h)
        storedX = Double(max(0, (bounds.width - w) / 2)).rounded()
        storedY = Double(max(0, (bounds.height - h) / 2)).rounded()
    }

    // MARK: Bearbeiten

    private func startEditing(_ item: TodoList.Item) {
        if let id = editing, id != item.id { commit() }
        draft = item.text
        editing = item.id
        // erst wenn das Feld steht, kann es den Fokus nehmen
        DispatchQueue.main.async { focus = .item(item.id) }
    }

    /// Speichert den Entwurf; leerer Text löscht den Eintrag (siehe TodoList.edit).
    private func commit() {
        guard let id = editing else { return }
        editing = nil
        todos.edit(id, draft)
    }
}
