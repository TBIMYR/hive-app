import AppKit
import Carbon.HIToolbox

/// The push-to-talk key, also while Hive is in the background.
/// Right ⌥ alone needs a listen-only event tap (macOS asks once for Input Monitoring); ⌃⌥Space is a Carbon hotkey.
/// Right ⌥ is also used for typing characters (⌥L = @): if another key is pressed while it is held, the
/// recording is dropped instead of sent.
@MainActor
final class PushToTalk {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// held together with another key: not meant for Hive
    var onCancel: () -> Void = {}
    var onPermission: (Bool) -> Void = { _ in }
    /// tap not possible yet (Input Monitoring missing)
    private(set) var needsPermission = false { didSet { if needsPermission != oldValue { onPermission(needsPermission) } } }

    private var trigger: VoiceSettings.Trigger?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var hotkeys: Hotkeys?
    private var down = false

    /// key code of the right Option key, and its device-dependent flag (NX_DEVICERALTKEYMASK)
    static let rightOptionCode: Int64 = 61
    static let rightOptionFlag: UInt64 = 0x40

    func start(_ trigger: VoiceSettings.Trigger) {
        guard trigger != self.trigger else { return }
        stop()
        self.trigger = trigger
        switch trigger {
        case .rightOption:
            installTap()
        case .controlOptionSpace:
            hotkeys = Hotkeys([.init(id: 1, code: kVK_Space, modifiers: controlKey | optionKey,
                                     onPress: { [weak self] in self?.onPress() },
                                     onRelease: { [weak self] in self?.onRelease() })])
        }
    }

    func stop() {
        trigger = nil
        retry?.invalidate()
        retry = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        hotkeys = nil
        down = false
        needsPermission = false
    }

    /// Trying to create the tap is what puts Hive into the Input Monitoring list; without the permission it fails,
    /// so ask once and try again every few seconds: granted in System Settings, it works without a restart.
    private func installTap() {
        guard !createTap() else { return }
        needsPermission = true
        voiceLog("no Input Monitoring permission yet")
        CGRequestListenEventAccess()
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.trigger == .rightOption, self.createTap() else { return }
                self.retry?.invalidate()
                self.retry = nil
                voiceLog("Input Monitoring granted, right ⌥ works")
            }
        }
    }

    private func createTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, user in
            guard let user else { return Unmanaged.passUnretained(event) }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.rawValue
            // Not MainActor.assumeIsolated: its executor check crashed in here (null object in
            // swift_task_isMainExecutor) when the tap fired inside a nested run loop. The tap runs on the main
            // run loop anyway; one hop to the main queue costs nothing noticeable.
            DispatchQueue.main.async {
                Unmanaged<PushToTalk>.fromOpaque(user).takeUnretainedValue().handle(type, code: code, flags: flags)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        needsPermission = false
        return true
    }

    private func handle(_ type: CGEventType, code: Int64, flags: UInt64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where code == Self.rightOptionCode:
            let now = flags & Self.rightOptionFlag != 0
            guard now != down else { return }
            down = now
            now ? onPress() : onRelease()
        case .keyDown where down:
            down = false
            onCancel()
        default:
            break
        }
    }
}
