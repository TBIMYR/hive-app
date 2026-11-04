import Foundation
import HiveCore
import SwiftUI
import VoiceKit

/// The broadcast field: the user types one message ("lu.pm and or.pm should check their tickets", "all PMs: …"),
/// a `claude -p` of its own (keeper.broadcast) finds the recipients and the message for each, and Hive types it
/// into those sessions. Same rule as the voice: clear, short ones go out at once, the rest waits for a click.
@MainActor
final class BroadcastController: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let to: String
        let text: String
        var failure: String?
    }

    @Published var open = false
    @Published private(set) var thinking = false
    /// what keeper.broadcast says to the user (a question back, why it asks first); empty in plain cases
    @Published private(set) var reply = ""
    /// who got what, from the last message
    @Published private(set) var sent: [Line] = []
    /// waiting for Send or Cancel
    @Published private(set) var asking: [Handoff.Message] = []

    private unowned let store: StateStore
    private let brain = Brain(name: Brain.broadcastName, systemPrompt: BroadcastController.prompt)
    private var notes: [String] = []

    init(store: StateStore) { self.store = store }

    /// starts claude ahead of the first message, so that one is quick too
    func warmUp() { brain.start() }

    func submit(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        if !asking.isEmpty {
            notes.append("the user did not send the waiting messages (\(asking.map(\.to).joined(separator: ", "))); dropped")
            asking = []
        }
        thinking = true
        reply = ""
        sent = []
        var prompt = "[HIVE STATE \(Date().formatted(date: .omitted, time: .shortened))]\n\(StateSummary.lines(store.displaySessions))\n"
        prompt += notes.map { "[HIVE] \($0)\n" }.joined()
        notes = []
        prompt += "\n[USER] \(text)"
        brain.ask(prompt, delta: { _ in }, done: { [weak self] in self?.answered($0) })
    }

    private func answered(_ full: String) {
        let (spoken, directives) = Directives.parse(full)
        voiceLog("broadcast: \(full.replacingOccurrences(of: "\n", with: " ⏎ "))")
        let reachable = Set(store.displaySessions.filter { store.tmux($0) != nil }.map(\.name))
        let plan = Broadcast.plan(directives, reachable: reachable)
        reply = full.isEmpty ? "No answer from Claude. Try again." : spoken
        asking = plan.ask
        Task {
            await deliver(plan.now)
            thinking = false
        }
    }

    func confirm() {
        let messages = asking
        asking = []
        Task { await deliver(messages) }
    }

    func cancel() {
        notes.append("the user did not send: \(asking.map { "\($0.to): \($0.text)" }.joined(separator: " | "))")
        asking = []
    }

    private func deliver(_ messages: [Handoff.Message]) async {
        for m in messages {
            var line = Line(to: m.to, text: m.text)
            line.failure = switch await store.deliver(m.text, to: m.to) {
            case nil: nil
            case .unknownSession: "no such session"
            case .notInHive: "not running in Hive"
            case .dialogChanged: "its dialog changed"
            case .noMatchingOption: "shows a choice, the text fits no option"
            case .typingFailed: "typing failed"
            }
            notes.append(line.failure.map { "sending to \(m.to) FAILED: \($0)" } ?? "delivered to \(m.to): \(m.text)")
            sent.append(line)
        }
    }

    static let prompt = """
    You are the broadcast field of Hive, a Mac app that watches the user's Claude Code sessions. The user types one \
    message, usually in German, for one or more sessions, e.g. "lu.pm und or.pm sollen ihre Tickets checken" or \
    "alle PMs: schreibt einen Handover". Find the recipients and the message for each, and pass it on.

    Every turn starts with [HIVE STATE]: the running sessions with name, project (PM marks a project's PM session),
    status, task line and what each said last. Recipients are named exactly as listed there. "alle PMs" means every
    session marked PM, "alle von Lumen" every session of that project, "alle" every running session. Only listed
    sessions can receive.

    One marker line per recipient, at the end:
    - [[reply <name>: <message>]] when it is clear who is meant and what to say, and the message is short and harmless
      (a check, "mach weiter", "schreib einen Handover", a small task). It goes out at once.
    - [[send <name>: <message>]] when the recipient or the meaning is unclear, the message is long or a bigger new task,
      or it is hard to undo (deleting, closing or restarting sessions, pushing, deploying, sending mail, spending
      money). The app shows it and the user clicks Send first.
    Write each message as the user would type it into that session: in the user's language, self-contained, without
    the list of recipients, addressed to that one session ("Bitte check deine Tickets."), not longer than what the user wrote. If a session shows a
    choice dialog, a number picks that option.

    Before the markers, at most one short line for the user, in their language, no Markdown: nothing at all in plain
    cases, and never remarks, opinions or small talk; why you ask first, if you use [[send]]; a short question back if you need more (then no markers). If no
    session fits, say so in one short line.

    [HIVE] lines report what happened to earlier messages. Never claim yourself that something was sent.
    """
}

/// The field behind the toolbar's megaphone (⌘B).
struct BroadcastPanel: View {
    @ObservedObject var broadcast: BroadcastController
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Broadcast").font(.headline)
            TextField("e.g. lu.pm and or.pm should check their tickets", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(3...8)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Hive.card))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focused ? Hive.ink.opacity(0.35) : Hive.hair))
                .focused($focused)
                .disabled(broadcast.thinking)
                .onSubmit { broadcast.submit(text); text = "" }
            if broadcast.thinking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working out who gets it…").foregroundStyle(.secondary)
                }
            }
            if !broadcast.reply.isEmpty {
                Text(broadcast.reply).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(broadcast.sent) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: line.failure == nil ? "checkmark" : "xmark")
                        .foregroundStyle(line.failure == nil ? Hive.busy : Hive.need)
                    Text(line.to).bold()
                    Text(line.failure.map { "not sent: \($0)" } ?? line.text)
                        .foregroundStyle(line.failure == nil ? Hive.ink : Hive.need)
                        .lineLimit(2)
                }
                .font(.body)
            }
            if !broadcast.asking.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(broadcast.asking, id: \.to) { m in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(m.to).bold()
                            Text(m.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { broadcast.cancel() }
                        Button("Send") { broadcast.confirm() }.keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 520)
        .onAppear {
            focused = true
            broadcast.warmUp()
        }
    }
}
