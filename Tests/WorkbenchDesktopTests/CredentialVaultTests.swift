import Foundation
import Security
import Testing
import WorkbenchCore
@testable import WorkbenchDesktop

struct CredentialVaultTests {
    @Test func disposableKeychainItemIsBoundToItsDestination() throws {
        let vault = CredentialVault(service: "org.sessiondock.tests." + UUID().uuidString)
        var c = ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .sftp, username: "fixture")
        let ref = try vault.save("disposable-fixture", for: c)
        defer { try? vault.delete(reference: ref) }
        c.credentialReference = ref
        #expect(try vault.read(for: c) == "disposable-fixture")
        #expect(try vault.entries().map(\.id).contains(ref))
        var moved = c; moved.host = "other.example"
        #expect(throws: (any Error).self) { try vault.read(for: moved) }
        let updated = try vault.save("replacement-fixture", for: c)
        #expect(updated == ref)
        #expect(try vault.read(for: c) == "replacement-fixture")
        try vault.delete(reference: ref)
        #expect(throws: (any Error).self) { try vault.read(for: c) }
    }
    @Test func emptySecretAndForeignReferenceAreRejected() {
        let vault = CredentialVault(service: "org.sessiondock.tests." + UUID().uuidString)
        var c = ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .rdp)
        #expect(throws: (any Error).self) { try vault.save("", for: c) }
        c.credentialReference = "foreign-account"
        #expect(throws: (any Error).self) { try vault.read(for: c) }
    }
    @Test func deniedKeychainAccessIsNotReportedAsAnEmptyPassword() {
        let vault = CredentialVault(service: "org.sessiondock.tests", copyItem: { _, _ in errSecAuthFailed })
        var c = ConnectionRecord(name: "Fixture", host: "fixture.example", kind: .rdp)
        c.credentialReference = UUID().uuidString
        #expect(throws: (any Error).self) { try vault.read(for: c) }
    }
}

@MainActor struct CredentialEditorTests {
    @Test func passwordReplacementPreservesSavedWorkspaceReference() throws {
        let model = WorkspaceModel()
        model.vault = CredentialVault(service: "org.sessiondock.tests." + UUID().uuidString)
        let original = ConnectionRecord(name: "Fixture", host: "rdp.example", kind: .rdp, username: "fixture")
        try model.saveConnection(original, password: "old-fixture", forgetCredential: false)
        let saved = try #require(model.selected)
        let durableBytes = try DocumentCodec.encode(model.workspace.document)
        try model.saveConnection(saved, password: "new-fixture", forgetCredential: false)
        let updated = try #require(model.selected)
        defer {
            for ref in [saved.credentialReference, updated.credentialReference].compactMap({ $0 }) { try? model.vault.delete(reference: ref) }
        }
        let reopened = try #require(DocumentCodec.decode(durableBytes).connections.first)
        #expect(try model.vault.read(for: reopened) == "old-fixture")
        #expect(try model.vault.read(for: updated) == "new-fixture")
    }
    @Test func missingSavedItemCanBeReplacedWithoutPublishingSecret() throws {
        let model = WorkspaceModel()
        model.vault = CredentialVault(service: "org.sessiondock.tests." + UUID().uuidString)
        var c = ConnectionRecord(name: "Fixture", host: "rdp.example", kind: .rdp, username: "fixture")
        c.credentialReference = UUID().uuidString
        try model.saveConnection(c)
        try model.saveConnection(c, password: "disposable-fixture", forgetCredential: false)
        let saved = try #require(model.selected)
        defer { if let reference = saved.credentialReference { try? model.vault.delete(reference: reference) } }
        #expect(try model.vault.read(for: saved) == "disposable-fixture")
        let data = try DocumentCodec.encode(model.workspace.document)
        #expect(!String(decoding: data, as: UTF8.self).contains("disposable-fixture"))
    }
}
