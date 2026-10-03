import SwiftUI
import UniformTypeIdentifiers
import HiveCore

/// Leiste „Pinned“ über der Übersicht: Klick wählt, Rechtsklick öffnet das Session-Menü, Ziehen ordnet um.
struct PinBar: View {
    @EnvironmentObject private var store: StateStore
    let items: [OverviewItem]
    @Binding var dragging: String?

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Text("Pinned")
                .textCase(.uppercase).kerning(0.6)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Hive.muted)
                .frame(height: 26)
            ForEach(items) { it in
                PinChip(item: it, isSelected: it.name == store.selected)
                    .onTapGesture { store.selected = it.name }
                    .contextMenu { SessionMenu(store: store, session: it.session) }
                    .onDrag {
                        dragging = it.name
                        return NSItemProvider(object: it.name as NSString)
                    }
                    .onDrop(of: [.text], delegate: PinDropDelegate(target: it.name, store: store, dragging: $dragging))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ein Pin: Status-Punkt, Name, Kurzstatus.
struct PinChip: View {
    let item: OverviewItem
    let isSelected: Bool

    var body: some View {
        let st = item.status
        let loud = st.rank == 0
        HStack(spacing: 6) {
            Circle().fill(st.color).frame(width: 8, height: 8)
            Text(item.name).font(.hiveMono(11.5, .medium)).foregroundStyle(Hive.ink)
            Text(st.label).font(.system(size: 11)).foregroundStyle(loud ? st.color : Hive.muted)
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(loud ? st.color.opacity(0.06) : Color.clear)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Hive.ink : (loud ? st.color.opacity(0.5) : Hive.hair), lineWidth: isSelected ? 2 : 1)
        )
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

/// Umordnen beim Ziehen: Schon beim Überfahren eines Pins rückt der gezogene an dessen Platz.
/// Den gezogenen Namen merkt sich `onDrag` in `dragging`; die Daten des NSItemProvider lassen sich während des
/// Ziehens nicht verlässlich lesen. Fremder Text (z. B. aus einer anderen App) hat kein `dragging` und wird abgelehnt.
struct PinDropDelegate: DropDelegate {
    let target: String
    let store: StateStore
    @Binding var dragging: String?

    func validateDrop(info: DropInfo) -> Bool { dragging.map(store.isPinned) == true }

    func dropEntered(info: DropInfo) {
        guard let name = dragging, store.isPinned(name) else { return }
        withAnimation(.easeOut(duration: 0.15)) { store.movePin(name, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Reiht Elemente nebeneinander und bricht in die nächste Zeile um, wenn die Breite nicht reicht.
/// Elemente einer Zeile stehen senkrecht mittig.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (offsets, _) = arrange(maxWidth: bounds.width, subviews: subviews)
        for (view, offset) in zip(subviews, offsets) {
            view.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var offsets: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        var rowStart = 0
        func finishRow(_ end: Int) {
            for i in rowStart..<end { offsets[i].y += (rowHeight - sizes[i].height) / 2 }
        }
        for (i, size) in sizes.enumerated() {
            if x > 0 && x + size.width > maxWidth {
                finishRow(i)
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
                rowStart = i
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        finishRow(sizes.count)
        return (offsets, CGSize(width: width, height: y + rowHeight))
    }
}
