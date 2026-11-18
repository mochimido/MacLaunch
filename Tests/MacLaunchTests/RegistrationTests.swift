import XCTest
@testable import MacLaunch

final class RegistrationTests: XCTestCase {
    private func item(_ name: String, slot: Int? = nil) -> LaunchItem { LaunchItem(name: name, target: "/tmp/\(name)", slot: slot) }

    func testLegacyOrderAndExplicitEmptyButtonsArePreserved() throws {
        var page = LaunchPage(name: "Apps", items: [item("A"), item("B"), item("C", slot: 8)])
        XCTAssertEqual(page.slotAssignments[page.items[0].id], 0)
        XCTAssertEqual(page.slotAssignments[page.items[1].id], 1)
        XCTAssertNil(page.item(at: 7))
        page.freezePositions()
        page.items.removeAll { $0.name == "A" }
        XCTAssertNil(page.item(at: 0))
        XCTAssertEqual(page.item(at: 1)?.name, "B")
        XCTAssertEqual(page.item(at: 8)?.name, "C")
    }

    func testBulkRegistrationStartsAtChosenSlotAndSkipsOccupiedButtons() throws {
        let page = LaunchPage(name: "Apps", items: [item("A", slot: 0), item("B", slot: 4)])
        var library = Library(pages: [page])
        let count = library.registerItems([item("C"), item("D"), item("E"), item("A")], to: page.id, startingAt: 3)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(library.pages[0].item(at: 0)?.name, "A")
        XCTAssertEqual(library.pages[0].item(at: 3)?.name, "C")
        XCTAssertEqual(library.pages[0].item(at: 4)?.name, "B")
        XCTAssertEqual(library.pages[0].item(at: 5)?.name, "D")
        XCTAssertEqual(library.pages[0].item(at: 6)?.name, "E")
        XCTAssertNil(library.pages[0].item(at: 1))
        _ = try library.validated()
    }

    func testMovingToEmptySlotLeavesSourceEmptyAndOccupiedTargetInserts() throws {
        let a = item("A", slot: 0), b = item("B", slot: 1)
        let page = LaunchPage(name: "Apps", items: [a, b])
        var library = Library(pages: [page])
        library.moveItem(a.id, to: page.id, at: 8)
        XCTAssertNil(library.pages[0].item(at: 0))
        XCTAssertEqual(library.pages[0].item(at: 8)?.id, a.id)
        library.moveItem(a.id, to: page.id, at: 1)
        XCTAssertEqual(library.pages[0].item(at: 1)?.id, a.id)
        XCTAssertEqual(library.pages[0].item(at: 2)?.id, b.id)
        XCTAssertNil(library.pages[0].item(at: 8))
        _ = try library.validated()
    }

    func testCrossPageCopyGetsNewIDAndBlankInsertionKeepsOrder() throws {
        let a = item("A", slot: 2)
        let source = LaunchPage(name: "Apps", items: [a])
        let destination = LaunchPage(name: "Work", items: [item("B", slot: 3)])
        var library = Library(pages: [source, destination])
        library.moveItem(a.id, to: destination.id, at: 3, copy: true)
        XCTAssertEqual(library.pages[0].item(at: 2)?.id, a.id)
        XCTAssertEqual(library.pages[1].item(at: 3)?.name, "A")
        XCTAssertNotEqual(library.pages[1].item(at: 3)?.id, a.id)
        library.insertBlank(in: destination.id, at: 3)
        XCTAssertNil(library.pages[1].item(at: 3))
        XCTAssertEqual(library.pages[1].item(at: 4)?.name, "A")
        XCTAssertEqual(library.pages[1].item(at: 5)?.name, "B")
        _ = try library.validated()
    }

    func testPreferencesWithoutNewSkinFieldsKeepExistingHotkeyAndItems() throws {
        let original = Library(pages: [LaunchPage(name: "Keep", items: [item("A")])])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["preferences"] = ["autoHide": false, "corner": "bottomLeft", "hotKey": "commandShiftSpace"]
        let library = try LibraryStore.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(library.preferences.skin, .fluentLight)
        XCTAssertEqual(library.preferences.columns, 7)
        XCTAssertFalse(library.preferences.autoHide)
        XCTAssertEqual(library.preferences.corner, .bottomLeft)
        XCTAssertEqual(library.preferences.hotKey, .defaultValue)
        XCTAssertEqual(library.pages, original.pages)
    }

    func testSlotAndLayoutValidationRejectsMalformedImport() throws {
        var library = Library(pages: [LaunchPage(name: "Bad", items: [item("A", slot: 4), item("B", slot: 4)])])
        XCTAssertThrowsError(try library.validated())
        library.pages[0].items[1].slot = -1
        XCTAssertThrowsError(try library.validated())
        library.pages[0].items[1].slot = 4999
        library.preferences.columns = 0
        XCTAssertThrowsError(try library.validated())
    }

    func testURLAndWeblocRegistrationAndAppCatalogPackageBoundaries() throws {
        XCTAssertEqual(RegistrationSource.url(from: "example.com/docs", assumeHTTPS: true)?.absoluteString, "https://example.com/docs")
        XCTAssertEqual(RegistrationSource.url(from: "\"/tmp/my file\"")?.path, "/tmp/my file")
        XCTAssertNil(RegistrationSource.url(from: "javascript:alert(1)", assumeHTTPS: true))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-registration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["One.app/Contents/Hidden.app", "Utilities/Two.app", "Deep/More/NotListed.app"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let link = directory.appendingPathComponent("Example.webloc")
        let data = try PropertyListSerialization.data(fromPropertyList: ["URL": "https://example.com/path"], format: .xml, options: 0)
        try data.write(to: link)
        XCTAssertEqual(RegistrationSource.item(from: link)?.target, "https://example.com/path")
        XCTAssertEqual(Set(RegistrationSource.applications(in: [directory]).map { $0.url.lastPathComponent }), ["One.app", "Two.app"])
    }
}
