//
//  DatabaseKeyStore.swift
//  Chronicle
//

import Foundation
import Security

enum DatabaseKeyStoreError: LocalizedError {
    case keychain(operation: String, status: OSStatus)
    case missingKey
    case invalidKeyLength(Int)
    case randomGeneration(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let operation, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Database key \(operation) failed: \(detail)"
        case .missingKey:
            return "The encrypted Chronicle archive exists, but its device-only Keychain key is missing. The archive was not replaced or reset."
        case .invalidKeyLength(let length):
            return "The stored database key has an invalid length (\(length) bytes)."
        case .randomGeneration(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Secure database key generation failed: \(detail)"
        }
    }
}

final class DatabaseKeyStore: @unchecked Sendable {
    nonisolated static let shared = DatabaseKeyStore()

    nonisolated private static let keyLength = 32
    nonisolated private static let service = "com.Chronicle.Chronicle.database-key"
    nonisolated private static let account = "activity.sqlite.v1"

    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var cachedKey: Data?

    nonisolated private init() {}

    nonisolated func databaseKey(createIfMissing: Bool = true) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey {
            return cachedKey
        }

        if let existingKey = try readKey() {
            guard existingKey.count == Self.keyLength else {
                throw DatabaseKeyStoreError.invalidKeyLength(existingKey.count)
            }
            cachedKey = existingKey
            return existingKey
        }

        guard createIfMissing else {
            throw DatabaseKeyStoreError.missingKey
        }

        let generatedKey = try generateKey()
        do {
            try addKey(generatedKey)
            cachedKey = generatedKey
            return generatedKey
        } catch DatabaseKeyStoreError.keychain(_, errSecDuplicateItem) {
            guard let racedKey = try readKey() else {
                throw DatabaseKeyStoreError.keychain(operation: "read after concurrent creation", status: errSecItemNotFound)
            }
            guard racedKey.count == Self.keyLength else {
                throw DatabaseKeyStoreError.invalidKeyLength(racedKey.count)
            }
            cachedKey = racedKey
            return racedKey
        }
    }

    /// Deletes the device-only archive key after every encrypted database copy has been
    /// removed. The in-memory cache is cleared only when Keychain confirms deletion (or that
    /// the item was already absent), so a failed wipe cannot strand a remaining archive.
    nonisolated func deleteDatabaseKey() throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            cachedKey = nil
        default:
            throw DatabaseKeyStoreError.keychain(operation: "delete", status: status)
        }
    }

    nonisolated private func readKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw DatabaseKeyStoreError.keychain(operation: "read", status: errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw DatabaseKeyStoreError.keychain(operation: "read", status: status)
        }
    }

    nonisolated private func addKey(_ key: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DatabaseKeyStoreError.keychain(operation: "store", status: status)
        }
    }

    nonisolated private func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: Self.keyLength)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw DatabaseKeyStoreError.randomGeneration(status: status)
        }
        return Data(bytes)
    }
}
