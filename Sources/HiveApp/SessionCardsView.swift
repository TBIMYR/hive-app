import SwiftUI
import HiveCore

/// Ansicht „Cards“: Favoriten zuerst (ohne Überschrift), darunter Abschnitte nach Dringlichkeit wie im Dashboard,
/// große Karten mit dem Kasten „Now“ (letzter Arbeitsschritt, Frage oder letztes Ergebnis).
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
                     isFavorite: it.isFavorite,
                     canReply: it.status.rank == 0 && it.session.acceptsReply && store.tmux(it.session) != nil,
                     canAnswer: it.status.rank == 0 && !it.status.core.waitsAtStart && store.tmux(it.session) != nil) {
                    store.toggleFavorite(it.name)
                }
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
    /// Antwortfeld unten (nur „braucht dich“, in tmux und ohne offenen Auswahl-Dialog)
    var canReply = false
    /// Antwort-Knöpfe für Auswahlfrage oder Freigabe (nur „braucht dich“, in tmux, nicht beim Start)
    var canAnswer = false
    let toggleFavorite: () -> Void

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
                StarButton(isOn: isFavorite, toggle: toggleFavorite)
                    .padding(.trailing, -4)
            }

            let line = NowLine(session, rank: status.rank)
            // roter Grund nur, wenn der Kasten „Now“ nichts Besseres zeigt
            if line == nil, let why = status.why {
                Text(why).font(.system(size: 12.5, weight: .medium)).foregroundStyle(status.color).lineLimit(1)
            }

            // Aufgabe: grau, wenn sie deutlich älter ist als die letzte Aktivität
            let outdated = session.taskOutdated
            Text(session.task?.text ?? "No task line")
                .font(.system(size: 13.5, weight: session.task?.text == nil || outdated ? .medium : .semibold))
                .foregroundStyle(session.task?.text == nil || outdated ? Hive.muted : Hive.ink)
                .lineLimit(2)

            if let line {
                NowBox(line: line, tint: status.rank == 0 ? status.color : (isPm ? color : nil), now: now,
                       answerFor: canAnswer ? session : nil)
            }

            if canReply { ReplyField(session: session) }

            // Meta: Projekt · Branch, rechts wo die Session läuft
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                if let b = session.branch, b != "HEAD" {
                    Text("·")
                    Text(b).truncationMode(.middle)
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
            .padding(.top, 2)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.rank == 0 ? status.color.opacity(0.06) : (isPm ? color.opacity(0.07) : Color.clear))
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Hive.ink : (status.rank == 0 ? status.color.opacity(0.5) : (isPm ? color.opacity(0.35) : Hive.hair)),
                              lineWidth: isSelected ? 3 : 1)
        )
        .overlay { if status.rank == 1 && !isSelected { PulsingBorder(color: status.color) } }
        .opacity(status.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

/// Kasten „Now“: arbeitend der letzte Arbeitsschritt, wartend Freigabe oder Frage, bereit der letzte Satz.
/// Heller, halb durchsichtiger Grund mit feinem Rand, damit er auch auf getönten Karten (PM, wartend) ruhig wirkt.
struct NowBox: View {
    let line: NowLine
    /// Tönung der Karte (Statusfarbe wartend, Projektfarbe bei PMs), nil = neutral
    let tint: Color?
    let now: Date
    /// Session, die per Knopf geantwortet werden kann; nil = keine Knöpfe
    var answerFor: Session? = nil

    private var icon: String {
        switch line.kind {
        case .working: "gearshape"
        case .permission: "lock"
        case .question, .choice: "questionmark.bubble"
        case .done: "checkmark"
        }
    }

    /// Knöpfe statt Liste: Freigabe oder eine einzelne Frage ohne Mehrfachauswahl
    private var buttons: Bool {
        answerFor != nil && (line.kind == .permission || (line.kind == .choice && line.singleChoice))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Hive.ink2)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.text)
                    .font(.system(size: 13, weight: line.kind == .permission ? .semibold : .regular))
                    .foregroundStyle(Hive.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                let since = line.kind == .working ? dur(line.at, now: now) : ""
                if line.detail != nil || !since.isEmpty {
                    HStack(spacing: 5) {
                        if let d = line.detail { CodeChip(text: d) }
                        if !since.isEmpty { Text(line.detail == nil ? since : "· \(since)").fixedSize() }
                    }
                    .font(.system(size: 12)).foregroundStyle(Hive.muted).lineLimit(1)
                }
                if buttons, let s = answerFor {
                    AnswerButtons(session: s, line: line).padding(.top, 4)
                } else if line.kind == .choice {
                    ForEach(Array(line.options.enumerated()), id: \.offset) { i, o in
                        Text("\(i + 1) · \(o)").lineLimit(1)
                    }
                    .font(.system(size: 12)).foregroundStyle(Hive.muted)
                    Text("Answer in the terminal").font(.system(size: 12, weight: .medium)).foregroundStyle(Hive.ink2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Hive.card.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint?.opacity(0.22) ?? Hive.hair, lineWidth: 1))
    }
}

/// Antwort-Knöpfe im Kasten „Now“: je Option einer Auswahlfrage oder Allow/Always allow/Deny bei einer
/// Freigabe. Ein Klick prüft den Bildschirm und tippt die Ziffer (Tmux.answer); nie automatisch.
/// Gesperrt, solange in das Terminal dieser Session getippt wird.
struct AnswerButtons: View {
    @EnvironmentObject private var store: StateStore
    @ObservedObject private var activity = TerminalActivity.shared
    let session: Session
    let line: NowLine
    @State private var sending = false
    @State private var note: String?
    /// „Always allow“ steht auf dem Bildschirm (einmal gelesen, wenn die Freigabe erscheint)
    @State private var hasAlways = false

    private struct Choice: Identifiable {
        let id: String
        let answer: ScreenDialog.Answer
        let primary: Bool
    }

    private var choices: [Choice] {
        if line.kind == .permission {
            var c = [Choice(id: "Allow", answer: .permission(.allow), primary: true)]
            if hasAlways { c.append(Choice(id: "Always allow", answer: .permission(.alwaysAllow), primary: false)) }
            c.append(Choice(id: "Deny", answer: .permission(.deny), primary: false))
            return c
        }
        return line.options.map { Choice(id: $0, answer: .option($0), primary: false) }
    }

    private var typing: Bool { activity.typingIn != nil && activity.typingIn == store.tmux(session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(spacing: 6) {
                ForEach(choices) { c in
                    Button(c.id) { send(c.answer) }
                        .buttonStyle(AnswerButtonStyle(primary: c.primary))
                }
            }
            .disabled(sending || typing)
            .help(typing ? "You are typing in this terminal – wait a moment" : "")
            if let note {
                Text(note).font(.system(size: 11.5)).foregroundStyle(Hive.need).lineLimit(2)
            }
        }
        .task(id: line) {
            note = nil
            guard line.kind == .permission else { return }
            hasAlways = await store.dialog(session)?.permission(.alwaysAllow) != nil
        }
    }

    private func send(_ answer: ScreenDialog.Answer) {
        guard !sending else { return }
        sending = true
        note = nil
        Task {
            note = await store.answer(answer, known: line.options, to: session)
            sending = false
        }
    }
}

/// Kleiner Knopf im Hive-Stil: „Allow“ dunkel gefüllt, sonst hell mit Rand.
struct AnswerButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(primary ? Hive.card : Hive.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(primary ? Hive.ink : Hive.card)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(primary ? Color.clear : Hive.hair2, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Befehl oder Pfad in Schreibmaschinenschrift auf grauem Grund.
struct CodeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.hiveMono(12))
            .foregroundStyle(Hive.ink2)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Hive.hair)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Einzeiliges Antwortfeld in wartenden Karten: Enter tippt den Text per tmux in die Session.
/// Ein Klick ins Feld holt nur den Fokus; die Karte wird dabei nicht ausgewählt (sonst nähme
/// das Terminal der Auswahl den Fokus gleich wieder an sich).
struct ReplyField: View {
    @EnvironmentObject private var store: StateStore
    let session: Session
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("", text: $text, prompt: Text("Reply…").foregroundColor(Hive.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Hive.ink)
                .focused($focused)
                .disabled(sending)
                .onSubmit(send)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Hive.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Hive.hair2 : Hive.hair, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .onChange(of: text) { error = nil }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Hive.need).lineLimit(2)
            }
        }
    }

    private func send() {
        guard SessionControl.replyText(text) != nil, !sending else { return }
        sending = true
        let sent = text
        Task {
            if let e = await store.reply(sent, to: session) {
                error = "Not sent: \(e)"
            } else {
                text = ""
            }
            sending = false
            focused = true
        }
    }
}
