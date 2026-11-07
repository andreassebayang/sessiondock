import SwiftUI
import WorkbenchCore

struct ConnectionEditor: View {
    let model: WorkspaceModel
    @ViewState var draft: ConnectionRecord
    @ViewState private var tags = ""
    @ViewState private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Properties").font(.title2.weight(.semibold))
            Text("Save a connection configuration on this Mac.").foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $draft.name)
                Picker("Protocol", selection: $draft.kind) { ForEach(ConnectionKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .onChange(of: draft.kind) { old, new in if draft.port == old.defaultPort { draft.port = new.defaultPort } }
                TextField(draft.kind == .web ? "HTTP(S) URL" : "Hostname or IP", text: $draft.host)
                TextField("Port", value: $draft.port, format: .number.grouping(.never))
                TextField("Username", text: Binding(get: { draft.username ?? "" }, set: { draft.username = $0.isEmpty ? nil : $0 }))
                Picker("Folder", selection: $draft.folderID) {
                    Text("Workspace root").tag(nil as UUID?)
                    ForEach(model.workspace.document.folders) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Environment", selection: $draft.environment) { ForEach(ConnectionEnvironment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                TextField("Tags (comma separated)", text: $tags)
                Toggle("Favorite", isOn: $draft.isFavorite)
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...5)
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("editorError") }
            Text("Passwords and private keys are never stored in this file. Metadata is not encrypted.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Connection") {
                    draft.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    do { try model.saveConnection(draft); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540)
        .onAppear { tags = draft.tags.joined(separator: ", ") }
    }
}

struct FolderEditor: View {
    let model: WorkspaceModel
    @ViewState var draft: FolderRecord
    @ViewState private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Folder Properties").font(.title2.weight(.semibold))
            TextField("Name", text: $draft.name)
            Picker("Parent", selection: $draft.parentID) {
                Text("Workspace root").tag(nil as UUID?)
                ForEach(model.workspace.document.folders.filter { !model.workspace.folderIDs(under: draft.id).contains($0.id) }) { Text($0.name).tag(Optional($0.id)) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Folder") { do { try model.saveFolder(draft); dismiss() } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 400)
    }
}
