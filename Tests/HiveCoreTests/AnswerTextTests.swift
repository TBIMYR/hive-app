import Testing
@testable import HiveCore

@Test func answerSplitsIntoHeadingsParagraphsItemsAndCode() {
    let text = """
    ## Result
    All tests pass. The grid
    shrinks again.

    1. Cards: slim with the terminal
       on screen.
    2. Voice: every reply goes out.
      - also in the broadcast field

    ```
    swift test
    ```
    | Session | State |
    |---|---|
    | lu.01 | done |
    """
    #expect(AnswerText.blocks(text) == [
        .heading("Result"),
        .paragraph("All tests pass. The grid shrinks again."),
        .item(marker: "1", text: "Cards: slim with the terminal on screen.", depth: 0),
        .item(marker: "2", text: "Voice: every reply goes out.", depth: 0),
        .item(marker: "•", text: "also in the broadcast field", depth: 1),
        .code("swift test"),
        .code("| Session | State |\n|---|---|\n| lu.01 | done |"),
    ])
}

@Test func anUnclosedCodeBlockKeepsItsLines() {
    #expect(AnswerText.blocks("Run:\n```\nmake") == [.paragraph("Run:"), .code("make")])
}
