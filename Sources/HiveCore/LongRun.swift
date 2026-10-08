import Foundation

/// A command that may run for minutes (git clone): working folder, environment, timeout, cancellable.
/// stdout and stderr are read concurrently, so a full stderr pipe can't stall the process. Cancel and
/// timeout end the whole process tree (`gh repo clone` starts `git`, which would keep the pipes open).
public final class LongRun: @unchecked Sendable {
    public struct Result: Sendable {
        public let status: Int32
        public let out: String
        public let err: String
        public let timedOut: Bool
        public let cancelled: Bool
    }

    private let process = Process()
    private let lock = NSLock()
    private var cancelledFlag = false
    private var timedOutFlag = false

    public init(_ path: String, _ args: [String], cwd: String? = nil, env: [String: String]? = nil) {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env { process.environment = env }
    }

    /// Blocks until the command ends, the timeout hits, or `cancel()` is called. status -1 = could not start.
    public func run(timeout: TimeInterval = 300) -> Result {
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return Result(status: -1, out: "", err: error.localizedDescription, timedOut: false, cancelled: false)
        }
        if lock.withLock({ cancelledFlag }) { killTree() }
        let buffers = Buffers()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) { buffers.set(out: out.fileHandleForReading.readDataToEndOfFile()) }
        DispatchQueue.global().async(group: group) { buffers.set(err: err.fileHandleForReading.readDataToEndOfFile()) }
        let stop = DispatchWorkItem { [self] in
            guard process.isRunning else { return }
            lock.withLock { timedOutFlag = true }
            killTree()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        process.waitUntilExit()
        stop.cancel()
        // a leftover grandchild may still hold the pipes: don't wait for it forever
        _ = group.wait(timeout: .now() + 2)
        let (o, e) = buffers.get()
        return lock.withLock {
            Result(status: process.terminationStatus,
                   out: String(decoding: o, as: UTF8.self),
                   err: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                   timedOut: timedOutFlag, cancelled: cancelledFlag)
        }
    }

    public func cancel() {
        lock.withLock { cancelledFlag = true }
        if process.isRunning { killTree() }
    }

    /// SIGTERM to the process and all its descendants (children first, found with `pgrep -P`).
    private func killTree() {
        let root = process.processIdentifier
        guard root > 0 else { return }
        var all: [pid_t] = []
        var queue = [root]
        while let p = queue.popLast() {
            all.append(p)
            queue += Self.children(of: p)
        }
        for p in all.reversed() { kill(p, SIGTERM) }
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { pid_t($0) }
    }

    private final class Buffers: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data()
        func set(out d: Data) { lock.withLock { out = d } }
        func set(err d: Data) { lock.withLock { err = d } }
        func get() -> (Data, Data) { lock.withLock { (out, err) } }
    }
}
