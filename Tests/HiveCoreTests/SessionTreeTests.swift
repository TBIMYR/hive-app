import Testing
@testable import HiveCore

private func s(_ name: String, group: String, isPm: Bool = false) -> Session {
    Session(name: name, group: group, isPm: isPm)
}

/// Zeilen als „name/tiefe“, letzte Zeile einer Gruppe mit „*“
private func tree(_ items: [Session]) -> [String] {
    SessionTree.grouped(items, session: { $0 }).map {
        "\($0.item.name)/\($0.depth)" + ($0.isLastInGroup ? "*" : "")
    }
}

@Test func treeGruppeFolgtDemDringendstenMitglied() {
    // schon sortiert: wartender Worker lu.01 vorn, PM lu.pm weiter hinten
    let items = [s("lu.01", group: "lu"), s("or.pm", group: "or", isPm: true), s("lu.pm", group: "lu", isPm: true),
                 s("or.01", group: "or"), s("lu.02", group: "lu")]
    #expect(tree(items) == ["lu.pm/0", "lu.01/1", "lu.02/1*", "or.pm/0", "or.01/1*"])
}

@Test func treeWorkerInEingabereihenfolge() {
    let items = [s("lu.pm", group: "lu", isPm: true), s("lu.03", group: "lu"), s("lu.01", group: "lu"),
                 s("lu.02", group: "lu")]
    #expect(tree(items) == ["lu.pm/0", "lu.03/1", "lu.01/1", "lu.02/1*"])
}

@Test func treeOhnePmFlach() {
    let items = [s("fj.02", group: "fj"), s("lu.pm", group: "lu", isPm: true), s("fj.01", group: "fj"),
                 s("keeper", group: "")]
    #expect(tree(items) == ["fj.02/0*", "lu.pm/0*", "fj.01/0*", "keeper/0*"])
}

@Test func treeMehrerePmsErsterIstKopf() {
    let items = [s("lu.01", group: "lu"), s("lu.pm2", group: "lu", isPm: true), s("lu.pm", group: "lu", isPm: true)]
    #expect(tree(items) == ["lu.pm2/0", "lu.01/1", "lu.pm/1*"])
}

@Test func treePmAlleinIstLetzter() {
    #expect(tree([s("or.pm", group: "or", isPm: true)]) == ["or.pm/0*"])
}

@Test func treeLeer() {
    #expect(tree([]).isEmpty)
}
