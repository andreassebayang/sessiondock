import Foundation
import Testing
@testable import WorkbenchCore

struct ConnectionLaunchTests {
    @Test func webPortControlsDestination() throws {
        let record = ConnectionRecord(name: "Local", host: "http://localhost", kind: .web, port: 8080)
        #expect(try ConnectionLaunch.webURL(for: record).port == 8080)
    }
    @Test func sshUsesExplicitArgumentsAndTrustVerification() throws {
        let c = ConnectionRecord(name: "Host", host: "example.com", kind: .ssh, port: 2200, username: "alice")
        let args = try ConnectionLaunch.sshArguments(for: c)
        #expect(args.contains("StrictHostKeyChecking=ask"))
        #expect(args.contains("ForwardAgent=no"))
        #expect(args.contains("ClearAllForwardings=yes"))
        #expect(args.contains("PermitLocalCommand=no"))
        #expect(Array(args.suffix(6)) == ["-p", "2200", "-l", "alice", "--", "example.com"])
        #expect(args.prefix(2) == ["-F", "/dev/null"])
    }
    @Test func sshRejectsInjectedOptionsAndWrongProtocol() {
        for host in ["-oProxyCommand=x", "host;touch /tmp/no", "host\ncommand"] {
            let c = ConnectionRecord(name: "Host", host: host, kind: .ssh)
            #expect(throws: (any Error).self) { try ConnectionLaunch.sshArguments(for: c) }
        }
        let c = ConnectionRecord(name: "Host", host: "host.example", kind: .ssh, username: "user;command")
        #expect(throws: (any Error).self) { try ConnectionLaunch.sshArguments(for: c) }
        #expect(throws: (any Error).self) { try ConnectionLaunch.sshArguments(for: ConnectionRecord(name: "Web", host: "https://example.com", kind: .web)) }
    }
    @Test func webNavigationAllowsOnlyCredentialFreeHTTP() throws {
        for s in ["https://example.com/", "http://127.0.0.1:8080/path?q=value#section"] { #expect(WebNavigationPolicy.permits(try #require(URL(string:s)))) }
        for s in ["file:///etc/passwd", "javascript:alert(1)", "ssh://example.com", "https://user:password@example.com/", "https://example.com:0", "http://example.com:65536"] { #expect(!WebNavigationPolicy.permits(try #require(URL(string:s)))) }
    }
    @Test func childEnvironmentDoesNotInheritSecrets() {
        let env = ConnectionLaunch.environment(from: ["HOME":"/tmp", "USER":"fixture", "SSH_AUTH_SOCK":"/tmp/socket", "API_SECRET":"do-not-forward", "SSH_ASKPASS":"/tmp/executable", "DYLD_INSERT_LIBRARIES":"/tmp/library"])
        #expect(env.contains("SSH_AUTH_SOCK=/tmp/socket"))
        #expect(!env.contains(where: { $0.contains("do-not-forward") || $0.hasPrefix("SSH_ASKPASS=") || $0.hasPrefix("DYLD_") }))
    }
    @Test func staleSessionCallbackCannotReconnectAfterStop() {
        var state = SessionState()
        let first = state.begin()
        state.stop()
        state.didFinish(generation: first)
        #expect(state.phase == .disconnected)
        let next = state.begin()
        state.didFail(generation: first)
        #expect(state.phase == .connecting)
        state.didFinish(generation: next)
        #expect(state.phase == .connected)
    }
}
