import Foundation

public enum ConnectionLaunch {
    public static func webURL(for connection: ConnectionRecord) throws -> URL {
        guard connection.kind == .web, var parts = URLComponents(string: connection.host), (1...65535).contains(connection.port) else { throw ValidationError("web URL and port") }
        parts.port = connection.port
        guard let url = parts.url, WebNavigationPolicy.permits(url) else { throw ValidationError("web URL") }
        return url
    }
    public static func sshArguments(for connection: ConnectionRecord) throws -> [String] {
        guard connection.kind == .ssh else { throw ValidationError("SSH connection type") }
        var document = WorkbenchDocument(); var record = connection; record.folderID = nil
        document.connections = [record]; try DocumentCodec.validate(document)
        var args = ["-F", "/dev/null", "-tt"]
        for option in ["StrictHostKeyChecking=ask", "UpdateHostKeys=no", "ForwardAgent=no", "ForwardX11=no", "ClearAllForwardings=yes", "PermitLocalCommand=no", "EscapeChar=none", "ConnectTimeout=15", "ServerAliveInterval=30", "ServerAliveCountMax=3"] { args += ["-o", option] }
        args += ["-p", String(connection.port)]
        if let user = connection.username, !user.isEmpty {
            guard user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.@-".contains($0)) }), !user.hasPrefix("-") else { throw ValidationError("SSH username") }
            args += ["-l", user]
        }
        return args + ["--", connection.host]
    }
    public static func environment(from source: [String: String]) -> [String] {
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "SSH_AUTH_SOCK"]
        return allowed.compactMap { key in source[key].map { "\(key)=\($0)" } } + ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "TERM=xterm-256color", "LANG=en_US.UTF-8"]
    }
}
public enum WebNavigationPolicy {
    public static func permits(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return false }
        return parts.port.map { (1...65535).contains($0) } ?? true
    }
}
public enum SessionPhase: String, Sendable { case disconnected, connecting, connected, failed }
public struct SessionState: Sendable {
    public private(set) var phase: SessionPhase = .disconnected
    public private(set) var generation = UUID()
    public init() {}
    @discardableResult public mutating func begin() -> UUID { generation = UUID(); phase = .connecting; return generation }
    public mutating func stop() { generation = UUID(); phase = .disconnected }
    public mutating func didFinish(generation: UUID) { if generation == self.generation && phase == .connecting { phase = .connected } }
    public mutating func didFail(generation: UUID) { if generation == self.generation && phase != .disconnected { phase = .failed } }
}
