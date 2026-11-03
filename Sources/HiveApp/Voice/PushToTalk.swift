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

    private func installTap() {
        if !CGPreflightListenEventAccess() {
            needsPermission = true
            CGRequestListenEventAccess()
            // granted in System Settings: try again until it works, no restart needed
            retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, CGPreflightListenEventAccess() else { return }
                    self.retry?.invalidate()
                    self.retry = nil
                    self.installTap()
                }
            }
            return
        }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, user in
            guard let user else { return Unmanaged.passUnretained(event) }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.rawValue
            MainActor.assumeIsolated {
                Unmanaged<PushToTalk>.fromOpaque(user).takeUnretainedValue().handle(type, code: code, flags: flags)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else {
            needsPermission = true
            voiceLog("event tap not possible (Input Monitoring?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        needsPermission = false
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
