//
//  KeychainHelper.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.hashripper.wificreds"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        // If an item for this account already exists, update it; otherwise add
        let query: [CFString: Any] = [
            kSecClass            : kSecClassGenericPassword,
            kSecAttrService      : service,
            kSecAttrAccount      : account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData        : data
        ]

        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load(account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass            : kSecClassGenericPassword,
            kSecAttrService      : service,
            kSecAttrAccount      : account,
            kSecReturnData       : true,
            kSecMatchLimit       : kSecMatchLimitOne
        ]

        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
        guard let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Unknown error (\(status))"
        }
    }
}
