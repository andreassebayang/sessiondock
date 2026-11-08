import Foundation
import Testing
@testable import WorkbenchDesktop

struct SFTPTests {
    @Test func remoteNamesCannotEscapeTheSelectedFolder() throws {
        #expect(try SFTPPath.child("home", name: "report.txt") == "home/report.txt")
        for name in ["..", ".", "../escape", "/absolute", "a/b", "bad\0name", ""] {
            #expect(throws: (any Error).self) { try SFTPPath.child("home", name: name) }
        }
        #expect(throws: (any Error).self) { try SFTPPath.validate(String(repeating: "x", count: 4097)) }
    }
    @Test func localPublishDoesNotOverwriteWithoutConsent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("partial"), target = folder.appendingPathComponent("target")
        try Data("new".utf8).write(to: source); try Data("old".utf8).write(to: target)
        #expect(throws: (any Error).self) { try SFTPTransport.publish(source, to: target, overwrite: false) }
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        try SFTPTransport.publish(source, to: target, overwrite: true)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
    }
}
