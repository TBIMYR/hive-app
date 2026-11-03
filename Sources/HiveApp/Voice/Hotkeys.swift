import Carbon.HIToolbox

/// Global hotkeys via Carbon: they report press and release and need no Accessibility permission.
final class Hotkeys {
    struct Key {
        let id: UInt32
        let code: Int
        let modifiers: Int
        let onPress: () -> Void
        var onRelease: (() -> Void)?
    }

    private var keys: [UInt32: Key] = [:]
    private var refs: [EventHotKeyRef] = []
    private var down: Set<UInt32> = []

    init(_ keys: [Key]) {
        for k in keys { self.keys[k.id] = k }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let event, let user else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<Hotkeys>.fromOpaque(user).takeUnretainedValue()
            me.handle(id: hk.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, 2, &types, me, nil)
        for k in keys {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(k.code), UInt32(k.modifiers), EventHotKeyID(signature: 0x48565643, id: k.id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status != noErr { voiceLog("hotkey \(k.id) could not be registered (\(status)), taken by another app?") }
            if let ref { refs.append(ref) }
        }
    }

    private func handle(id: UInt32, pressed: Bool) {
        guard let k = keys[id] else { return }
        if pressed {
            guard down.insert(id).inserted else { return }   // key repeat
            k.onPress()
        } else {
            down.remove(id)
            k.onRelease?()
        }
    }
}
