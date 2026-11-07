import Foundation

public struct ImportPreview: Sendable {
    public let document: WorkbenchDocument
    public init(data: Data) throws { document = try DocumentCodec.decode(data) }
}
public struct Workspace: Sendable {
    public private(set) var document: WorkbenchDocument
    public init(document: WorkbenchDocument) throws { try DocumentCodec.validate(document); self.document = document }
    private mutating func update(_ change: (inout WorkbenchDocument) throws -> Void) throws {
        var candidate = document; try change(&candidate); try DocumentCodec.validate(candidate); document = candidate
    }
    public mutating func upsert(_ connection: ConnectionRecord) throws {
        try update { d in
            if let index = d.connections.firstIndex(where: { $0.id == connection.id }) { d.connections[index] = connection }
            else { d.connections.append(connection) }
        }
    }
    public mutating func upsertFolder(_ folder: FolderRecord) throws {
        try update { d in
            if let index = d.folders.firstIndex(where: { $0.id == folder.id }) { d.folders[index] = folder }
            else { d.folders.append(folder) }
        }
    }
    public mutating func duplicateConnection(id: UUID) throws -> UUID {
        guard var record = document.connections.first(where: { $0.id == id }) else { throw ValidationError("connection selection") }
        record.id = UUID(); record.name = String(record.name.prefix(195)) + " Copy"; record.credentialReference = nil
        try upsert(record); return record.id
    }
    public mutating func removeConnection(id: UUID) throws {
        try update { d in d.connections.removeAll { $0.id == id } }
    }
    public func folderIDs(under id: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [id]; var added = true
        while added {
            added = false
            for folder in document.folders where folder.parentID.map(ids.contains) == true {
                if ids.insert(folder.id).inserted { added = true }
            }
        }
        return ids
    }
    public mutating func removeFolder(id: UUID) throws -> Set<UUID> {
        let ids = folderIDs(under: id)
        let removed = Set(document.connections.filter { $0.folderID.map(ids.contains) == true }.map(\.id))
        try update { d in
            d.folders.removeAll { ids.contains($0.id) }; d.connections.removeAll { removed.contains($0.id) }
        }
        return removed
    }
    public func connections(matching query: String, folderID: UUID?, favoritesOnly: Bool) -> [ConnectionRecord] {
        let ids = folderID.map(folderIDs)
        return document.connections.filter { c in
            (!favoritesOnly || c.isFavorite) && (ids == nil || c.folderID.map { ids!.contains($0) } == true) &&
            (query.isEmpty || ([c.name, c.host] + c.tags).contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func exportData(removeHosts: Bool, removeUsernames: Bool) throws -> Data {
        var export = document
        for i in export.connections.indices {
            export.connections[i].credentialReference = nil; export.connections[i].notes = ""; export.connections[i].tags = []
            if removeHosts { export.connections[i].host = export.connections[i].kind == .web ? "https://redacted.invalid" : "redacted.invalid" }
            if removeUsernames { export.connections[i].username = nil }
        }
        return try DocumentCodec.encode(export)
    }
}
