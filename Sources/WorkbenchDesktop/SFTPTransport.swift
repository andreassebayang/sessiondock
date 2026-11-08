import Foundation
import CSFTP
import WorkbenchCore

struct SFTPEntry: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let size: UInt64
    let isDirectory: Bool
}
enum SFTPPath {
    static func validate(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\0") else { throw ValidationError("remote path") }
    }
    static func child(_ folder: String, name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw ValidationError("remote filename") }
        let result = folder + (folder.hasSuffix("/") ? "" : "/") + name
        try validate(result); return result
    }
}
struct SFTPError: LocalizedError {
    let code: Int32
    var errorDescription: String? {
        switch code {
        case -2: "Transfer cancelled. Reconnect to continue."
        case -3: "SSH host key is unknown or changed. Verify the host in an SSH session before using SFTP."
        case -4: "SFTP authentication failed. Load your key into the SSH agent or save a password in Keychain."
        case -5: "SFTP file operation failed. Check permissions, destination, and atomic rename support."
        case -6: "Directory exceeds the 10,000-entry limit. Open a smaller folder."
        default: "SFTP connection failed. Check the host, port, and network."
        }
    }
}
private final class SFTPContext: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws { guard let p = wb_sftp_create() else { throw SFTPError(code: -1) }; pointer = p }
}
private final class SFTPEntries {
    var entries: [SFTPEntry] = []
}
final class SFTPTransport: @unchecked Sendable {
    private let context: SFTPContext
    private let queue = DispatchQueue(label: "org.sessiondock.sftp", qos: .userInitiated)
    init() throws { context = try SFTPContext() }
    deinit { let c = context; queue.async { wb_sftp_destroy(c.pointer) } }
    func cancel() { wb_sftp_cancel(context.pointer) }
    private func perform<T: Sendable>(_ operation: @escaping @Sendable (OpaquePointer) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try operation(context.pointer)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func check(_ result: Int32) throws { if result != 0 { throw SFTPError(code: result) } }
    func connect(_ c: ConnectionRecord, password: String?) async throws {
        guard c.kind == .sftp, let user = c.username, !user.isEmpty else { throw ValidationError("SFTP username") }
        var document = WorkbenchDocument(); var record = c; record.folderID = nil; document.connections = [record]
        try DocumentCodec.validate(document)
        let hosts = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts").path
        try await perform { context in
            let result: Int32
            if let password { result = wb_sftp_connect(context, c.host, Int32(c.port), user, password, hosts) }
            else { result = wb_sftp_connect(context, c.host, Int32(c.port), user, nil, hosts) }
            try Self.check(result)
        }
    }
    func list(_ path: String) async throws -> [SFTPEntry] {
        try SFTPPath.validate(path)
        return try await perform { context in
            let collector = SFTPEntries()
            let result = wb_sftp_list(context, path, Unmanaged.passUnretained(collector).toOpaque()) { opaque, name, size, directory in
                guard let opaque, let name, let text = String(validatingCString: name), !text.contains("\0") else { return }
                Unmanaged<SFTPEntries>.fromOpaque(opaque).takeUnretainedValue().entries.append(SFTPEntry(name: text, size: size, isDirectory: directory != 0))
            }
            try Self.check(result)
            return collector.entries.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    func download(_ path: String, to destination: URL, overwrite: Bool) async throws {
        try SFTPPath.validate(path)
        try await perform { context in
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(".sessiondock-" + UUID().uuidString)
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw SFTPError(code: -5) }
            defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
            try Self.check(wb_sftp_download(context, path, fd))
            guard fsync(fd) == 0 else { throw SFTPError(code: -5) }
            try Self.publish(temporary, to: destination, overwrite: overwrite)
        }
    }
    static func publish(_ temporary: URL, to destination: URL, overwrite: Bool) throws {
        if overwrite {
            guard rename(temporary.path, destination.path) == 0 else { throw SFTPError(code: -5) }
        } else {
            guard link(temporary.path, destination.path) == 0 else { throw SFTPError(code: -5) }
            unlink(temporary.path)
        }
    }
    func upload(_ source: URL, to path: String, overwrite: Bool) async throws {
        try SFTPPath.validate(path)
        let temporary = path + ".sessiondock-" + UUID().uuidString
        try SFTPPath.validate(temporary)
        try await perform { context in
            let fd = open(source.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw SFTPError(code: -5) }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw SFTPError(code: -5) }
            try Self.check(wb_sftp_upload(context, fd, temporary, path, overwrite ? 1 : 0))
        }
    }
}
