import SwiftUI
import WorkbenchCore

struct TransferPreview: View {
    let model: WorkspaceModel
    let state: TransferState
    @ViewState private var removeHosts = true
    @ViewState private var removeUsernames = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch state {
            case .importing(let preview):
                Text("Review Import").font(.title2.weight(.semibold))
                Text(preview.document.name).font(.headline)
                Text("\(preview.document.folders.count) folders · \(preview.document.connections.count) connections")
                Text("Import replaces this window's workspace. Your current file will not be overwritten. The imported configuration must be saved separately.")
                Text("No connections or commands will be started.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Replace Workspace") { Task { await model.importConfirmed(preview) } }.keyboardShortcut(.defaultAction)
                }
            case .exporting:
                Text("Review Export").font(.title2.weight(.semibold))
                Text("\(model.workspace.document.folders.count) folders · \(model.workspace.document.connections.count) connections")
                Toggle("Replace hostnames with redacted.invalid", isOn: $removeHosts)
                Toggle("Remove usernames", isOn: $removeUsernames)
                Text("Credential references, notes, and tags are always removed. Workspace, folder, connection names, and environment labels remain. Review them before sharing.").foregroundStyle(.secondary)
                if !removeHosts { Text("Hostnames and URLs will be included.").foregroundStyle(.orange) }
                HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Export JSON…") { Task { await model.exportDocument(removeHosts: removeHosts, removeUsernames: removeUsernames) } }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 480).disabled(model.isBusy)
    }
}
