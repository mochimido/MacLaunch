import AppKit

final class ShortcutRecorder: NSView {
    private(set) var shortcut: LaunchShortcut
    private(set) var isRecording = false
    private var heldModifiers: UInt32 = 0
    private var monitor: Any?
    var onStatus: ((String?, Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    init(shortcut: LaunchShortcut, frame: NSRect) {
        self.shortcut = shortcut
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("ショートカット入力")
        setAccessibilityHelp("クリックしてから、設定したいキーの組み合わせを押してください。")
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { stopMonitoring() }

    override func becomeFirstResponder() -> Bool {
        beginRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        stopMonitoring()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        beginRecording()
        return true
    }

    func setShortcut(_ value: LaunchShortcut) {
        shortcut = value
        stopRecording()
        onStatus?(nil, true)
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        heldModifiers = 0
        onStatus?("設定したい組み合わせを押してください。Escで入力をやめます。", true)
        updateAccessibility()
        needsDisplay = true
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true,
                  self.window?.firstResponder === self else { return event }
            // Holding a recorded menu key (such as ⌘Q) must not trigger that command on repeat.
            if event.type == .keyDown && event.isARepeat { return nil }
            guard self.isRecording else { return event }
            if event.type == .flagsChanged {
                self.heldModifiers = LaunchShortcut.modifiers(from: event.modifierFlags)
                self.needsDisplay = true
                return event
            }
            return self.capture(event) ? nil : event
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func stopRecording() {
        isRecording = false
        heldModifiers = 0
        updateAccessibility()
        needsDisplay = true
    }

    private func capture(_ event: NSEvent) -> Bool {
        let flags = LaunchShortcut.modifiers(from: event.modifierFlags)
        if flags == 0 && (event.keyCode == 53 || event.keyCode == 36) {
            stopRecording()
            onStatus?(nil, true)
            return true
        }
        if (flags == 0 || flags == 512) && event.keyCode == 48 {
            stopRecording()
            onStatus?(nil, true)
            return false
        }
        do {
            let candidate = try LaunchShortcut.capture(event)
            try SystemShortcutConflict.validate(candidate)
            shortcut = candidate
            stopRecording()
            onStatus?(nil, true)
        } catch {
            onStatus?(error.localizedDescription, false)
        }
        return true
    }

    private func updateAccessibility() {
        setAccessibilityValue(isRecording ? "キーを押してください。現在：\(shortcut.title)" : shortcut.title)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (isRecording ? Style.pale : NSColor.controlBackgroundColor).setFill()
        shape.fill()
        (isRecording ? Style.accent : Style.line).setStroke()
        shape.lineWidth = isRecording ? 2 : 1
        shape.stroke()
        let modifiers = LaunchShortcut.modifierTitle(heldModifiers)
        let title = isRecording ? (modifiers.isEmpty ? "キーを押してください…" : modifiers + " …") : shortcut.title
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isRecording ? 16 : 21, weight: .medium),
            .foregroundColor: isRecording ? Style.accent : Style.ink
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
