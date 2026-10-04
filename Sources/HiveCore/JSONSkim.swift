import Foundation

/// Minimal JSON walker over raw bytes: visits the keys of an object and skips every value that is not
/// asked for without building it. Transcript lines carry large message content; decoding them in full
/// made the first usage scan several times slower.
struct JSONSkim {
    private let p: UnsafePointer<UInt8>
    private let end: Int
    private(set) var i = 0

    init(_ p: UnsafePointer<UInt8>, count: Int) {
        self.p = p
        self.end = count
    }

    private mutating func skipSpace() {
        while i < end, p[i] == 0x20 || p[i] == 0x0A || p[i] == 0x0D || p[i] == 0x09 { i += 1 }
    }

    /// Calls `visit` with each key of the object at the cursor; `visit` must consume the value
    /// (via `string()`, `number()`, `object(_:)` or `skip()`). False if the JSON is malformed.
    mutating func object(_ visit: (inout JSONSkim, String) -> Bool) -> Bool {
        skipSpace()
        guard i < end, p[i] == UInt8(ascii: "{") else { return false }
        i += 1
        skipSpace()
        if i < end, p[i] == UInt8(ascii: "}") { i += 1; return true }
        while true {
            skipSpace()
            guard let key = string() else { return false }
            skipSpace()
            guard i < end, p[i] == UInt8(ascii: ":") else { return false }
            i += 1
            skipSpace()
            guard visit(&self, key) else { return false }
            skipSpace()
            guard i < end else { return false }
            if p[i] == UInt8(ascii: ",") { i += 1; continue }
            if p[i] == UInt8(ascii: "}") { i += 1; return true }
            return false
        }
    }

    /// Whether an object starts at the cursor.
    var peekObject: Bool { i < end && p[i] == UInt8(ascii: "{") }

    /// The string at the cursor; nil if there is none (then the cursor stays put).
    mutating func string() -> String? {
        guard i < end, p[i] == UInt8(ascii: "\"") else { return nil }
        let start = i
        guard skipString() else { return nil }
        let raw = UnsafeBufferPointer(start: p + start + 1, count: i - start - 2)
        if !raw.contains(UInt8(ascii: "\\")) { return String(decoding: raw, as: UTF8.self) }
        // with escapes: let Foundation decode just this string
        let data = Data(UnsafeBufferPointer(start: p + start, count: i - start))
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
    }

    /// String or other value; strings come back as String, everything else is skipped and gives nil.
    mutating func stringOrSkip() -> (ok: Bool, value: String?) {
        if i < end, p[i] == UInt8(ascii: "\"") {
            let s = string()
            return (s != nil, s)
        }
        return (skip(), nil)
    }

    /// Number at the cursor, otherwise the value is skipped and nil returned.
    mutating func number() -> (ok: Bool, value: Double?) {
        let start = i
        while i < end, let c = Optional(p[i]), (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E || c == 0x65 || c == 0x45 {
            i += 1
        }
        if i > start {
            return (true, Double(String(decoding: UnsafeBufferPointer(start: p + start, count: i - start), as: UTF8.self)))
        }
        return (skip(), nil)
    }

    /// Skips the value at the cursor.
    mutating func skip() -> Bool {
        guard i < end else { return false }
        switch p[i] {
        case UInt8(ascii: "\""):
            return skipString()
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while i < end {
                switch p[i] {
                case UInt8(ascii: "\""):
                    guard skipString() else { return false }
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { i += 1; return true }
                default:
                    break
                }
                i += 1
            }
            return false
        default:
            // number, true, false, null
            let start = i
            while i < end, p[i] != UInt8(ascii: ","), p[i] != UInt8(ascii: "}"), p[i] != UInt8(ascii: "]"),
                  p[i] != 0x20, p[i] != 0x0A, p[i] != 0x0D, p[i] != 0x09 { i += 1 }
            return i > start
        }
    }

    /// Cursor on the opening quote; afterwards behind the closing one.
    private mutating func skipString() -> Bool {
        i += 1
        while i < end {
            switch p[i] {
            case UInt8(ascii: "\\"): i += 2
            case UInt8(ascii: "\""): i += 1; return true
            default: i += 1
            }
        }
        return false
    }
}
