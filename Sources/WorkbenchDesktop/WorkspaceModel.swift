import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WorkbenchCore

@MainActor @Observable public final class WorkspaceModel {
    public private(set) var workspace = try! Workspace(document: WorkbenchDocument())
    public var selectedFolderID: UUID?
    public var selectedConnectionID: UUID?
    public private(set) var openTabIDs: [UUID] = []
    public var activeTabID: UUID?
    var sessions: [UUID: RemoteSession] = [:]
    var activeSessionCount: Int { sessions.values.filter(\.isActive).count }
    var selectedSession: RemoteSession? { (activeTabID ?? selectedConnectionID).flatMap { sessions[$0] } }
    var canConnect: Bool { selected.map { !(sessions[$0.id]?.isActive ?? false) && !(sessions[$0.id]?.processRunning ?? false) } ?? false }
    public var query = ""
    public var favoritesOnly = false
    public private(set) var loadedFile: LoadedDocument?
    public private(set) var isDirty = false
    public private(set) var isBusy = false
    @ObservationIgnored weak var window: NSWindow?
    public var errorMessage: String?
    var editingConnection: ConnectionRecord?
    var showsEditor = false
    var showsVault = false
    var showsFolderEditor = false
    var editingFolder: FolderRecord?
    var transfer: TransferState?
    var status = "Local workspace · Connect on demand"
    @ObservationIgnored var vault = CredentialVault()
    public init() {}
    var selected: ConnectionRecord? { workspace.document.connections.first { $0.id == selectedConnectionID } }
    var displayed: [ConnectionRecord] { workspace.connections(matching: query, folderID: selectedFolderID, favoritesOnly: favoritesOnly) }
    public func saveConnection(_ c: ConnectionRecord) throws { try saveConnection(c, password: nil, forgetCredential: false) }
    func saveConnection(_ c: ConnectionRecord, password: String?, forgetCredential: Bool) throws {
        var next = workspace
        try next.upsert(c)
        var record = c
        if forgetCredential { record.credentialReference = nil }
        if let password, !password.isEmpty {
            guard [.rdp, .vnc, .sftp].contains(record.kind) else { throw ValidationError("credential-enabled adapter") }
            record.credentialReference = nil
            record.credentialReference = try vault.save(password, for: record)
        }
        try next.upsert(record)
        // Previous references may belong to another saved workspace; deletion is explicit.
        workspace = next
        if let session = sessions[c.id], !session.isActive, session.connection != record { session.disconnect(); sessions.removeValue(forKey: c.id) }
        selectedConnectionID = c.id; isDirty = true
    }
    func deleteCredential(_ reference: String) throws {
        try vault.delete(reference: reference)
        for var connection in workspace.document.connections where connection.credentialReference == reference {
            connection.credentialReference = nil; try workspace.upsert(connection); isDirty = true
        }
    }
    public func saveFolder(_ folder: FolderRecord) throws { try workspace.upsertFolder(folder); isDirty = true }
    public func openTab(_ id: UUID) {
        guard workspace.document.connections.contains(where: { $0.id == id }) else { return }
        if !openTabIDs.contains(id) { openTabIDs.append(id) }; activeTabID = id; selectedConnectionID = id
    }
    public func closeTab(_ id: UUID) { sessions.removeValue(forKey: id)?.disconnect(); openTabIDs.removeAll { $0 == id }; if activeTabID == id { activeTabID = openTabIDs.last } }
    public func deleteFolder(_ id: UUID) throws {
        let removed = try workspace.removeFolder(id: id)
        for id in removed { closeTab(id) }
        if selectedConnectionID.map(removed.contains) == true { selectedConnectionID = nil }
        selectedFolderID = nil; isDirty = true
    }
    public func commitImport(_ preview: ImportPreview) {
        stopAllSessions(); sessions = [:]
        workspace = try! Workspace(document: preview.document)
        loadedFile = nil; openTabIDs = []; activeTabID = nil; selectedConnectionID = nil; selectedFolderID = nil
        query = ""; favoritesOnly = false; isDirty = true; status = "Imported workspace · Save As to create a local file"
    }
    func report(_ error: Error) {
        if let error = error as? ValidationError { errorMessage = error.localizedDescription }
        else if let error = error as? DesktopSetupError { errorMessage = error.localizedDescription }
        else if let error = error as? VaultError { errorMessage = error.localizedDescription }
        else if let error = error as? SFTPError { errorMessage = error.localizedDescription }
        else if let error = error as? DocumentStoreError { errorMessage = error.localizedDescription }
        else { errorMessage = "The operation could not be completed. Check the file and its permissions." }
    }
    func addConnection() {
        editingConnection = ConnectionRecord(folderID: selectedFolderID, name: "", host: "", kind: .ssh); showsEditor = true
    }
    func editSelected() { if let selected { editingConnection = selected; showsEditor = true } }
    func duplicateSelected() {
        guard let selected else { return }
        do { selectedConnectionID = try workspace.duplicateConnection(id: selected.id); isDirty = true } catch { report(error) }
    }
    func toggleFavorite(_ c: ConnectionRecord) {
        var c = c; c.isFavorite.toggle(); do { try saveConnection(c) } catch { report(error) }
    }
    func renameWorkspace() {
        let field = NSTextField(string: workspace.document.name)
        let alert = NSAlert(); alert.messageText = "Rename Workspace"; alert.accessoryView = field
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { var d = workspace.document; d.name = field.stringValue; workspace = try Workspace(document: d); isDirty = true } catch { report(error) }
    }
    func deleteSelected() {
        guard let selected else { return }
        let alert = NSAlert(); alert.messageText = "Delete connection?"; alert.informativeText = "The selected configuration and tab will be removed, and its active session will be stopped."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try workspace.removeConnection(id: selected.id); closeTab(selected.id); selectedConnectionID = nil; isDirty = true } catch { report(error) }
    }
    func confirmDeleteFolder(_ folder: FolderRecord) {
        let ids = workspace.folderIDs(under: folder.id)
        let count = workspace.document.connections.filter { $0.folderID.map(ids.contains) == true }.count
        let alert = NSAlert(); alert.messageText = "Delete folder and its contents?"
        alert.informativeText = "This removes \(ids.count) folders, \(count) connections, and their tabs. Their active sessions will be stopped. This cannot be undone."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { do { try deleteFolder(folder.id) } catch { report(error) } }
    }
    func confirmDiscard() async -> Bool {
        guard !isBusy else { return false }
        if isDirty {
            let alert = NSAlert(); alert.messageText = "Save changes to this workspace?"
            alert.informativeText = "Unsaved changes will be lost if you discard them."
            alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { if !(await save()) { return false } }
            else if response != .alertSecondButtonReturn { return false }
        }
        if activeSessionCount > 0 {
            let alert = NSAlert(); alert.messageText = "Disconnect active sessions?"
            alert.informativeText = "This will stop \(activeSessionCount) active sessions in this window."
            alert.addButton(withTitle: "Disconnect and Continue"); alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
        return true
    }
    func stopAllSessions() { for session in sessions.values { session.disconnect() } }
    func connectSelected() {
        guard let c = selected, canConnect else { return }
        var acknowledgesVNC = false
        if c.kind == .vnc {
            let alert = NSAlert(); alert.messageText = "Use unencrypted VNC transport?"
            alert.informativeText = "This VNC adapter does not encrypt screen, keyboard, or authentication traffic. Use a trusted network or an existing encrypted tunnel. Clipboard sharing stays off."
            alert.addButton(withTitle: "Continue with VNC"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            acknowledgesVNC = true
        }
        let session = RemoteSession(connection: c)
        do {
            let password = [.rdp, .vnc, .sftp].contains(c.kind) ? try vault.read(for: c) : nil
            try session.connect(password: password, vncTransportAcknowledged: acknowledgesVNC); sessions[c.id] = session; openTab(c.id) } catch { report(error) }
    }
    func requestCloseTab(_ id: UUID) {
        if sessions[id]?.isActive == true {
            let alert = NSAlert(); alert.messageText = "Disconnect and close this tab?"
            alert.informativeText = "The active session will be stopped. The connection configuration will remain."
            alert.addButton(withTitle: "Disconnect and Close"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        closeTab(id)
    }
    func newDocument() async {
        guard await confirmDiscard() else { return }
        stopAllSessions(); sessions = [:]
        workspace = try! Workspace(document: WorkbenchDocument()); loadedFile = nil; isDirty = false
        openTabIDs = []; activeTabID = nil; selectedConnectionID = nil; selectedFolderID = nil; query = ""; favoritesOnly = false
    }
    func chooseFile() -> URL? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    func openDocument(importing: Bool = false) async {
        guard !isBusy, let url = chooseFile() else { return }
        await loadDocument(from: url, importing: importing) { await self.confirmDiscard() }
    }
    func loadDocument(from url: URL, importing: Bool, confirmReplacement: () async -> Bool) async {
        if !importing { guard await confirmReplacement() else { return } }
        isBusy = true; defer { isBusy = false }
        do {
            let loaded = try await Task.detached { try DocumentStore.load(from: url) }.value
            if importing { transfer = .importing(try ImportPreview(data: loaded.sourceData)); return }
            stopAllSessions(); sessions = [:]
            workspace = try Workspace(document: loaded.document); loadedFile = loaded; isDirty = false
            openTabIDs = []; activeTabID = nil; selectedConnectionID = nil; selectedFolderID = nil; query = ""; favoritesOnly = false
            status = "Opened local workspace"
        } catch { report(error) }
    }
    func importConfirmed(_ preview: ImportPreview) async {
        transfer = nil
        guard await confirmDiscard() else { return }
        commitImport(preview)
    }
    @discardableResult func save(asNew: Bool = false, preserving source: URL? = nil) async -> Bool {
        guard !isBusy else { return false }
        var url = loadedFile?.url; var expected = loadedFile?.sourceData
        if asNew || url == nil {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Workspace.json"
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            do { try DocumentStore.requireSeparateDestination(chosen, preserving: source) }
            catch { errorMessage = "Choose a different filename to preserve the external version."; return false }
            url = chosen; expected = nil
            // A save-panel replacement requires a fresh, explicit content snapshot.
            if FileManager.default.fileExists(atPath: chosen.path) {
                do { expected = try await Task.detached { try DocumentStore.load(from: chosen).sourceData }.value }
                catch { report(error); return false }
            }
        }
        guard let url else { return false }
        let document = workspace.document; let baseline = expected
        isBusy = true; defer { isBusy = false }
        do {
            loadedFile = try await Task.detached { try DocumentStore.save(document, to: url, expectedData: baseline) }.value
            isDirty = false; status = "Saved locally · Metadata is not encrypted"; return true
        } catch DocumentStoreError.conflict {
            isBusy = false
            let alert = NSAlert(); alert.messageText = "The file changed outside this window"
            alert.informativeText = "Save a separate copy to preserve both versions."
            alert.addButton(withTitle: "Save As…"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { return await save(asNew: true, preserving: url) }; return false
        } catch { report(error); return false }
    }
    func exportDocument(removeHosts: Bool, removeUsernames: Bool) async {
        guard !isBusy else { return }
        do {
            let bytes = try workspace.exportData(removeHosts: removeHosts, removeUsernames: removeUsernames)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Workspace-export.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try DocumentStore.requireSeparateDestination(url, preserving: loadedFile?.url)
            let d = try DocumentCodec.decode(bytes)
            isBusy = true; defer { isBusy = false }
            try await Task.detached {
                let baseline = FileManager.default.fileExists(atPath: url.path) ? try DocumentStore.load(from: url).sourceData : nil
                _ = try DocumentStore.save(d, to: url, expectedData: baseline)
            }.value
            transfer = nil; status = "Exported configuration · Review remaining names before sharing"
        } catch { report(error) }
    }
}

enum TransferState: Identifiable {
    case importing(ImportPreview), exporting
    var id: String { switch self { case .importing: "import"; case .exporting: "export" } }
}
