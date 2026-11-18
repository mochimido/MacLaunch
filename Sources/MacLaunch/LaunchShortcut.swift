import AppKit
import Carbon

struct LaunchShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    var keyLabel: String?

    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    static let defaultValue = LaunchShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, keyLabel }

    init(from decoder: Decoder) throws {
        // Read existing 1.0 collections without changing their pages or shortcut.
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            guard let preset = HotKeyChoice(rawValue: legacy) else {
                throw LibraryError.invalid("保存された呼び出しキーを読み込めません。")
            }
            self = preset.shortcut
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            keyCode = try values.decode(UInt32.self, forKey: .keyCode)
            modifiers = try values.decode(UInt32.self, forKey: .modifiers)
            keyLabel = try values.decodeIfPresent(String.self, forKey: .keyLabel)
        }
        try validate()
    }

    func validate() throws {
        guard Self.keyNames[keyCode] != nil, modifiers & ~Self.modifierMask == 0 else {
            throw LibraryError.invalid("このキーは呼び出しショートカットに使用できません。")
        }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 || Self.functionKeys.contains(keyCode) else {
            throw LibraryError.invalid("⌘・⌃・⌥のいずれかを組み合わせてください。F1〜F20は単独でも指定できます。")
        }
        if let keyLabel, (keyLabel.count > 12 || keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)) {
            throw LibraryError.invalid("キーの表示名が正しくありません。")
        }
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func modifierTitle(_ modifiers: UInt32) -> String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined(separator: " ")
    }

    var title: String {
        let prefix = Self.modifierTitle(modifiers)
        let key = keyLabel.flatMap { $0.isEmpty ? nil : $0 } ?? Self.keyNames[keyCode] ?? "Key \(keyCode)"
        return prefix.isEmpty ? key : prefix + " " + key
    }

    static func capture(_ event: NSEvent) throws -> Self {
        let code = UInt32(event.keyCode)
        var label: String?
        if !specialKeys.contains(code), let characters = event.characters(byApplyingModifiers: []),
           !characters.isEmpty, !characters.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            label = String(characters.uppercased().prefix(12))
        }
        let shortcut = Self(keyCode: code, modifiers: modifiers(from: event.modifierFlags), keyLabel: label)
        try shortcut.validate()
        return shortcut
    }

    // Virtual key codes keep the binding stable across Japanese/English input modes.
    static let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    static let specialKeys: Set<UInt32> = functionKeys.union([36, 48, 49, 51, 53, 65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95, 102, 104, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126])
    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 10: "§", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        64: "F17", 65: "テンキー .", 67: "テンキー ×", 69: "テンキー +", 71: "Clear", 75: "テンキー ÷", 76: "Enter",
        78: "テンキー -", 79: "F18", 80: "F19", 81: "テンキー =", 82: "テンキー 0", 83: "テンキー 1", 84: "テンキー 2",
        85: "テンキー 3", 86: "テンキー 4", 87: "テンキー 5", 88: "テンキー 6", 89: "テンキー 7", 90: "F20", 91: "テンキー 8", 92: "テンキー 9",
        93: "¥", 94: "_", 95: "テンキー ,", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 102: "英数", 103: "F11", 104: "かな",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

enum SystemShortcutConflict {
    static func isReserved(_ shortcut: LaunchShortcut) -> Bool {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let entries = array?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains { item in
            guard let code = item[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = item[kHISymbolicHotKeyModifiers as String] as? NSNumber,
                  let enabled = item[kHISymbolicHotKeyEnabled as String] as? NSNumber else { return false }
            return enabled.boolValue && code.uint32Value == shortcut.keyCode
                && modifiers.uint32Value & LaunchShortcut.modifierMask == shortcut.modifiers
        }
    }

    static func validate(_ shortcut: LaunchShortcut) throws {
        try shortcut.validate()
        if isReserved(shortcut) {
            throw LibraryError.invalid("\(shortcut.title) はmacOSのショートカットで使用されています。別の組み合わせを入力してください。")
        }
    }
}

protocol ShortcutRegistering: AnyObject {
    func register(_ shortcut: LaunchShortcut) throws
}

enum ShortcutChange {
    static func apply(_ shortcut: LaunchShortcut, to store: LibraryStore, registrar: ShortcutRegistering) throws {
        try shortcut.validate()
        let previous = store.library.preferences.hotKey
        try registrar.register(shortcut)
        do { try store.update { $0.preferences.hotKey = shortcut } }
        catch {
            // Restore the live key as well as leaving the stored preference untouched.
            do { try registrar.register(previous) }
            catch let rollbackError {
                throw LibraryError.invalid("設定の保存と元のキーの再登録に失敗しました。メニューバーから呼び出せます。\n\(rollbackError.localizedDescription)")
            }
            throw error
        }
    }
}
