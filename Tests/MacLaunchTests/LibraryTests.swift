import XCTest
@testable import MacLaunch

final class LibraryTests: XCTestCase {
    private func fixture() -> Library {
        Library(pages: [
            LaunchPage(name: "Apps", items: [LaunchItem(name: "A", target: "/Applications/A.app"), LaunchItem(name: "B", target: "https://example.com")]),
            LaunchPage(name: "Work", items: [LaunchItem(name: "C", target: "/tmp/c")])
        ])
    }

    func testMoveWithinAndAcrossPagesPreservesOrderAndIDs() throws {
        var library = fixture()
        let a = library.pages[0].items[0], b = library.pages[0].items[1], c = library.pages[1].items[0]
        library.moveItem(b.id, to: library.pages[0].id, before: a.id)
        XCTAssertEqual(library.pages[0].items.map(\.id), [b.id, a.id])
        library.moveItem(a.id, to: library.pages[1].id, before: c.id)
        XCTAssertEqual(library.pages[0].items.map(\.id), [b.id])
        XCTAssertEqual(library.pages[1].items.map(\.id), [a.id, c.id])
        library.moveItem(a.id, to: library.pages[1].id, before: a.id)
        XCTAssertEqual(library.pages[1].items.map(\.id), [a.id, c.id])
        _ = try library.validated()
    }

    func testPageDeletionAlwaysLeavesValidSelectionAndOnePage() throws {
        var library = fixture()
        library.removePage(library.selectedPageID)
        XCTAssertEqual(library.pages.count, 1)
        XCTAssertEqual(library.selectedPageID, library.pages[0].id)
        library.removePage(library.selectedPageID)
        XCTAssertEqual(library.pages.count, 1)
        _ = try library.validated()
    }

    func testRejectUnsafeTargetsAndMalformedCollections() throws {
        for input in ["javascript:alert(1)", "data:text/html,hi", "https://", "relative/path", "", "/tmp/\0foo"] {
            XCTAssertNil(LaunchItem.validTarget(input), input)
        }
        XCTAssertEqual(LaunchItem.validTarget("file:///tmp/a%20b"), "/tmp/a b")
        XCTAssertEqual(LaunchItem.validTarget("/tmp/a/../b"), "/tmp/b")
        var library = fixture()
        library.pages[1].items.append(library.pages[0].items[0])
        XCTAssertThrowsError(try library.validated())
        library = fixture(); library.selectedPageID = UUID()
        XCTAssertThrowsError(try library.validated())
        library = fixture(); library.schemaVersion = 999
        XCTAssertThrowsError(try library.validated())
    }

    func testAtomicPersistenceRollbackAndImportBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let original = fixture()
        let store = try LibraryStore(fileURL: url, defaults: original)
        XCTAssertEqual(try LibraryStore(fileURL: url, defaults: fixture()).library, original)
        let originalData = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.update { $0.pages.removeAll() })
        XCTAssertEqual(store.library, original)
        XCTAssertEqual(try Data(contentsOf: url), originalData)
        try store.update { $0.pages[0].name = "Changed" }
        XCTAssertEqual(try LibraryStore(fileURL: url, defaults: fixture()).library.pages[0].name, "Changed")
        try store.replace(with: original)
        let backup = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("library-backup-") }!
        XCTAssertEqual(try LibraryStore.decode(Data(contentsOf: backup)).pages[0].name, "Changed")
        XCTAssertEqual(store.library, original)
    }

    func testCorruptConfigurationIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maclaunch-corrupt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let broken = Data("broken configuration".utf8)
        try broken.write(to: url)
        XCTAssertThrowsError(try LibraryStore(fileURL: url, defaults: fixture()))
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }
}
