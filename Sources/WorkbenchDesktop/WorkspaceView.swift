import SwiftUI
import WorkbenchCore

public struct WorkspaceView: View {
    @ViewState private var model = WorkspaceModel()
    @ViewState private var showsInspector = true
    @FocusState private var searchFocused: Bool
    public init() {}
    public var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HSplitView {
                sidebar.frame(minWidth: 180, idealWidth: 220, maxWidth: 330)
                center.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                if showsInspector { inspector.frame(minWidth: 230, idealWidth: 260, maxWidth: 350) }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                Text(model.status).lineLimit(1)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.mini) }
                Text(model.isDirty ? "Unsaved changes" : "No unsaved changes").foregroundStyle(model.isDirty ? .primary : .secondary)
            }.font(.caption).padding(.horizontal, 12).frame(height: 28).background(.bar)
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(WindowBridge(model: model))
        .focusedSceneValue(\.workbench, model)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { Task { await model.openDocument() } } label: { Label("Open Workspace", systemImage: "folder") }.help("Open a local JSON workspace")
                Menu {
                    Button("New Connection…", action: model.addConnection)
                    Button("New Folder…") { model.editingFolder = nil; model.showsFolderEditor = true }
                } label: { Label("Add", systemImage: "plus") }.help("Add a connection or folder")
            }
            ToolbarItemGroup {
                Button { if let id = model.selectedConnectionID { model.openTab(id) } } label: { Label("Open Configuration", systemImage: "rectangle.on.rectangle") }.disabled(model.selected == nil)
                Button {} label: { Label("Connect", systemImage: "play.fill") }.disabled(true).help("Remote connections are not available in this version")
                Button { Task { await model.save() } } label: { Label("Save", systemImage: "square.and.arrow.down") }.help("Save workspace (⌘S)")
            }
            ToolbarItem(placement: .automatic) {
                TextField("Search name, host, tag", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 220).focused($searchFocused).accessibilityLabel("Search connections")
            }
            ToolbarItem { Button { showsInspector.toggle() } label: { Label("Toggle Inspector", systemImage: "sidebar.right") } }
        }
        .disabled(model.isBusy)
        .onReceive(NotificationCenter.default.publisher(for: .workbenchSearch)) { _ in searchFocused = true }
        .sheet(isPresented: $model.showsEditor) { if let draft = model.editingConnection { ConnectionEditor(model: model, draft: draft) } }
        .sheet(isPresented: $model.showsFolderEditor) { FolderEditor(model: model, draft: model.editingFolder ?? FolderRecord(parentID: model.selectedFolderID, name: "")) }
        .sheet(item: $model.transfer) { TransferPreview(model: model, state: $0) }
        .alert("Operation Failed", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
    private var sidebar: some View {
        List {
            Section("Workspace") {
                Button { model.selectedFolderID = nil; model.favoritesOnly = false; model.activeTabID = nil } label: { Label(model.workspace.document.name, systemImage: "externaldrive").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                Button { model.selectedFolderID = nil; model.favoritesOnly = true; model.activeTabID = nil } label: { Label("Favorites", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            Section("Folders") {
                ForEach(model.workspace.document.folders.filter { $0.parentID == nil }) { FolderBranch(model: model, folder: $0) }
                Button { model.editingFolder = nil; model.showsFolderEditor = true } label: { Label("New Folder", systemImage: "folder.badge.plus").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Section {
                Text("LOCAL ONLY").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text("No active remote sessions").font(.caption).foregroundStyle(.secondary)
            }
        }.listStyle(.sidebar)
    }
    private var center: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.activeTabID = nil } label: { Label("Inventory", systemImage: "list.bullet.rectangle") }.buttonStyle(.borderless).foregroundStyle(model.activeTabID == nil ? .primary : .secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(model.openTabIDs, id: \.self) { id in
                            if let c = model.workspace.document.connections.first(where: { $0.id == id }) {
                                HStack(spacing: 5) {
                                    Button { model.activeTabID = id; model.selectedConnectionID = id } label: { Label(c.name, systemImage: c.kind.symbol) }.buttonStyle(.borderless)
                                    Button { model.closeTab(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.borderless).accessibilityLabel("Close tab \(c.name)")
                                }.padding(.horizontal, 8).padding(.vertical, 6).background(model.activeTabID == id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 42).background(.bar)
            Divider()
            if let id = model.activeTabID, let c = model.workspace.document.connections.first(where: { $0.id == id }) {
                disconnected(c)
            } else { inventory }
        }
    }
    private var inventory: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.favoritesOnly ? "Favorites" : model.workspace.document.folders.first(where: { $0.id == model.selectedFolderID })?.name ?? "All Connections").font(.title2.weight(.semibold))
                    Text("\(model.displayed.count) configurations · Stored on this Mac").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Connection", action: model.addConnection)
            }.padding(16)
            if model.workspace.document.connections.isEmpty {
                ContentUnavailableView {
                    Label("Build your connection library", systemImage: "externaldrive.connected.to.line.below")
                } description: { Text("Organize hosts into folders, label environments, and save a local workspace.") } actions: { Button("Add Connection", action: model.addConnection) }
            } else {
                Table(model.displayed, selection: $model.selectedConnectionID) {
                    TableColumn("Name") { c in Label(c.name, systemImage: c.kind.symbol).lineLimit(1) }.width(min: 120, ideal: 190)
                    TableColumn("Protocol") { Text($0.kind.title).font(.caption.monospaced()) }.width(65)
                    TableColumn("Host") { Text($0.host).lineLimit(1).foregroundStyle(.secondary) }
                    TableColumn("Environment") { EnvironmentLabel(environment: $0.environment) }.width(95)
                    TableColumn("Favorite") { c in Button { model.toggleFavorite(c) } label: { Image(systemName: c.isFavorite ? "star.fill" : "star").foregroundStyle(c.isFavorite ? Color.orange : Color.secondary) }.buttonStyle(.borderless).accessibilityLabel(c.isFavorite ? "Remove favorite" : "Add favorite") }.width(55)
                }.contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first {
                        Button("Open Configuration") { model.openTab(id) }
                        Button("Edit…") { model.selectedConnectionID = id; model.editSelected() }
                        Button("Duplicate") { model.selectedConnectionID = id; model.duplicateSelected() }
                        Button("Delete…", role: .destructive) { model.selectedConnectionID = id; model.deleteSelected() }
                    }
                } primaryAction: { ids in if let id = ids.first { model.openTab(id) } }
                if model.displayed.isEmpty { Text("No matching connections. Clear the search or select a different folder.").foregroundStyle(.secondary).padding() }
            }
        }
    }
    private func disconnected(_ c: ConnectionRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: c.kind.symbol).font(.largeTitle).foregroundStyle(.secondary)
                VStack(alignment: .leading) { Text(c.name).font(.title2.weight(.semibold)); Text("\(c.kind.title) · Disconnected").foregroundStyle(.secondary) }
                Spacer(); EnvironmentLabel(environment: c.environment)
            }
            Divider()
            LabeledContent("Host", value: c.host)
            LabeledContent("Port", value: String(c.port))
            Text("The \(c.kind.title) adapter is not available in this version. No remote session has been started.").foregroundStyle(.secondary)
            Button("Edit Configuration") { model.selectedConnectionID = c.id; model.editSelected() }
            Spacer()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inspector").font(.headline)
                if let c = model.selected {
                    Label(c.kind.title, systemImage: c.kind.symbol).foregroundStyle(.secondary)
                    Text(c.name).font(.title3.weight(.semibold)).textSelection(.enabled)
                    GroupBox("Connection") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(c.host).textSelection(.enabled)
                            Text("Port \(c.port)").foregroundStyle(.secondary)
                            if let username = c.username { Text("User: \(username)") }
                            Text("Disconnected").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    EnvironmentLabel(environment: c.environment)
                    if !c.tags.isEmpty { Text("Tags: " + c.tags.joined(separator: ", ")).font(.caption) }
                    if !c.notes.isEmpty { Text(c.notes).textSelection(.enabled) }
                    Button("Edit Properties…", action: model.editSelected)
                    Button(c.isFavorite ? "Remove Favorite" : "Add Favorite") { model.toggleFavorite(c) }
                    Divider()
                    Text("No password stored. Local metadata is not encrypted.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Select a connection to inspect its configuration.").foregroundStyle(.secondary)
                    Divider()
                    Text(model.loadedFile?.url.path ?? "Unsaved workspace").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Rename Workspace…", action: model.renameWorkspace)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
}

struct FolderBranch: View {
    let model: WorkspaceModel
    let folder: FolderRecord
    var body: some View {
        DisclosureGroup {
            ForEach(model.workspace.document.folders.filter { $0.parentID == folder.id }) { FolderBranch(model: model, folder: $0) }
        } label: {
            Button { model.selectedFolderID = folder.id; model.favoritesOnly = false; model.activeTabID = nil } label: {
                Label(folder.name, systemImage: model.selectedFolderID == folder.id ? "folder.fill" : "folder")
                    .foregroundStyle(model.selectedFolderID == folder.id ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .contextMenu {
                Button("Edit Folder…") { model.editingFolder = folder; model.showsFolderEditor = true }
                Button("Add Subfolder…") { model.selectedFolderID = folder.id; model.editingFolder = nil; model.showsFolderEditor = true }
                Button("Delete Folder…", role: .destructive) { model.confirmDeleteFolder(folder) }
            }
        }
    }
}
struct EnvironmentLabel: View {
    let environment: ConnectionEnvironment
    var body: some View {
        HStack(spacing: 4) { Image(systemName: environment == .production ? "exclamationmark.shield" : "circle"); Text(environment.rawValue.capitalized) }
            .font(.caption).foregroundStyle(environment == .production ? Color.orange : Color.secondary)
    }
}
