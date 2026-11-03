import HiveCore
import XCTest
@testable import VoiceKit

final class SentenceSplitterTests: XCTestCase {
    func testSplitsStreamedTextIntoSentences() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.feed("Drei Sessions arbei"), [])
        XCTAssertEqual(s.feed("ten gerade. Eine wartet "), ["Drei Sessions arbeiten gerade."])
        XCTAssertEqual(s.feed("auf dich!"), [])
        XCTAssertEqual(s.flush(), ["Eine wartet auf dich!"])
    }

    func testJoinsVeryShortPiecesWithTheNextSentence() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.feed("Ja. Das mache ich gleich. "), ["Ja. Das mache ich gleich."])
    }

    func testAbbreviationsAndNumbersAreNoSentenceEnd() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.feed("Das ist z. B. bei lu.01 so, seit dem 3. Mai. Weiter "), ["Das ist z. B. bei lu.01 so, seit dem 3. Mai."])
    }

    func testStripsMarkdown() {
        XCTAssertEqual(SentenceSplitter.speakable("- **lu.01** wartet"), "lu.01 wartet")
        XCTAssertNil(SentenceSplitter.speakable(" ** "))
    }
}

final class DirectiveTests: XCTestCase {
    func testParsesProposalAndHidesIt() {
        let (spoken, d) = Directives.parse("Ich würde lu.01 sagen, dass es pushen soll. Soll ich?\n[[send lu.01: Bitte jetzt pushen.]]")
        XCTAssertEqual(spoken, "Ich würde lu.01 sagen, dass es pushen soll. Soll ich?")
        XCTAssertEqual(d, [.propose(to: "lu.01", text: "Bitte jetzt pushen.")])
    }

    func testConfirmAndCancel() {
        XCTAssertEqual(Directives.parse("Mach ich.\n[[confirm]]").directives, [.confirm])
        XCTAssertEqual(Directives.parse("Gut, lasse ich.\n[[ cancel ]]").directives, [.cancel])
        XCTAssertEqual(Directives.parse("Kaputt [[send : x]]").directives, [])
    }

    func testSpokenFilterHoldsBackMarkersWhileStreaming() {
        var f = SpokenFilter()
        var out = f.feed("Soll ich? ")
        out += f.feed("[")
        out += f.feed("[send lu.01: x]]")
        out += f.finish()
        XCTAssertEqual(out, "Soll ich? ")
    }

    func testSingleBracketIsSpokenLater() {
        var f = SpokenFilter()
        XCTAssertEqual(f.feed("a ["), "a ")
        XCTAssertEqual(f.feed("1] b"), "[1] b")
    }
}

final class HandoffTests: XCTestCase {
    func testSendsOnlyAfterAConfirmInALaterAnswer() {
        var h = Handoff()
        XCTAssertNil(h.apply([.propose(to: "lu.01", text: "pushen")]))
        XCTAssertEqual(h.pending?.to, "lu.01")
        XCTAssertEqual(h.apply([.confirm]), .send(.init(to: "lu.01", text: "pushen")))
        XCTAssertNil(h.pending)
    }

    func testConfirmInTheSameAnswerDoesNotSend() {
        var h = Handoff()
        XCTAssertNil(h.apply([.propose(to: "lu.01", text: "pushen"), .confirm]))
        XCTAssertNotNil(h.pending)
    }

    func testConfirmWithoutProposalDoesNothing() {
        var h = Handoff()
        XCTAssertNil(h.apply([.confirm]))
    }

    func testCancelAndChangedProposal() {
        var h = Handoff()
        _ = h.apply([.propose(to: "lu.01", text: "a")])
        XCTAssertNil(h.apply([.propose(to: "lu.01", text: "b")]))
        XCTAssertNil(h.apply([.cancel, .confirm]))
        XCTAssertNil(h.pending)
    }
}

final class QuickReplyTests: XCTestCase {
    func testParsesReply() {
        XCTAssertEqual(Directives.parse("An or.pm: Ja. Schicke ich gleich.\n[[reply or.pm: Ja, releasen.]]").directives,
                       [.reply(to: "or.pm", text: "Ja, releasen.")])
    }

    func testShortReplyToAWaitingSessionGoesOutAfterTheCountdown() {
        var h = Handoff()
        XCTAssertEqual(h.apply([.reply(to: "or.pm", text: "Ja.")], waiting: ["or.pm"]), .countdown(.init(to: "or.pm", text: "Ja.")))
        XCTAssertNil(h.pending)
    }

    func testReplyToASessionThatDoesNotWaitNeedsAYes() {
        var h = Handoff()
        XCTAssertNil(h.apply([.reply(to: "lu.01", text: "Ja.")], waiting: ["or.pm"]))
        XCTAssertEqual(h.pending, .init(to: "lu.01", text: "Ja."))
    }

    func testLongReplyNeedsAYes() {
        var h = Handoff()
        let long = String(repeating: "a", count: Handoff.quickReplyLimit + 1)
        XCTAssertNil(h.apply([.reply(to: "or.pm", text: long)], waiting: ["or.pm"]))
        XCTAssertNotNil(h.pending)
    }
}

final class AttentionTests: XCTestCase {
    func testOnlyRunningSessionsThatNeedTheUser() {
        let waiting = Session(name: "or.pm", group: "orbit", alive: true, status: "waiting", waitingFor: "Release?")
        let busy = Session(name: "lu.01", group: "lumen", alive: true, status: "busy")
        let gone = Session(name: "fj.01", group: "fjord", alive: false, status: "waiting")
        XCTAssertEqual(Attention.needs([waiting, busy, gone]).mapValues(\.reason), ["or.pm": "Release?"])
    }
}

final class DialogReplyTests: XCTestCase {
    let approval = ScreenDialog.parse("""
    Bash command: git push
    ❯ 1. Yes
      2. Yes, and don't ask again for git push commands
      3. No, and tell Claude what to do differently (esc)
    """)!

    func testNumberSpokenYesAlwaysAndNo() {
        XCTAssertEqual(DialogReply.answer("1", in: approval), .option("Yes"))
        XCTAssertEqual(DialogReply.answer("Ja, erlaub das.", in: approval), .permission(.allow))
        XCTAssertEqual(DialogReply.answer("immer erlauben", in: approval), .permission(.alwaysAllow))
        XCTAssertEqual(DialogReply.answer("Nein, nicht pushen", in: approval), .permission(.deny))
        XCTAssertNil(DialogReply.answer("Frag später nochmal", in: approval))
        XCTAssertNil(DialogReply.answer("7", in: approval))
    }

    func testDescribe() {
        XCTAssertTrue(DialogReply.describe(approval).hasPrefix("1. Yes / 2. Yes, and don't ask again"))
    }
}

final class SpokenNamesTests: XCTestCase {
    let sessions = [
        Session(name: "lu.01", project: "lumen", group: "lumen"),
        Session(name: "lu.pm", project: "lumen", group: "lumen", isPm: true),
        Session(name: "or.12", project: "orbit", group: "orbit"),
        Session(name: "helper.02", project: "fjord", group: "fjord"),
        Session(name: "kiosk", project: "kiosk", group: "kiosk"),
    ]

    func testProjectNameAndNumberAsWords() {
        let n = SpokenNames(sessions)
        XCTAssertEqual(n.spoken["lu.01"], "Lumen eins")
        XCTAssertEqual(n.spoken["lu.pm"], "Lumen PM")
        XCTAssertEqual(n.spoken["or.12"], "Orbit zwölf")
        XCTAssertEqual(n.spoken["helper.02"], "Helper zwei")
        XCTAssertEqual(n.spoken["kiosk"], "kiosk")
        XCTAssertEqual(SpokenNames([Session(name: "ki.web-sync", group: "kiosk")]).spoken["ki.web-sync"], "ki web sync")
    }

    func testOwnNamesForPrefixOrWholeName() {
        let n = SpokenNames(sessions, overrides: ["lu": "Luna", "or.12": "die Zwölf"])
        XCTAssertEqual(n.spoken["lu.01"], "Luna eins")
        XCTAssertEqual(n.spoken["or.12"], "die Zwölf")
    }

    func testSoundalikesKeepTheirRealNames() {
        let n = SpokenNames([Session(name: "lu.01", project: "lumen", group: "lumen"),
                             Session(name: "lumen.01", project: "lumen", group: "lumen")])
        XCTAssertEqual(n.spoken["lu.01"], "lu.01")
        XCTAssertEqual(n.spoken["lumen.01"], "lumen.01")
    }

    func testReplacesNamesInASentence() {
        let n = SpokenNames(sessions)
        XCTAssertEqual(n.speakable("Lu.01 wartet, lu.pm auch. An or.12: Ja."), "Lumen eins wartet, Lumen PM auch. An Orbit zwölf: Ja.")
        XCTAssertEqual(n.speakable("Datei lu.01.txt bleibt"), "Datei lu.01.txt bleibt")
    }
}

final class StateSummaryTests: XCTestCase {
    func testAddsTheSpokenName() {
        let s = Session(name: "lu.01", project: "lumen", group: "lumen", alive: true, status: "idle")
        XCTAssertEqual(StateSummary.lines([s], names: SpokenNames([s])), "- lu.01 [project lumen] spoken \"Lumen eins\"; status: idle")
    }

    func testListsRunningSessionsAndOfflineNames() {
        let busy = Session(name: "lu.01", project: "lumen", group: "lumen", alive: true, status: "busy",
                           task: .init(text: "Login page", state: "working", updatedAt: nil, stale: false))
        let waiting = Session(name: "or.pm", project: "orbit", group: "orbit", isPm: true, alive: true, status: "waiting",
                              waitingFor: "Approve the release?", lastSentence: "Soll ich releasen?")
        let off = Session(name: "fj.02", group: "fjord", hasHandover: true)
        let text = StateSummary.lines([waiting, off, busy])
        XCTAssertEqual(text, """
        - lu.01 [project lumen]; status: busy; task: "Login page" (working)
        - or.pm [project orbit, PM]; status: waiting; waits for: Approve the release?; last said: "Soll ich releasen?"
        offline with handover: fj.02
        """)
    }
}
