import Foundation
import HiveCore

/// Claude as one long-running `claude -p` process in stream-json mode: it starts once,
/// keeps the conversation and streams every answer token by token. Uses the normal Claude login, no API key.
/// After `idleAfter` without a question it quits; the next question starts it again (and the conversation anew).
@MainActor
final class Brain {
    static let idleAfter: TimeInterval = 10 * 60
    /// longest wait for one answer before claude is restarted
    static let turnTimeout: TimeInterval = 45
    /// process IDs of the running brain(s); Claude Code lists them in ~/.claude/sessions, Hive leaves them out
    static var ownPIDs: Set<Int> = []
    private var process: Process?
    private var idleTimer: Timer?
    private var turnTimer: Timer?
    private var stdin: FileHandle?
    private var lineBuffer = Data()
    private var onDelta: ((String) -> Void)?
    private var onDone: ((String) -> Void)?
    private var answer = ""

    /// the session name it registers under (`claude -n`); Hive leaves these out of its lists
    let name: String
    private let systemPrompt: String

    init(name: String, systemPrompt: String) {
        self.name = name
        self.systemPrompt = systemPrompt
    }

    static let voiceName = "keeper.voice"
    static let broadcastName = "keeper.broadcast"
    static let names: Set<String> = [voiceName, broadcastName]

    static let voicePrompt = """
    You are the voice of Hive, a Mac app that watches the user's Claude Code sessions. The user talks to you \
    by voice, in German, and hears your answer read aloud.

    How to answer:
    - Always in German, and talk like a relaxed colleague at the next desk, not like a news anchor or a report:
      casual everyday German with "du" and short sentences ("Läuft.", "Klar, mach ich.", "Drei sind gerade dran.").
      Usually one or two short sentences. No lists, no Markdown, no emoji, no URLs.
    - Everything is read aloud by a speech voice, so write words the way they are spoken in full: no apostrophe forms
      ("eine", "ein", "ob es", "gibt es", not "'ne", "'n", "ob's", "gibt's"), no colons, brackets, slashes, arrows,
      quotes or dashes as punctuation, no file names, paths, ticket numbers or version numbers. Say technical
      terms in plain German where you can ("Pull Request" rather than "PR", "Fehler" rather than "Bug"), numbers as
      you would say them, and complete sentences rather than fragments.
    - Say what matters first, then stop. Do not read out the whole state; summarise loosely ("Drei sind grad dran,
      und Lumen eins will was von dir."). Drop details the user did not ask for; they can ask.
    - Start as short as possible; the user asks for more if they want it. Only mention what is going on: sessions
      that work, wait for the user or just finished. Never list the ones that do nothing. If nothing runs in what
      was asked about, just say so ("Bei Lumen läuft grad nichts."). Name single sessions only when it is one or two.
    - No stiff phrases like "Ich würde … schreiben", "Möchtest du, dass …", "Bezüglich"; say it the short way
      ("Soll ich Lumen eins sagen, dass es pushen soll?").
    - Write session names as they are ("lu.01"); the app reads them aloud in their spoken form. The state lists that
      form (spoken "Lumen eins"); the user says it, and "Lumen eins" means lu.01. In markers always use the real name.
    - If something is unclear, ask one short question back.
    - You do not need the last word. When the user closes a topic ("schau ich mir selbst an", "kümmer mich drum",
      "passt", "danke", "später"), do not confirm it, repeat it or add advice: answer with only [[quiet]] (the app
      then says nothing and stops listening), or at most "Okay." If a proposal was waiting for a yes, add [[cancel]].

    Every user turn starts with a block [HIVE STATE] listing the running sessions: name, project, status
    (busy = working, idle, waiting = waits for the user), the task line with its state (working, blocked, waiting, done)
    and the last thing the session said. Only state what is there; if you do not know, say so.

    Passing something on: you can send a message to a running session, as if the user typed it there.
    Clear cases, just do it: when it is obvious which session is meant and what to say, and the message is short and
    harmless (an answer to its question, "mach weiter", "schreib einen Handover", a small task), do not ask back and do
    not repeat the message: say only "Okay, geht an Lumen eins." (or "Mach ich."), and put on a separate last line
    [[reply <session name>: <the message, in German, as the user would type it>]]. The app shows the text and waits a
    moment, so the user can still stop it. A message without a session name means the session in [HIVE] focus.
    Ask first only when the session or the content is unclear, the message is long or a bigger new task, or it is hard
    to undo (deleting, closing or restarting sessions, pushing, deploying, sending mail, spending money):
    1. Say briefly what you would send to whom and ask "Soll ich?". Put on a separate last line:
       [[send <session name>: <the exact message, in German, self-contained, written as an instruction to that session>]]
    2. Only in a later turn, when the user clearly agrees, answer very briefly (e.g. "Mach ich.") and put [[confirm]]
       on the last line. If the user declines, put [[cancel]]. If they want changes, make a new [[send …]] proposal.
    If [HIVE] says the session shows a choice dialog, the message is the option number (e.g. [[reply lu.02: 1]]);
    say the choice in two or three words ("Okay, einmal erlaubt."). Never pick an option that allows something
    permanently unless the user said so.

    Hive also speaks up by itself: a turn with [HIVE EVENT] instead of [USER] means a session just started needing the
    user, or just finished. Tell the user briefly who needs them and for what, or who is done and the gist, in your own
    words, the way a colleague would say it: what the session wants ("Orbit zwei will einen Testlauf starten, darf es?",
    "Lumen eins fragt, ob es weitermachen soll"), never technical labels like "Berechtigungs-Dialog", "Auswahl-Dialog"
    or "Permission". A plain "mach weiter" or a next step afterwards goes to the session in [HIVE] focus.

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
        p.arguments = ["-p", "-n", name, "--model", model,
                       "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages", "--no-session-persistence",
                       "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                       "--system-prompt", systemPrompt]
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
                voiceLog("claude \(self?.name ?? "") exited (\(proc.terminationStatus))")
                Self.ownPIDs.remove(Int(proc.processIdentifier))
                self?.process = nil
                self?.stdin = nil
                self?.finish()
            }
        }
        do { try p.run() } catch { voiceLog("could not start claude: \(error.localizedDescription)"); return }
        process = p
        let pid = Int(p.processIdentifier)
        Self.ownPIDs.insert(pid)
        stdin = input.fileHandleForWriting
        voiceLog("claude started as \(name) (\(model))")
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
        // claude did not start: end the turn at once instead of leaving the voice in "Thinking"
        guard let stdin, let data = try? JSONSerialization.data(withJSONObject: msg) else { finish(); return }
        stdin.write(data + Data("\n".utf8))
        // a hung claude ends the turn too (its termination calls finish)
        turnTimer?.invalidate()
        turnTimer = Timer.scheduledTimer(withTimeInterval: Self.turnTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBusy else { return }
                voiceLog("claude took longer than \(Int(Self.turnTimeout))s, restarting it")
                self.process?.terminate()
            }
        }
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
        turnTimer?.invalidate()
        let done = onDone
        onDone = nil
        onDelta = nil
        done?(answer)
    }
}
