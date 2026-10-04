import Foundation
import Testing
@testable import HiveCore

// MARK: Hilfen für kleine Protokolle

private func json(_ o: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
}

private func toolUse(_ name: String, _ input: [String: Any], id: String = "t1", at: String = "2026-10-04T09:00:00.000Z") -> String {
    json(["type": "assistant", "timestamp": at,
          "message": ["role": "assistant", "content": [["type": "tool_use", "id": id, "name": name, "input": input]]]])
}

private func toolResult(_ id: String = "t1", at: String = "2026-10-04T09:00:05.000Z") -> String {
    json(["type": "user", "timestamp": at,
          "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]]])
}

private func said(_ text: String, at: String = "2026-10-04T08:59:00.000Z") -> String {
    json(["type": "assistant", "timestamp": at, "message": ["role": "assistant", "content": [["type": "text", "text": text]]]])
}

private func action(_ lines: String...) -> WorkAction? { Transcript.parseTail(lines.joined(separator: "\n")).lastAction }

// MARK: letzter Arbeitsschritt

@Test func bashMitBeschreibungZeigtBeschreibungUndBefehl() throws {
    let a = try #require(action(toolUse("Bash", ["command": "npm test -- pdf", "description": "Running tests"])))
    #expect(a.tool == "Bash")
    #expect(a.text == "Running tests")
    #expect(a.detail == "npm test -- pdf")
    #expect(a.at == "2026-10-04T09:00:00.000Z")
    #expect(a.pending)
}

@Test func bashOhneBeschreibungZeigtBefehlEinzeiligGekuerzt() throws {
    let long = "git -C ~/Development/lumen log --oneline\n  | head -20 " + String(repeating: "x", count: 120)
    let a = try #require(action(toolUse("Bash", ["command": long])))
    #expect(!a.text.contains("\n"))
    #expect(a.text.hasPrefix("git -C ~/Development/lumen log --oneline | head -20"))
    let d = try #require(a.detail)
    #expect(!d.contains("\n"))
    #expect(d.count <= 81)
    #expect(d.hasSuffix("…"))
}

@Test func toolResultBeendetPending() throws {
    let a = try #require(action(toolUse("Bash", ["command": "ls"]), toolResult()))
    #expect(a.pending == false)
}

@Test func fremdesToolResultBeendetPendingNicht() throws {
    let a = try #require(action(toolUse("Bash", ["command": "ls"], id: "t2"), toolResult("t1")))
    #expect(a.pending)
}

@Test func juengsterToolUseGewinnt() throws {
    let a = try #require(action(toolUse("Read", ["file_path": "/x/a.swift"], id: "t1"), toolResult("t1"),
                                toolUse("Edit", ["file_path": "/x/or/Kalender.swift"], id: "t2")))
    #expect(a.text == "Editing Kalender.swift")
    #expect(a.pending)
}

@Test func werkzeugeWerdenBeschrieben() {
    #expect(action(toolUse("Write", ["file_path": "/a/b/fj.md"]))?.text == "Editing fj.md")
    #expect(action(toolUse("MultiEdit", ["file_path": "/a/b/c.ts"]))?.text == "Editing c.ts")
    #expect(action(toolUse("NotebookEdit", ["notebook_path": "/a/n.ipynb"]))?.text == "Editing n.ipynb")
    #expect(action(toolUse("Read", ["file_path": "/a/b/lu.swift"]))?.text == "Reading lu.swift")
    #expect(action(toolUse("Grep", ["pattern": "TODO"]))?.text == "Searching TODO")
    #expect(action(toolUse("Glob", ["pattern": "**/*.swift"]))?.text == "Searching **/*.swift")
    #expect(action(toolUse("Task", ["description": "Find callers"]))?.text == "Running agent: Find callers")
    #expect(action(toolUse("Agent", ["description": "Review diff"]))?.text == "Running agent: Review diff")
    #expect(action(toolUse("WebFetch", ["url": "https://example.com/docs/a"]))?.text == "Browsing example.com")
    #expect(action(toolUse("WebSearch", ["query": "swift testing"]))?.text == "Browsing swift testing")
    #expect(action(toolUse("TodoWrite", ["todos": []]))?.text == "TodoWrite")
}

@Test func dateiwerkzeugeHabenDenPfadAlsDetail() {
    #expect(action(toolUse("Edit", ["file_path": "/a/b/c.ts"]))?.detail == "/a/b/c.ts")
}

@Test func askUserQuestionZeigtDieFrageUndOptionen() {
    let a = action(toolUse("AskUserQuestion", ["questions": [["question": "Push to stage?",
                                                             "options": [["label": "Yes", "description": "now"], ["label": "Later"]]]]]))
    #expect(a?.text == "Push to stage?")
    #expect(a?.options == ["Yes", "Later"])
    #expect(action(toolUse("Bash", ["command": "ls"]))?.options == nil)
}

@Test func ohneToolUseKeinArbeitsschritt() {
    #expect(action(said("Fertig.")) == nil)
}

// MARK: letzter Satz

private func sentence(_ text: String) -> String? { Transcript.parseTail(said(text)).lastSentence }

@Test func letzterSatzDesLetztenAbsatzes() {
    #expect(sentence("Erster Absatz. Mit zwei Sätzen.\n\nDer Export ist fertig. Er wartet auf fj.pm zur Durchsicht.")
            == "Er wartet auf fj.pm zur Durchsicht.")
}

@Test func markdownWirdEntfernt() {
    #expect(sentence("Alles gut.\n\n**Fertig:** `npm test` läuft *grün*.") == "Fertig: npm test läuft grün.")
    #expect(sentence("## Ergebnis\n\nSiehe [Doku](https://x.y/z) für mehr.") == "Siehe Doku für mehr.")
}

@Test func listeLiefertDenLetztenPunkt() {
    #expect(sentence("Offen:\n\n- Tests schreiben\n- Push an or.pm") == "Push an or.pm")
}

@Test func frageAmEnde() {
    #expect(sentence("Ich habe zwei Wege gefunden. Soll ich A nehmen, z. B. mit Cache?") == "Soll ich A nehmen, z. B. mit Cache?")
}

@Test func satzWirdGekuerzt() throws {
    let s = try #require(sentence(String(repeating: "lang ", count: 60) + "Ende."))
    #expect(s.count <= 141)
    #expect(s.hasSuffix("…"))
}

@Test func ohneTextKeinSatz() {
    #expect(Transcript.parseTail(toolUse("Bash", ["command": "ls"])).lastSentence == nil)
}

@Test func fixtureLiefertBeides() throws {
    let tail = Transcript.parseTail(try String(contentsOfFile: fixture("transcript.jsonl"), encoding: .utf8))
    #expect(tail.lastSentence == "Ich fange mit dem Layout an.")
    #expect(tail.lastAction?.text == "Bash")
    #expect(tail.lastAction?.pending == false)
}

// MARK: Now-Zeile

private func work(_ tool: String = "Bash", text: String = "Running tests", detail: String? = "npm test",
                  pending: Bool = false) -> WorkAction {
    WorkAction(tool: tool, text: text, detail: detail, at: "2026-10-04T09:00:00.000Z", pending: pending)
}

@Test func arbeitendZeigtDenArbeitsschritt() throws {
    let s = Session(name: "lu.03", group: "lu", alive: true, status: "busy", lastAction: work(), lastSentence: "Egal.")
    let n = try #require(NowLine(s, rank: 1))
    #expect(n.kind == .working)
    #expect(n.text == "Running tests")
    #expect(n.detail == "npm test")
    #expect(n.at == "2026-10-04T09:00:00.000Z")
}

@Test func arbeitendOhneArbeitsschrittKeinKasten() {
    #expect(NowLine(Session(name: "lu.03", group: "lu", status: "busy", lastSentence: "x"), rank: 1) == nil)
}

@Test func freigabeUeberWaitingFor() throws {
    let s = Session(name: "lu.01", group: "lu", alive: true, status: "waiting", waitingFor: "Permission prompt",
                    lastAction: work(text: "Pushing", detail: "git push origin feat/sort"), lastSentence: "Soll ich?")
    let n = try #require(NowLine(s, rank: 0))
    #expect(n.kind == .permission)
    #expect(n.text == "Allow Bash?")
    #expect(n.detail == "git push origin feat/sort")
}

@Test func freigabeUeberPending() throws {
    let s = Session(name: "lu.01", group: "lu", status: "waiting", lastAction: work("Edit", text: "Editing a.swift",
                    detail: "/x/a.swift", pending: true))
    #expect(NowLine(s, rank: 0)?.text == "Allow Edit?")
}

@Test func offeneAskUserQuestionIstEineFrageMitOptionen() throws {
    let ask = WorkAction(tool: "AskUserQuestion", text: "Push to stage?", detail: nil, at: nil, pending: true,
                         options: ["Yes", "Later"])
    let s = Session(name: "or.01", group: "or", status: "waiting", lastAction: ask, lastSentence: "Alt.")
    let n = try #require(NowLine(s, rank: 0))
    #expect(n.kind == .choice)
    #expect(n.text == "Push to stage?")
    #expect(n.options == ["Yes", "Later"])
}

// MARK: Antwortfeld

@Test func antwortfeldNurOhneOffenenWerkzeugaufrufUndOhneFreigabe() {
    #expect(Session(name: "or.01", group: "or", status: "waiting", waitingFor: "idle", lastAction: work()).acceptsReply)
    #expect(Session(name: "or.01", group: "or", status: "waiting").acceptsReply)
    #expect(!Session(name: "or.01", group: "or", status: "waiting", lastAction: work(pending: true)).acceptsReply)
    #expect(!Session(name: "or.01", group: "or", status: "waiting", waitingFor: "Permission prompt").acceptsReply)
}

@Test func wartendSonstMitLetztemSatz() throws {
    let s = Session(name: "or.01", group: "or", status: "waiting", waitingFor: "idle", lastAction: work(),
                    lastSentence: "Soll ich pushen?")
    let n = try #require(NowLine(s, rank: 0))
    #expect(n.kind == .question)
    #expect(n.text == "Soll ich pushen?")
    #expect(NowLine(Session(name: "or.01", group: "or", status: "waiting"), rank: 0) == nil)
}

@Test func bereitMitLetztemSatzSonstNichts() {
    let s = Session(name: "fj.01", group: "fj", alive: true, status: "idle", lastAction: work(), lastSentence: "Export fertig.")
    #expect(NowLine(s, rank: 2) == NowLine(kind: .done, text: "Export fertig.", detail: nil, at: nil))
    #expect(NowLine(Session(name: "fj.01", group: "fj", status: "idle", lastAction: work()), rank: 2) == nil)
}

// MARK: veraltete Aufgaben-Zeile

private func task(_ at: String?) -> Session.TaskLine { .init(text: "Kalender", state: "working", updatedAt: at, stale: false) }

@Test func aufgabeVeraltetWennZweiStundenAelterAlsLetzteAktivitaet() {
    let old = Session(name: "fj.01", group: "fj", statusUpdatedAt: "2026-10-04T08:00:00Z", task: task("2026-10-04T05:00:00Z"))
    #expect(old.taskOutdated)
    let fresh = Session(name: "fj.01", group: "fj", statusUpdatedAt: "2026-10-04T08:00:00Z", task: task("2026-10-04T07:00:00Z"))
    #expect(!fresh.taskOutdated)
    let byAction = Session(name: "fj.01", group: "fj", statusUpdatedAt: "2026-10-04T06:00:00Z", task: task("2026-10-04T05:00:00Z"),
                           lastAction: work())
    #expect(byAction.taskOutdated, "lastAction 09:00 ist mehr als 2 h nach 05:00")
    #expect(!Session(name: "fj.01", group: "fj", task: task("2026-10-04T05:00:00Z")).taskOutdated)
    #expect(!Session(name: "fj.01", group: "fj", statusUpdatedAt: "2026-10-04T08:00:00Z", task: task(nil)).taskOutdated)
}

// MARK: Antwort-Knöpfe

@Test func askUserQuestionMerktSichAnzahlDerFragenUndMultiSelect() throws {
    let one = try #require(action(toolUse("AskUserQuestion", ["questions": [["question": "Push?", "multiSelect": false,
                                                                           "options": [["label": "Yes"], ["label": "No"]]]]])))
    #expect(one.questionCount == 1)
    #expect(one.multiSelect == false)
    let multi = try #require(action(toolUse("AskUserQuestion", ["questions": [["question": "Which?", "multiSelect": true,
                                                                             "options": [["label": "A"], ["label": "B"]]]]])))
    #expect(multi.multiSelect == true)
    let two = try #require(action(toolUse("AskUserQuestion", ["questions": [["question": "A?", "options": [["label": "x"]]],
                                                                           ["question": "B?", "options": [["label": "y"]]]]])))
    #expect(two.questionCount == 2)
}

@Test func knoepfeNurBeiGenauEinerFrageOhneMultiSelect() {
    func line(count: Int?, multi: Bool?) -> NowLine? {
        let ask = WorkAction(tool: "AskUserQuestion", text: "Push?", detail: nil, at: nil, pending: true,
                             options: ["Yes", "Later"], questionCount: count, multiSelect: multi)
        return NowLine(Session(name: "or.01", group: "or", status: "waiting", lastAction: ask), rank: 0)
    }
    #expect(line(count: 1, multi: false)?.singleChoice == true)
    #expect(line(count: 1, multi: nil)?.singleChoice == true)
    #expect(line(count: 1, multi: true)?.singleChoice == false)
    #expect(line(count: 2, multi: false)?.singleChoice == false)
    // altes Protokoll ohne Anzahl: lieber keine Knöpfe
    #expect(line(count: nil, multi: nil)?.singleChoice == false)
}
