import AppKit

enum RegistrationMode: Int { case applications, files, url }

final class RegistrationDropWell: FlippedView {
    var onURLs: (([URL]) -> Void)?
    var headline = "ここへドロップして選択"
    private var active = false { didSet { needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("ファイルまたはURLのドロップ先")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { active = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { active = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        active = false
        let urls = RegistrationSource.urls(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onURLs?(urls)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        (active ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (active ? NSColor.controlAccentColor : .separatorColor).setStroke()
        path.setLineDash([5, 4], count: 2, phase: 0)
        path.stroke()
        let icon = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        icon?.draw(in: NSRect(x: (bounds.width - 30) / 2, y: bounds.height / 2 - 42, width: 30, height: 30))
        let text = NSAttributedString(string: headline, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: bounds.height / 2 + 4))
    }
}

final class RegistrationWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let existing: LaunchItem?
    private let onCommit: ([LaunchItem]) throws -> (count: Int, nextSlot: Int)
    private let pageName: String
    private let columns: Int
    private let destinationLabel = NSTextField(labelWithString: "")
    private let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 644, height: 586))
    private let source = FlippedView(frame: NSRect(x: 20, y: 119, width: 604, height: 244))
    private var mode: RegistrationMode
    private var catalog: [ApplicationEntry] = []
    private var rows: [ApplicationEntry] = []
    private var pendingURLs: [URL] = []
    private var isUpdating = false
    private var catalogLoaded = false
    private let modeControl = NSSegmentedControl()
    private let appFilter = NSSearchField()
    private let appScope = NSSegmentedControl()
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let pathField = NSTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton()
    private let keepOpen = NSButton(checkboxWithTitle: "登録後も開いたままにする", target: nil, action: nil)
    private let preview = NSImageView()

    init(existing: LaunchItem? = nil, pageName: String, slot: Int, columns: Int,
         mode: RegistrationMode? = nil, onCommit: @escaping ([LaunchItem]) throws -> (count: Int, nextSlot: Int)) {
        self.existing = existing
        self.onCommit = onCommit
        self.pageName = pageName
        self.columns = columns
        self.mode = mode ?? existing.map { item in item.url?.isFileURL == false ? .url : (item.url?.pathExtension.lowercased() == "app" ? .applications : .files) } ?? .applications
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 644, height: 586), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = existing == nil ? "アイテムの登録" : "アイテムのプロパティ"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.level = .modalPanel
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(hex: 0xF4F4F6).cgColor
        preview.frame = NSRect(x: 22, y: 23, width: 32, height: 32)
        preview.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        root.addSubview(preview)
        root.addSubview(Style.label(existing == nil ? "アイテムの登録" : "アイテムのプロパティ", size: 17, weight: .semibold,
                                    frame: NSRect(x: 66, y: 18, width: 540, height: 25)))
        destinationLabel.frame = NSRect(x: 66, y: 46, width: 540, height: 18)
        destinationLabel.font = .systemFont(ofSize: 11)
        destinationLabel.textColor = .secondaryLabelColor
        updateDestination(slot)
        root.addSubview(destinationLabel)
        modeControl.segmentCount = 3
        for (i, name) in ["アプリ", "ファイル・フォルダ", "URL"].enumerated() { modeControl.setLabel(name, forSegment: i); modeControl.setWidth(199, forSegment: i) }
        modeControl.frame = NSRect(x: 20, y: 79, width: 604, height: 27)
        modeControl.selectedSegment = self.mode.rawValue
        modeControl.target = self; modeControl.action = #selector(sourceModeChanged)
        root.addSubview(modeControl)
        root.addSubview(source)

        root.addSubview(Style.label("登録名", size: 12, frame: NSRect(x: 20, y: 388, width: 72, height: 20)))
        nameField.frame = NSRect(x: 94, y: 383, width: 530, height: 26)
        nameField.placeholderString = "自動入力されます。好きな名前に変更できます。"
        nameField.delegate = self
        nameField.setAccessibilityLabel("登録名")
        root.addSubview(nameField)
        root.addSubview(Style.label("登録先", size: 12, frame: NSRect(x: 20, y: 427, width: 72, height: 20)))
        pathField.frame = NSRect(x: 94, y: 422, width: 440, height: 26)
        pathField.delegate = self
        pathField.setAccessibilityLabel("ファイルまたはURL")
        root.addSubview(pathField)
        let browse = button("参照…", frame: NSRect(x: 542, y: 420, width: 82, height: 30), action: #selector(browseAny))
        root.addSubview(browse)
        status.frame = NSRect(x: 94, y: 458, width: 530, height: 36)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        root.addSubview(status)
        let line = NSBox(frame: NSRect(x: 20, y: 502, width: 604, height: 1)); line.boxType = .separator
        root.addSubview(line)
        keepOpen.frame = NSRect(x: 20, y: 539, width: 300, height: 22)
        keepOpen.isHidden = existing != nil
        root.addSubview(keepOpen)
        let cancel = button("キャンセル", frame: NSRect(x: 424, y: 533, width: 96, height: 32), action: #selector(cancel))
        cancel.keyEquivalent = "\u{1B}"
        root.addSubview(cancel)
        saveButton.frame = NSRect(x: 528, y: 533, width: 96, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.title = existing == nil ? "登録" : "保存"
        saveButton.keyEquivalent = "\r"
        saveButton.target = self; saveButton.action = #selector(commit)
        root.addSubview(saveButton)
        if let existing {
            nameField.stringValue = existing.name
            pathField.stringValue = existing.target
            if let url = existing.url { setPreview(url) }
        }
        buildSource()
        validateForm()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = RegistrationSource.applications()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.catalog = apps
                self.catalogLoaded = true
                if self.mode == .applications { self.filterApps() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String, frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame; button.bezelStyle = .rounded
        return button
    }

    func runModal(relativeTo parent: NSWindow?) {
        guard let window else { return }
        if let screen = parent?.screen {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(mode == .applications ? appFilter : pathField)
        NSApp.runModal(for: window)
        window.orderOut(nil)
    }

    @objc private func sourceModeChanged() {
        guard let chosen = RegistrationMode(rawValue: modeControl.selectedSegment) else { return }
        mode = chosen
        if pendingURLs.count > 1 {
            pendingURLs = []; nameField.stringValue = ""; pathField.stringValue = ""
            nameField.isEnabled = true; pathField.isEnabled = true
        }
        buildSource()
        window?.makeFirstResponder(mode == .applications ? appFilter : pathField)
    }

    private func updateDestination(_ slot: Int) {
        destinationLabel.stringValue = "登録先：\(pageName)  ／  \(slot / columns + 1)行 \(slot % columns + 1)列"
    }

    private func buildSource() {
        source.subviews.forEach { $0.removeFromSuperview() }
        switch mode {
        case .applications:
            appFilter.frame = NSRect(x: 0, y: 0, width: 386, height: 27)
            appFilter.placeholderString = "アプリ名で検索"
            appFilter.setAccessibilityLabel("登録するアプリを検索")
            appFilter.delegate = self
            appFilter.sendsSearchStringImmediately = true
            source.addSubview(appFilter)
            appScope.segmentCount = 2
            appScope.setLabel("すべて", forSegment: 0); appScope.setLabel("起動中", forSegment: 1)
            appScope.setWidth(98, forSegment: 0); appScope.setWidth(98, forSegment: 1)
            appScope.frame = NSRect(x: 404, y: 0, width: 200, height: 27)
            if appScope.selectedSegment < 0 { appScope.selectedSegment = 0 }
            appScope.target = self; appScope.action = #selector(scopeChanged)
            source.addSubview(appScope)
            if table.tableColumns.isEmpty {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
                column.width = 580
                table.addTableColumn(column)
                table.headerView = nil
                table.rowHeight = 38
                table.allowsMultipleSelection = existing == nil
                table.style = .inset
                table.delegate = self; table.dataSource = self
                table.target = self; table.doubleAction = #selector(commit)
                table.setAccessibilityLabel("登録できるアプリ一覧")
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 36, width: 604, height: 208))
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            scroll.borderType = .bezelBorder
            scroll.documentView = table
            source.addSubview(scroll)
            filterApps()
        case .files:
            let well = RegistrationDropWell(frame: NSRect(x: 0, y: 0, width: 604, height: 176))
            well.headline = "ファイル・フォルダをここにドロップ（複数可）"
            well.onURLs = { [weak self] in self?.setURLs($0) }
            source.addSubview(well)
            source.addSubview(button("ファイルを選択…", frame: NSRect(x: 0, y: 195, width: 174, height: 32), action: #selector(browseFiles)))
            source.addSubview(button("フォルダを選択…", frame: NSRect(x: 182, y: 195, width: 174, height: 32), action: #selector(browseFolders)))
            let common = NSPopUpButton(frame: NSRect(x: 372, y: 196, width: 232, height: 30))
            common.addItem(withTitle: "よく使うフォルダから選択")
            for (name, url) in RegistrationSource.commonFolders { common.addItem(withTitle: name); common.lastItem?.representedObject = url }
            common.target = self; common.action = #selector(commonFolder(_:))
            source.addSubview(common)
        case .url:
            let well = RegistrationDropWell(frame: NSRect(x: 0, y: 0, width: 604, height: 145))
            well.headline = "ブラウザのURL・リンクをここにドロップ"
            well.onURLs = { [weak self] in self?.setURLs($0) }
            source.addSubview(well)
            source.addSubview(button("クリップボードから入力", frame: NSRect(x: 0, y: 164, width: 218, height: 32), action: #selector(pasteURL)))
            let helper = Style.label("下の「登録先」にURLを入力しても登録できます。\n例：https://example.com", size: 12, color: .secondaryLabelColor,
                                     frame: NSRect(x: 0, y: 207, width: 604, height: 36))
            helper.maximumNumberOfLines = 2
            source.addSubview(helper)
        }
        pathField.placeholderString = mode == .url ? "https://example.com" : "/Applications/… またはファイルのパス"
        validateForm()
    }

    @objc private func scopeChanged() { filterApps() }
    private func filterApps() {
        let all = appScope.selectedSegment == 1 ? RegistrationSource.runningApplications : catalog
        let text = appFilter.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = text.isEmpty ? all : all.filter { $0.name.localizedStandardContains(text) }
        isUpdating = true
        table.reloadData()
        isUpdating = false
        if pathField.stringValue.isEmpty {
            status.stringValue = !catalogLoaded && appScope.selectedSegment == 0 ? "アプリを読み込んでいます…" : "\(rows.count)件のアプリ。⌘クリック・Shiftクリックでまとめて選択できます。"
            status.textColor = .secondaryLabelColor
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let entry = rows[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 580, height: 38))
        let icon = NSImageView(frame: NSRect(x: 6, y: 7, width: 24, height: 24))
        icon.image = NSWorkspace.shared.icon(forFile: entry.url.path)
        cell.addSubview(icon); cell.imageView = icon
        let text = NSTextField(labelWithString: entry.name)
        text.font = .systemFont(ofSize: 12)
        text.frame = NSRect(x: 40, y: 11, width: 530, height: 18)
        text.lineBreakMode = .byTruncatingTail
        cell.addSubview(text); cell.textField = text
        cell.toolTip = entry.url.path
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].url : nil }
        if !selected.isEmpty { setURLs(selected) }
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === appFilter { filterApps(); return }
        if obj.object as? NSTextField === pathField { pendingURLs = [] }
        validateForm()
    }

    private func setURLs(_ urls: [URL]) {
        pendingURLs = existing == nil ? urls : Array(urls.prefix(1))
        let items = pendingURLs.compactMap(RegistrationSource.item(from:))
        guard let first = items.first else { setStatus("登録できるファイルまたはURLを選択してください。", error: true); return }
        nameField.isEnabled = items.count == 1
        pathField.isEnabled = items.count == 1
        if items.count == 1 {
            if existing == nil || nameField.stringValue.isEmpty { nameField.stringValue = first.name }
            pathField.stringValue = first.target
        } else {
            nameField.stringValue = "\(items.count)件をまとめて登録"
            pathField.stringValue = items.map(\.name).joined(separator: "、")
        }
        if let url = first.url { setPreview(url) }
        validateForm()
    }

    private func setPreview(_ url: URL) {
        preview.image = url.isFileURL ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
    }

    private func itemsFromForm() throws -> [LaunchItem] {
        if pendingURLs.count > 1 { return pendingURLs.compactMap(RegistrationSource.item(from:)) }
        guard let url = RegistrationSource.url(from: pathField.stringValue, assumeHTTPS: mode == .url),
              var item = RegistrationSource.item(from: url) else { throw LibraryError.invalid("アプリを選ぶか、正しいファイルのパス・URLを入力してください。") }
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
            throw LibraryError.invalid("登録先が見つかりません。「参照…」から選び直してください。")
        }
        let title = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { item.name = title }
        guard Library.validName(item.name) else { throw LibraryError.invalid("登録名は1〜80文字で入力してください。") }
        if let existing { item.id = existing.id; item.slot = existing.slot }
        return [item]
    }

    private func validateForm() {
        do {
            let items = try itemsFromForm()
            saveButton.isEnabled = !items.isEmpty
            saveButton.title = existing == nil ? (items.count > 1 ? "\(items.count)件を登録" : "登録") : "保存"
            setStatus(items.count > 1 ? "選択した\(items.count)件を、空いているボタンへ順番に登録します。" : "登録名は省略できます。登録先から自動で名前を設定します。")
        } catch {
            saveButton.isEnabled = false
            if pathField.stringValue.isEmpty { setStatus("一覧から選ぶ、ドロップする、または登録先を入力してください。") }
            else { setStatus(error.localizedDescription, error: true) }
        }
    }
    private func setStatus(_ text: String, error: Bool = false) {
        status.stringValue = text
        status.textColor = error ? .systemRed : .secondaryLabelColor
    }

    @objc private func commit() {
        do {
            let items = try itemsFromForm()
            guard !items.isEmpty else { return }
            let result = try onCommit(items)
            let count = result.count
            guard count > 0 else { setStatus("選択したアイテムは、このページにすでに登録されています。", error: true); return }
            if keepOpen.state == .on && existing == nil {
                pendingURLs = []
                nameField.isEnabled = true; pathField.isEnabled = true
                nameField.stringValue = ""; pathField.stringValue = ""
                isUpdating = true; table.deselectAll(nil); isUpdating = false
                saveButton.isEnabled = false
                saveButton.title = "登録"
                preview.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
                updateDestination(result.nextSlot)
                setStatus("\(count)件を登録しました。続けて次のアイテムを選べます。")
                status.textColor = .systemGreen
            } else { cancel() }
        } catch { setStatus(error.localizedDescription, error: true) }
    }

    @objc private func cancel() { NSApp.stopModal(); window?.orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.stopModal(); return true }
    @objc private func browseAny() { browse(files: true, directories: true) }
    @objc private func browseFiles() { browse(files: true, directories: false) }
    @objc private func browseFolders() { browse(files: false, directories: true) }
    private func browse(files: Bool, directories: Bool) {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = files; picker.canChooseDirectories = directories
        picker.allowsMultipleSelection = existing == nil
        picker.treatsFilePackagesAsDirectories = false
        picker.prompt = "選択"
        picker.beginSheetModal(for: window) { [weak self] result in
            if result == .OK { self?.setURLs(picker.urls) }
        }
    }
    @objc private func commonFolder(_ sender: NSPopUpButton) {
        if let url = sender.selectedItem?.representedObject as? URL { setURLs([url]) }
    }
    @objc private func pasteURL() {
        let urls = RegistrationSource.urls(from: .general)
        if urls.isEmpty { setStatus("クリップボードにURLまたはファイルのパスがありません。", error: true) }
        else { setURLs(urls) }
    }
}
