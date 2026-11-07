import Foundation

public enum ConnectionKind: String, Codable, CaseIterable, Sendable {
    case ssh, rdp, vnc, web, sftp
    public var defaultPort: Int { switch self { case .ssh, .sftp: 22; case .rdp: 3389; case .vnc: 5900; case .web: 443 } }
    public var title: String { rawValue.uppercased() }
    public var symbol: String { switch self { case .ssh: "terminal"; case .rdp: "desktopcomputer"; case .vnc: "display.2"; case .web: "globe"; case .sftp: "externaldrive" } }
}
public enum ConnectionEnvironment: String, Codable, CaseIterable, Sendable { case production, staging, lab }
public struct ConnectionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var folderID: UUID?
    public var name: String
    public var kind: ConnectionKind
    public var host: String
    public var port: Int
    public var username: String?
    public var credentialReference: String?
    public var tags: [String]
    public var environment: ConnectionEnvironment
    public var notes: String
    public var isFavorite: Bool
    public init(id: UUID = UUID(), folderID: UUID? = nil, name: String, host: String, kind: ConnectionKind, port: Int? = nil, username: String? = nil, credentialReference: String? = nil, tags: [String] = [], environment: ConnectionEnvironment = .lab, notes: String = "", isFavorite: Bool = false) {
        self.id = id; self.folderID = folderID; self.name = name; self.host = host; self.kind = kind; self.port = port ?? kind.defaultPort
        self.username = username; self.credentialReference = credentialReference; self.tags = tags; self.environment = environment; self.notes = notes; self.isFavorite = isFavorite
    }
}
public struct FolderRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var name: String
    public init(id: UUID = UUID(), parentID: UUID? = nil, name: String) { self.id = id; self.parentID = parentID; self.name = name }
}
public struct WorkbenchDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var id: UUID = UUID()
    public var name: String = "Untitled Workspace"
    public var folders: [FolderRecord] = []
    public var connections: [ConnectionRecord] = []
    public init() {}
}
public struct ValidationError: LocalizedError, Sendable {
    public let field: String
    public var errorDescription: String? { "Invalid \(field). Check the document format and allowed limits." }
    public init(_ field: String) { self.field = field }
}
