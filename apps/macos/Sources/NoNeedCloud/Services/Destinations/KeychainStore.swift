import Foundation
import Security

protocol KeychainStore: AnyObject, Sendable {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

/// Secrets are stored under one generic-password item per credential
/// reference (`kSecClassGenericPassword`, service "NoNeedCloud").
final class SecKeychainStore: KeychainStore {
    static let service = "NoNeedCloud"

    init() {}

    func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw DestinationError("Keychain save failed (OSStatus \(status)).")
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DestinationError("Keychain save failed (OSStatus \(addStatus)).")
        }
    }

    func load(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess { return result as? Data }
        guard status == errSecItemNotFound else {
            throw DestinationError("Keychain read failed (OSStatus \(status)).")
        }
        return nil
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DestinationError("Keychain delete failed (OSStatus \(status)).")
        }
    }
}

/// S3 secrets as stored in the Keychain under the config's secret reference.
struct S3SecretPayload: Codable, Equatable, Sendable {
    var secretAccessKey: String
    var sessionToken: String?
}
