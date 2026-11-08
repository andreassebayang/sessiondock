import Foundation
import AppKit
import Testing
import WorkbenchCore
@testable import WorkbenchDesktop

@MainActor struct DesktopAdapterTests {
    @Test func rdpDefaultsKeepTrustAndRedirectionRestrictions() throws {
        let c = ConnectionRecord(name: "Fixture", host: "rdp.example", kind: .rdp, username: "fixture")
        let config = try RDPDesktop.configuration(for: c, password: "disposable-fixture")
        #expect(!config.hideCertificateWarnings)
        #expect(!config.clipboardEnabled)
        #expect(!config.audioPlaybackEnabled)
        #expect(!config.legacyCredSSP)
        #expect(config.sharedDrives.isEmpty)
    }
    @Test func rdpRefusesMissingCredentialsBeforeNetworking() {
        let c = ConnectionRecord(name: "Fixture", host: "rdp.example", kind: .rdp)
        #expect(throws: (any Error).self) { try RDPDesktop.configuration(for: c, password: nil) }
    }
    @Test func vncRequiresExplicitTransportAcknowledgment() {
        let c = ConnectionRecord(name: "Fixture", host: "vnc.example", kind: .vnc)
        #expect(throws: (any Error).self) { try VNCDesktop(connection: c, password: nil, transportAcknowledged: false) }
    }
}

@MainActor struct DesktopProtocolFixtureTests {
    private func fixture(_ arguments: [String]) throws -> (Process, FileHandle, Int) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("NativeFixtures/desktop-server.py")
        process.arguments = [script.path] + arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte == Data([10]) { break }; line.append(byte)
        }
        guard let port = Int(String(decoding: line, as: UTF8.self)) else { process.terminate(); throw ValidationError("fixture startup") }
        return (process, output.fileHandleForReading, port)
    }
    @Test func vncRendersRealLoopbackFramebufferAndDisconnects() async throws {
        _ = NSApplication.shared
        let (server, _, port) = try fixture(["vnc"])
        defer { if server.isRunning { server.terminate() } }
        let desktop = try VNCDesktop(connection: ConnectionRecord(name: "Fixture", host: "127.0.0.1", kind: .vnc, port: port), password: nil, transportAcknowledged: true)
        var connected = false
        desktop.onState = { phase, _ in if phase == .connected { connected = true } }
        desktop.start()
        defer { desktop.disconnect() }
        for _ in 0..<250 { if connected && !desktop.view.subviews.isEmpty { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(connected)
        #expect(!desktop.view.subviews.isEmpty)
        desktop.disconnect()
        #expect(desktop.view.subviews.isEmpty)
    }
    @Test func vncRejectsMalformedClipboardWithoutCrashing() async throws {
        _ = NSApplication.shared
        let (server, _, port) = try fixture(["vnc-bad-clipboard"])
        defer { if server.isRunning { server.terminate() } }
        let desktop = try VNCDesktop(connection: ConnectionRecord(name: "Fixture", host: "127.0.0.1", kind: .vnc, port: port), password: nil, transportAcknowledged: true)
        var failed = false
        desktop.onState = { phase, _ in if phase == .failed { failed = true } }
        desktop.start(); defer { desktop.disconnect() }
        for _ in 0..<250 { if failed { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(failed)
    }
    @Test(arguments: ["vnc-huge-name", "vnc-huge-zlib"])
    func vncRejectsOversizedWireLengths(mode: String) async throws {
        _ = NSApplication.shared
        let (server, _, port) = try fixture([mode])
        defer { if server.isRunning { server.terminate() } }
        let desktop = try VNCDesktop(connection: ConnectionRecord(name: "Fixture", host: "127.0.0.1", kind: .vnc, port: port), password: nil, transportAcknowledged: true)
        var failed = false
        desktop.onState = { phase, _ in if phase == .failed { failed = true } }
        desktop.start(); defer { desktop.disconnect() }
        for _ in 0..<250 { if failed { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(failed)
    }
    @Test func untrustedRDPTLSCannotSendCredentials() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cert = folder.appendingPathComponent("cert.pem"), key = folder.appendingPathComponent("key.pem")
        let generate = Process(); generate.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        generate.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost", "-days", "1", "-keyout", key.path, "-out", cert.path]
        generate.standardError = FileHandle.nullDevice; generate.standardOutput = FileHandle.nullDevice
        try generate.run(); generate.waitUntilExit(); #expect(generate.terminationStatus == 0)
        let (server, output, port) = try fixture(["rdp-untrusted", cert.path, key.path])
        defer { if server.isRunning { server.terminate() } }
        let desktop = RDPDesktop()
        var failed = false
        desktop.onState = { phase, _ in if phase == .failed { failed = true } }
        try desktop.start(ConnectionRecord(name: "Fixture", host: "127.0.0.1", kind: .rdp, port: port, username: "fixture"), password: "disposable-fixture")
        defer { desktop.disconnect() }
        for _ in 0..<500 { if failed { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(failed)
        for _ in 0..<100 { if !server.isRunning { break }; try await Task.sleep(for: .milliseconds(20)) }
        if server.isRunning { server.terminate() }
        server.waitUntilExit()
        let result = String(decoding: try output.readToEnd() ?? Data(), as: UTF8.self)
        #expect(!result.contains("APPLICATION_BYTES:") || result.contains("APPLICATION_BYTES:0"))
    }

}
