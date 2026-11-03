import Foundation

/// Claude as one long-running `claude -p` process in stream-json mode: it starts once,
/// keeps the conversation and streams every answer token by token. Uses the normal Claude login, no API key.
@MainActor
final class Brain {
    private let model: String
    private var process: Process?
    private var stdin: FileHandle?
    private var lineBuffer = Data()
    private var onDelta: ((String) -> Void)?
    private var onDone: ((String) -> Void)?
    private var answer = ""

    init(model: String) { self.model = model }

    static let systemPrompt = """
    You are the voice of Hive, a Mac app that watches the user's Claude Code sessions. The user talks to you \
    by voice, in German, and hears your answer read aloud.

    How to answer:
    - Always in German, spoken style: usually one to three short sentences. No lists, no Markdown, no emoji, no URLs.
    - Say what matters first. Do not read out the whole state; summarise ("Drei Sessions arbeiten, eine wartet auf dich").
    - Session names like "lu.01" may be written as they are.
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
    These markers are never read aloud. Never claim a message was sent; the app reports that itself in the next turn as
    [HIVE] lines.
    """

    func start() {
        guard process == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["claude", "-p", "--model", model,
                       "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages", "--no-session-persistence",
                       "--setting-sources", "", "--strict-mcp-config", "--tools", "",
                       "--system-prompt", Self.systemPrompt]
        // a neutral folder, so no project's CLAUDE.md is read
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":" + NSString(string: "~/.npm-global/bin:~/.local/bin").expandingTildeInPath
            + ":/opt/homebrew/bin:/usr/local/bin"
        p.environment = env
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
                log("claude exited (\(proc.terminationStatus)), restarting with the next question")
                self?.process = nil
                self?.finish()
            }
        }
        do { try p.run() } catch { log("could not start claude: \(error.localizedDescription)"); return }
        process = p
        stdin = input.fileHandleForWriting
        log("claude started (\(model))")
    }

    /// Sends one turn; `delta` gets the text as it streams, `done` the whole answer.
    func ask(_ text: String, delta: @escaping (String) -> Void, done: @escaping (String) -> Void) {
        start()
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
