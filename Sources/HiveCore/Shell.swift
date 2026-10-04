import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let out: String
        let err: String
    }

    /// Starts the program and waits; after `timeout` seconds it is terminated. status -1 = could not be started.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return Result(status: -1, out: "", err: error.localizedDescription) }
        let stop = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        stop.cancel()
        return Result(status: p.terminationStatus,
                      out: String(decoding: o, as: UTF8.self),
                      err: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
