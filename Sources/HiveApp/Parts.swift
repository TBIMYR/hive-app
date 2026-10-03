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

/// Waben-Signet von hive (sieben Waben, spitze Seite oben), wie das App-Symbol und public/icons/hive.svg.
struct HiveMark: Shape {
    /// Mittelpunkte im 512er-Raster des Signets
    private static let centers: [CGPoint] = [
        CGPoint(x: 256, y: 256), CGPoint(x: 363.39, y: 256), CGPoint(x: 148.61, y: 256),
        CGPoint(x: 309.69, y: 349), CGPoint(x: 202.31, y: 349), CGPoint(x: 309.69, y: 163), CGPoint(x: 202.31, y: 163),
    ]

    func path(in rect: CGRect) -> Path {
        // Waben reichen von x 101…411 und y 109…403 (mit Rundung); auf das Rechteck einpassen
        let scale = min(rect.width / 310, rect.height / 294)
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for c in Self.centers {
            let p = CGPoint(x: mid.x + (c.x - 256) * scale, y: mid.y + (c.y - 256) * scale)
            let r = 50 * scale
            path.move(to: CGPoint(x: p.x, y: p.y - r))
            for i in 1..<6 {
                let a = CGFloat.pi / 3 * CGFloat(i) - .pi / 2
                path.addLine(to: CGPoint(x: p.x + r * cos(a), y: p.y + r * sin(a)))
            }
            path.closeSubpath()
        }
        return path
    }
}
