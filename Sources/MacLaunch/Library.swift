import Foundation

struct LaunchItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var target: String
    var slot: Int? = nil

    var url: URL? {
        guard let normalized = Self.validTarget(target) else { return nil }
        if normalized.hasPrefix("/") { return URL(fileURLWithPath: normalized) }
        return URL(string: normalized)
    }

    static func validTarget(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\0") else { return nil }
        if value.hasPrefix("/") || value.hasPrefix("~/") {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        guard let url = URL(string: value) else { return nil }
        if url.isFileURL {
            guard (url.host == nil || url.host == "" || url.host == "localhost"), url.path.hasPrefix("/") else { return nil }
            return url.standardizedFileURL.path
        }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url.absoluteString
    }
}

struct LaunchPage: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var items: [LaunchItem] = []

    /// Old collections have no explicit slots. Preserve their order while reserving saved positions.
    var slotAssignments: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var occupied = Set(items.compactMap(\.slot))
        for item in items { if let slot = item.slot { result[item.id] = slot } }
        var next = 0
        for item in items where item.slot == nil {
            while occupied.contains(next) { next += 1 }
            result[item.id] = next
            occupied.insert(next)
        }
        return result
    }

    func item(at slot: Int) -> LaunchItem? {
        let assignments = slotAssignments
        return items.first { assignments[$0.id] == slot }
    }

    func firstFreeSlot(startingAt start: Int = 0) -> Int {
        let occupied = Set(slotAssignments.values)
        var next = max(0, start)
        while occupied.contains(next) { next += 1 }
        return next
    }

    mutating func freezePositions() {
        let positions = slotAssignments
        for index in items.indices { items[index].slot = positions[items[index].id] }
        items.sort { ($0.slot ?? 0) < ($1.slot ?? 0) }
    }
}

enum LauncherSkinName: String, Codable, CaseIterable {
    case fluentLight, solidDark, glass
    var title: String {
        switch self { case .fluentLight: return "Fluent Light"; case .solidDark: return "Solid Dark"; case .glass: return "Glass Blue" }
    }
}

enum TabPosition: String, Codable { case top, bottom }

enum HotKeyChoice: String, Codable, CaseIterable {
    case commandShiftSpace, controlOptionSpace, commandOptionSpace
    var shortcut: LaunchShortcut {
        switch self {
        case .commandShiftSpace: return .defaultValue
        case .controlOptionSpace: return LaunchShortcut(keyCode: 49, modifiers: 4096 | 2048)
        case .commandOptionSpace: return LaunchShortcut(keyCode: 49, modifiers: 256 | 2048)
        }
    }
    var title: String { shortcut.title }
}

enum Corner: String, Codable, CaseIterable {
    case disabled, bottomRight, bottomLeft, topRight, topLeft
    var title: String {
        switch self {
        case .disabled: return "使用しない"
        case .bottomRight: return "右下"
        case .bottomLeft: return "左下"
        case .topRight: return "右上"
        case .topLeft: return "左上"
        }
    }
}

struct Preferences: Codable, Equatable {
    var autoHide = true
    var corner: Corner = .disabled
    var hotKey: LaunchShortcut = .defaultValue
    var skin: LauncherSkinName = .fluentLight
    var columns = 7
    var visibleRows = 3
    var showLabels = true
    var tabPosition: TabPosition = .top

    init() {}
    private enum CodingKeys: String, CodingKey { case autoHide, corner, hotKey, skin, columns, visibleRows, showLabels, tabPosition }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        autoHide = try values.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        corner = try values.decodeIfPresent(Corner.self, forKey: .corner) ?? .disabled
        hotKey = try values.decodeIfPresent(LaunchShortcut.self, forKey: .hotKey) ?? .defaultValue
        skin = try values.decodeIfPresent(LauncherSkinName.self, forKey: .skin) ?? .fluentLight
        columns = try values.decodeIfPresent(Int.self, forKey: .columns) ?? 7
        visibleRows = try values.decodeIfPresent(Int.self, forKey: .visibleRows) ?? 3
        showLabels = try values.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true
        tabPosition = try values.decodeIfPresent(TabPosition.self, forKey: .tabPosition) ?? .top
    }
}

enum LibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct Library: Codable, Equatable {
    var schemaVersion = 1
    var pages: [LaunchPage]
    var selectedPageID: UUID
    var preferences = Preferences()

    init(pages: [LaunchPage]) {
        self.pages = pages
        selectedPageID = pages.first?.id ?? UUID()
    }

    var selectedIndex: Int { pages.firstIndex { $0.id == selectedPageID } ?? 0 }

    func validated() throws -> Library {
        try preferences.hotKey.validate()
        guard (5...12).contains(preferences.columns), (2...12).contains(preferences.visibleRows) else {
            throw LibraryError.invalid("表示するボタンの列数または行数が正しくありません。")
        }
        guard schemaVersion == 1 else { throw LibraryError.invalid("このバージョンでは読み込めない設定形式です。") }
        guard (1...50).contains(pages.count) else { throw LibraryError.invalid("ページ数は1〜50にしてください。") }
        guard Set(pages.map(\.id)).count == pages.count,
              pages.contains(where: { $0.id == selectedPageID }) else {
            throw LibraryError.invalid("ページの識別情報が正しくありません。")
        }
        let items = pages.flatMap(\.items)
        guard items.count <= 5000, Set(items.map(\.id)).count == items.count else {
            throw LibraryError.invalid("登録アイテム数が多すぎるか、識別情報が重複しています。")
        }
        for page in pages {
            guard Self.validName(page.name) else { throw LibraryError.invalid("ページ名は1〜80文字で入力してください。") }
            let slots = page.items.compactMap(\.slot)
            guard slots.allSatisfy({ (0..<5000).contains($0) }), Set(slots).count == slots.count else {
                throw LibraryError.invalid("ボタンの位置が重複しているか、範囲を超えています。")
            }
        }
        for item in items {
            guard Self.validName(item.name), LaunchItem.validTarget(item.target) != nil else {
                throw LibraryError.invalid("登録名または登録先が正しくありません。ファイルの絶対パス、http / https のURLを指定してください。")
            }
        }
        return self
    }

    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && !name.contains("\0")
    }

    mutating func moveItem(_ id: UUID, to pageID: UUID, before targetID: UUID? = nil) {
        guard id != targetID, let destination = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let positions = pages[destination].slotAssignments
        let slot = targetID.flatMap { positions[$0] } ?? ((positions.values.max() ?? -1) + 1)
        moveItem(id, to: pageID, at: slot)
    }

    mutating func freezePositions() { for index in pages.indices { pages[index].freezePositions() } }

    mutating func moveItem(_ id: UUID, to pageID: UUID, at slot: Int, copy: Bool = false) {
        guard (0..<5000).contains(slot),
              let source = pages.firstIndex(where: { $0.items.contains { $0.id == id } }),
              let destination = pages.firstIndex(where: { $0.id == pageID }) else { return }
        freezePositions()
        guard let index = pages[source].items.firstIndex(where: { $0.id == id }) else { return }
        if !copy && source == destination && pages[source].items[index].slot == slot { return }
        var item = pages[source].items[index]
        if copy { item.id = UUID() } else { pages[source].items.remove(at: index) }
        if pages[destination].items.contains(where: { $0.slot == slot }) {
            for i in pages[destination].items.indices where (pages[destination].items[i].slot ?? 0) >= slot {
                pages[destination].items[i].slot! += 1
            }
        }
        item.slot = slot
        pages[destination].items.append(item)
        pages[destination].freezePositions()
    }

    /// Fill the chosen empty button, then the next available buttons; never replace occupied buttons.
    @discardableResult mutating func registerItems(_ incoming: [LaunchItem], to pageID: UUID, startingAt slot: Int) -> Int {
        guard let page = pages.firstIndex(where: { $0.id == pageID }) else { return 0 }
        freezePositions()
        var next = max(0, slot)
        var added = 0
        for var item in incoming {
            if pages[page].items.contains(where: { $0.target == item.target }) { continue }
            next = pages[page].firstFreeSlot(startingAt: next)
            item.id = UUID()
            item.slot = next
            pages[page].items.append(item)
            next += 1
            added += 1
        }
        pages[page].freezePositions()
        return added
    }

    mutating func insertBlank(in pageID: UUID, at slot: Int) {
        freezePositions()
        guard let page = pages.firstIndex(where: { $0.id == pageID }) else { return }
        for index in pages[page].items.indices where (pages[page].items[index].slot ?? 0) >= slot {
            pages[page].items[index].slot! += 1
        }
    }

    mutating func removePage(_ id: UUID) {
        guard pages.count > 1, pages.contains(where: { $0.id == id }) else { return }
        let oldIndex = selectedIndex
        pages.removeAll { $0.id == id }
        if selectedPageID == id { selectedPageID = pages[min(oldIndex, pages.count - 1)].id }
    }
}

final class LibraryStore {
    let fileURL: URL
    private(set) var library: Library

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacLaunch/library.json")
    }

    init(fileURL: URL, defaults: @autoclosure () -> Library) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            library = try Self.decode(Data(contentsOf: fileURL))
        } else {
            library = try defaults().validated()
            try Self.write(library, to: fileURL)
        }
    }

    static func decode(_ data: Data) throws -> Library {
        guard data.count < 10_000_000 else { throw LibraryError.invalid("設定ファイルが大きすぎます（上限10MB）。") }
        return try JSONDecoder().decode(Library.self, from: data).validated()
    }

    static func write(_ library: Library, to url: URL) throws {
        _ = try library.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(library)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    func update(_ mutate: (inout Library) -> Void) throws {
        var next = library
        mutate(&next)
        try Self.write(next, to: fileURL)
        library = next
    }

    func replace(with next: Library) throws {
        _ = try next.validated()
        // Keep a recoverable copy before replacing a user's collection.
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("library-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        try Self.write(next, to: fileURL)
        library = next
    }
}
