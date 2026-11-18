import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private var store: LibraryStore!
    private var panel: LauncherPanel!
    private var statusItem: NSStatusItem!
    private let hotKey = GlobalHotKey()
    private var hotKeyAvailable = true
    private var root: DropSurface!
    private var tabsScroll: NSScrollView!
    private var search: NSSearchField!
    private var grid: PageScrollView!
    private var footer: NSTextField!
    private var pinButton: NSButton!
    private var shortcutLabel: NSTextField!
    private var tiles: [ItemTile] = []
    private var visibleItems: [LaunchItem] = []
    private var highlightedIndex: Int?
    private var query = ""
    private var pinned = false
    private var dragging = false
    private var modalDepth = 0
    private var menuDepth = 0
    private var shownAt = Date.distantPast
    private var pointerWasInside = false
    private var outsideSince: Date?
    private var cornerSince: Date?
    private var cornerLatched = false
    private var lastCornerPoint = NSPoint.zero
    private var timer: Timer?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var icons: [String: NSImage] = [:]
    private var searchVisible = false
    private var captionLabel: NSTextField!
    private var searchToggle: NSButton!
    private var modeButton: NSButton!
    private var newItemButton: NSButton!
    private var settingsButton: NSButton!
    private var hideButton: NSButton!
    private var pageAddButton: NSButton!
    private var layout: LauncherLayout { LauncherLayout(preferences: store.library.preferences, searching: searchVisible || !query.isEmpty) }
    private var palette: LauncherSkin { LauncherSkin(name: store.library.preferences.skin) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        let config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacLaunch", isDirectory: true).appendingPathComponent("library.json")
        do {
            store = try LibraryStore(fileURL: config, defaults: Self.makeDefaults())
        } catch {
            let alert = NSAlert()
            alert.messageText = "設定を読み込めませんでした"
            alert.informativeText = "\(error.localizedDescription)\n\n既存の設定をバックアップして初期設定で起動できます。"
            alert.addButton(withTitle: "バックアップして起動")
            alert.addButton(withTitle: "終了")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
            do {
                if FileManager.default.fileExists(atPath: config.path) {
                    let backup = config.deletingLastPathComponent().appendingPathComponent("library-recovery-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: config, to: backup)
                }
                try LibraryStore.write(Self.makeDefaults(), to: config)
                store = try LibraryStore(fileURL: config, defaults: Self.makeDefaults())
            } catch {
                alert.messageText = "設定を保存できません"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                NSApp.terminate(nil)
                return
            }
        }
        buildPanel()
        buildStatusItem()
        hotKey.onPress = { [weak self] in self?.toggle() }
        do { try hotKey.register(store.library.preferences.hotKey) }
        catch { hotKeyAvailable = false; DispatchQueue.main.async { self.report(error) } }
        refresh()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible, !self.pinned, self.modalDepth == 0, self.menuDepth == 0 else { return }
            self.hide()
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    private static func makeDefaults() -> Library {
        func application(_ name: String, _ path: String) -> LaunchItem? {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return LaunchItem(name: name, target: path)
        }
        let apps: [(String, String)] = [
            ("Finder", "/System/Library/CoreServices/Finder.app"),
            ("Safari", "/Applications/Safari.app"),
            ("メール", "/System/Applications/Mail.app"),
            ("メモ", "/System/Applications/Notes.app"),
            ("カレンダー", "/System/Applications/Calendar.app"),
            ("リマインダー", "/System/Applications/Reminders.app"),
            ("システム設定", "/System/Applications/System Settings.app"),
            ("写真", "/System/Applications/Photos.app"),
            ("プレビュー", "/System/Applications/Preview.app"),
            ("テキストエディット", "/System/Applications/TextEdit.app"),
            ("ターミナル", "/System/Applications/Utilities/Terminal.app"),
            ("計算機", "/System/Applications/Calculator.app")
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Library(pages: [
            LaunchPage(name: "アプリ", items: apps.compactMap { application($0.0, $0.1) }),
            LaunchPage(name: "フォルダ", items: [
                LaunchItem(name: "ホーム", target: home.path),
                LaunchItem(name: "ダウンロード", target: home.appendingPathComponent("Downloads").path),
                LaunchItem(name: "書類", target: home.appendingPathComponent("Documents").path),
                LaunchItem(name: "デスクトップ", target: home.appendingPathComponent("Desktop").path)
            ]),
            LaunchPage(name: "Web", items: [LaunchItem(name: "Apple", target: "https://www.apple.com/jp/")])
        ])
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "MacLaunchを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        for (title, action, key) in [("元に戻す", "undo:", "z"), ("カット", "cut:", "x"),
                                     ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"), ("すべて選択", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func buildPanel() {
        let size = NSSize(width: layout.width, height: layout.height)
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "MacLaunch"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(type)?.isHidden = true }
        root = DropSurface(frame: NSRect(origin: .zero, size: size))
        root.onDrop = { [weak self] pasteboard, _ in self?.acceptDrop(pasteboard) ?? false }
        root.onMenu = { [weak self] in self?.settingsMenu() ?? NSMenu() }
        root.onPaste = { [weak self] in self?.pasteRegistration() }
        panel.contentView = root
        pinButton = Style.symbolButton("lock.open", help: "ウィンドウロック", frame: .zero, target: self, action: #selector(togglePin))
        root.addSubview(pinButton)
        captionLabel = Style.label("MacLaunch", size: 11, weight: .semibold, frame: .zero)
        root.addSubview(captionLabel)
        shortcutLabel = Style.label("", size: 9, color: .secondaryLabelColor, frame: .zero)
        shortcutLabel.alignment = .right
        root.addSubview(shortcutLabel)
        modeButton = Style.symbolButton("square.grid.3x3", help: "表示を拡張・縮小", frame: .zero, target: self, action: #selector(toggleRows))
        searchToggle = Style.symbolButton("magnifyingglass", help: "検索（⌘F）", frame: .zero, target: self, action: #selector(toggleSearch))
        newItemButton = Style.symbolButton("plus", help: "アイテム登録（⌘N）", frame: .zero, target: self, action: #selector(addItems))
        settingsButton = Style.symbolButton("gearshape", help: "設定・スキン", frame: .zero, target: self, action: #selector(settingsClicked(_:)))
        hideButton = Style.symbolButton("xmark", help: "隠す（Esc）", frame: .zero, target: self, action: #selector(hide))
        for button in [modeButton, searchToggle, newItemButton, settingsButton, hideButton] { root.addSubview(button!) }
        tabsScroll = NSScrollView(frame: .zero)
        tabsScroll.drawsBackground = false
        tabsScroll.horizontalScrollElasticity = .none
        tabsScroll.verticalScrollElasticity = .none
        root.addSubview(tabsScroll)
        pageAddButton = Style.symbolButton("plus", help: "ページを追加", frame: .zero, target: self, action: #selector(addPage))
        root.addSubview(pageAddButton)
        search = NSSearchField(frame: .zero)
        search.placeholderString = "すべてのページから検索"
        search.font = .systemFont(ofSize: 11)
        search.sendsSearchStringImmediately = true
        search.delegate = self; search.target = self; search.action = #selector(searchSubmitted)
        search.setAccessibilityLabel("すべてのページから検索")
        root.addSubview(search)
        grid = PageScrollView(frame: .zero)
        grid.drawsBackground = false
        grid.hasVerticalScroller = true; grid.autohidesScrollers = true; grid.scrollerStyle = .overlay
        grid.onPage = { [weak self] in self?.changePage($0) }
        root.addSubview(grid)
        footer = Style.label("", size: 9, frame: .zero)
        root.addSubview(footer)
        layoutChrome()
    }

    private func layoutChrome() {
        let l = layout
        let top = panel.frame.maxY
        let origin = panel.frame.origin
        panel.setContentSize(NSSize(width: l.width, height: l.height))
        var newOrigin = NSPoint(x: origin.x, y: top - panel.frame.height)
        if panel.isVisible, let screen = panel.screen?.visibleFrame {
            newOrigin.x = min(max(newOrigin.x, screen.minX + 6), screen.maxX - panel.frame.width - 6)
            newOrigin.y = min(max(newOrigin.y, screen.minY + 6), screen.maxY - panel.frame.height - 6)
        }
        panel.setFrameOrigin(newOrigin)
        root.frame.size = NSSize(width: l.width, height: l.height)
        root.skin = palette
        panel.backgroundColor = palette.frame
        panel.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        pinButton.frame = NSRect(x: 6, y: 3, width: 21, height: 22)
        pinButton.image = NSImage(systemSymbolName: pinned ? "lock.fill" : "lock.open", accessibilityDescription: "ウィンドウロック")
        pinButton.contentTintColor = pinned ? palette.accent : palette.muted
        captionLabel.frame = NSRect(x: 31, y: 7, width: 108, height: 17)
        captionLabel.textColor = palette.ink
        shortcutLabel.frame = NSRect(x: 139, y: 8, width: max(30, l.width - 259), height: 16)
        shortcutLabel.textColor = palette.muted
        for (index, button) in [modeButton!, searchToggle!, newItemButton!, settingsButton!, hideButton!].enumerated() {
            button.frame = NSRect(x: l.width - 114 + CGFloat(index) * 22, y: 3, width: 21, height: 22)
            button.contentTintColor = palette.ink
        }
        modeButton.toolTip = store.library.preferences.visibleRows > 3 ? "3行に縮小" : "6行に拡張"
        searchToggle.contentTintColor = l.searching ? palette.accent : palette.ink
        tabsScroll.frame = NSRect(x: 10, y: l.tabY + 2, width: l.width - 44, height: 26)
        pageAddButton.frame = NSRect(x: l.width - 30, y: l.tabY + 3, width: 20, height: 24)
        pageAddButton.contentTintColor = palette.muted
        search.frame = NSRect(x: 11, y: 31, width: l.gridWidth, height: 25)
        search.isHidden = !l.searching
        grid.frame = l.gridFrame
        footer.frame = l.footerFrame
        footer.textColor = palette.muted
    }

    @objc private func toggleRows() { update { $0.preferences.visibleRows = $0.preferences.visibleRows > 3 ? 3 : 6 } }
    @objc private func toggleSearch() {
        searchVisible.toggle()
        if !searchVisible { query = ""; search.stringValue = "" }
        refresh()
        panel.makeFirstResponder(searchVisible ? search : root)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacLaunch")
            button.image?.isTemplate = true
            button.toolTip = "MacLaunch — クリックで表示、右クリックで設定"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func refresh() {
        guard panel != nil else { return }
        layoutChrome()
        shortcutLabel.stringValue = hotKeyAvailable ? store.library.preferences.hotKey.title : "キー未登録"
        renderTabs()
        renderGrid()
    }

    private func renderTabs() {
        let strip = PageStrip(frame: NSRect(x: 0, y: 0, width: tabsScroll.bounds.width, height: 26))
        strip.onPage = { [weak self] in self?.changePage($0) }
        var x: CGFloat = 0
        var selectedFrame = NSRect.zero
        for (index, page) in store.library.pages.enumerated() {
            let selected = page.id == store.library.selectedPageID
            let width = min(140, max(64, (page.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5)]).width + 16))
            let button = TabButton(title: page.name, target: self, action: #selector(tabClicked(_:)))
            button.frame = NSRect(x: x, y: 0, width: width, height: 26)
            button.tag = index; button.isBordered = false
            button.skin = palette; button.selectedPage = selected
            button.toolTip = "\(page.name)（\(page.items.count)件）— 右クリックで編集。ドラッグ中に重ねるとページ切替。"
            button.setAccessibilityValue(selected ? "選択中" : "")
            button.contextualMenu = { [weak self] in self?.pageMenu(page) ?? NSMenu() }
            button.onDragHover = { [weak self] in self?.selectPage(index) }
            button.onPageDrop = { [weak self] pb, copy in
                guard let self else { return false }
                return self.acceptDrop(pb, pageID: page.id, slot: self.store.library.pages[index].firstFreeSlot(), copy: copy)
            }
            strip.addSubview(button)
            if selected { selectedFrame = button.frame }
            x += width + 3
        }
        strip.frame.size.width = max(tabsScroll.bounds.width, x)
        tabsScroll.documentView = strip
        strip.scrollToVisible(selectedFrame)
    }

    private func renderGrid() {
        let library = store.library
        let page = library.pages[library.selectedIndex]
        let positions = page.slotAssignments
        let l = layout
        highlightedIndex = nil
        visibleItems = query.isEmpty ? page.items : library.pages.flatMap(\.items).filter {
            $0.name.localizedStandardContains(query) || $0.target.localizedStandardContains(query)
        }
        tiles = []
        let count: Int
        if query.isEmpty {
            let last = (positions.values.max() ?? -1) + 1
            count = max(l.columns * library.preferences.visibleRows, ((last + 1 + l.columns - 1) / l.columns) * l.columns)
        } else { count = visibleItems.count }
        let rows = max(library.preferences.visibleRows, (count + l.columns - 1) / l.columns)
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: l.gridWidth, height: CGFloat(rows) * (l.cellHeight + l.pitch) - l.pitch))
        let bySlot = Dictionary(uniqueKeysWithValues: page.items.compactMap { item in positions[item.id].map { ($0, item) } })
        for index in 0..<count {
            let item = query.isEmpty ? bySlot[index] : visibleItems[index]
            let tile = ItemTile(item: item, slot: index, skin: palette, showLabels: library.preferences.showLabels,
                                icon: item.map(icon(for:)), frame: l.frame(for: index))
            tile.onLaunch = { [weak self] in
                if let item { self?.launch(item) } else { self?.showRegistration(slot: index) }
            }
            tile.onSelect = { [weak self] in self?.highlight(index); self?.panel.makeFirstResponder(self?.root) }
            tile.onHover = { [weak self] inside in
                guard let self else { return }
                if inside { self.footer.stringValue = item.map { "\($0.name)  —  \($0.target)" } ?? "空きボタン \(index + 1)  ·  ダブルクリック・右クリック・⌘Vで登録" }
                else { self.resetFooter() }
            }
            tile.onMenu = { [weak self] in
                guard let self else { return NSMenu() }
                return item.map(self.itemMenu) ?? self.addMenu(slot: index)
            }
            tile.onDrop = { [weak self] pb, slot, copy in self?.acceptDrop(pb, slot: slot, copy: copy) ?? false }
            tile.onDragState = { [weak self] in self?.dragging = $0 }
            document.addSubview(tile); tiles.append(tile)
        }
        if !query.isEmpty && visibleItems.isEmpty {
            let empty = Style.label("見つかりませんでした", size: 12, color: palette.muted,
                                    frame: NSRect(x: 0, y: l.gridHeight / 2 - 12, width: l.gridWidth, height: 24))
            empty.alignment = .center; document.addSubview(empty)
        }
        grid.documentView = document
        resetFooter()
    }

    private func resetFooter() {
        let page = store.library.pages[store.library.selectedIndex]
        footer.stringValue = query.isEmpty ? "\(page.name) · \(page.items.count)件  ｜  空きボタンをダブルクリックで登録" : "すべてのページ · \(visibleItems.count)件"
    }

    private func icon(for item: LaunchItem) -> NSImage {
        if let cached = icons[item.target] { return cached }
        let image: NSImage
        if let url = item.url, url.isFileURL { image = NSWorkspace.shared.icon(forFile: url.path) }
        else { image = NSImage(systemSymbolName: "globe.americas.fill", accessibilityDescription: nil)! }
        icons[item.target] = image
        return image
    }

    @discardableResult private func update(_ mutation: (inout Library) -> Void) -> Bool {
        do { try store.update(mutation); refresh(); return true }
        catch { report(error); return false }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow, modalDepth == 0, menuDepth == 0 else { return event }
        let command = event.modifierFlags.contains(.command)
        if command, let key = event.charactersIgnoringModifiers {
            if key == "f" { searchVisible = true; refresh(); panel.makeFirstResponder(search); return nil }
            if key == "v", !(panel.firstResponder is NSTextView) { pasteRegistration(); return nil }
            if key == "n" { addItems(); return nil }
            if let digit = Int(key), (1...9).contains(digit) { selectPage(digit - 1); return nil }
            if event.keyCode == 123 { changePage(-1); return nil }
            if event.keyCode == 124 { changePage(1); return nil }
            return event
        }
        if event.keyCode == 53 {
            if !search.stringValue.isEmpty {
                search.stringValue = ""; query = ""; renderGrid(); panel.makeFirstResponder(root)
            } else if searchVisible { searchVisible = false; refresh(); panel.makeFirstResponder(root) }
            else { hide() }
            return nil
        }
        let editing = panel.firstResponder is NSTextView
        if editing {
            if event.keyCode == 125 && !tiles.isEmpty { panel.makeFirstResponder(root); highlight(0); return nil }
            return event
        }
        if [123, 124, 125, 126].contains(Int(event.keyCode)), !tiles.isEmpty {
            let offset = [123: -1, 124: 1, 125: layout.columns, 126: -layout.columns][Int(event.keyCode)]!
            let next = highlightedIndex.map { min(tiles.count - 1, max(0, $0 + offset)) } ?? 0
            highlight(next)
            return nil
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let index = highlightedIndex, tiles.indices.contains(index) { tiles[index].onLaunch?() }
            else if let item = visibleItems.first { launch(item) }
            return nil
        }
        if !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
           let text = event.characters, text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
            searchVisible = true
            layoutChrome()
            panel.makeFirstResponder(search)
            // Deliver the original event through AppKit so Japanese input methods keep their composition state.
            return event
        }
        return event
    }

    private func highlight(_ index: Int) {
        highlightedIndex = index
        for (i, tile) in tiles.enumerated() { tile.keyboardSelected = i == index }
        tiles[index].scrollToVisible(tiles[index].bounds)
    }

    @objc private func togglePin() {
        pinned.toggle()
        pinButton.image = NSImage(systemSymbolName: pinned ? "lock.fill" : "lock.open", accessibilityDescription: "ウィンドウロック")
        pinButton.contentTintColor = pinned ? palette.accent : palette.muted
        pinButton.toolTip = pinned ? "ウィンドウロックを解除" : "ウィンドウロック：登録作業中も表示を固定"
        pinButton.setAccessibilityValue(pinned ? "固定中" : "固定していません")
        outsideSince = nil
    }

    private func toggle() { panel.isVisible ? hide() : show() }

    private func show(activate: Bool = true) {
        guard modalDepth == 0 else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if !panel.isVisible, let frame = screen?.visibleFrame {
            let x = min(max(mouse.x - panel.frame.width / 2, frame.minX + 12), frame.maxX - panel.frame.width - 12)
            let y = min(max(mouse.y - panel.frame.height + 24, frame.minY + 12), frame.maxY - panel.frame.height - 12)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        query = ""; search.stringValue = ""; searchVisible = false; refresh()
        shownAt = Date()
        pointerWasInside = panel.frame.contains(mouse)
        outsideSince = nil
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(root)
        } else { panel.orderFrontRegardless() }
    }

    @objc private func hide() {
        guard modalDepth == 0 else { return }
        panel.orderOut(nil)
        outsideSince = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidResignKey(_ notification: Notification) {
        if !pinned, modalDepth == 0, menuDepth == 0 { hide() }
    }

    private func tick() {
        guard panel != nil, modalDepth == 0, menuDepth == 0, !dragging,
              NSApp.modalWindow == nil else { return }
        let point = NSEvent.mouseLocation
        let corner = store.library.preferences.corner
        if corner != .disabled, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let f = screen.frame
            let right = corner == .bottomRight || corner == .topRight
            let top = corner == .topLeft || corner == .topRight
            let inCorner = (right ? point.x >= f.maxX - 5 : point.x <= f.minX + 5)
                && (top ? point.y >= f.maxY - 5 : point.y <= f.minY + 5)
            if inCorner {
                if cornerSince == nil { cornerSince = Date(); lastCornerPoint = point }
                if !cornerLatched, Date().timeIntervalSince(cornerSince!) > 0.25 {
                    cornerLatched = true
                    if !panel.isVisible { show(activate: NSEvent.pressedMouseButtons == 0) }
                }
            } else {
                cornerSince = nil
                if hypot(point.x - lastCornerPoint.x, point.y - lastCornerPoint.y) > 30 { cornerLatched = false }
            }
        } else { cornerSince = nil; cornerLatched = false }
        guard panel.isVisible, store.library.preferences.autoHide, !pinned, NSEvent.pressedMouseButtons == 0 else { return }
        if panel.frame.contains(point) { pointerWasInside = true; outsideSince = nil; return }
        // Keyboard invocation remains available until the pointer has entered the panel.
        guard pointerWasInside, Date().timeIntervalSince(shownAt) > 1 else { return }
        if outsideSince == nil { outsideSince = Date() }
        if Date().timeIntervalSince(outsideSince!) > 0.55 { hide() }
    }

    private func report(_ error: Error) {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let alert = NSAlert()
        alert.messageText = "操作を完了できませんでした"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func trackedMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) { menuDepth += 1 }
    func menuDidClose(_ menu: NSMenu) { menuDepth = max(0, menuDepth - 1); outsideSince = nil }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = settingsMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        } else { toggle() }
    }

    @objc private func settingsClicked(_ sender: NSButton) {
        settingsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    private func settingsMenu() -> NSMenu {
        let menu = trackedMenu()
        let title = NSMenuItem(title: "MacLaunch  1.2", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(ActionItem("アイテム登録…（⌘N）") { [weak self] in self?.showRegistration() })
        let skins = NSMenuItem(title: "スキン", action: nil, keyEquivalent: "")
        let skinMenu = NSMenu()
        for skin in LauncherSkinName.allCases {
            skinMenu.addItem(ActionItem(skin.title, checked: store.library.preferences.skin == skin) { [weak self] in self?.update { $0.preferences.skin = skin } })
        }
        skins.submenu = skinMenu; menu.addItem(skins)
        let display = NSMenuItem(title: "表示・ボタン配置", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.addItem(ActionItem("アイコン名を表示", checked: store.library.preferences.showLabels) { [weak self] in self?.update { $0.preferences.showLabels.toggle() } })
        displayMenu.addItem(ActionItem("タブを上に表示", checked: store.library.preferences.tabPosition == .top) { [weak self] in self?.update { $0.preferences.tabPosition = .top } })
        displayMenu.addItem(ActionItem("タブを下に表示", checked: store.library.preferences.tabPosition == .bottom) { [weak self] in self?.update { $0.preferences.tabPosition = .bottom } })
        displayMenu.addItem(.separator())
        for columns in [5, 7, 9] {
            displayMenu.addItem(ActionItem("\(columns)列", checked: store.library.preferences.columns == columns) { [weak self] in self?.update { $0.preferences.columns = columns } })
        }
        displayMenu.addItem(.separator())
        for rows in [3, 6] {
            displayMenu.addItem(ActionItem("\(rows)行を表示", checked: store.library.preferences.visibleRows == rows) { [weak self] in self?.update { $0.preferences.visibleRows = rows } })
        }
        display.submenu = displayMenu; menu.addItem(display)
        menu.addItem(.separator())
        menu.addItem(ActionItem("カーソルが外れたら隠す", checked: store.library.preferences.autoHide) { [weak self] in
            self?.update { $0.preferences.autoHide.toggle() }
        })
        let corners = NSMenuItem(title: "画面の隅から呼び出す", action: nil, keyEquivalent: "")
        let cornerMenu = NSMenu()
        for corner in Corner.allCases {
            cornerMenu.addItem(ActionItem(corner.title, checked: store.library.preferences.corner == corner) { [weak self] in
                self?.update { $0.preferences.corner = corner }
            })
        }
        corners.submenu = cornerMenu
        menu.addItem(corners)
        let shortcut = NSMenuItem(title: "呼び出しキー\(hotKeyAvailable ? "" : "（登録できませんでした）")", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        shortcutMenu.addItem(ActionItem("ショートカットを変更…") { [weak self] in self?.editShortcut() })
        shortcutMenu.addItem(.separator())
        for choice in HotKeyChoice.allCases {
            shortcutMenu.addItem(ActionItem(choice.title, checked: store.library.preferences.hotKey == choice.shortcut) { [weak self] in
                guard let self else { return }
                if self.hotKeyAvailable && self.store.library.preferences.hotKey == choice.shortcut { return }
                do {
                    try ShortcutChange.apply(choice.shortcut, to: self.store, registrar: self.hotKey)
                    self.hotKeyAvailable = true
                } catch { self.hotKeyAvailable = self.hotKey.isRegistered; self.report(error) }
                self.refresh()
            })
        }
        shortcut.submenu = shortcutMenu
        menu.addItem(shortcut)
        menu.addItem(.separator())
        menu.addItem(ActionItem("アプリ・フォルダ・ファイルを追加…") { [weak self] in self?.addItems() })
        menu.addItem(ActionItem("URLを追加…") { [weak self] in self?.editItem(nil) })
        menu.addItem(ActionItem("ページを追加…") { [weak self] in self?.addPage() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("設定を書き出す…") { [weak self] in self?.exportLibrary() })
        menu.addItem(ActionItem("設定を読み込む…") { [weak self] in self?.importLibrary() })
        menu.addItem(ActionItem("設定フォルダを開く") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.store.fileURL.deletingLastPathComponent())
        })
        menu.addItem(ActionItem("使い方") { [weak self] in self?.showHelp() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("MacLaunchを終了") { NSApp.terminate(nil) })
        return menu
    }

    private func editShortcut() {
        if !panel.isVisible { show() }
        modalDepth += 1
        // Unregister only this app's shortcut while recording, including the current binding.
        hotKey.suspend()
        defer {
            if !hotKey.isRegistered {
                do { try hotKey.register(store.library.preferences.hotKey) }
                catch { report(error) }
            }
            hotKeyAvailable = hotKey.isRegistered
            modalDepth -= 1
            outsideSince = nil
            refresh()
        }
        let alert = NSAlert()
        alert.messageText = "呼び出しショートカット"
        alert.informativeText = "入力欄をクリックして、設定したいキーの組み合わせを押してください。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "初期設定に戻す")
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: 178))
        let current = Style.label("現在：\(store.library.preferences.hotKey.title)", size: 12, color: Style.muted,
                                  frame: NSRect(x: 0, y: 0, width: 440, height: 20))
        content.addSubview(current)
        let recorder = ShortcutRecorder(shortcut: store.library.preferences.hotKey,
                                        frame: NSRect(x: 0, y: 30, width: 440, height: 56))
        content.addSubview(recorder)
        let status = Style.label("", size: 11, color: Style.muted, frame: NSRect(x: 0, y: 96, width: 440, height: 42))
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byWordWrapping
        content.addSubview(status)
        let hint = Style.label("⌘・⌃・⌥とキーを組み合わせます。F1〜F20は単独でも指定可能です。", size: 10, color: Style.muted,
                               frame: NSRect(x: 0, y: 145, width: 440, height: 32))
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping
        content.addSubview(hint)
        recorder.onStatus = { [weak recorder, weak alert] message, valid in
            guard let recorder else { return }
            status.stringValue = message ?? "\(recorder.shortcut.title) を設定します。「保存」で確定します。"
            status.textColor = valid ? Style.muted : .systemRed
            alert?.buttons[0].isEnabled = valid
        }
        alert.accessoryView = content
        alert.window.initialFirstResponder = recorder
        while true {
            let result = alert.runModal()
            if result == .alertThirdButtonReturn {
                recorder.setShortcut(.defaultValue)
                alert.window.initialFirstResponder = alert.buttons[0]
                continue
            }
            guard result == .alertFirstButtonReturn else { break }
            do {
                try ShortcutChange.apply(recorder.shortcut, to: store, registrar: hotKey)
                break
            } catch {
                report(error)
                hotKey.suspend()
                alert.window.initialFirstResponder = recorder
            }
        }
    }

    private func addMenu(slot: Int? = nil) -> NSMenu {
        let page = store.library.pages[store.library.selectedIndex]
        let position = slot ?? page.firstFreeSlot()
        let menu = trackedMenu()
        menu.addItem(ActionItem("アイテム登録…") { [weak self] in self?.showRegistration(pageID: page.id, slot: position) })
        menu.addItem(ActionItem("ファイル・フォルダを選択して登録…") { [weak self] in self?.quickFiles(pageID: page.id, slot: position) })
        menu.addItem(ActionItem("URLを登録…") { [weak self] in self?.showRegistration(pageID: page.id, slot: position, mode: .url) })
        let running = NSMenuItem(title: "起動中のアプリを登録", action: nil, keyEquivalent: "")
        let apps = NSMenu()
        for app in RegistrationSource.runningApplications {
            let action = ActionItem(app.name) { [weak self] in _ = self?.registerURLs([app.url], pageID: page.id, slot: position) }
            action.image = NSWorkspace.shared.icon(forFile: app.url.path)
            apps.addItem(action)
        }
        running.submenu = apps; menu.addItem(running)
        let folders = NSMenuItem(title: "よく使うフォルダを登録", action: nil, keyEquivalent: "")
        let folderMenu = NSMenu()
        for (name, url) in RegistrationSource.commonFolders {
            folderMenu.addItem(ActionItem(name) { [weak self] in _ = self?.registerURLs([url], pageID: page.id, slot: position) })
        }
        folders.submenu = folderMenu; menu.addItem(folders)
        menu.addItem(.separator())
        let paste = ActionItem("クリップボードから登録（⌘V）") { [weak self] in
            _ = self?.registerURLs(RegistrationSource.urls(from: .general), pageID: page.id, slot: position)
        }
        paste.isEnabled = NSPasteboard.general.availableType(from: [.fileURL, .URL, .string]) != nil
        menu.addItem(paste)
        return menu
    }

    private func itemMenu(_ item: LaunchItem) -> NSMenu {
        let menu = trackedMenu()
        menu.addItem(ActionItem("開く") { [weak self] in self?.launch(item) })
        menu.addItem(ActionItem("プロパティ…") { [weak self] in self?.editItem(item) })
        if let page = store.library.pages.first(where: { $0.items.contains { $0.id == item.id } }), let slot = page.slotAssignments[item.id] {
            menu.addItem(ActionItem("この前に空白を挿入") { [weak self] in self?.update { $0.insertBlank(in: page.id, at: slot) } })
        }
        if let url = item.url, url.isFileURL {
            menu.addItem(ActionItem("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        let move = NSMenuItem(title: "ページへ移動", action: nil, keyEquivalent: "")
        let pages = NSMenu()
        for page in store.library.pages {
            pages.addItem(ActionItem(page.name, checked: page.items.contains { $0.id == item.id }) { [weak self] in
                self?.update { $0.moveItem(item.id, to: page.id) }
            })
        }
        move.submenu = pages
        menu.addItem(move)
        menu.addItem(.separator())
        menu.addItem(ActionItem("登録を解除…") { [weak self] in
            guard let self, self.confirm("「\(item.name)」の登録を解除しますか？", detail: "元のアプリやファイルは削除されません。", button: "登録を解除") else { return }
            self.update { library in
                library.freezePositions()
                for index in library.pages.indices { library.pages[index].items.removeAll { $0.id == item.id } }
            }
        })
        return menu
    }

    private func pageMenu(_ page: LaunchPage) -> NSMenu {
        let menu = trackedMenu()
        menu.addItem(ActionItem("ページ名を変更…") { [weak self] in self?.renamePage(page) })
        let index = store.library.pages.firstIndex { $0.id == page.id }!
        if index > 0 {
            menu.addItem(ActionItem("左へ移動") { [weak self] in self?.update { $0.pages.swapAt(index, index - 1) } })
        }
        if index < store.library.pages.count - 1 {
            menu.addItem(ActionItem("右へ移動") { [weak self] in self?.update { $0.pages.swapAt(index, index + 1) } })
        }
        if store.library.pages.count > 1 {
            menu.addItem(.separator())
            menu.addItem(ActionItem("ページを削除…") { [weak self] in
                guard let self, self.confirm("「\(page.name)」を削除しますか？", detail: "このページの\(page.items.count)件の登録も解除されます。元のファイルは削除されません。", button: "ページを削除") else { return }
                self.update { $0.removePage(page.id) }
            })
        }
        return menu
    }

    @objc private func tabClicked(_ sender: NSButton) { selectPage(sender.tag) }
    private func selectPage(_ index: Int) {
        guard store.library.pages.indices.contains(index) else { return }
        query = ""; search.stringValue = ""
        update { $0.selectedPageID = $0.pages[index].id }
        panel.makeFirstResponder(root)
    }
    private func changePage(_ offset: Int) {
        guard query.isEmpty else { return }
        let count = store.library.pages.count
        selectPage((store.library.selectedIndex + offset + count) % count)
    }

    @objc private func addPage() {
        guard store.library.pages.count < 50 else { report(LibraryError.invalid("ページは最大50個です。")); return }
        guard let name = prompt("ページを追加", label: "ページ名", value: "", placeholder: "例：仕事、制作、よく使うもの") else { return }
        let page = LaunchPage(name: name)
        query = ""; search.stringValue = ""
        update { $0.pages.append(page); $0.selectedPageID = page.id }
    }

    private func renamePage(_ page: LaunchPage) {
        guard let name = prompt("ページ名を変更", label: "ページ名", value: page.name, placeholder: "ページ名") else { return }
        update { library in
            if let index = library.pages.firstIndex(where: { $0.id == page.id }) { library.pages[index].name = name }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === search else { return }
        query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        renderGrid()
    }
    @objc private func searchSubmitted() {
        if let first = visibleItems.first { launch(first) }
    }

    private func launch(_ item: LaunchItem) {
        guard let url = item.url else { return }
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
            report(LibraryError.invalid("登録先が見つかりません。右クリックの「プロパティ」から登録先を変更してください。\n\n\(url.path)"))
            return
        }
        if !pinned { hide() }
        if url.isFileURL && url.pathExtension.lowercased() == "app" {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { DispatchQueue.main.async { self?.report(error) } }
            }
        } else if !NSWorkspace.shared.open(url) {
            report(LibraryError.invalid("「\(item.name)」を開けませんでした。登録先と関連付けを確認してください。"))
        }
    }

    @objc private func addItems() { showRegistration() }

    private func editItem(_ existing: LaunchItem?) { showRegistration(existing: existing, mode: existing == nil ? .url : nil) }

    private func showRegistration(existing: LaunchItem? = nil, pageID: UUID? = nil, slot: Int? = nil, mode: RegistrationMode? = nil) {
        if !panel.isVisible { show() }
        let library = store.library
        let destination = existing.flatMap { item in library.pages.first { $0.items.contains { $0.id == item.id } }?.id }
            ?? pageID ?? library.selectedPageID
        guard let page = library.pages.first(where: { $0.id == destination }) else { return }
        var nextSlot = existing.flatMap { page.slotAssignments[$0.id] } ?? slot ?? page.firstFreeSlot()
        modalDepth += 1
        defer {
            modalDepth -= 1; outsideSince = nil
            panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(root)
        }
        let editor = RegistrationWindow(existing: existing, pageName: page.name, slot: nextSlot,
                                        columns: library.preferences.columns, mode: mode) { [weak self] items in
            guard let self else { return (0, 0) }
            var added = 0
            try self.store.update { library in
                if let existing, let replacement = items.first {
                    for p in library.pages.indices {
                        if let i = library.pages[p].items.firstIndex(where: { $0.id == existing.id }) {
                            var item = replacement
                            item.id = existing.id; item.slot = library.pages[p].items[i].slot
                            library.pages[p].items[i] = item
                            added = 1
                        }
                    }
                } else { added = library.registerItems(items, to: destination, startingAt: nextSlot) }
            }
            if let currentPage = self.store.library.pages.first(where: { $0.id == destination }) { nextSlot = currentPage.firstFreeSlot(startingAt: nextSlot) }
            self.query = ""; self.search.stringValue = ""; self.searchVisible = false
            self.refresh()
            return (added, nextSlot)
        }
        editor.runModal(relativeTo: panel)
    }

    private func quickFiles(pageID: UUID, slot: Int) {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil; panel.makeKeyAndOrderFront(nil) }
        let picker = NSOpenPanel()
        picker.title = "ファイル・フォルダを登録"
        picker.prompt = "登録"
        picker.canChooseFiles = true; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.treatsFilePackagesAsDirectories = false
        if picker.runModal() == .OK { _ = registerURLs(picker.urls, pageID: pageID, slot: slot) }
    }

    private func acceptDrop(_ pasteboard: NSPasteboard, pageID: UUID? = nil, slot: Int? = nil, copy: Bool = false) -> Bool {
        guard query.isEmpty else { footer.stringValue = "検索を閉じてからドロップしてください。"; return false }
        let destination = pageID ?? store.library.selectedPageID
        guard let page = store.library.pages.first(where: { $0.id == destination }) else { return false }
        let targetSlot = slot ?? page.firstFreeSlot()
        if let raw = pasteboard.string(forType: .launchItem), let id = UUID(uuidString: raw) {
            return update { $0.moveItem(id, to: destination, at: targetSlot, copy: copy) }
        }
        return registerURLs(RegistrationSource.urls(from: pasteboard), pageID: destination, slot: targetSlot)
    }

    @discardableResult private func registerURLs(_ urls: [URL], pageID: UUID, slot: Int) -> Bool {
        let items = urls.compactMap(RegistrationSource.item(from:))
        guard !items.isEmpty else { footer.stringValue = "登録できるファイル・フォルダ・URLがありません。"; return false }
        var count = 0
        guard update({ count = $0.registerItems(items, to: pageID, startingAt: slot) }) else { return false }
        footer.stringValue = count > 0 ? "\(count)件を登録しました。" : "このページにはすでに登録されています。"
        return count > 0
    }

    private func pasteRegistration() {
        let page = store.library.pages[store.library.selectedIndex]
        let slot = query.isEmpty ? highlightedIndex ?? page.firstFreeSlot() : page.firstFreeSlot()
        query = ""; search.stringValue = ""
        _ = registerURLs(RegistrationSource.urls(from: .general), pageID: page.id, slot: slot)
    }

    private func prompt(_ title: String, label: String, value: String, placeholder: String) -> String? {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = value
        input.placeholderString = placeholder
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        while alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if Library.validName(name) { return name }
            report(LibraryError.invalid("名前は1〜80文字で入力してください。"))
        }
        return nil
    }

    private func confirm(_ title: String, detail: String, button: String) -> Bool {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func exportLibrary() {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let picker = NSSavePanel()
        picker.title = "設定を書き出す"
        picker.nameFieldStringValue = "MacLaunch-backup.json"
        if picker.runModal() == .OK, let url = picker.url {
            do { try LibraryStore.write(store.library, to: url) }
            catch { report(error) }
        }
    }

    private func importLibrary() {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let picker = NSOpenPanel()
        picker.title = "設定を読み込む"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let next = try LibraryStore.decode(Data(contentsOf: url))
            guard confirm("設定を読み込みますか？", detail: "\(next.pages.count)ページ、\(next.pages.flatMap(\.items).count)アイテムに置き換えます。現在の設定は設定フォルダにバックアップされます。", button: "読み込む") else { return }
            let previous = store.library.preferences.hotKey
            let changed = next.preferences.hotKey != previous || !hotKeyAvailable
            if changed { try hotKey.register(next.preferences.hotKey) }
            do { try store.replace(with: next) }
            catch { if changed { try? hotKey.register(previous) }; throw error }
            hotKeyAvailable = true
            query = ""; search.stringValue = ""; icons.removeAll()
            refresh()
        } catch { report(error) }
    }

    private func showHelp() {
        modalDepth += 1
        defer { modalDepth -= 1; outsideSince = nil }
        let alert = NSAlert()
        alert.messageText = "MacLaunchの使い方"
        alert.informativeText = "メニューバーの4つの四角、または \(store.library.preferences.hotKey.title) で呼び出します。\n\n• アプリ・ファイル・URLをドロップして登録\n• アイコンをドラッグして並べ替え\n• 空きボタンをダブルクリックで登録画面\n• アプリ一覧・起動中アプリから複数登録\n• 右クリックでプロパティ・ページ移動・登録解除\n• ホイールでページ切替（項目が多い場合はタブの上で）\n• ⌘1〜9：ページ移動　⌘F：検索　⌘N：登録\n• 矢印キーで選択、Returnで起動、Escで隠す\n• 左上の鍵でウィンドウロック\n• 歯車 → スキンから外観を切替\n\n画面の隅からの呼び出しは設定から有効にできます。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
