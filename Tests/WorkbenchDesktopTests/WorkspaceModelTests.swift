import Foundation
import Testing
import WorkbenchCore
@testable import WorkbenchDesktop

@MainActor struct WorkspaceModelTests {
    @Test func editingDisconnectedProfileInvalidatesOldSession() throws {
        let model = WorkspaceModel()
        var record = ConnectionRecord(name: "Fixture", host: "old.example", kind: .ssh)
        try model.saveConnection(record)
        model.sessions[record.id] = RemoteSession(connection: record)
        record.host = "new.example"
        try model.saveConnection(record)
        #expect(model.sessions[record.id] == nil)
    }
    @Test func invalidEditDoesNotChangeDocumentOrDirtyState() throws {
        let m = WorkspaceModel()
        let before = m.workspace.document
        let invalid = ConnectionRecord(name: "Bad", host: "-flag", kind: .ssh)
        #expect(throws: (any Error).self) { try m.saveConnection(invalid) }
        #expect(m.workspace.document == before)
        #expect(!m.isDirty)
    }
    @Test func deleteSubtreeClosesItsTabs() throws {
        let m = WorkspaceModel()
        let f = FolderRecord(name: "Lab"); try m.saveFolder(f)
        let c = ConnectionRecord(folderID: f.id, name: "Server", host: "host.example", kind: .ssh)
        try m.saveConnection(c); m.openTab(c.id)
        #expect(m.openTabIDs == [c.id])
        try m.deleteFolder(f.id)
        #expect(m.openTabIDs.isEmpty)
        #expect(m.activeTabID == nil)
        #expect(m.workspace.document.connections.isEmpty)
    }
    @Test func importPreviewCancelDoesNotMutateAndCommitDetachesOriginalFile() throws {
        let m = WorkspaceModel()
        let c = ConnectionRecord(name: "Local", host: "local.example", kind: .ssh)
        try m.saveConnection(c)
        let before = m.workspace.document
        let preview = try ImportPreview(data: DocumentCodec.encode(WorkbenchDocument()))
        #expect(m.workspace.document == before)
        m.commitImport(preview)
        #expect(m.workspace.document.connections.isEmpty)
        #expect(m.loadedFile == nil)
        #expect(m.isDirty)
    }
    @Test func tabCloseDoesNotDeleteConfiguration() throws {
        let m = WorkspaceModel()
        let c = ConnectionRecord(name: "Host", host: "host.example", kind: .rdp)
        try m.saveConnection(c); m.openTab(c.id); m.openTab(c.id)
        #expect(m.openTabIDs.count == 1)
        m.closeTab(c.id)
        #expect(m.workspace.document.connections.count == 1)
        #expect(m.openTabIDs.isEmpty)
    }
    @Test func openCurrentFileAfterSavingUsesNewBytes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("workspace.json")
        let original = try DocumentStore.save(WorkbenchDocument(), to: url, expectedData: nil)
        let m = WorkspaceModel()
        let c = ConnectionRecord(name: "New edit", host: "new.example", kind: .ssh)
        try m.saveConnection(c)
        await m.loadDocument(from: url, importing: false) {
            do { _ = try DocumentStore.save(m.workspace.document, to: url, expectedData: original.sourceData); return true }
            catch { Issue.record("Fixture save failed"); return false }
        }
        #expect(m.workspace.document.connections.map(\.id) == [c.id])
        #expect(m.loadedFile?.sourceData == (try Data(contentsOf: url)))
        #expect(!m.isDirty)
    }
    @Test func closingTabStopsItsPTYAndPreservesConfiguration() async throws {
        let m = WorkspaceModel()
        let c = ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .ssh)
        try m.saveConnection(c); m.openTab(c.id)
        let runtime = RemoteSession(connection: c)
        try runtime.startTerminal(executable: "/bin/cat", arguments: [])
        m.sessions[c.id] = runtime
        m.closeTab(c.id)
        for _ in 0..<150 { if !runtime.processRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!runtime.processRunning)
        #expect(m.sessions[c.id] == nil)
        #expect(m.workspace.document.connections.count == 1)
    }
    @Test func importingWorkspaceStopsAllProcesses() async throws {
        let m = WorkspaceModel()
        let c = ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .ssh)
        try m.saveConnection(c); m.openTab(c.id)
        let runtime = RemoteSession(connection: c)
        try runtime.startTerminal(executable: "/bin/cat", arguments: [])
        m.sessions[c.id] = runtime
        m.commitImport(try ImportPreview(data: DocumentCodec.encode(WorkbenchDocument())))
        for _ in 0..<150 { if !runtime.processRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!runtime.processRunning)
        #expect(m.sessions.isEmpty)
    }
}
