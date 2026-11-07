import Foundation
import Testing
@testable import WorkbenchCore

struct DocumentStoreTests {
    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func testSaveLoadAndPrivatePermissions() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("document.json")
        let saved = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        XCTAssertEqual(try DocumentStore.load(from: url).document, saved.document)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var d = saved.document; d.name = "Changed"
        XCTAssertEqual(try DocumentStore.save(d, to: url, expectedData: saved.sourceData).document.name, "Changed")
    }
    @Test func testRejectsModifiedAndDeletedDestination() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("document.json")
        let loaded = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        let other = Data("external".utf8); try other.write(to: url)
        XCTAssertThrowsError(try DocumentStore.save(loaded.document, to: url, expectedData: loaded.sourceData))
        XCTAssertEqual(try Data(contentsOf: url), other)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try DocumentStore.save(loaded.document, to: url, expectedData: loaded.sourceData))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @Test func testRefusesExistingNewDestinationAndInvalidSave() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("document.json")
        let loaded = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        XCTAssertThrowsError(try DocumentStore.save(loaded.document, to: url, expectedData: nil))
        var invalid = loaded.document; invalid.schemaVersion = 9
        XCTAssertThrowsError(try DocumentStore.save(invalid, to: url, expectedData: loaded.sourceData))
        XCTAssertEqual(try Data(contentsOf: url), loaded.sourceData)
    }
    @Test func testFailedLoadAndWritePreserveData() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("document.json")
        let loaded = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        XCTAssertThrowsError(try DocumentStore.load(from: dir))
        XCTAssertThrowsError(try DocumentStore.save(loaded.document, to: dir.appendingPathComponent("missing/file.json"), expectedData: nil))
        XCTAssertEqual(try Data(contentsOf: url), loaded.sourceData)
    }
    @Test func testRejectsSymlink() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("document.json"), link = dir.appendingPathComponent("link.json")
        let loaded = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertThrowsError(try DocumentStore.load(from: link))
        XCTAssertThrowsError(try DocumentStore.save(loaded.document, to: link, expectedData: loaded.sourceData))
        XCTAssertEqual(try Data(contentsOf: url), loaded.sourceData)
    }
    @Test func testSeparateCopyRejectsOriginalAndPathAliases() throws {
        let dir = try temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("original.json")
        let alias = dir.appendingPathComponent("alias.json")
        _ = try DocumentStore.save(WorkbenchDocument(), to: original, expectedData: nil)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        XCTAssertThrowsError(try DocumentStore.requireSeparateDestination(original, preserving: original))
        XCTAssertThrowsError(try DocumentStore.requireSeparateDestination(alias, preserving: original))
        XCTAssertNoThrow(try DocumentStore.requireSeparateDestination(dir.appendingPathComponent("copy.json"), preserving: original))
    }
}
