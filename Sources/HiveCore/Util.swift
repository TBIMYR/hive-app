import Foundation

extension Optional where Wrapped == String {
    /// Wie `x || null` in JS: leerer String zählt als fehlend.
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}

/// JSON-Zahl, aber kein Bool (JSONSerialization liefert beides als NSNumber; JS: typeof x === 'number').
func number(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

/// Nicht-leerer String oder nil.
func string(_ v: Any?) -> String? { (v as? String).nonEmpty }

private let isoSeconds: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Wie `new Date(ms).toISOString()`: UTC, immer drei Nachkommastellen, Millisekunden abgeschnitten.
func isoString(ms: Double) -> String {
    let whole = (ms / 1000).rounded(.down)
    let frac = Int(ms - whole * 1000)
    let base = isoSeconds.string(from: Date(timeIntervalSince1970: whole))
    return String(base.dropLast()) + String(format: ".%03dZ", frac)
}

/// ISO-Zeit mit oder ohne Nachkommastellen, mit Z oder Offset.
public func parseISO(_ s: String) -> Date? {
    isoSeconds.date(from: s) ?? isoFractional.date(from: s)
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
