import SwiftUI

struct VaultManager: View {
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var entries: [VaultEntry] = []
    @ViewState private var selection: String?
    @ViewState private var error: String?
    @ViewState private var confirmsDeletion = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Passwords").font(.title2.weight(.semibold))
            Text("Stored in this Mac’s Keychain. Replacing a password keeps the previous entry so saved workspaces can still use it.").foregroundStyle(.secondary)
            List(entries, selection: $selection) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.protocolName.uppercased()) · \(entry.host):\(entry.port)")
                    Text(entry.username.isEmpty ? "No username" : entry.username).font(.caption).foregroundStyle(.secondary)
                    Text(entry.id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }.tag(entry.id)
            }.overlay { if entries.isEmpty && error == nil { Text("No saved passwords").foregroundStyle(.secondary) } }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Refresh", action: refresh)
                Button("Delete Password…", role: .destructive) { confirmsDeletion = true }.disabled(selection == nil)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 600, height: 440)
        .onAppear(perform: refresh)
        .alert("Delete this password permanently?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Password", role: .destructive) {
                guard let selection else { return }
                do { try model.deleteCredential(selection); self.selection = nil; refresh() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("Workspaces using this credential will need a password entered again. This can also affect other saved workspaces. This cannot be undone.") }
    }
    private func refresh() {
        do { entries = try model.vault.entries(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
