import SwiftUI

/// Übersicht: Abschnitte nach Dringlichkeit wie im Dashboard, aber ruhigere Karten und ohne Kopfleiste.
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Binding var selected: String?
    @Binding var newPreset: NewSessionPreset?
    @State private var showOffline = false

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Braucht dich", Hive.need), (1, "Arbeitet", Hive.busy), (2, "Bereit", Hive.idle), (3, "Offline", Hive.off),
    ]

    var body: some View {
        Group {
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("hive läuft nicht", systemImage: "hexagon", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .background(Hive.bg)
    }

    private var board: some View {
        let labels = store.labels
        let all = store.sessions.map { ($0, Status($0)) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Self.sections, id: \.rank) { sec in
                    let items = sorted(all.filter { $0.1.rank == sec.rank }, rank: sec.rank, labels: labels)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(sec.title, items.count, sec.color, collapsible: sec.rank == 3)
                            if sec.rank != 3 || showOffline {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)],
                                          alignment: .leading, spacing: 12) {
                                    ForEach(items, id: \.0.name) { s, k in
                                        Tile(session: s, status: k, label: labels[s.groupKey] ?? s.groupKey,
                                             color: store.color(for: s.groupKey), inTmux: store.tmuxNames.contains(s.name),
                                             isSelected: s.name == selected, now: store.now)
                                            .onTapGesture { selected = s.name }
                                            .contextMenu {
                                                if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == s.groupKey }) {
                                                    Button("\(next) im selben Projekt starten") {
                                                        newPreset = NewSessionPreset(name: next, dir: s.cwd)
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 60)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name und Status
            HStack(spacing: 7) {
                Text(session.name).font(.hiveMono(15, .semibold)).lineLimit(1).fixedSize()
                if session.isPm == true {
                    Text("PM").font(.system(size: 10, weight: .bold)).foregroundStyle(Hive.muted).fixedSize()
                }
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
                .lineLimit(2, reservesSpace: true)

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
                if inTmux {
                    Image(systemName: "terminal").help("Läuft in der App")
                } else if session.alive == true && session.kind != "bg" {
                    Text("iTerm").fixedSize()
                }
            }
            .lineLimit(1)
            .font(.system(size: 11.5))
            .foregroundStyle(Hive.muted)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.rank == 0 ? status.color.opacity(0.06) : Color.clear)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Hive.ink : (status.rank == 0 ? status.color.opacity(0.5) : Hive.hair),
                              lineWidth: isSelected ? 2 : 1)
        )
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
