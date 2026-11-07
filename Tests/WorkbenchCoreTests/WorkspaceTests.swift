import Foundation
import Testing
@testable import WorkbenchCore

struct WorkspaceTests {
    @Test func testCRUDAndDuplicate() throws {
        var w = try Workspace(document: WorkbenchDocument())
        let f = FolderRecord(name: "Lab"); try w.upsertFolder(f)
        let c = ConnectionRecord(folderID: f.id, name: "Server", host: "host.example", kind: .ssh)
        try w.upsert(c); let id = try w.duplicateConnection(id: c.id)
        XCTAssertTrue(id != c.id); XCTAssertEqual(w.document.connections.count, 2)
        try w.removeConnection(id: id); XCTAssertEqual(w.document.connections.map(\.id), [c.id])
    }
    @Test func testSubtreeRemovalAndRollback() throws {
        let a = FolderRecord(name: "A"), bID = UUID()
        let b = FolderRecord(id: bID, parentID: a.id, name: "B")
        var d = WorkbenchDocument(); d.folders = [a,b]
        let c = ConnectionRecord(folderID: b.id, name: "Child", host: "host.example", kind: .ssh)
        d.connections = [c]; var w = try Workspace(document: d)
        var invalid = c; invalid.port = 0
        XCTAssertThrowsError(try w.upsert(invalid)); XCTAssertEqual(w.document, d)
        XCTAssertEqual(try w.removeFolder(id: a.id), [c.id])
        XCTAssertTrue(w.document.folders.isEmpty); XCTAssertTrue(w.document.connections.isEmpty)
    }
    @Test func testFilterMatchesNameHostTagAndDescendants() throws {
        let f = FolderRecord(name: "Parent"), childID = UUID()
        var d = WorkbenchDocument(); d.folders = [f, FolderRecord(id: childID, parentID: f.id, name: "Child")]
        d.connections = [ConnectionRecord(folderID: childID, name: "Café", host: "lab.example", kind: .ssh, tags: ["urgent"], isFavorite: true), ConnectionRecord(name: "Other", host: "other.example", kind: .rdp)]
        let w = try Workspace(document: d)
        for q in ["CAFE", "LAB", "urgent"] { XCTAssertEqual(w.connections(matching: q, folderID: f.id, favoritesOnly: true).count, 1) }
        XCTAssertEqual(w.connections(matching: "Other", folderID: f.id, favoritesOnly: false).count, 0)
    }
    @Test func testSafeExportRemainsImportableWithoutMutatingSource() throws {
        var d = WorkbenchDocument()
        d.connections = [ConnectionRecord(name: "Web", host: "https://admin.example/path", kind: .web, username: "admin", credentialReference: "opaque-id", tags: ["internal"], notes: "private")]
        let w = try Workspace(document: d)
        let data = try w.exportData(removeHosts: true, removeUsernames: true)
        let exported = try ImportPreview(data: data).document
        XCTAssertEqual(exported.connections[0].host, "https://redacted.invalid")
        XCTAssertEqual(exported.connections[0].username, nil)
        XCTAssertEqual(exported.connections[0].credentialReference, nil)
        XCTAssertEqual(exported.connections[0].notes, "")
        XCTAssertTrue(exported.connections[0].tags.isEmpty)
        XCTAssertEqual(w.document, d)
        XCTAssertThrowsError(try ImportPreview(data: Data("broken".utf8)))
        XCTAssertEqual(w.document, d)
    }
    @Test func testPreservedExportFieldsAndDuplicateLongLabel() throws {
        var d = WorkbenchDocument(); d.connections = [ConnectionRecord(name: String(repeating: "a", count: 200), host: "host.example", kind: .ssh, username: "user", credentialReference: "id")]
        var w = try Workspace(document: d)
        _ = try w.duplicateConnection(id: d.connections[0].id)
        XCTAssertEqual(w.document.connections.count, 2)
        XCTAssertNoThrow(try DocumentCodec.validate(w.document))
        let e = try DocumentCodec.decode(w.exportData(removeHosts: false, removeUsernames: false))
        XCTAssertEqual(e.connections[0].host, "host.example"); XCTAssertEqual(e.connections[0].username, "user")
        XCTAssertEqual(e.connections[0].credentialReference, nil)
    }
}
