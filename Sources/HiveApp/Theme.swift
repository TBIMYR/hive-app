import AppKit
import SwiftUI

/// Farben wie die Tokens in public/index.html (hell / dunkel).
enum Hive {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    static let bg = dyn(0xF6F6F5, 0x0A0A0A)
    static let card = dyn(0xFFFFFF, 0x141414)
    static let ink = dyn(0x0B0B0B, 0xF5F5F4)
    static let ink2 = dyn(0x3D3D3D, 0xC9C9C6)
    static let muted = dyn(0x8C8C8C, 0x7D7D79)
    static let hair = dyn(0xE6E6E4, 0x242423)
    static let hair2 = dyn(0xCFCFCC, 0x3A3A38)
    static let soft = dyn(0xEFEFED, 0x1D1D1C)

    static let need = Color(nsColor: NSColor(hex: 0xE5341F))
    static let block = Color(nsColor: NSColor(hex: 0xF08C00))
    static let busy = Color(nsColor: NSColor(hex: 0x12A150))
    static let wait = Color(nsColor: NSColor(hex: 0x8B5CF6))
    static let shell = Color(nsColor: NSColor(hex: 0x2F6FED))
    static let idle = dyn(0xB4B4B0, 0x5C5C59)
    static let off = dyn(0xD4D4D0, 0x333331)
    /// Herz der Favoriten: kräftiges Pink, bewusst nicht das Rot von „Needs you“
    static let favorite = Color(nsColor: NSColor(hex: 0xFF2D55))

    // Projektfarben: bewusst ohne Rot/Orange/Grün, damit sie nie wie ein Status aussehen
    static let palette: [UInt32] = [0x2F6FED, 0x8B3DFF, 0xE0319A, 0x0A9FB5, 0x1B1B1B,
                                    0x6D4AFF, 0xC026D3, 0x0F766E, 0x4F46E5, 0x7C5C3B]

    static let mono = "SF Mono"
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    static func hiveMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// „<1 min“, „12 min“, „3 h“, „2 d“ wie dur() im Dashboard.
func dur(_ iso: String?, now: Date = Date()) -> String {
    guard let iso, let d = parseISO(iso) else { return "" }
    let s = max(0, now.timeIntervalSince(d))
    if s < 60 { return "<1 min" }
    if s < 3600 { return "\(Int((s / 60).rounded())) min" }
    if s < 86400 { return "\(Int((s / 3600).rounded())) h" }
    return "\(Int((s / 86400).rounded())) d"
}

func ago(_ iso: String?, now: Date = Date()) -> String {
    let d = dur(iso, now: now)
    return d.isEmpty ? "" : (d == "<1 min" ? "just now" : "\(d) ago")
}

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

func parseISO(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }
