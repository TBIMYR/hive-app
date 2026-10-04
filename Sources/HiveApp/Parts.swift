import SwiftUI
import HiveCore

// MARK: Bausteine

/// Langsam pulsierender Rahmen für arbeitende Sessions; bei „Bewegung reduzieren“ ruhig.
struct PulsingBorder: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            shape(opacity: 0.6)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                // 2,4 s pro Atemzug, Deckkraft 0,2 … 0,85
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 2 * .pi / 2.4) + 1) / 2
                shape(opacity: 0.2 + 0.65 * phase)
            }
        }
    }

    private func shape(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(color.opacity(opacity), lineWidth: 2)
            .allowsHitTesting(false)
    }
}

struct Token: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.hiveMono(10.5, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}

/// Status als Punkt + Text; nur „braucht dich“ wird eine gefüllte Pille.
struct StatusLabel: View {
    let status: Status
    var since: String = ""

    var body: some View {
        let loud = status.rank == 0
        HStack(spacing: 5) {
            Circle().fill(loud ? Color.white : status.color).frame(width: 7, height: 7)
            Text(status.label).lineLimit(1).truncationMode(.tail)
            if !since.isEmpty { Text(since).foregroundStyle(loud ? Color.white.opacity(0.8) : Hive.muted).fixedSize() }
        }
        .font(.system(size: 12, weight: loud ? .semibold : .medium))
        .foregroundStyle(loud ? Color.white : Hive.ink2)
        .padding(.horizontal, loud ? 9 : 0).padding(.vertical, loud ? 3 : 0)
        .background(loud ? status.color : Color.clear)
        .clipShape(Capsule())
    }
}

/// Stern für Favoriten: gefüllt in Hive.ink, solange Favorit, sonst graue Kontur. Immer sichtbar, damit nichts hüpft.
/// Als Button fängt er den Klick ab, die Auswahl der Session (onTapGesture darunter) bleibt unberührt.
struct StarButton: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Hive.ink : Hive.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove from favorites" : "Favorite")
        .accessibilityLabel(isOn ? "Remove from favorites" : "Favorite")
    }
}

/// Eine Session mit allem, was die Ansichten zeigen; der Rahmen (OverviewView) berechnet das einmal je Durchlauf.
struct OverviewItem: Identifiable {
    let session: Session
    let status: Status
    /// Projektname (labels[groupKey] ?? groupKey)
    let project: String
    let color: Color
    let inTmux: Bool
    /// „<1 min“, „12 min“ seit dem letzten Statuswechsel, nur bei lebenden Sessions
    let since: String
    /// Favorit (Stern gefüllt, steht vorn)
    let isFavorite: Bool

    var id: String { session.id }
    var name: String { session.name }
}

/// Abschnittskopf: Punkt, Titel, Anzahl, Linie. Mit `expanded` einklappbar (Offline).
struct SectionHeader: View {
    let title: String
    let count: Int
    let color: Color
    var expanded: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
            Text("\(count)").font(.system(size: 13)).foregroundStyle(Hive.muted).monospacedDigit()
            if let expanded {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Hive.muted)
            }
            Rectangle().fill(Hive.hair).frame(height: 1).padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}

/// Signet von hive: eine Wabe (spitze Seite oben), wie das App-Symbol. Runde Ecken entstehen beim
/// Zeichnen durch eine zusätzliche Linie mit runder Verbindung.
struct HiveMark: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / sqrt(3), rect.height / 2)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<6 {
            let a = CGFloat.pi / 3 * CGFloat(i) - .pi / 2
            let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}
