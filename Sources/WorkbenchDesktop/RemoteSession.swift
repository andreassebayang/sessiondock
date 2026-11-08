import AppKit
import SwiftUI
import SwiftTerm
import WebKit
import WorkbenchCore

@MainActor final class SafeTerminalDelegate: TerminalViewDelegate {
    weak var target: LocalProcessTerminalView?
    init(target: LocalProcessTerminalView? = nil) { self.target = target }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { target?.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { target?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { target?.scrolled(source: source, position: position) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {}
}

@MainActor @Observable final class RemoteSession: NSObject, LocalProcessTerminalViewDelegate, WKNavigationDelegate, WKUIDelegate {
    let connection: ConnectionRecord
    private var state = SessionState()
    var phase: SessionPhase { state.phase }
    var isActive: Bool { phase == .connecting || phase == .connected }
    var detail = "Disconnected"
    private(set) var exitCode: Int32?
    private(set) var currentURL: URL?
    @ObservationIgnored private(set) var terminalView: LocalProcessTerminalView?
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var terminalDelegate: SafeTerminalDelegate?
    @ObservationIgnored private var webGeneration: UUID?
    @ObservationIgnored private var activeNavigation: WKNavigation?
    private(set) var processRunning = false
    init(connection: ConnectionRecord) { self.connection = connection; super.init() }
    func connect() throws {
        guard !isActive, !processRunning else { return }
        switch connection.kind {
        case .ssh: try startTerminal(executable: "/usr/bin/ssh", arguments: ConnectionLaunch.sshArguments(for: connection))
        case .web:
            let url = try ConnectionLaunch.webURL(for: connection)
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            let view = WKWebView(frame: .zero, configuration: config)
            webView = view; view.navigationDelegate = self; view.uiDelegate = self
            webGeneration = state.begin(); detail = "Loading webpage…"; currentURL = url
            view.load(URLRequest(url: url))
        default: throw ValidationError("available connection type; choose SSH or Web")
        }
    }
    func startTerminal(executable: String, arguments: [String]) throws {
        guard !processRunning else { throw ValidationError("session already running") }
        state.begin(); exitCode = nil; detail = "SSH client running · Verify login in the terminal"
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let proxy = SafeTerminalDelegate(target: terminal)
        terminalDelegate = proxy; terminal.terminalDelegate = proxy; terminal.processDelegate = self
        terminalView = terminal
        terminal.startProcess(executable: executable, args: arguments, environment: ConnectionLaunch.environment(from: ProcessInfo.processInfo.environment))
        processRunning = terminal.process.running
        guard processRunning else { state.didFail(generation: state.generation); detail = "Could not start SSH client"; throw ValidationError("SSH process launch") }
    }
    func disconnect() {
        state.stop(); webGeneration = nil; activeNavigation = nil; detail = "Disconnected"
        if let view = webView { view.navigationDelegate = nil; view.uiDelegate = nil; view.stopLoading(); view.removeFromSuperview() }; webView = nil
        if let terminal = terminalView {
            terminal.terminate()
            Task { @MainActor [weak terminal] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let process = terminal?.process, process.running, process.shellPid > 0 else { return }
                // Escalate only the child still owned by this terminal instance.
                kill(process.shellPid, SIGKILL)
            }
        }
    }
    private func disposeWebView() {
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView?.stopLoading(); webView?.removeFromSuperview(); webView = nil
        activeNavigation = nil; webGeneration = nil
    }
    func reloadWeb() { guard let webView, isActive else { return }; webGeneration = state.begin(); detail = "Loading webpage…"; webView.reload() }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        guard source === terminalView else { return }; processRunning = false; guard isActive else { return }; state.didFail(generation: state.generation); detail = "Could not start SSH client"
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminalView else { return }; processRunning = false; self.exitCode = exitCode
        if isActive {
            if exitCode == 0 { state.stop(); detail = "SSH client exited normally" }
            else { state.didFail(generation: state.generation); detail = "SSH client exited · Review the terminal for details" }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView, isActive, let url = navigationAction.request.url, WebNavigationPolicy.permits(url), navigationAction.targetFrame != nil, !navigationAction.shouldPerformDownload else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView, navigationResponse.canShowMIMEType, let url = navigationResponse.response.url, WebNavigationPolicy.permits(url) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView, isActive else { return }; activeNavigation = navigation; webGeneration = state.begin(); detail = "Loading webpage…"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, navigation === activeNavigation, let generation = webGeneration else { return }
        state.didFinish(generation: generation); currentURL = webView.url; detail = "Connected · Web"
    }
    private func navigationFailed(_ view: WKWebView, navigation: WKNavigation?, error: Error) {
        guard view === webView, navigation === activeNavigation, let generation = webGeneration else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        disposeWebView(); state.didFail(generation: generation); detail = "Web connection failed · Check the URL, network, and certificate"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, navigation: navigation, error: error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, navigation: navigation, error: error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }; disposeWebView(); state.didFail(generation: state.generation); detail = "Web content process stopped · Reconnect to continue"
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) { completionHandler(nil) }
}

struct NativeSessionView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView {
        let container = NSView(); install(in: container); return container
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 500)
    }
    func updateNSView(_ container: NSView, context: Context) {
        if view.superview !== container { install(in: container) }
    }
    private func install(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview(); view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor), view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
    }
}
