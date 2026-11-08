import SwiftUI
import WorkbenchCore

struct ConnectionEditor: View {
    let model: WorkspaceModel
    @ViewState var draft: ConnectionRecord
    @ViewState private var tags = ""
    @ViewState private var error: String?
    @ViewState private var password = ""
    @ViewState private var forgetCredential = false
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
                if draft.kind == .web { Text("Port overrides any port in the URL.").font(.caption).foregroundStyle(.secondary) }
                TextField("Username", text: Binding(get: { draft.username ?? "" }, set: { draft.username = $0.isEmpty ? nil : $0 }))
                if [.rdp, .vnc, .sftp].contains(draft.kind) {
                    SecureField(draft.credentialReference != nil ? "Replace saved password" : (draft.kind == .sftp ? "Password (optional with SSH agent)" : "Password"), text: $password)
                    Text("Stored in this Mac’s Keychain when you save. RDP requires a username and password. Previous credentials stay in Saved Passwords until deleted.").font(.caption).foregroundStyle(.secondary)
                    if draft.credentialReference != nil { Toggle("Detach saved password", isOn: $forgetCredential) }
                }
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
            Text("Passwords stay in Keychain. Private keys stay outside the workspace file. Metadata is not encrypted.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Connection") {
                    draft.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    do { try model.saveConnection(draft, password: password.isEmpty ? nil : password, forgetCredential: forgetCredential); password = ""; dismiss() } catch { self.error = error.localizedDescription }
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
