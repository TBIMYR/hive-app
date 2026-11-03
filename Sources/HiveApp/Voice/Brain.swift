import Foundation
import HiveCore

/// Claude as one long-running `claude -p` process in stream-json mode: it starts once,
/// keeps the conversation and streams every answer token by token. Uses the normal Claude login, no API key.
/// After `idleAfter` without a question it quits; the next question starts it again (and the conversation anew).
@MainActor
final class Brain {
    static let idleAfter: TimeInterval = 10 * 60
    private var process: Process?
    private var idleTimer: Timer?
    private var stdin: FileHandle?
    private var lineBuffer = Data()
    private var onDelta: ((String) -> Void)?
    private var onDone: ((String) -> Void)?
    private var answer = ""

    init() {}

    static let systemPrompt = """
    You are the voice of Hive, a Mac app that watches the user's Claude Code sessions. The user talks to you \
    by voice, in German, and hears your answer read aloud.

    How to answer:
    - Always in German, and talk like a relaxed colleague at the next desk, not like a news anchor or a report:
      casual everyday German with "du", contractions and short half sentences ("Okay, kurz:", "Läuft.", "Klar, mach ich.",
      "gibt's", "hab", "'ne", "grad"). Usually one or two short sentences. No lists, no Markdown, no emoji, no URLs.
    - Say what matters first, then stop. Do not read out the whole state; summarise loosely ("Drei sind grad dran,
      und Lumen eins will was von dir."). Drop details the user did not ask for; they can ask.
    - No stiff phrases like "Ich würde … schreiben", "Möchtest du, dass …", "Bezüglich"; say it the short way
      ("Soll ich Lumen eins sagen, dass es pushen soll?").
    - Write session names as they are ("lu.01"); the app reads them aloud in their spoken form. The state lists that
      form (spoken "Lumen eins"); the user says it, and "Lumen eins" means lu.01. In markers always use the real name.
    - If something is unclear, ask one short question back.

    Every user turn starts with a block [HIVE STATE] listing the running sessions: name, project, status
    (busy = working, idle, waiting = waits for the user), the task line with its state (working, blocked, waiting, done)
    and the last thing the session said. Only state what is there; if you do not know, say so.

    Passing a task on: you can send a message to a running session, as if the user typed it there. Never send without
    the user's explicit yes:
    1. Say in one sentence to whom you would send what and ask "Soll ich das schicken?". Put on a separate last line:
       [[send <session name>: <the exact message, in German, self-contained, written as an instruction to that session>]]
    2. Only in a later turn, when the user clearly agrees, answer very briefly (e.g. "Mach ich.") and put [[confirm]]
       on the last line. If the user declines, put [[cancel]]. If they want changes, make a new [[send …]] proposal.
    Quick reply: when a session waits for the user (status waiting or blocked) and the user gives a short answer to its
    question, do not ask back. Say whom it goes to and what, e.g. "An or.pm: Ja, releasen. Schicke ich gleich.", and put
    [[reply <session name>: <the answer as the user would type it>]] on the last line. The app waits a moment after
    reading it out, so the user can still stop it. A reply without a session name means the session in [HIVE] focus.
    Anything longer or new (a task, not an answer) goes through [[send …]] with a yes.
    If [HIVE] says the session shows a choice dialog, the reply text is the option number (e.g. [[reply lu.02: 1]])
    and you say which option you pick ("An lu.02: Ja, einmal erlauben."). Never pick an option that allows
    something permanently unless the user said so.

    Hive also speaks up by itself: a turn with [HIVE EVENT] instead of [USER] means a session just started needing the
    user. Then tell the user briefly who needs them and for what, in your own words.

    These markers are never read aloud. Never claim a message was sent; the app reports that itself in the next turn as
    [HIVE] lines.
    """

    /// The login PATH often lacks it (npm puts it in a folder that only .zshrc adds), so also the usual places.
    static let claudePath: String? = {
        let usual = ["~/.npm-global/bin", "~/.local/bin", "~/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
            .map { NSString(string: $0).expandingTildeInPath }.joined(separator: ":")
        return LoginShell.findExecutable("claude", path: [LoginShell.path ?? "", usual].joined(separator: ":"))
    }()

    func start() {
        guard process == nil else { return }
        let model = VoiceSettings.model
        guard let claude = Self.claudePath else {
            voiceLog("claude not found in the login PATH")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["-p", "--model", model,
                       "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages", "--no-session-persistence",
                       "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                       "--system-prompt", Self.systemPrompt]
        // a neutral folder, so no project's CLAUDE.md is read
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        p.environment = Tmux.environment()
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            Task { @MainActor in self?.receive(data) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                voiceLog("claude exited (\(proc.terminationStatus))")
                self?.process = nil
                self?.stdin = nil
                self?.finish()
            }
        }
        do { try p.run() } catch { voiceLog("could not start claude: \(error.localizedDescription)"); return }
        process = p
        stdin = input.fileHandleForWriting
        voiceLog("claude started (\(model))")
    }

    /// Quits the process (voice turned off, model changed, or idle for a while).
    func stop() {
        idleTimer?.invalidate()
        process?.terminate()
    }

    /// Sends one turn; `delta` gets the text as it streams, `done` the whole answer.
    func ask(_ text: String, delta: @escaping (String) -> Void, done: @escaping (String) -> Void) {
        start()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in if self?.isBusy == false { self?.stop() } }
        }
        onDelta = delta
        onDone = done
        answer = ""
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        stdin?.write(data + Data("\n".utf8))
    }

    var isBusy: Bool { onDone != nil }

    private func receive(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<nl]
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj)
        }
    }

    private func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "stream_event":
            guard let ev = m["event"] as? [String: Any], ev["type"] as? String == "content_block_delta",
                  let d = ev["delta"] as? [String: Any], let t = d["text"] as? String else { return }
            answer += t
            onDelta?(t)
        case "result":
            if answer.isEmpty, let r = m["result"] as? String { answer = r }
            finish()
        default: break
        }
    }

    private func finish() {
        let done = onDone
        onDone = nil
        onDelta = nil
        done?(answer)
    }
}
