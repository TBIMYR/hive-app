import SwiftUI
import HiveCore

/// Ansicht „List“: eine Zeile je Session ohne Abschnitte, Favoriten zuerst, Offline eingeklappt am Ende.
/// Worker stehen eingerückt unter ihrem PM (SessionTree), Favoriten, aktiv und offline je für sich.
/// ScrollView + LazyVStack statt List, damit Hintergründe, Auswahlrahmen und Kontextmenü wie in den Karten bleiben.
struct SessionListView: View {
    @EnvironmentObject private var store: StateStore
    /// Favoriten, schon sortiert (SessionOrder), auch offline
    let favorites: [OverviewItem]
    /// übrige Sessions, schon sortiert (SessionOrder), ohne Favoriten
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    var body: some View {
        // Favoriten und aktive je für sich gruppiert, aber eine durchgehende Streifenfolge
        let top = SessionTree.grouped(favorites, session: \.session)
            + SessionTree.grouped(items.filter { $0.status.rank < 3 }, session: \.session)
        let offline = SessionTree.grouped(items.filter { $0.status.rank == 3 }, session: \.session)
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(Array(top.enumerated()), id: \.element.item.id) { i, r in row(r, index: i) }
            if !offline.isEmpty {
                SectionHeader(title: "Offline", count: offline.count, color: Hive.off, expanded: $showOffline)
                    .padding(.top, 22).padding(.bottom, 8)
                if showOffline {
                    ForEach(Array(offline.enumerated()), id: \.element.item.id) { i, r in row(r, index: i) }
                }
            }
        }
    }

    private func row(_ r: SessionTree.Row<OverviewItem>, index: Int) -> some View {
        let it = r.item
        let indent: CGFloat = r.depth > 0 ? Self.indent : 0
        return SessionRow(item: it, isSelected: it.name == store.selected, striped: index.isMultiple(of: 2),
                          nameWidth: SessionRow.nameWidth - indent) { store.toggleFavorite(it.name) }
            .onTapGesture { store.selected = it.name }
            .contextMenu { SessionMenu(store: store, session: it.session) }
            .padding(.leading, indent)
            .background(alignment: .leading) {
                if r.depth > 0 {
                    TreeLine(isLast: r.isLastInGroup).stroke(Hive.hair2, lineWidth: 1.5).frame(width: indent)
                }
            }
    }

    /// Einrückung der Worker unter ihrem PM
    static let indent: CGFloat = 28
}

/// Feine Linie links von einem eingerückten Worker: senkrecht (beim letzten nur bis zur Mitte), dazu ein kurzer
/// waagrechter Strich zur Zeile. Ragt oben und unten um den Zeilenabstand hinaus, damit die Linie durchgeht.
private struct TreeLine: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + 13, gap: CGFloat = 4
        var p = Path()
        p.move(to: CGPoint(x: x, y: rect.minY - gap))
        p.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY + gap))
        p.move(to: CGPoint(x: x, y: rect.midY))
        p.addLine(to: CGPoint(x: x + 9, y: rect.midY))
        return p
    }
}

struct SessionRow: View {
    let item: OverviewItem
    let isSelected: Bool
    /// abwechselnder Hintergrund (jede zweite Zeile)
    let striped: Bool
    /// Breite der Namensspalte; eingerückte Zeilen bekommen sie um die Einrückung schmaler, damit die übrigen
    /// Spalten bündig bleiben
    var nameWidth: CGFloat = SessionRow.nameWidth
    let toggleFavorite: () -> Void
    @State private var hover = false

    static let nameWidth: CGFloat = 140

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        let task = item.session.task?.text
        HStack(spacing: 14) {
            Circle().fill(st.color).frame(width: 9, height: 9).frame(width: 14)
            Text(item.name).font(.hiveMono(14, .medium)).foregroundStyle(Hive.ink)
                .frame(width: nameWidth, alignment: .leading)
            Text(loud ? [st.label, st.why].compactMap { $0 }.joined(separator: " · ") : st.label)
                .font(.system(size: 12.5, weight: loud ? .semibold : .regular))
                .foregroundStyle(loud ? st.color : Hive.ink2)
                .frame(width: 210, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(item.color).frame(width: 6, height: 6)
                Text(task ?? "No task line").foregroundStyle(task == nil ? Hive.muted : Hive.ink2)
            }
            .help(item.project)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.since).font(.system(size: 12)).foregroundStyle(Hive.muted).monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            HeartButton(isOn: item.isFavorite, visible: hover, toggle: toggleFavorite)
                .padding(.leading, -4)
        }
        .font(.system(size: 13.5))
        .lineLimit(1).truncationMode(.tail)
        .padding(.horizontal, 14).padding(.vertical, 15)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(loud || striped ? Hive.card : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Hive.ink : Color.clear, lineWidth: 2))
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
