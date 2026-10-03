import CoreServices
import Foundation

/// Meldet Änderungen unter den Ordnern (rekursiv). Gedrosselt: das erste Ereignis löst nach `delay`
/// genau eine Meldung aus, weitere Ereignisse in dieser Zeit gehen darin auf. So ruft eine Session,
/// die gerade ins Protokoll schreibt, höchstens fünfmal pro Sekunde einen Neuaufbau aus.
public final class Watcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "hive.watcher")
    private let delay: TimeInterval
    private let onChange: @Sendable () -> Void
    private var scheduled = false   // nur auf `queue`

    public init(paths: [String], delay: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue().eventArrived()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func eventArrived() {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.onChange()
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
