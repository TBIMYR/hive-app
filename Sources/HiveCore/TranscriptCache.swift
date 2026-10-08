import Foundation

/// Parsed transcript tails per session, re-read only when a file read for it has changed size.
/// Transcripts only grow, so the size is enough. Saves parsing every session's tail on every refresh
/// (the app refreshes up to five times a second while sessions work).
public final class TranscriptCache: @unchecked Sendable {
    struct Entry {
        let files: [(path: String, size: UInt64?)]
        let tail: Tail
        let starts: [Date?]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// transcripts parsed (for tests)
    public private(set) var parses = 0

    public init() {}

    public func read(dir: String, sessionId: String) -> (tail: Tail, backgroundStarts: [Date?]) {
        let key = "\(dir)/\(sessionId)"
        if let e = lock.withLock({ entries[key] }), e.files.allSatisfy({ Self.size($0.path) == $0.size }) {
            return (e.tail, e.starts)
        }
        let (text, files) = Transcript.readTailTracked(dir: dir, sessionId: sessionId)
        let e = Entry(files: files, tail: Transcript.parseTail(text), starts: Transcript.backgroundStarts(text))
        lock.withLock {
            entries[key] = e
            parses += 1
        }
        return (e.tail, e.starts)
    }

    private static func size(_ path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
    }
}
