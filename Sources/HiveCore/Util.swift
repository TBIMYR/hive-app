import Foundation

extension Optional where Wrapped == String {
    /// Like `x || null` in JS: empty string counts as missing.
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}

/// JSON number, but not a bool (JSONSerialization returns both as NSNumber; JS: typeof x === 'number').
func number(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

/// Non-empty string or nil.
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

/// Like `new Date(ms).toISOString()`: UTC, always three decimal places, milliseconds truncated.
func isoString(ms: Double) -> String {
    let whole = (ms / 1000).rounded(.down)
    let frac = Int(ms - whole * 1000)
    let base = isoSeconds.string(from: Date(timeIntervalSince1970: whole))
    return String(base.dropLast()) + String(format: ".%03dZ", frac)
}

/// ISO time with or without decimal places, with Z or offset.
public func parseISO(_ s: String) -> Date? {
    isoSeconds.date(from: s) ?? isoFractional.date(from: s)
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
