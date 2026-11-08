import AppKit
import SwiftUI

private struct WorkbenchKey: FocusedValueKey { typealias Value = WorkspaceModel }
extension FocusedValues {
    var workbench: WorkspaceModel? { get { self[WorkbenchKey.self] } set { self[WorkbenchKey.self] = newValue } }
}
extension Notification.Name { static let workbenchSearch = Notification.Name("org.connectionworkbench.search") }

struct WindowBridge: NSViewRepresentable {
    let model: WorkspaceModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.delegate = coordinator; model.window = window; window.minSize = NSSize(width: 960, height: 640)
            window.title = model.workspace.document.name + " — Connection Workbench"
            window.isDocumentEdited = model.isDirty; window.representedURL = model.loadedFile?.url
        }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let model: WorkspaceModel
        var permitsClose = false
        var deciding = false
        init(model: WorkspaceModel) { self.model = model }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if permitsClose { return true }
            guard !deciding, !model.isBusy else { return false }
            deciding = true
            Task {
                defer { deciding = false }
                if await model.confirmDiscard() { model.stopAllSessions(); permitsClose = true; sender.performClose(nil) }
            }
            return false
        }
    }
}

public final class WorkbenchAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let models = sender.windows.compactMap { ($0.delegate as? WindowBridge.Coordinator)?.model }
        Task { @MainActor in
            for model in models { if !(await model.confirmDiscard()) { sender.reply(toApplicationShouldTerminate: false); return } }
            for model in models { model.stopAllSessions() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

public struct WorkbenchCommands: Commands {
    @FocusedValue(\.workbench) private var model
    @Environment(\.openWindow) private var openWindow
    public init() {}
    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "workspace") }.keyboardShortcut("n")
            Button("New Workspace") { Task { await model?.newDocument() } }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model == nil || model?.isBusy == true)
            Button("Open Workspace…") { Task { await model?.openDocument() } }.keyboardShortcut("o").disabled(model == nil || model?.isBusy == true)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Task { await model?.save() } }.keyboardShortcut("s").disabled(model == nil || model?.isBusy == true)
            Button("Save As…") { Task { await model?.save(asNew: true) } }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model == nil || model?.isBusy == true)
            Button("Close Window") { model?.window?.performClose(nil) }.keyboardShortcut("w").disabled(model == nil || model?.isBusy == true)
            Divider()
            Button("Import JSON…") { Task { await model?.openDocument(importing: true) } }.disabled(model == nil || model?.isBusy == true)
            Button("Export JSON…") { model?.transfer = .exporting }.disabled(model == nil || model?.isBusy == true)
        }
        CommandMenu("Connection") {
            Group {
            Button("Add Connection…") { model?.addConnection() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Add Folder…") { model?.editingFolder = nil; model?.showsFolderEditor = true }.keyboardShortcut("n", modifiers: [.command, .control])
            Button("Rename Workspace…") { model?.renameWorkspace() }
            Button("Edit Selected Folder…") {
                if let folder = model?.workspace.document.folders.first(where: { $0.id == model?.selectedFolderID }) { model?.editingFolder = folder; model?.showsFolderEditor = true }
            }.disabled(model?.selectedFolderID == nil)
            Button("Delete Selected Folder…") {
                if let folder = model?.workspace.document.folders.first(where: { $0.id == model?.selectedFolderID }) { model?.confirmDeleteFolder(folder) }
            }.disabled(model?.selectedFolderID == nil)
            Divider()
            Button("Edit Properties…") { model?.editSelected() }.keyboardShortcut("e").disabled(model?.selected == nil)
            Button("Duplicate") { model?.duplicateSelected() }.keyboardShortcut("d").disabled(model?.selected == nil)
            Button("Delete Connection…") { model?.deleteSelected() }.keyboardShortcut(.delete, modifiers: [.command]).disabled(model?.selected == nil)
            Button("Connect") { model?.connectSelected() }.keyboardShortcut("k").disabled(model?.canConnect != true)
            Button("Disconnect") { model?.selectedSession?.disconnect() }.keyboardShortcut("k", modifiers: [.command, .shift]).disabled(model?.selectedSession?.isActive != true)
            Button("Open Configuration") { if let id = model?.selectedConnectionID { model?.openTab(id) } }.keyboardShortcut(.return, modifiers: [.command]).disabled(model?.selected == nil)
            Button("Close Configuration Tab") { if let id = model?.activeTabID { model?.requestCloseTab(id) } }.keyboardShortcut("w", modifiers: [.command, .option]).disabled(model?.activeTabID == nil)
        }.disabled(model == nil || model?.isBusy == true)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Connections") { NotificationCenter.default.post(name: .workbenchSearch, object: nil) }.keyboardShortcut("f").disabled(model == nil)
        }
    }
}
