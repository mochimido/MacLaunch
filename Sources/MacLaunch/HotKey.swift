import AppKit
import Carbon

final class GlobalHotKey: ShortcutRegistering {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var currentShortcut: LaunchShortcut?
    var isRegistered: Bool { reference != nil }
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4D4C4348 else { return OSStatus(eventNotHandledErr) }
            owner.onPress?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: LaunchShortcut) throws {
        try SystemShortcutConflict.validate(shortcut)
        if reference != nil && currentShortcut == shortcut { return }
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                        EventHotKeyID(signature: 0x4D4C4348, id: nextID),
                                        GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else {
            throw LibraryError.invalid("\(shortcut.title) を登録できませんでした（\(status)）。別の組み合わせを入力してください。")
        }
        if let reference { UnregisterEventHotKey(reference) }
        reference = newReference
        currentShortcut = shortcut
        nextID += 1
    }

    func suspend() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        currentShortcut = nil
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
