import SwiftUI
import HiveCore

/// Übersicht: Abschnitte nach Dringlichkeit wie im Dashboard, aber ruhigere Karten und ohne Kopfleiste.
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Binding var selected: String?
    @Binding var newPreset: NewSessionPreset?
    @State private var showOffline = false

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Needs you", Hive.need), (1, "Working", Hive.busy), (2, "Ready", Hive.idle), (3, "Offline", Hive.off),
    ]

    var body: some View {
        Group {
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("No sessions readable", systemImage: "hexagon", description: Text(error))
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                ForEach(Self.sections, id: \.rank) { sec in
                    let items = SessionOrder.sorted(all.filter { $0.1.rank == sec.rank },
                                                    session: { $0.0 }, status: { $0.1.core }, labels: labels)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeader(sec.title, items.count, sec.color, collapsible: sec.rank == 3)
                            if sec.rank != 3 || showOffline {
                                grid(items, labels: labels)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func grid(_ items: [(Session, Status)], labels: [String: String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            ForEach(items, id: \.0.id) { s, k in
                Tile(session: s, status: k, label: labels[s.groupKey] ?? s.groupKey,
                     color: store.color(for: s.groupKey), inTmux: store.tmux(s) != nil,
                     isSelected: s.name == selected, now: store.now)
                    .onTapGesture { selected = s.name }
                    .contextMenu {
                        if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == s.groupKey }) {
                            Button("Start \(next) in the same project") {
                                newPreset = NewSessionPreset(name: next, dir: s.cwd)
                            }
                        }
                    }
            }
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
}

// MARK: Bausteine

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
    }

    /// Markdown der Antwort (fett, Code …) als formatierter Text statt mit Sternchen; Zeilenumbrüche raus.
    private func plain(_ s: String?) -> AttributedString? {
        guard let s, !s.isEmpty else { return nil }
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: flat, options: opts)) ?? AttributedString(flat)
    }
}
