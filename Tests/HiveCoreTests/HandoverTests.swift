import Testing
@testable import HiveCore

@Test func frontmatterFelderUndBody() {
    let r = Handover.parseFrontmatter("---\na: 1\nb: x: y\n---\nbody\n")
    #expect(r.fields == ["a": "1", "b": "x: y"])
    #expect(r.body == "body\n")
}

@Test func ohneFrontmatterIstAllesBody() {
    let r = Handover.parseFrontmatter("# Nur Body\n")
    #expect(r.fields.isEmpty)
    #expect(r.body == "# Nur Body\n")
}

@Test func nichtGeschlossenesFrontmatterHatKeineFelder() {
    #expect(Handover.parseFrontmatter("---\nsession: x\n").fields.isEmpty)
}

@Test func ordnerWirdNachNameGelesen() {
    let m = Handover.readDir(fixture("handover"))
    let e = m["al.01"]
    #expect(e?.task == "Startseite Layout #12, PR offen")
    #expect(e?.state == "working")
    #expect(e?.updatedAt == "2026-09-30T16:09:00+02:00")
    #expect(e?.project == "alpha")
    #expect(m["archive"] == nil)
}

@Test func kaputteDateienHabenKeineAufgabeUndKeinenFehler() {
    let m = Handover.readDir(fixture("handover-broken"))
    #expect(m["kaputt"]?.task == nil)
    #expect(m["kaputt"]?.error == nil)
    #expect(m["nofm"]?.task == nil)
}

@Test func fehlenderOrdnerIstLeer() {
    #expect(Handover.readDir("/nonexistent").isEmpty)
}

@Test func textOhneFrontmatterFuerDieAnsicht() {
    #expect(Handover.body("al.01", dir: fixture("handover"))?.hasPrefix("# Handover al.01") == true)
    #expect(Handover.body("nofm", dir: fixture("handover-broken")) == "# Nur Body\n")
    #expect(Handover.body("gibtsnicht", dir: fixture("handover")) == nil)
    #expect(Handover.body("../handover/al.01", dir: fixture("handover")) == nil, "nur einfache Namen wie im Server")
}
