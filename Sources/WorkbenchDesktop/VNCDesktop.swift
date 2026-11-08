import AppKit
@preconcurrency import RoyalVNCKit
import WorkbenchCore

private final class BoundedVNCAllocator: VNCFramebufferAllocator {
    private let base = VNCFramebufferMallocAllocator()
    func allocate(size: Int) throws -> UnsafeMutableRawPointer {
        guard size > 0, size <= 64 * 1024 * 1024 else { throw ValidationError("VNC framebuffer size (maximum 64 MiB)") }
        return try base.allocate(size: size)
    }
    func deallocate(buffer: UnsafeMutableRawPointer) { base.deallocate(buffer: buffer) }
    func lockReadOnly() { base.lockReadOnly() }
    func unlockReadOnly() { base.unlockReadOnly() }
    func lockReadWrite() { base.lockReadWrite() }
    func unlockReadWrite() { base.unlockReadWrite() }
}
private struct VNCFrameDelivery: @unchecked Sendable { let connection: VNCConnection; let framebuffer: VNCFramebuffer }
@MainActor final class VNCDesktop: NSObject, @preconcurrency VNCConnectionDelegate {
    let view = NSView()
    var onState: ((SessionPhase, String) -> Void)?
    private let engine: VNCConnection
    private let username: String?
    private var password: String?
    private var stopped = false
    init(connection: ConnectionRecord, password: String?, transportAcknowledged: Bool) throws {
        guard transportAcknowledged, connection.kind == .vnc else { throw ValidationError("VNC unencrypted transport acknowledgment") }
        var document = WorkbenchDocument(); var record = connection; record.folderID = nil; document.connections = [record]; try DocumentCodec.validate(document)
        let settings = VNCConnection.Settings(isDebugLoggingEnabled: false, hostname: connection.host, port: UInt16(connection.port), isShared: true,
            isScalingEnabled: true, useDisplayLink: true, inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: false, colorDepth: .depth24Bit, frameEncodings: .default)
        let logger = VNCCustomLogger(logDebugHandler: { _ in }, logInfoHandler: { _ in }, logWarningHandler: { _ in }, logErrorHandler: { _ in })
        engine = VNCConnection(settings: settings, logger: logger, framebufferAllocator: BoundedVNCAllocator(), context: nil)
        self.password = password; username = connection.username
        super.init(); engine.delegate = self
    }
    func start() { engine.connect() }
    func disconnect() { stopped = true; onState = nil; password = nil; engine.delegate = nil; engine.disconnect(); view.subviews.forEach { $0.removeFromSuperview() } }
    nonisolated func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        let status = connectionState.status.rawValue, failed = connectionState.error != nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !stopped else { return }
            switch status {
            case VNCConnection.Status.connected.rawValue: onState?(.connected, "Connected · VNC · Unencrypted transport")
            case VNCConnection.Status.disconnected.rawValue:
                password = nil; onState?(failed ? .failed : .disconnected, failed ? "VNC failed · Check authentication and server settings" : "VNC session ended")
            default: break
            }
        }
    }
    nonisolated func connection(_ connection: VNCConnection, credentialFor authenticationType: VNCAuthenticationType, completion: @escaping (VNCCredential?) -> Void) {
        let request = VNCCredentialRequest(type: authenticationType, completion: completion)
        DispatchQueue.main.async { [weak self] in
            guard let self, !stopped, let password else { request.completion(nil); return }
            if request.type.requiresUsername, let username, !username.isEmpty { request.completion(VNCUsernamePasswordCredential(username: username, password: password)) }
            else if request.type.requiresPassword && !request.type.requiresUsername { request.completion(VNCPasswordCredential(password: password)) }
            else { request.completion(nil) }
            self.password = nil
        }
    }
    nonisolated func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        let delivery = VNCFrameDelivery(connection: connection, framebuffer: framebuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self, !stopped else { return }
            let child = VNCCAFramebufferView(frame: view.bounds, framebuffer: delivery.framebuffer, connection: delivery.connection, connectionDelegate: self)
            child.autoresizingMask = [.width, .height]; view.subviews.forEach { $0.removeFromSuperview() }; view.addSubview(child)
        }
    }
    nonisolated func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {}
    nonisolated func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {}
    nonisolated func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {}
}
private struct VNCCredentialRequest: @unchecked Sendable { let type: VNCAuthenticationType; let completion: (VNCCredential?) -> Void }
