import AppKit
import SwiftUI
import WorkbenchCore

@MainActor @Observable final class SFTPBrowser {
    private(set) var path = "."
    var requestedPath = "."
    private(set) var remote: [SFTPEntry] = []
    var selectedRemote: String?
    var localFolder = FileManager.default.homeDirectoryForCurrentUser
    private(set) var local: [SFTPEntry] = []
    var selectedLocal: String?
    private(set) var busy = true
    private(set) var connected = false
    var message = "Connecting…"
    var error: String?
    @ObservationIgnored private let transport: SFTPTransport
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored var onState: ((SessionPhase, String) -> Void)?
    init() throws { transport = try SFTPTransport(); refreshLocal() }
    func start(_ connection: ConnectionRecord, password: String?) {
        let token = generation
        task = Task {
            do {
                try await transport.connect(connection, password: password)
                let entries = try await transport.list(path)
                guard token == generation else { return }
                remote = entries; connected = true; busy = false; message = "Connected · SFTP"
                onState?(.connected, message)
            } catch { guard token == generation else { return }; fail(error); disconnectResources(); onState?(.failed, "SFTP connection failed") }
        }
    }
    func disconnect() { generation = UUID(); disconnectResources(); message = "Disconnected" }
    private func disconnectResources() { task?.cancel(); transport.cancel(); connected = false; busy = false }
    private func fail(_ failure: Error) {
        error = (failure as? SFTPError)?.errorDescription ?? (failure as? ValidationError)?.errorDescription ?? "The file operation could not be completed. Check permissions and try again."
        busy = false; message = "Operation failed"
    }
    func refreshLocal() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: localFolder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
            guard urls.count <= 10000 else { throw ValidationError("local directory entry count") }
            local = try urls.map { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return SFTPEntry(name: url.lastPathComponent, size: UInt64(max(0, values.fileSize ?? 0)), isDirectory: values.isDirectory == true)
            }.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            selectedLocal = nil
        } catch { fail(error) }
    }
    func chooseLocal() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { localFolder = url; refreshLocal() }
    }
    func openLocalSelection() {
        guard let name = selectedLocal, local.first(where: { $0.name == name })?.isDirectory == true else { return }
        localFolder.appendPathComponent(name); refreshLocal()
    }
    func refreshRemote(to newPath: String? = nil) {
        guard connected, !busy else { return }
        let next = newPath ?? path; busy = true; message = "Loading folder…"; let token = generation
        task = Task {
            do {
                let entries = try await transport.list(next)
                guard token == generation else { return }
                path = next; requestedPath = next; remote = entries; selectedRemote = nil; busy = false; message = "Connected · SFTP"
            } catch { guard token == generation else { return }; requestedPath = path; fail(error) }
        }
    }
    func openRemoteSelection() {
        guard let name = selectedRemote, remote.first(where: { $0.name == name })?.isDirectory == true else { return }
        do { refreshRemote(to: try SFTPPath.child(path, name: name)) } catch { fail(error) }
    }
    func parentRemote() {
        refreshRemote(to: path + "/..")
    }
    func downloadSelection() {
        guard connected, !busy, let name = selectedRemote, remote.first(where: { $0.name == name })?.isDirectory == false else { return }
        let panel = NSSavePanel(); panel.directoryURL = localFolder; panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let overwrite = FileManager.default.fileExists(atPath: url.path)
        busy = true; message = "Downloading…"; let token = generation
        task = Task {
            do {
                try await transport.download(SFTPPath.child(path, name: name), to: url, overwrite: overwrite)
                guard token == generation else { return }
                busy = false; message = "Download complete"; refreshLocal()
            } catch { guard token == generation else { return }; fail(error) }
        }
    }
    func uploadFiles() {
        guard connected, !busy else { return }
        let panel = NSOpenPanel(); panel.directoryURL = localFolder; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        var approved: [(URL, Bool)] = []
        for file in files {
            let exists = remote.contains { $0.name == file.lastPathComponent }
            if exists {
                let alert = NSAlert(); alert.messageText = "Replace remote file?"; alert.informativeText = file.lastPathComponent
                alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            approved.append((file, exists))
        }
        busy = true; let token = generation
        task = Task {
            do {
                for (index, item) in approved.enumerated() {
                    guard token == generation else { return }
                    message = "Uploading \(index + 1) of \(approved.count)…"
                    try await transport.upload(item.0, to: SFTPPath.child(path, name: item.0.lastPathComponent), overwrite: item.1)
                }
                let entries = try await transport.list(path)
                guard token == generation else { return }
                remote = entries; busy = false; message = "Upload queue complete"
            } catch { guard token == generation else { return }; fail(error) }
        }
    }
}
struct SFTPBrowserPane: View {
    @Bindable var browser: SFTPBrowser
    let disconnect: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(browser.message).font(.caption)
                if browser.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Upload Files…", action: browser.uploadFiles).disabled(!browser.connected || browser.busy)
                Button("Download…", action: browser.downloadSelection).disabled(!browser.connected || browser.busy || browser.remote.first(where: { $0.name == browser.selectedRemote })?.isDirectory != false)
                if browser.busy { Button("Cancel and Disconnect", action: disconnect) }
            }
            HSplitView {
                VStack(alignment: .leading) {
                    HStack { Text("This Mac").font(.headline); Spacer(); Button("Choose Folder…", action: browser.chooseLocal) }
                    Text(browser.localFolder.path).font(.caption).lineLimit(2).textSelection(.enabled)
                    HStack { Button("Up") { browser.localFolder.deleteLastPathComponent(); browser.refreshLocal() }; Button("Open Folder", action: browser.openLocalSelection).disabled(browser.local.first(where: { $0.name == browser.selectedLocal })?.isDirectory != true); Button("Refresh", action: browser.refreshLocal) }
                    fileList(browser.local, selection: $browser.selectedLocal, open: browser.openLocalSelection)
                }.frame(minWidth: 190)
                VStack(alignment: .leading) {
                    Text("Remote Server").font(.headline)
                    TextField("Remote path", text: $browser.requestedPath).onSubmit { browser.refreshRemote(to: browser.requestedPath) }.disabled(!browser.connected || browser.busy)
                    HStack { Button("Up", action: browser.parentRemote); Button("Open Folder", action: browser.openRemoteSelection).disabled(browser.remote.first(where: { $0.name == browser.selectedRemote })?.isDirectory != true); Button("Refresh") { browser.refreshRemote() } }.disabled(!browser.connected || browser.busy)
                    fileList(browser.remote, selection: $browser.selectedRemote, open: browser.openRemoteSelection)
                }.frame(minWidth: 190)
            }
        }.padding(10)
        .alert("SFTP", isPresented: Binding(get: { browser.error != nil }, set: { if !$0 { browser.error = nil } })) { Button("OK") { browser.error = nil } } message: { Text(browser.error ?? "") }
    }
    private func fileList(_ entries: [SFTPEntry], selection: Binding<String?>, open: @escaping () -> Void) -> some View {
        List(entries, selection: selection) { entry in
            HStack { Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc"); Spacer(); if !entry.isDirectory { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) } }.tag(entry.name).onTapGesture(count: 2) { selection.wrappedValue = entry.name; open() }
        }.overlay { if entries.isEmpty && !browser.busy { Text("No files").foregroundStyle(.secondary) } }
    }
}
