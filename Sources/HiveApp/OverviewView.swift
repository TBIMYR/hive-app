import SwiftUI
import HiveCore

/// Übersicht: Abschnitte nach Dringlichkeit wie im Dashboard, aber ruhigere Karten und ohne Kopfleiste.
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Binding var selected: String?
    @Binding var newPreset: NewSessionPreset?
    @State private var showOffline = false
    @State private var tileHeight: CGFloat = 150

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Braucht dich", Hive.need), (1, "Arbeitet", Hive.busy), (2, "Bereit", Hive.idle), (3, "Offline", Hive.off),
    ]

    var body: some View {
        Group {
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("Keine Sessions lesbar", systemImage: "hexagon", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .background(Hive.bg)
    }

    private var board: some View {
        let labels = store.labels
        let all = store.displaySessions.map { ($0, store.status($0)) }
        // PMs stehen ohne eigenen Abschnitt bei den übrigen Karten; sie heben sich nur durch die Projektfarbe ab (Tile)
        let addRank = all.map(\.1.rank).filter { $0 != 3 }.min()
        return ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                ForEach(Self.sections, id: \.rank) { sec in
                    let items = sorted(all.filter { $0.1.rank == sec.rank }, rank: sec.rank, labels: labels)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeader(sec.title, items.count, sec.color, collapsible: sec.rank == 3)
                            if sec.rank != 3 || showOffline {
                                grid(items, labels: labels, add: sec.rank == addRank)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func grid(_ items: [(Session, Status)], labels: [String: String], add: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            ForEach(items, id: \.0.id) { s, k in
                Tile(session: s, status: k, label: labels[s.groupKey] ?? s.groupKey,
                     color: store.color(for: s.groupKey), inTmux: store.tmux(s) != nil,
                     isSelected: s.name == selected, now: store.now)
                    .background(GeometryReader { g in Color.clear.preference(key: TileHeightKey.self, value: g.size.height) })
                    .onTapGesture { selected = s.name }
                    .contextMenu {
                        if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == s.groupKey }) {
                            Button("\(next) im selben Projekt starten") {
                                newPreset = NewSessionPreset(name: next, dir: s.cwd)
                            }
                        }
                    }
            }
            // Neue Session als letzte Karte im ersten Worker-Abschnitt
            if add && Tmux.path != nil {
                AddTile(height: tileHeight) { newPreset = NewSessionPreset() }
            }
        }
        // Höhe der höchsten Karte im eigenen Abschnitt an „Neue Session“ weitergeben (LazyVGrid streckt nicht)
        .onPreferenceChange(TileHeightKey.self) { h in if add && h > 0 { tileHeight = h } }
    }

    private func sectionHeader(_ title: String, _ n: Int, _ color: Color, collapsible: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
            Text("\(n)").font(.system(size: 13)).foregroundStyle(Hive.muted).monospacedDigit()
            if collapsible {
                Image(systemName: showOffline ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Hive.muted)
            }
            Rectangle().fill(Hive.hair).frame(height: 1).padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { if collapsible { showOffline.toggle() } }
    }

    /// Reihenfolge wie im Dashboard: „Braucht dich“ nach Wartezeit, sonst Rückmeldung zuerst, dann Projekt, PM, Name.
    private func sorted(_ items: [(Session, Status)], rank: Int, labels: [String: String]) -> [(Session, Status)] {
        items.sorted { a, b in
            if rank == 0 {
                return (a.0.statusUpdatedAt.flatMap(parseISO) ?? .distantPast) < (b.0.statusUpdatedAt.flatMap(parseISO) ?? .distantPast)
            }
            if (a.1.cls == "wait") != (b.1.cls == "wait") { return a.1.cls == "wait" }
            let la = labels[a.0.groupKey] ?? "", lb = labels[b.0.groupKey] ?? ""
            if la != lb { return la.localizedCompare(lb) == .orderedAscending }
            if (a.0.isPm == true) != (b.0.isPm == true) { return a.0.isPm == true }
            return a.0.name < b.0.name
        }
    }
}

// MARK: Bausteine

/// Höhe der höchsten Karte eines Abschnitts (auch mit Hinweiszeile), für die Karte „Neue Session“.
struct TileHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Gestrichelte Karte „Neue Session“ im Raster.
struct AddTile: View {
    var height: CGFloat = 150
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                Text("Neue Session").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hover ? Hive.ink : Hive.muted)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(hover ? Hive.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hover ? Hive.ink2 : Hive.hair2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Neue Session in tmux starten (⌘N)")
    }
}

/// Langsam pulsierender Rahmen für arbeitende Sessions; bei „Bewegung reduzieren“ ruhig.
struct PulsingBorder: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            shape(opacity: 0.6)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                // 2,4 s pro Atemzug, Deckkraft 0,2 … 0,85
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 2 * .pi / 2.4) + 1) / 2
                shape(opacity: 0.2 + 0.65 * phase)
            }
        }
    }

    private func shape(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(color.opacity(opacity), lineWidth: 2)
            .allowsHitTesting(false)
    }
}

struct Token: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.hiveMono(10.5, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}

/// Status als Punkt + Text; nur „braucht dich“ wird eine gefüllte Pille.
struct StatusLabel: View {
    let status: Status
    var since: String = ""

    var body: some View {
        let loud = status.rank == 0
        HStack(spacing: 5) {
            Circle().fill(loud ? Color.white : status.color).frame(width: 7, height: 7)
            Text(status.label).lineLimit(1).truncationMode(.tail)
            if !since.isEmpty { Text(since).foregroundStyle(loud ? Color.white.opacity(0.8) : Hive.muted).fixedSize() }
        }
        .font(.system(size: 12, weight: loud ? .semibold : .medium))
        .foregroundStyle(loud ? Color.white : Hive.ink2)
        .padding(.horizontal, loud ? 9 : 0).padding(.vertical, loud ? 3 : 0)
        .background(loud ? status.color : Color.clear)
        .clipShape(Capsule())
    }
}

struct Tile: View {
    let session: Session
    let status: Status
    let label: String
    let color: Color
    let inTmux: Bool
    let isSelected: Bool
    let now: Date

    private var isPm: Bool { session.isPm == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name und Status
            HStack(spacing: 7) {
                if isPm { Token(text: session.abbr, color: color) }
                Text(session.name).font(.hiveMono(isPm ? 16 : 15, .semibold)).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                StatusLabel(status: status, since: session.alive == true ? dur(session.statusUpdatedAt, now: now) : "")
                    .layoutPriority(-1)
            }

            if let why = status.why {
                Text(why).font(.system(size: 12.5, weight: .medium)).foregroundStyle(status.color).lineLimit(1)
            }

            // Aufgabe
            Text(session.task?.text ?? "Keine Aufgaben-Zeile")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(session.task?.text == nil ? Hive.muted : Hive.ink)
                .lineLimit(2, reservesSpace: true)

            // Letzte Antwort
            Text(plain(session.lastAssistant?.text) ?? AttributedString(" "))
                .font(.system(size: 12.5))
                .foregroundStyle(Hive.ink2)
                .lineSpacing(3).lineLimit(2, reservesSpace: true)

            // Meta: Projekt · Branch · Zeit, rechts wo die Session läuft
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                if let b = session.branch, b != "HEAD" {
                    Text("·")
                    Text(b).truncationMode(.middle)
                }
                if let when = session.lastAssistant?.at ?? session.task?.updatedAt {
                    Text("·")
                    Text(ago(when, now: now)).fixedSize()
                }
                Spacer(minLength: 6)
                if !session.errors.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .help("Lesefehler: " + session.errors.joined(separator: "\n"))
                }
                if inTmux {
                    Image(systemName: "terminal").help("Läuft in der App")
                } else if session.alive == true && session.kind != "bg" {
                    Text("iTerm").fixedSize()
                }
            }
            .lineLimit(1)
            .font(.system(size: 11.5))
            .foregroundStyle(Hive.muted)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.rank == 0 ? status.color.opacity(0.06) : (isPm ? color.opacity(0.07) : Color.clear))
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Hive.ink : (status.rank == 0 ? status.color.opacity(0.5) : (isPm ? color.opacity(0.35) : Hive.hair)),
                              lineWidth: isSelected ? 2 : 1)
        )
        .overlay { if status.rank == 1 && !isSelected { PulsingBorder(color: status.color) } }
        .opacity(status.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    /// Markdown der Antwort (fett, Code …) als formatierter Text statt mit Sternchen; Zeilenumbrüche raus.
    private func plain(_ s: String?) -> AttributedString? {
        guard let s, !s.isEmpty else { return nil }
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: flat, options: opts)) ?? AttributedString(flat)
    }
}
