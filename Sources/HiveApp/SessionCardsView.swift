import SwiftUI
import HiveCore

/// Ansicht „Cards“: Favoriten zuerst (ohne Überschrift), darunter Abschnitte nach Dringlichkeit wie im Dashboard,
/// große Karten mit letzter Antwort.
struct SessionCardsView: View {
    @EnvironmentObject private var store: StateStore
    /// Favoriten, schon sortiert (SessionOrder), auch offline
    let favorites: [OverviewItem]
    /// übrige Sessions, schon sortiert (SessionOrder), ohne Favoriten
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Needs you", Hive.need), (1, "Working", Hive.busy), (2, "Ready", Hive.idle), (3, "Offline", Hive.off),
    ]

    var body: some View {
        // PMs stehen ohne eigenen Abschnitt bei den übrigen Karten; sie heben sich nur durch die Projektfarbe ab (Tile)
        VStack(alignment: .leading, spacing: 34) {
            if !favorites.isEmpty { grid(favorites) }
            ForEach(Self.sections, id: \.rank) { sec in
                let part = items.filter { $0.status.rank == sec.rank }
                if !part.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: sec.title, count: part.count, color: sec.color,
                                      expanded: sec.rank == 3 ? $showOffline : nil)
                        if sec.rank != 3 || showOffline { grid(part) }
                    }
                }
            }
        }
    }

    private func grid(_ part: [OverviewItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            ForEach(part) { it in
                Tile(session: it.session, status: it.status, label: it.project, color: it.color,
                     inTmux: it.inTmux, isSelected: it.name == store.selected, now: store.now,
                     isFavorite: it.isFavorite) { store.toggleFavorite(it.name) }
                    .onTapGesture { store.selected = it.name }
                    .contextMenu { SessionMenu(store: store, session: it.session) }
            }
        }
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
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    @State private var hover = false

    private var isPm: Bool { session.isPm == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name und Status
            HStack(spacing: 7) {
                if isPm { Token(text: session.abbr, color: color) }
                Text(session.name).font(.hiveMono(isPm ? 16 : 15, .semibold)).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                HeartButton(isOn: isFavorite, visible: hover, toggle: toggleFavorite)
                StatusLabel(status: status, since: session.alive == true ? dur(session.statusUpdatedAt, now: now) : "")
                    .layoutPriority(-1)
            }

            if let why = status.why {
                Text(why).font(.system(size: 12.5, weight: .medium)).foregroundStyle(status.color).lineLimit(1)
            }

            // Aufgabe
            Text(session.task?.text ?? "No task line")
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
                        .help("Read error: " + session.errors.joined(separator: "\n"))
                }
                if inTmux {
                    Image(systemName: "terminal").help("Runs in the app")
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
        .onHover { hover = $0 }
    }

    /// Markdown der Antwort (fett, Code …) als formatierter Text statt mit Sternchen; Zeilenumbrüche raus.
    private func plain(_ s: String?) -> AttributedString? {
        guard let s, !s.isEmpty else { return nil }
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: flat, options: opts)) ?? AttributedString(flat)
    }
}
