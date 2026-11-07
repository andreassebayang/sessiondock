import Foundation
import Darwin

public enum DocumentCodec {
    public static let maxBytes = 10 * 1024 * 1024
    public static func decode(_ data: Data) throws -> WorkbenchDocument {
        guard data.count <= maxBytes else { throw ValidationError("file size (maximum 10 MiB)") }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ValidationError("document") }
            try keys(root, allowed: ["schemaVersion", "id", "name", "folders", "connections"])
            guard let folders = root["folders"] as? [[String: Any]], let connections = root["connections"] as? [[String: Any]] else { throw ValidationError("collections") }
            for folder in folders { try keys(folder, allowed: ["id", "parentID", "name"]) }
            for connection in connections {
                try keys(connection, allowed: ["id", "folderID", "name", "kind", "host", "port", "username", "credentialReference", "tags", "environment", "notes", "isFavorite"])
            }
            let document = try JSONDecoder().decode(WorkbenchDocument.self, from: data)
            try validate(document); return document
        } catch let error as ValidationError { throw error }
        catch { throw ValidationError("JSON document") }
    }
    private static func keys(_ value: [String: Any], allowed: Set<String>) throws {
        guard Set(value.keys).isSubset(of: allowed) else { throw ValidationError("unrecognized fields") }
    }
    public static func encode(_ document: WorkbenchDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= maxBytes else { throw ValidationError("file size (maximum 10 MiB)") }
        return data
    }
    public static func validate(_ document: WorkbenchDocument) throws {
        guard document.schemaVersion == 1 else { throw ValidationError("schema version") }
        try label(document.name)
        guard document.folders.count + document.connections.count <= 10_000 else { throw ValidationError("entry count") }
        let ids = document.folders.map(\.id) + document.connections.map(\.id)
        guard Set(ids).count == ids.count else { throw ValidationError("duplicate identifiers") }
        let folders = Dictionary(uniqueKeysWithValues: document.folders.map { ($0.id, $0) })
        for folder in document.folders {
            try label(folder.name)
            var current: UUID? = folder.id; var seen = Set<UUID>()
            while let id = current {
                guard seen.insert(id).inserted, seen.count <= 32, let node = folders[id] else { throw ValidationError("folder hierarchy") }
                current = node.parentID
            }
        }
        for connection in document.connections {
            try label(connection.name)
            if let parent = connection.folderID, folders[parent] == nil { throw ValidationError("connection folder") }
            guard (1...65535).contains(connection.port) else { throw ValidationError("port") }
            guard !connection.host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw ValidationError("host") }
            if connection.kind == .web {
                guard let url = URLComponents(string: connection.host), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, let host = url.host, validHost(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))), url.port.map({ (1...65535).contains($0) }) ?? true else { throw ValidationError("web URL") }
            } else if !validHost(connection.host) { throw ValidationError("host") }
            for value in connection.tags + [connection.username ?? "", connection.credentialReference ?? ""] {
                guard value.count <= 200, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ValidationError("username, tag, or credential reference") }
            }
            guard connection.notes.utf8.count <= maxBytes else { throw ValidationError("notes size") }
        }
    }
    private static func label(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 200, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ValidationError("label (maximum 200 characters)") }
    }
    private static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, host.utf8.count == host.count, !host.hasPrefix("-") else { return false }
        var ipv6 = in6_addr(), ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 || host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return true }
        if host.contains(":"), !host.contains(".") { return false }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { part in
            !part.isEmpty && part.count <= 63 && part.first != "-" && part.last != "-" && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
