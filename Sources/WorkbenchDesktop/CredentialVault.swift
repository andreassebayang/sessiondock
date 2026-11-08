import Foundation
import Security
import WorkbenchCore

struct CredentialVault {
    typealias CopyItem = (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    let service: String
    private let copyItem: CopyItem
    init(service: String = "org.sessiondock.credentials", copyItem: @escaping CopyItem = SecItemCopyMatching) {
        self.service = service; self.copyItem = copyItem
    }
    private func query(_ reference: String) throws -> [String: Any] {
        guard UUID(uuidString: reference) != nil else { throw ValidationError("credential reference") }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: reference, kSecAttrSynchronizable as String: false]
    }
    private func binding(_ c: ConnectionRecord) throws -> Data {
        try JSONEncoder().encode([c.kind.rawValue, c.host.lowercased(), String(c.port), c.username ?? ""])
    }
    func save(_ password: String, for connection: ConnectionRecord) throws -> String {
        guard !password.isEmpty, password.utf8.count <= 65536, !password.contains("\0") else { throw ValidationError("password length") }
        let reference = connection.credentialReference ?? UUID().uuidString
        var attributes = try query(reference)
        let values: [String: Any] = [kSecValueData as String: Data(password.utf8), kSecAttrGeneric as String: try binding(connection)]
        if connection.credentialReference != nil {
            // Refuse to replace a reference belonging to another destination.
            _ = try read(for: connection)
            try check(SecItemUpdate(attributes as CFDictionary, values as CFDictionary))
        } else {
            attributes.merge(values) { _, new in new }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            attributes[kSecAttrLabel as String] = "SessionDock credential"
            try check(SecItemAdd(attributes as CFDictionary, nil))
        }
        return reference
    }
    func read(for connection: ConnectionRecord) throws -> String? {
        guard let reference = connection.credentialReference else { return nil }
        var attributes = try query(reference)
        attributes[kSecReturnData as String] = true; attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(copyItem(attributes as CFDictionary, &result))
        guard let item = result as? [String: Any], let data = item[kSecValueData as String] as? Data,
              item[kSecAttrGeneric as String] as? Data == (try binding(connection)),
              let password = String(data: data, encoding: .utf8), !password.isEmpty else { throw ValidationError("credential destination; save a new password for this host") }
        return password
    }
    func entries() throws -> [VaultEntry] {
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = copyItem(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        return ((result as? [[String: Any]]) ?? []).compactMap { item in
            guard let reference = item[kSecAttrAccount as String] as? String, UUID(uuidString: reference) != nil,
                  let metadata = item[kSecAttrGeneric as String] as? Data,
                  let fields = try? JSONDecoder().decode([String].self, from: metadata), fields.count == 4 else { return nil }
            return VaultEntry(id: reference, protocolName: fields[0], host: fields[1], port: fields[2], username: fields[3])
        }.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }
    func delete(reference: String) throws {
        let status = SecItemDelete(try query(reference) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw VaultError(status: status) }
    }
}
struct VaultError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        switch status {
        case errSecItemNotFound: "Saved credential is missing. Enter and save it again."
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed: "Keychain access was denied, cancelled, or locked. Unlock Keychain and try again."
        default: "Keychain could not complete the operation (\(status))."
        }
    }
}

struct VaultEntry: Identifiable {
    let id: String
    let protocolName: String
    let host: String
    let port: String
    let username: String
}
