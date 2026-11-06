//
//  CredentialStoreTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Security
import Testing
@testable import RagnarokGame

private enum KeychainTestEnvironment {
    static let isAvailable: Bool = {
        let store = CredentialStore(service: "test.\(UUID().uuidString)")
        let account = "probe"
        do {
            try store.setPassword("probe", for: account)
            try store.deletePassword(for: account)
            return true
        } catch let error as CredentialStoreError
            where error.status == errSecMissingEntitlement || error.status == errSecInteractionNotAllowed {
            return false
        } catch {
            return true
        }
    }()
}

@Suite(.enabled(if: KeychainTestEnvironment.isAvailable, "The Keychain is not available in this test environment."))
struct CredentialStoreTests {
    private let service = "test.\(UUID().uuidString)"
    private let account = "account"

    private var store: CredentialStore {
        CredentialStore(service: service)
    }

    private func cleanUp() {
        try? store.deletePassword(for: account)
    }

    @Test func missingPasswordReturnsNil() throws {
        defer { cleanUp() }

        let password = try store.password(for: account)
        #expect(password == nil)
    }

    @Test func savedPasswordCanBeRead() throws {
        defer { cleanUp() }

        try store.setPassword("secret", for: account)

        let password = try store.password(for: account)
        #expect(password == "secret")
    }

    @Test func savingAgainUpdatesPassword() throws {
        defer { cleanUp() }

        try store.setPassword("secret", for: account)
        try store.setPassword("updated", for: account)

        let password = try store.password(for: account)
        #expect(password == "updated")
    }

    @Test func deletedPasswordCanNoLongerBeRead() throws {
        defer { cleanUp() }

        try store.setPassword("secret", for: account)
        try store.deletePassword(for: account)

        let password = try store.password(for: account)
        #expect(password == nil)
    }

    @Test func deletingMissingPasswordDoesNotThrow() {
        #expect(throws: Never.self) {
            try store.deletePassword(for: account)
        }
    }
}
