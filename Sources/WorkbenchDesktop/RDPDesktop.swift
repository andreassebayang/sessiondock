import AppKit
import RDPKit
import RDPKitAppKit
import WorkbenchCore

@MainActor final class RDPDesktop {
    let view = DesktopCanvas()
    let video = RDPRemoteDesktopVideoView(frame: .zero)
    let input = RDPRemoteInputView(frame: .zero)
    var onState: ((SessionPhase, String) -> Void)?
    private var session: RDPLiveSession?
    private var displayControl: RDPDisplayControlSession?
    private var resizeTask: Task<Void, Never>?
    private var frameID = 0
    static func configuration(for c: ConnectionRecord, password: String?) throws -> RDPConnectionConfiguration {
        guard c.kind == .rdp, let username = c.username, !username.isEmpty, let password, !password.isEmpty else { throw DesktopSetupError.missingRDPCredentials }
        var document = WorkbenchDocument(); var record = c; record.folderID = nil; document.connections = [record]; try DocumentCodec.validate(document)
        guard let credentials = try RDPCredentials.validated(username: username, password: password) else { throw ValidationError("RDP credentials") }
        return RDPConnectionConfiguration(host: c.host, port: UInt16(c.port), credentials: credentials, timeoutSeconds: 15,
            hideCertificateWarnings: false, graphicsFrameCaptureLimit: nil, desktopWidth: 1280, desktopHeight: 720,
            clipboardEnabled: false, clipboardFetchesRemoteCopies: false, audioPlaybackEnabled: false,
            legacyRSAKeyExchange: .never, legacyCredSSP: false, sharedDrives: [], clientName: "SESSIONDOCK")
    }
    init() {
        for child in [video, input] as [NSView] { child.frame = view.bounds; child.autoresizingMask = [.width, .height]; view.addSubview(child) }
        view.onResize = { [weak self] in self?.scheduleResize() }
    }
    func start(_ connection: ConnectionRecord, password: String?) throws {
        let configuration = try Self.configuration(for: connection, password: password)
        let live = RDPLiveSession(threadName: "SessionDock remote desktop")
        session = live
        let recipient = live.recipient(self)
        live.start(events: RDPLiveSession.Events(
            onFrameDecoded: { [weak self] presentation, _, _, _ in
                guard let self, self.session === live else { return }
                self.frameID += 1; self.video.present(presentation, id: self.frameID)
                self.input.rdpFrame = RDPFrameMetadata(presentation.frame)
                self.onState?(.connected, "Connected · RDP · TLS")
            },
            onFrameDecodeFailed: { [weak self] _, _ in
                guard let self, self.session === live else { return }
                self.onState?(.connecting, "RDP connected · Waiting for a display frame")
            },
            onEnd: { [weak self] report in
                live.deliver { [weak self] in
                    guard let self, self.session === live else { return }
                    self.input.inputSession = nil; self.displayControl = nil
                    self.onState?(report.failure == nil ? .disconnected : .failed, report.failure == nil ? "RDP session ended" : "RDP failed · Check credentials, TLS trust, and server compatibility")
                    self.session = nil
                }
            }
        )) { run in
            RDPSessionClient().run(configuration: configuration, onGraphicsFrame: run.onGraphicsFrame,
                onInputReady: { input in recipient.deliver { owner in guard owner.session === live else { return }; owner.input.inputSession = input } },
                onDisplayControlReady: { control in recipient.deliver { owner in guard owner.session === live else { return }; owner.displayControl = control; owner.scheduleResize() } },
                onCertificate: { certificate in
                    if !certificate.trusted || certificate.host.lowercased() != connection.host.lowercased() {
                        run.cancellation.cancel()
                        recipient.deliver { owner in
                            guard owner.session === live else { return }
                            owner.input.inputSession = nil; owner.displayControl = nil
                            owner.onState?(.failed, "RDP certificate is not trusted for this host. No credential was sent.")
                            owner.session = nil; live.cancel()
                        }
                    }
                },
                onWireReceive: run.onWireReceive, liveReport: run.liveReport, cancellation: run.cancellation)
        }
    }
    private func scheduleResize() {
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, let control = displayControl else { return }
            control.sendSingleMonitorLayout(width: UInt32(min(4096, max(640, view.bounds.width))), height: UInt32(min(2160, max(480, view.bounds.height))))
        }
    }
    func disconnect() {
        onState = nil; resizeTask?.cancel(); input.inputSession = nil; input.rdpFrame = nil
        session?.cancel(); session = nil; displayControl = nil; video.clear()
    }
}
@MainActor final class DesktopCanvas: NSView {
    var onResize: (() -> Void)?
    override func layout() { super.layout(); onResize?() }
}

enum DesktopSetupError: LocalizedError {
    case missingRDPCredentials
    var errorDescription: String? { "RDP needs a username and password. Open Edit Properties and save the password in macOS Keychain, then connect again." }
}
