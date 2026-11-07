import Testing
import Foundation
@testable import WorkbenchCore

struct DocumentCodecTests {
    func sample() -> WorkbenchDocument {
        var d = WorkbenchDocument()
        d.connections = [ConnectionRecord(name: "Lab", host: "lab.example", kind: .ssh)]
        return d
    }
    @Test func testRoundTrip() throws {
        let d = sample()
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(d)), d)
    }
    @Test func testUnsupportedVersion() {
        var d = sample(); d.schemaVersion = 2
        XCTAssertThrowsError(try DocumentCodec.encode(d))
    }
    @Test func testDuplicateIDsAcrossEntities() {
        var d = sample(); d.folders = [FolderRecord(id: d.connections[0].id, name: "Folder")]
        XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testMissingParent() {
        var d = sample(); d.connections[0].folderID = UUID()
        XCTAssertThrowsError(try DocumentCodec.validate(d))
        d = sample(); d.folders = [FolderRecord(parentID: UUID(), name: "Orphan")]
        XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testFolderCycle() {
        let a = UUID(), b = UUID()
        var d = sample(); d.folders = [FolderRecord(id: a, parentID: b, name: "A"), FolderRecord(id: b, parentID: a, name: "B")]
        XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testDepthBoundary() throws {
        var d = sample(); var parent: UUID?
        for _ in 0..<32 { let f = FolderRecord(parentID: parent, name: "Level"); d.folders.append(f); parent = f.id }
        XCTAssertNoThrow(try DocumentCodec.validate(d))
        d.folders.append(FolderRecord(parentID: parent, name: "Too deep"))
        XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testEntryLimit() {
        var d = WorkbenchDocument()
        d.connections = (0..<10_000).map { _ in ConnectionRecord(name: "Host", host: "h.example", kind: .ssh) }
        XCTAssertNoThrow(try DocumentCodec.validate(d))
        d.folders = [FolderRecord(name: "Excess")]
        XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testByteLimit() throws {
        let data = try DocumentCodec.encode(sample())
        var padded = data; padded.append(Data(repeating: 32, count: 10 * 1024 * 1024 - data.count))
        XCTAssertNoThrow(try DocumentCodec.decode(padded))
        padded.append(32)
        XCTAssertThrowsError(try DocumentCodec.decode(padded))
    }
    @Test func testInvalidPortAndHost() {
        for host in ["-oProxyCommand=x", "host name", "foo\nbar", "ssh://host", "host/path", "user@host", "999.999.999.999", "foo..bar"] {
            var d = sample(); d.connections[0].host = host
            XCTAssertThrowsError(try DocumentCodec.validate(d), host)
        }
        for host in ["example.org", "127.0.0.1", "::1", "2001:db8::1"] {
            var d = sample(); d.connections[0].host = host
            XCTAssertNoThrow(try DocumentCodec.validate(d), host)
        }
        for port in [0, -1, 65536] {
            var d = sample(); d.connections[0].port = port
            XCTAssertThrowsError(try DocumentCodec.validate(d))
        }
        for port in [1, 65535] {
            var d = sample(); d.connections[0].port = port
            XCTAssertNoThrow(try DocumentCodec.validate(d))
        }
    }
    @Test func testWebRejectsUserinfoAndDangerousSchemes() {
        for url in ["https://user:password@example.com", "javascript:alert(1)", "file:///tmp/a", "https://example.com?q=secret", "https://example.com/#secret"] {
            var d = sample(); d.connections[0].kind = .web; d.connections[0].host = url
            XCTAssertThrowsError(try DocumentCodec.validate(d))
        }
        var d = sample(); d.connections[0].kind = .web; d.connections[0].host = "https://example.com/admin"
        XCTAssertNoThrow(try DocumentCodec.validate(d))
    }
    @Test func testRejectsSecretsAndUnknownFields() throws {
        let bytes = try DocumentCodec.encode(sample())
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        obj["password"] = "do-not-log"
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: obj)))
        obj.removeValue(forKey: "password")
        var connections = try XCTUnwrap(obj["connections"] as? [[String: Any]])
        connections[0]["options"] = ["privateKey": "do-not-log"]; obj["connections"] = connections
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: obj)))
    }
    @Test func testLabelAndHostBounds() {
        var d = sample(); d.connections[0].name = String(repeating: "é", count: 200)
        XCTAssertNoThrow(try DocumentCodec.validate(d))
        d.connections[0].name.append("é"); XCTAssertThrowsError(try DocumentCodec.validate(d))
        d = sample(); d.name = " \n "; XCTAssertThrowsError(try DocumentCodec.validate(d))
        let host = [63, 63, 63, 61].map { String(repeating: "a", count: $0) }.joined(separator: ".")
        d = sample(); d.connections[0].host = host; XCTAssertEqual(host.count, 253)
        XCTAssertNoThrow(try DocumentCodec.validate(d))
        d.connections[0].host.append("a"); XCTAssertThrowsError(try DocumentCodec.validate(d))
    }
    @Test func testErrorsDoNotEchoImportedSecrets() {
        do { _ = try DocumentCodec.decode(Data("{\"password\":\"do-not-log\"}".utf8)); XCTFail("Expected rejection") }
        catch { XCTAssertFalse(error.localizedDescription.contains("do-not-log")) }
    }
}
