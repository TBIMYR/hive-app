import SwiftUI

/// Übersicht wie public/index.html: Kopf mit Status-Band und Projekten, darunter Abschnitte nach Dringlichkeit.
struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Binding var selected: String?
    @State private var newPreset: NewSessionPreset?
    @State private var only: Int?
    @State private var showOffline = false

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Braucht dich", Hive.need), (1, "Arbeitet", Hive.busy), (2, "Bereit", Hive.idle), (3, "Offline", Hive.off),
    ]

    private var all: [(s: Session, k: Status)] { store.sessions.map { ($0, Status($0)) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Hive.ink).frame(height: 1)
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("hive läuft nicht", systemImage: "hexagon", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .background(Hive.bg)
        .sheet(item: $newPreset) { preset in
            NewSessionSheet(preset: preset) { name in
                selected = name
                store.refreshSoon()
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        let labels = store.labels
        let count = { (r: Int) in all.filter { $0.k.rank == r }.count }
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Sessions").font(.system(size: 22, weight: .heavy)).tracking(-0.6)
                HStack(spacing: 0) {
                    segment(nil, "Alle", all.filter { $0.k.rank != 3 }.count, nil)
                    segment(0, "Braucht dich", count(0), Hive.need)
                    segment(1, "Arbeitet", count(1), Hive.busy)
                    segment(2, "Bereit", count(2), Hive.idle)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Hive.ink, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
                Button("Neue Session") { newPreset = NewSessionPreset() }
                    .disabled(Tmux.path == nil)
                    .help(Tmux.path == nil ? "tmux ist nicht installiert" : "claude -n in tmux starten")
            }
            .padding(.horizontal, 24).frame(height: 60)
            Rectangle().fill(Hive.hair).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Text("PROJEKTE").font(.system(size: 11, weight: .bold)).tracking(1.2)
                        .foregroundStyle(Hive.muted).padding(.trailing, 6)
                    ForEach(labels.sorted { $0.value.localizedCompare($1.value) == .orderedAscending }, id: \.key) { key, label in
                        projectChip(key: key, label: label)
                    }
                    let offline = count(3)
                    if offline > 0 {
                        Button("\(offline) offline \(showOffline ? "ausblenden" : "zeigen")") { showOffline.toggle() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(showOffline ? Hive.ink : Hive.muted).padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 44)
        }
        .background(Hive.card)
    }

    private func segment(_ rank: Int?, _ label: String, _ n: Int, _ c: Color?) -> some View {
        let on = only == rank
        let alarm = rank == 0 && n > 0
        let fg: Color = alarm ? .white : (on ? Hive.card : Hive.ink)
        return Button { only = rank } label: {
            HStack(spacing: 7) {
                if let c { Circle().fill(alarm ? .white : c).frame(width: 8, height: 8) }
                Text(label).font(.system(size: 13, weight: .semibold))
                Text("\(n)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(alarm ? Hive.need : (on ? Hive.ink : Color.clear))
            .overlay(alignment: .leading) { if rank != nil { Rectangle().fill(Hive.ink).frame(width: 1) } }
            .overlay { if alarm && on { Rectangle().strokeBorder(Hive.ink, lineWidth: 3) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectChip(key: String, label: String) -> some View {
        let members = store.sessions.filter { $0.groupKey == key }
        let live = members.filter { Status($0).rank != 3 || showOffline }.count
        let next = SessionNaming.nextName(in: members)
        return HStack(spacing: 6) {
            Token(text: members.first?.abbr ?? "?", color: store.color(for: key), large: false)
            Text(label).font(.system(size: 13, weight: .semibold))
            Text("\(live)").font(.system(size: 13)).foregroundStyle(Hive.muted).monospacedDigit()
            if let next {
                Button {
                    newPreset = NewSessionPreset(name: next, dir: SessionNaming.dir(for: next, in: members))
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Hive.soft).clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("\(next) in \(label) starten")
                .disabled(Tmux.path == nil)
            }
        }
        .padding(.leading, 5).padding(.trailing, 7).padding(.vertical, 4)
    }

    // MARK: Fläche

    private var board: some View {
        let labels = store.labels
        let shown = all.filter { x in
            (x.k.rank != 3 || showOffline) && (only == nil || x.k.rank == only)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(Self.sections, id: \.rank) { sec in
                    let items = sorted(shown.filter { $0.k.rank == sec.rank }, rank: sec.rank, labels: labels)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 9) {
                                Circle().fill(sec.color).frame(width: 9, height: 9)
                                Text(sec.title.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(1.4)
                                Text("\(items.count)").font(.hiveMono(11, .semibold)).foregroundStyle(Hive.muted)
                                Rectangle().fill(Hive.hair2).frame(height: 1)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)],
                                      alignment: .leading, spacing: 14) {
                                ForEach(items, id: \.s.name) { x in
                                    Tile(session: x.s, status: x.k, label: labels[x.s.groupKey] ?? x.s.groupKey,
                                         color: store.color(for: x.s.groupKey), inTmux: store.tmuxNames.contains(x.s.name),
                                         isSelected: x.s.name == selected, now: store.now)
                                        .onTapGesture { selected = x.s.name }
                                }
                            }
                        }
                    }
                }
                if shown.isEmpty {
                    Text("Keine Session passt zum Filter.").foregroundStyle(Hive.muted)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 60)
        }
    }

    /// Reihenfolge wie im Dashboard: „Braucht dich“ nach Wartezeit, sonst Rückmeldung zuerst, dann Projekt, PM, Name.
    private func sorted(_ items: [(s: Session, k: Status)], rank: Int, labels: [String: String]) -> [(s: Session, k: Status)] {
        items.sorted { a, b in
            if rank == 0 {
                return (a.s.statusUpdatedAt.flatMap(parseISO) ?? .distantPast) < (b.s.statusUpdatedAt.flatMap(parseISO) ?? .distantPast)
            }
            if (a.k.cls == "wait") != (b.k.cls == "wait") { return a.k.cls == "wait" }
            let la = labels[a.s.groupKey] ?? "", lb = labels[b.s.groupKey] ?? ""
            if la != lb { return la.localizedCompare(lb) == .orderedAscending }
            if (a.s.isPm == true) != (b.s.isPm == true) { return a.s.isPm == true }
            return a.s.name < b.s.name
        }
    }
}

// MARK: Bausteine

struct Token: View {
    let text: String
    let color: Color
    var large = true

    var body: some View {
        Text(text.uppercased())
            .font(.hiveMono(large ? 12 : 10.5, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 7 : 5)
            .frame(minWidth: large ? 30 : 22, minHeight: large ? 30 : 22)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: large ? 8 : 6))
    }
}

struct StatusPill: View {
    let status: Status
    var since: String = ""
    /// true: Text darf bei Platzmangel gekürzt werden (Dauer zuerst weg, dann „…“)
    var compressible = false

    var body: some View {
        let pill = HStack(spacing: 6) {
            Circle().fill(status.solid ? Color.white : status.color).frame(width: 7, height: 7)
            Text(status.label).font(.system(size: 12, weight: .bold)).truncationMode(.tail)
            if !since.isEmpty {
                Text(since).font(.system(size: 12)).opacity(0.8).monospacedDigit().fixedSize().layoutPriority(-1)
            }
        }
        .lineLimit(1)
        .foregroundStyle(status.solid ? Color.white : Hive.ink2)
        .padding(.horizontal, 10).frame(height: 26)
        .background(status.solid ? status.color : Hive.soft)
        .clipShape(Capsule())
        if compressible {
            ViewThatFits(in: .horizontal) {
                pill.fixedSize()
                StatusPill(status: status).fixedSize()   // ohne Dauer
                pill.frame(minWidth: 60)                 // notfalls gekürzt
            }
        } else {
            pill.fixedSize()
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

    private static let stateDE = ["working": "in Arbeit", "blocked": "blockiert", "waiting": "wartet",
                                  "done": "erledigt", "handover": "übergeben"]

    private var tint: Color {
        switch status.cls {
        case "need": Hive.need.opacity(0.07)
        case "block": Hive.block.opacity(0.08)
        default: .clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kopf
            // Kürzel, Name und Marken behalten ihre Breite; bei Platzmangel kürzt nur die Pille
            HStack(spacing: 9) {
                Token(text: session.abbr, color: color).fixedSize()
                Text(session.name).font(.hiveMono(17, .bold)).tracking(-0.3).lineLimit(1).fixedSize()
                if session.isPm == true { tag("PM", Hive.ink).fixedSize() }
                if session.kind == "bg" { tag("bg", Hive.block).fixedSize() }
                Spacer(minLength: 6)
                StatusPill(status: status, since: session.alive == true ? dur(session.statusUpdatedAt, now: now) : "",
                           compressible: true)
                    .layoutPriority(-1)
            }
            .padding(.horizontal, 16).padding(.top, 13)
            HStack(spacing: 5) {
                Text(label)
                if let b = session.branch, b != "HEAD" {
                    Text("·")
                    Text(b).font(.hiveMono(11)).truncationMode(.middle)
                }
            }
            .lineLimit(1)
            .font(.system(size: 12.5)).foregroundStyle(Hive.muted)
            .padding(.leading, 55).padding(.trailing, 16).padding(.top, 2)

            if let why = status.why {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(status.color).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16).padding(.top, 11)
            }

            // Inhalt
            VStack(alignment: .leading, spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        label("Aufgabe")
                        if let st = session.task?.state { chip(Self.stateDE[st] ?? st, st) }
                        if session.task?.stale == true { chip("älter als 1 h", "") }
                    }
                    if let t = session.task?.text {
                        Text(t).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Hive.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("noch keine Aufgaben-Zeile").font(.system(size: 13)).italic().foregroundStyle(Hive.muted)
                    }
                }
                if session.alive == true {
                    VStack(alignment: .leading, spacing: 3) {
                        label("Zuletzt")
                        Text(plain(session.lastAssistant?.text) ?? AttributedString("keine Antwort im sichtbaren Verlauf"))
                            .font(.system(size: 13)).lineSpacing(2)
                            .foregroundStyle(session.lastAssistant == nil ? Hive.muted : Hive.ink2)
                            .italic(session.lastAssistant == nil)
                            .lineLimit(3)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Fuß
            Rectangle().fill(Hive.hair).frame(height: 1)
            HStack(spacing: 10) {
                let when = session.lastAssistant?.at ?? session.task?.updatedAt
                Text(when.map { "letzte Antwort " + ago($0, now: now) } ?? "")
                Spacer()
                if inTmux {
                    Label("Terminal", systemImage: "terminal").foregroundStyle(Hive.ink2)
                } else if session.alive == true && session.kind != "bg" {
                    Text("läuft in iTerm").foregroundStyle(Hive.muted)
                }
            }
            .font(.system(size: 12)).foregroundStyle(Hive.muted)
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .background(tint)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Hive.ink : Hive.hair, lineWidth: isSelected ? 2 : 1)
        )
        .opacity(status.rank == 3 ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    /// Markdown der Antwort (fett, Code …) als formatierter Text statt mit Sternchen.
    private func plain(_ s: String?) -> AttributedString? {
        guard let s else { return nil }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t.uppercased()).font(.system(size: 9.5, weight: .heavy)).tracking(1)
            .foregroundStyle(c)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(c, lineWidth: 1.5))
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(1.3).foregroundStyle(Hive.muted)
    }

    private func chip(_ t: String, _ state: String) -> some View {
        let c: Color = switch state {
        case "blocked": Hive.block
        case "done": Hive.busy
        case "waiting": Hive.wait
        case "handover": Hive.ink
        default: Hive.ink2
        }
        return Text(t.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
            .foregroundStyle(c)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(state.isEmpty ? Hive.hair2 : c, lineWidth: 1))
    }
}
