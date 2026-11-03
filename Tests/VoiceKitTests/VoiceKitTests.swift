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
        XCTAssertEqual(h.apply([.confirm]), .init(to: "lu.01", text: "pushen"))
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

final class StateSummaryTests: XCTestCase {
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
