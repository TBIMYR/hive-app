import Testing
@testable import HiveCore

// Screens as `tmux capture-pane -p` delivers them (shortened)

private let ask = """
⏺ Ich habe den Export für lu.01 fertig. Zwei Punkte:
  1. Die Tabelle ist sortiert
  2. Der Kopf fehlt noch

────────────────────────────────────────
 ☐ Export

│ Soll ich den Export gleich nach stage pushen?

❯ 1. Ja, jetzt pushen
     Danach läuft der Build auf stage.
  2. Später
     Erst nach der Durchsicht durch lu.pm.
  3. Type something.
────────────────────────────────────────
  4. Chat about this

Enter to select · ↑/↓ to navigate · Esc to cancel
"""

private let bash = """
⏺ Bash(git push origin feat/sort)
  ⎿  Running…

────────────────────────────────────────
 Bash command

   git push origin feat/sort
   Push the branch for or.02

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for git push commands in /Users/x/Development/or
   3. No, and tell Claude what to do differently (esc)
"""

private let boxed = """
╭──────────────────────────────────────────╮
│ Edit file                                │
│ Do you want to make this edit to a.swift?│
│ ❯ 1. Yes                                 │
│   2. Yes, allow all edits during this session (shift+tab) │
│   3. No, and tell Claude what to do differently (esc)     │
╰──────────────────────────────────────────╯
"""

private let wrapped = """
│ Welche Variante für fj.01?

❯ 1. Die lange Variante mit allen Feldern und der zusätzlichen Spalte für
     Notizen
  2. Kurz
"""

@Test func parsesNumberedDialogOptions() throws {
    let d = try #require(ScreenDialog.parse(ask))
    #expect(d.options.map(\.number) == [1, 2, 3, 4])
    #expect(d.options.map(\.label) == ["Ja, jetzt pushen", "Später", "Type something.", "Chat about this"])
    #expect(d.options.map(\.selected) == [true, false, false, false])
}

@Test func numberedListInPrecedingTextDoesNotCount() throws {
    let d = try #require(ScreenDialog.parse(ask))
    #expect(!d.options.contains { $0.label == "Die Tabelle ist sortiert" })
}

@Test func noOptionsWithoutDialog() {
    #expect(ScreenDialog.parse("⏺ Fertig.\n  1. erstens\n\n> ") == nil)
    #expect(ScreenDialog.parse("") == nil)
    // a single line is not a dialog
    #expect(ScreenDialog.parse("❯ 1. Yes") == nil)
}

@Test func boxDrawingCharactersAreStripped() throws {
    let d = try #require(ScreenDialog.parse(boxed))
    #expect(d.options.map(\.label) == ["Yes", "Yes, allow all edits during this session (shift+tab)",
                                       "No, and tell Claude what to do differently (esc)"])
    #expect(d.options[0].selected)
}

@Test func findsOptionByItsText() throws {
    let d = try #require(ScreenDialog.parse(ask))
    #expect(d.option(labeled: "Später")?.number == 2)
    #expect(d.option(labeled: "  ja, jetzt pushen ")?.number == 1)
    // shortened from the transcript
    #expect(d.option(labeled: "Ja, jetzt pu…")?.number == 1)
    #expect(d.option(labeled: "Nie") == nil)
}

@Test func wrappedOptionMatchesByItsPrefix() throws {
    let d = try #require(ScreenDialog.parse(wrapped))
    let long = "Die lange Variante mit allen Feldern und der zusätzlichen Spalte für Notizen"
    #expect(d.option(labeled: long)?.number == 1)
}

@Test func ambiguousPrefixFindsNothing() throws {
    let d = try #require(ScreenDialog.parse("❯ 1. Ja, jetzt\n  2. Ja, später"))
    #expect(d.option(labeled: "Ja") == nil)
}

@Test func permissionMapsYesAndNo() throws {
    let d = try #require(ScreenDialog.parse(bash))
    #expect(d.permission(.allow)?.number == 1)
    #expect(d.permission(.alwaysAllow)?.number == 2)
    #expect(d.permission(.deny)?.number == 3)
    let e = try #require(ScreenDialog.parse(boxed))
    #expect(e.permission(.alwaysAllow)?.number == 2)
}

@Test func permissionWithoutAlwaysOption() throws {
    let d = try #require(ScreenDialog.parse(" Do you want to proceed?\n ❯ 1. Yes\n   2. No"))
    #expect(d.permission(.allow)?.number == 1)
    #expect(d.permission(.alwaysAllow) == nil)
    #expect(d.permission(.deny)?.number == 2)
}

@Test func choiceQuestionIsNotAPermissionPrompt() throws {
    let d = try #require(ScreenDialog.parse(ask))
    #expect(d.permission(.allow) == nil)
    #expect(d.permission(.deny) == nil)
}

@Test func sameDialogIsRecognizable() throws {
    let a = try #require(ScreenDialog.parse(bash))
    let moved = try #require(ScreenDialog.parse(bash.replacingOccurrences(of: " ❯ 1. Yes\n   2.", with: "   1. Yes\n ❯ 2.")))
    #expect(a.sameDialog(as: moved))
    #expect(moved.options[1].selected)
    let other = try #require(ScreenDialog.parse(bash.replacingOccurrences(of: "feat/sort", with: "main")))
    #expect(!a.sameDialog(as: other))
}

@Test func pickSelectsByAnswer() throws {
    #expect(ScreenDialog.pick(.option("Später"), on: ask)?.number == 2)
    #expect(ScreenDialog.pick(.permission(.deny), on: bash)?.number == 3)
    #expect(ScreenDialog.pick(.permission(.allow), on: ask) == nil)
    #expect(ScreenDialog.pick(.option("Später"), on: "⏺ Fertig.") == nil)
}

@Test func customInputInFreeTextOptionLocksSelection() throws {
    // someone is currently typing into "Type something": the selected option is none of the known ones
    let typing = ask.replacingOccurrences(of: "❯ 1. Ja", with: "  1. Ja")
        .replacingOccurrences(of: "  3. Type something.", with: "❯ 3. eigentlich lieber morgen")
    let d = try #require(ScreenDialog.parse(typing))
    #expect(d.selectionOutside(["Ja, jetzt pushen", "Später"]))
    #expect(try #require(ScreenDialog.parse(ask)).selectionOutside(["Ja, jetzt pushen", "Später"]) == false)
}

@Test func controlArguments() {
    #expect(SessionControl.captureArgs("lu.01") == ["capture-pane", "-p", "-t", "=lu.01:"])
    #expect(SessionControl.keyArgs("2", into: "lu.01") == ["send-keys", "-t", "=lu.01:", "2"])
}
