import SwiftUI
import WorkbenchDesktop
@main struct ConnectionWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(WorkbenchAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Connection Workbench", id: "workspace") { WorkspaceView().tint(.teal) }
            .defaultSize(width: 1240, height: 780)
            .commands { WorkbenchCommands() }
    }
}
