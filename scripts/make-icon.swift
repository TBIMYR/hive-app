// make-icon.swift — zeichnet das App-Symbol (eine Wabe auf dunkler Kachel) als .iconset.
//   swift scripts/make-icon.swift Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset
// Gleiche Wabe wie HiveMark in der App.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func hexagon(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<6 {
        let a = CGFloat.pi / 3 * CGFloat(i) + .pi / 2
        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    p.lineJoinStyle = .round
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS-Kachel: 824/1024 der Fläche, Eckenradius ~ 185/1024, leichter Schatten
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 12 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -s * 6 / 1024)
    shadow.set()
    NSGradient(starting: NSColor(calibratedWhite: 0.13, alpha: 1), ending: NSColor(calibratedWhite: 0.04, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // eine Wabe mittig, spitze Seite oben, etwa halb so hoch wie die Kachel, Ecken gerundet
    let color = NSColor.white
    color.setFill(); color.setStroke()
    let hex = hexagon(center: CGPoint(x: s / 2, y: s / 2), radius: tile.height * 0.25)
    hex.lineWidth = tile.height * 0.06
    hex.fill(); hex.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("\(out): 10 Bilder")
