import Testing
@testable import HiveCore

@Suite struct QuestionTextTests {
    @Test func listLinesBecomeItemsAndTheQuestionStandsApart() {
        let text = """
        The whole concept is drawn: 32 frames.
        My plan in three stages:
        1 Agenda: overview, first start.
        2. Notes: one text field per item.
        - Sharing
        Every stage brings its migration. Agreed?
        """
        #expect(QuestionText.blocks(text) == [
            .paragraph("The whole concept is drawn: 32 frames. My plan in three stages:"),
            .item(marker: "1", title: "Agenda:", text: "overview, first start."),
            .item(marker: "2", title: "Notes:", text: "one text field per item."),
            .item(marker: "•", title: nil, text: "Sharing"),
            .paragraph("Every stage brings its migration."),
            .ask("Agreed?"),
        ])
    }

    @Test func inlineNumbersInOneParagraphBecomeItems() {
        let text = "Found 3 bugs: (1) the rule fails, (2) the old tab opens, and (3) the label is missing in old years. "
            + "Six layout points come on top. How to go on?"
        #expect(QuestionText.blocks(text) == [
            .paragraph("Found 3 bugs:"),
            .item(marker: "1", title: nil, text: "the rule fails"),
            .item(marker: "2", title: nil, text: "the old tab opens"),
            .item(marker: "3", title: nil, text: "the label is missing in old years."),
            .paragraph("Six layout points come on top."),
            .ask("How to go on?"),
        ])
    }

    @Test func plainTextStaysOneParagraph() {
        #expect(QuestionText.blocks("Should lu.01 push now (1 commit)?") == [.ask("Should lu.01 push now (1 commit)?")])
        #expect(QuestionText.blocks("Done. Version 2 is live.") == [.paragraph("Done. Version 2 is live.")])
    }
}
