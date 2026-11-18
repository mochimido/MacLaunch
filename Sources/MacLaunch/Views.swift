import AppKit

extension NSPasteboard.PasteboardType {
    static let launchItem = NSPasteboard.PasteboardType("app.maclaunch.item")
}

enum Style {
    static let ink = NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.21, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.48, green: 0.50, blue: 0.52, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.13, green: 0.39, blue: 0.33, alpha: 1)
    static let pale = NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.91, alpha: 1)
    static let line = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let background = NSColor(calibratedRed: 0.975, green: 0.973, blue: 0.96, alpha: 1)

    static func label(_ title: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = ink, frame: NSRect) -> NSTextField {
        let view = NSTextField(labelWithString: title)
        view.frame = frame
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        view.lineBreakMode = .byTruncatingTail
        return view
    }

    static func symbolButton(_ symbol: String, help: String, frame: NSRect,
                             target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: target, action: action)
        button.frame = frame
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = muted
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DropSurface: FlippedView {
    override var acceptsFirstResponder: Bool { true }
    var onDrop: ((NSPasteboard, UUID?) -> Bool)?
    var onMenu: (() -> NSMenu)?
    var onPaste: (() -> Void)?
    var skin = LauncherSkin(name: .fluentLight) { didSet { needsDisplay = true } }
    private var highlighted = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.launchItem, .fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = true
        return sender.draggingPasteboard.availableType(from: [.launchItem]) != nil ? .move : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        return onDrop?(sender.draggingPasteboard, nil) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { highlighted = false }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = onMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    @objc func paste(_ sender: Any?) { onPaste?() }
    override func draw(_ dirtyRect: NSRect) {
        skin.frame.setFill()
        bounds.fill()
        skin.background.setFill()
        NSRect(x: 6, y: 28, width: bounds.width - 12, height: bounds.height - 53).fill()
        skin.border.withAlphaComponent(0.7).setStroke()
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        frame.lineWidth = 0.7
        frame.stroke()
        if highlighted {
            skin.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.stroke()
        }
    }
}

final class PageScrollView: NSScrollView {
    var onPage: ((Int) -> Void)?
    private var lastScroll = Date.distantPast
    override func scrollWheel(with event: NSEvent) {
        let overflow = (documentView?.bounds.height ?? 0) > contentView.bounds.height + 1
        if overflow && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) && !event.modifierFlags.contains(.option) {
            super.scrollWheel(with: event)
            return
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard abs(delta) > 0.5, event.momentumPhase.isEmpty,
              Date().timeIntervalSince(lastScroll) > 0.28 else { return }
        lastScroll = Date()
        onPage?(delta < 0 ? 1 : -1)
    }
}

final class PageStrip: FlippedView {
    var onPage: ((Int) -> Void)?
    private var lastScroll = Date.distantPast
    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard abs(delta) > 0.5, event.momentumPhase.isEmpty,
              Date().timeIntervalSince(lastScroll) > 0.28 else { return }
        lastScroll = Date()
        onPage?(delta < 0 ? 1 : -1)
    }
}

final class TabButton: NSButton {
    var contextualMenu: (() -> NSMenu)?
    var skin = LauncherSkin(name: .fluentLight)
    var selectedPage = false
    var onDragHover: (() -> Void)?
    var onPageDrop: ((NSPasteboard, Bool) -> Bool)?
    private var hoverTimer: Timer?
    private var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.launchItem, .fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        (selectedPage ? skin.button : hovered || isHighlighted ? skin.hover : skin.frame).setFill()
        path.fill()
        if selectedPage {
            skin.border.setStroke(); path.lineWidth = 0.7; path.stroke()
            skin.accent.setFill(); NSRect(x: 5, y: 1, width: bounds.width - 10, height: 2).fill()
        }
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: selectedPage ? .semibold : .regular), .foregroundColor: skin.ink])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: (bounds.height - text.size().height) / 2))
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextualMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovered = true
        hoverTimer?.invalidate()
        if !selectedPage {
            hoverTimer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in self?.onDragHover?() }
            if let hoverTimer { RunLoop.main.add(hoverTimer, forMode: .common) }
        }
        return sender.draggingPasteboard.availableType(from: [.launchItem]) == nil || NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hoverTimer?.invalidate(); hovered = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoverTimer?.invalidate(); hovered = false
        return onPageDrop?(sender.draggingPasteboard, NSEvent.modifierFlags.contains(.option)) ?? false
    }
}

final class ItemTile: NSControl, NSDraggingSource {
    let item: LaunchItem?
    let slot: Int
    private let skin: LauncherSkin
    private let showLabels: Bool
    private let icon: NSImage?
    var onLaunch: (() -> Void)?
    var onSelect: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onMenu: (() -> NSMenu)?
    var onDrop: ((NSPasteboard, Int, Bool) -> Bool)?
    var onDragState: ((Bool) -> Void)?
    var keyboardSelected = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var dropping = false { didSet { needsDisplay = true } }
    private var droppingInternal = false
    private var pressed = false { didSet { needsDisplay = true } }
    private var mouseStart: NSPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(item: LaunchItem?, slot: Int, skin: LauncherSkin, showLabels: Bool, icon: NSImage?, frame: NSRect) {
        self.item = item; self.slot = slot; self.skin = skin; self.showLabels = showLabels; self.icon = icon
        super.init(frame: frame)
        registerForDraggedTypes([.launchItem, .fileURL, .URL, .string])
        toolTip = item.map { "\($0.name)\n\($0.target)" } ?? "空きボタン：ダブルクリック・右クリックで登録。ドロップ、⌘Vでも登録できます。"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item?.name ?? "空きボタン \(slot + 1)：アイテム登録")
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(false) }
    override func draw(_ dirtyRect: NSRect) {
        skin.drawButton(in: bounds, hovered: hovering || dropping, down: pressed, selected: keyboardSelected, empty: item == nil)
        if dropping && droppingInternal && item != nil {
            skin.accent.setFill(); NSRect(x: 0, y: 2, width: 2, height: bounds.height - 4).fill()
        }
        let shift: CGFloat = pressed ? 1 : 0
        if let icon {
            let size: CGFloat = 32
            let image = item?.url?.isFileURL == false ? icon.withSymbolConfiguration(.init(paletteColors: [skin.ink])) ?? icon : icon
            image.draw(in: NSRect(x: (bounds.width - size) / 2 + shift, y: (showLabels ? bounds.height - size - 4 : (bounds.height - size) / 2) - shift, width: size, height: size))
        } else if hovering || keyboardSelected || dropping {
            skin.muted.withAlphaComponent(0.7).setStroke()
            let plus = NSBezierPath()
            plus.lineWidth = 1.2
            plus.move(to: NSPoint(x: bounds.midX - 5, y: bounds.midY)); plus.line(to: NSPoint(x: bounds.midX + 5, y: bounds.midY))
            plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 5)); plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 5))
            plus.stroke()
        }
        if showLabels, let item {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: item.name, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: skin.ink, .paragraphStyle: paragraph])
                .draw(in: NSRect(x: 2 + shift, y: 2 - shift, width: bounds.width - 4, height: 14))
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        mouseStart = event.locationInWindow; dragging = false; pressed = true
        onSelect?()
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if mouseStart != nil && !dragging && bounds.contains(convert(event.locationInWindow, from: nil)) {
            if item != nil || event.clickCount >= 2 { onLaunch?() }
        }
        mouseStart = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseStart, let item,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        dragging = true; pressed = false; onDragState?(true)
        let pasteboardItem = NSPasteboardItem(); pasteboardItem.setString(item.id.uuidString, forType: .launchItem)
        let dragItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        dragItem.setDraggingFrame(NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragState?(false); mouseStart = nil; dragging = false; pressed = false
    }
    override func rightMouseDown(with event: NSEvent) {
        onSelect?()
        if let menu = onMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func accessibilityPerformPress() -> Bool { onLaunch?(); return true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropping = true
        droppingInternal = sender.draggingPasteboard.availableType(from: [.launchItem]) != nil
        return sender.draggingPasteboard.availableType(from: [.launchItem]) == nil || NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropping = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropping = false
        return onDrop?(sender.draggingPasteboard, slot, NSEvent.modifierFlags.contains(.option)) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { dropping = false }
}

/// Menu items retain their actions only for the lifetime of their native menu.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}
