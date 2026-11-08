import SwiftUI
import WorkbenchCore

struct SessionPane: View {
    let session: RemoteSession
    let reconnect: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.connection.name, systemImage: session.connection.kind.symbol).font(.headline)
                Spacer()
                Text(session.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if session.connection.kind == .web, session.isActive { Button("Reload") { session.reloadWeb() } }
                Button("Disconnect") { session.disconnect() }.disabled(!session.isActive)
                if !session.isActive { Button("Reconnect", action: reconnect).disabled(session.processRunning) }
            }.padding(12)
            Divider()
            if let browser = session.sftpBrowser {
                SFTPBrowserPane(browser: browser, disconnect: session.disconnect)
            } else if let desktop = session.desktopView {
                NativeSessionView(view: desktop).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.connection.kind == .ssh, let terminal = session.terminalView {
                NativeSessionView(view: terminal).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let web = session.webView {
                NativeSessionView(view: web).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Session Disconnected", systemImage: "network.slash", description: Text("Reconnect to start a new session."))
            }
        }
    }
}
