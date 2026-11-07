import Foundation

public struct LoadedDocument: Sendable {
    public let document: WorkbenchDocument
    public let url: URL
    public let sourceData: Data
}
public enum DocumentStoreError: LocalizedError, Sendable {
    case conflict, destinationExists, unsafeFile, unavailable
    public var errorDescription: String? {
        switch self {
        case .conflict: "The file changed or was removed outside this window. Use Save As to preserve both versions."
        case .destinationExists: "The destination already exists. Choose a new filename."
        case .unsafeFile: "Choose a regular local file, not a symbolic link or directory."
        case .unavailable: "The file could not be read or saved. Check its location and permissions."
        }
    }
}
public enum DocumentStore {
    public static func requireSeparateDestination(_ destination: URL, preserving source: URL?) throws {
        if let source, destination.resolvingSymlinksInPath().standardizedFileURL == source.resolvingSymlinksInPath().standardizedFileURL {
            throw ValidationError("separate destination; preserve the original file")
        }
    }
    private static func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw DocumentStoreError.unsafeFile }
        guard (values.fileSize ?? Int.max) <= DocumentCodec.maxBytes else { throw ValidationError("file size") }
    }
    private static func read(_ url: URL) throws -> Data {
        try regularFile(url)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: DocumentCodec.maxBytes + 1) ?? Data()
        guard data.count <= DocumentCodec.maxBytes else { throw ValidationError("file size") }
        return data
    }
    public static func load(from url: URL) throws -> LoadedDocument {
        do {
            let data = try read(url)
            return LoadedDocument(document: try DocumentCodec.decode(data), url: url, sourceData: data)
        } catch let error as ValidationError { throw error }
        catch let error as DocumentStoreError { throw error }
        catch { throw DocumentStoreError.unavailable }
    }
    public static func save(_ document: WorkbenchDocument, to url: URL, expectedData: Data?) throws -> LoadedDocument {
        let bytes = try DocumentCodec.encode(document)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<LoadedDocument, Error> = .failure(DocumentStoreError.unavailable)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            outcome = Result {
                let fm = FileManager.default
                if let expectedData {
                    guard fm.fileExists(atPath: target.path) else { throw DocumentStoreError.conflict }
                    guard try read(target) == expectedData else { throw DocumentStoreError.conflict }
                } else {
                    // lstat-style attributes also detect dangling symlinks.
                    if (try? fm.attributesOfItem(atPath: target.path)) != nil { throw DocumentStoreError.destinationExists }
                }
                let temp = target.deletingLastPathComponent().appendingPathComponent(".workbench-\(UUID().uuidString).tmp")
                defer { try? fm.removeItem(at: temp) }
                guard fm.createFile(atPath: temp.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else { throw DocumentStoreError.unavailable }
                if expectedData != nil { _ = try fm.replaceItemAt(target, withItemAt: temp) }
                else { try fm.moveItem(at: temp, to: target) }
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                return LoadedDocument(document: document, url: url, sourceData: bytes)
            }
        }
        if coordinationError != nil { throw DocumentStoreError.unavailable }
        do { return try outcome.get() }
        catch let error as DocumentStoreError { throw error }
        catch let error as ValidationError { throw error }
        catch { throw DocumentStoreError.unavailable }
    }
}
