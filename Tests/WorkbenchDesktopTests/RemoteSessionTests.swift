import AppKit
import Foundation
import Testing
import WorkbenchCore
import SwiftTerm
import WebKit
import Observation
import os
@testable import WorkbenchDesktop

@MainActor struct RemoteSessionTests {
    @Test func terminalProcessExitsAndDisconnectReapsChild() async throws {
        let session = RemoteSession(connection: ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .ssh))
        try session.startTerminal(executable: "/bin/cat", arguments: [])
        #expect(session.processRunning)
        #expect(session.terminalView != nil)
        session.disconnect()
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = session.processRunning } onChange: { changed.withLock { $0 = true } }
        for _ in 0..<150 { if !session.processRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.processRunning)
        #expect(session.phase == .disconnected)
        #expect(changed.withLock { $0 })
    }
    @Test func terminalNaturallyExitsWithoutClaimingAuthenticatedSSH() async throws {
        let session = RemoteSession(connection: ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .ssh))
        try session.startTerminal(executable: "/usr/bin/printf", arguments: ["fixture-output\\r\\n"])
        #expect(session.phase != .connected)
        for _ in 0..<150 { if session.exitCode != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.processRunning)
        #expect(session.exitCode == 0)
        let text = String(decoding: try #require(session.terminalView).getBufferAsData(), as: UTF8.self)
        #expect(text.contains("fixture-output"))
    }
    @Test func failedWebLoadDisposesBrowser() throws {
        _ = NSApplication.shared
        let session = RemoteSession(connection: ConnectionRecord(name: "Web", host: "https://example.com", kind: .web))
        try session.connect()
        defer { session.disconnect() }
        let view = try #require(session.webView)
        let navigation = try #require(view.loadHTMLString("", baseURL: nil))
        session.webView(view, didStartProvisionalNavigation: navigation)
        session.webView(view, didFail: navigation, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        #expect(session.phase == .failed)
        #expect(session.webView == nil)
    }
    @Test func staleWebNavigationCannotCompleteNewerLoad() throws {
        _ = NSApplication.shared
        let session = RemoteSession(connection: ConnectionRecord(name: "Web", host: "https://example.com", kind: .web))
        try session.connect()
        defer { session.disconnect() }
        let view = try #require(session.webView)
        let first = try #require(view.loadHTMLString("", baseURL: nil))
        let second = try #require(view.loadHTMLString("", baseURL: nil))
        session.webView(view, didStartProvisionalNavigation: first)
        session.webView(view, didStartProvisionalNavigation: second)
        session.webView(view, didFinish: first)
        #expect(session.phase == .connecting)
        session.webView(view, didFinish: second)
        #expect(session.phase == .connected)
    }
    @Test func unsupportedProtocolCannotStartASession() {
        let session = RemoteSession(connection: ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .rdp))
        #expect(throws: (any Error).self) { try session.connect() }
        #expect(!session.isActive)
    }
    @Test func unknownTerminalEscapeRequestsCannotReadClipboard() {
        let proxy = SafeTerminalDelegate()
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        #expect(proxy.clipboardRead(source: view) == nil)
    }
}
