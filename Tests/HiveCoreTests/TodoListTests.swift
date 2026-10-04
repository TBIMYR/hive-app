import Testing
@testable import HiveCore

private let sample = """
# Todo

Notizen von Mika.
- [ ] Freigabe klären
* [X] Kim anrufen
  - [x] eingerückt erledigt
-  [ ]   viele Leerzeichen
Schluss

"""

@Test func parstAufgabenUndUebergehtFremdeZeilen() {
    let list = TodoList.parse(sample)
    #expect(list.items.map(\.text) == ["Freigabe klären", "Kim anrufen", "eingerückt erledigt", "  viele Leerzeichen"])
    #expect(list.items.map(\.done) == [false, true, true, false])
}

@Test func keineAufgabenOhneKaestchen() {
    let list = TodoList.parse("- normaler Punkt\n[ ] ohne Strich\n-[ ] ohne Abstand\n")
    #expect(list.items.isEmpty)
}

@Test func rendertUnveraendertVerlustfrei() {
    #expect(TodoList.parse(sample).render() == sample)
    #expect(TodoList.parse("").render() == "")
    #expect(TodoList.parse("ohne Zeilenende").render() == "ohne Zeilenende")
}

@Test func offeneVorErledigtenSonstDateiReihenfolge() {
    let list = TodoList.parse("- [x] a\n- [ ] b\n- [x] c\n- [ ] d\n")
    #expect(list.open.map(\.text) == ["b", "d"])
    #expect(list.done.map(\.text) == ["a", "c"])
    #expect(list.ordered.map(\.text) == ["b", "d", "a", "c"])
}

@Test func idsSindEindeutigUndBleibenBeiAenderungen() {
    var list = TodoList.parse("- [ ] a\n- [ ] b\n")
    let ids = list.items.map(\.id)
    #expect(Set(ids).count == 2)
    let c = list.add("c")
    list.remove(ids[0])
    #expect(list.items.map(\.id) == [ids[1], c!])
    #expect(!ids.contains(c!))
}

@Test func hinzufuegenHinterDemLetztenEintrag() {
    var list = TodoList.parse("# Todo\n- [ ] a\n- [x] b\n\nFuß\n")
    list.add("neu")
    #expect(list.render() == "# Todo\n- [ ] a\n- [x] b\n- [ ] neu\n\nFuß\n")
    #expect(list.open.map(\.text) == ["a", "neu"])
}

@Test func hinzufuegenOhneEintraegeAnsEnde() {
    var empty = TodoList.parse("")
    empty.add("erste")
    #expect(empty.render() == "- [ ] erste\n")

    var head = TodoList.parse("# Todo\n")
    head.add("x")
    #expect(head.render() == "# Todo\n- [ ] x\n")

    var bare = TodoList.parse("# Todo")
    bare.add("x")
    #expect(bare.render() == "# Todo\n- [ ] x")
}

@Test func hinzufuegenIgnoriertLeerenTextUndGlaettetZeilenumbrueche() {
    var list = TodoList.parse("")
    #expect(list.add("   ") == nil)
    #expect(list.items.isEmpty)
    list.add("  zwei\nZeilen  ")
    #expect(list.items.map(\.text) == ["zwei Zeilen"])
}

@Test func abhakenUndWiederAufmachen() {
    var list = TodoList.parse("Kopf\n* [ ] a\n")
    let id = list.items[0].id
    list.toggle(id)
    #expect(list.render() == "Kopf\n* [x] a\n")
    list.toggle(id)
    #expect(list.render() == "Kopf\n* [ ] a\n")
}

@Test func abhakenBehaeltEinrueckung() {
    var list = TodoList.parse("  - [ ] a\n")
    list.toggle(list.items[0].id)
    #expect(list.render() == "  - [x] a\n")
}

@Test func bearbeitenAendertNurDenText() {
    var list = TodoList.parse("Kopf\n- [x] alt\nFuß")
    list.edit(list.items[0].id, "  neu  ")
    #expect(list.render() == "Kopf\n- [x] neu\nFuß")
}

@Test func bearbeitenMitLeeremTextLoescht() {
    var list = TodoList.parse("- [ ] a\n- [ ] b\n")
    list.edit(list.items[0].id, "  ")
    #expect(list.render() == "- [ ] b\n")
}

@Test func entfernenLaesstFremdeZeilenStehen() {
    var list = TodoList.parse("# T\n- [ ] a\ntext\n- [ ] b\n")
    list.remove(list.items[0].id)
    #expect(list.render() == "# T\ntext\n- [ ] b\n")
}

@Test func erledigteEntfernen() {
    var list = TodoList.parse("# T\n- [x] a\n- [ ] b\n* [X] c\n")
    list.clearDone()
    #expect(list.render() == "# T\n- [ ] b\n")
    #expect(list.done.isEmpty)
}

@Test func unbekannteIdAendertNichts() {
    var list = TodoList.parse("- [ ] a\n")
    list.toggle(999); list.edit(999, "x"); list.remove(999)
    #expect(list.render() == "- [ ] a\n")
}
