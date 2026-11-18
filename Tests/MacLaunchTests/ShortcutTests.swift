import XCTest
import AppKit
import Carbon
@testable import MacLaunch

final class ShortcutTests: XCTestCase {
    private let custom = LaunchShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | controlKey), keyLabel: "J")

    private func fixture() -> Library {
        Library(pages: [LaunchPage(name: "Keep", items: [LaunchItem(name: "Document", target: "/tmp/document")])])
    }

    func testAllLegacyShortcutPreferencesMigrateWithoutLosingLibrary() throws {
        let original = fixture()
        let encoded = try JSONEncoder().encode(original)
        for legacy in HotKeyChoice.allCases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
            preferences["hotKey"] = legacy.rawValue
            json["preferences"] = preferences
            let migrated = try LibraryStore.decode(JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(migrated.pages, original.pages)
            XCTAssertEqual(migrated.selectedPageID, original.selectedPageID)
            XCTAssertEqual(migrated.preferences.hotKey, legacy.shortcut)
        }
    }

    func testCustomShortcutSurvivesSaveAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-shortcut-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let original = fixture()
        let store = try LibraryStore(fileURL: url, defaults: original)
        try ShortcutChange.apply(custom, to: store, registrar: FakeRegistrar())
        let reloaded = try LibraryStore(fileURL: url, defaults: fixture()).library
        XCTAssertEqual(reloaded.preferences.hotKey, custom)
        XCTAssertEqual(reloaded.preferences.hotKey.keyLabel, "J")
        XCTAssertEqual(reloaded.pages, original.pages)
    }

    func testInvalidKeysAndPlainTypingAreRejected() throws {
        for shortcut in [
            LaunchShortcut(keyCode: 0, modifiers: 0),
            LaunchShortcut(keyCode: 0, modifiers: UInt32(shiftKey)),
            LaunchShortcut(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)),
            LaunchShortcut(keyCode: 999, modifiers: UInt32(cmdKey)),
            LaunchShortcut(keyCode: 0, modifiers: 1 << 30),
            LaunchShortcut(keyCode: 0, modifiers: UInt32(cmdKey), keyLabel: "bad\nlabel")
        ] {
            XCTAssertThrowsError(try shortcut.validate())
            XCTAssertThrowsError(try JSONDecoder().decode(LaunchShortcut.self, from: JSONEncoder().encode(shortcut)))
        }
        try LaunchShortcut(keyCode: UInt32(kVK_F12), modifiers: 0).validate()
        try LaunchShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | shiftKey)).validate()
    }

    func testEventCaptureIgnoresCapsLockAndFunctionFlags() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .control, .capsLock, .function], timestamp: 0, windowNumber: 0,
            context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: UInt16(kVK_ANSI_J)))
        let captured = try LaunchShortcut.capture(event)
        XCTAssertEqual(captured, custom)
        XCTAssertEqual(LaunchShortcut(keyCode: custom.keyCode, modifiers: custom.modifiers, keyLabel: "Different"), custom)
    }

    func testRegistrationFailureLeavesPreferencesUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-conflict-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let store = try LibraryStore(fileURL: url, defaults: fixture())
        let before = try Data(contentsOf: url)
        let registrar = FakeRegistrar()
        registrar.reject = custom
        XCTAssertThrowsError(try ShortcutChange.apply(custom, to: store, registrar: registrar))
        XCTAssertEqual(store.library.preferences.hotKey, .defaultValue)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testFailedSaveRestoresThePreviouslyRegisteredShortcut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-rollback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let store = try LibraryStore(fileURL: url, defaults: fixture())
        // A directory at the destination forces an actual atomic-write failure.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let registrar = FakeRegistrar()
        XCTAssertThrowsError(try ShortcutChange.apply(custom, to: store, registrar: registrar))
        XCTAssertEqual(registrar.calls, [custom, .defaultValue])
        XCTAssertEqual(store.library.preferences.hotKey, .defaultValue)
    }
}

private final class FakeRegistrar: ShortcutRegistering {
    var calls: [LaunchShortcut] = []
    var reject: LaunchShortcut?
    func register(_ shortcut: LaunchShortcut) throws {
        calls.append(shortcut)
        if shortcut == reject { throw LibraryError.invalid("Shortcut is in use") }
    }
}
