import Foundation
import HomeAssistantKit
import OSLog
import Security

private let logger = Logger(subsystem: "HomeAssistantTV", category: "Keychain")

/// Persists the server address and access token in the Keychain.
enum CredentialStore {
    private static let service = "HomeAssistantTV"
    private static let account = "server"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> HAServerConfig? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Loading credentials failed: \(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(HAServerConfig.self, from: data)
    }

    static func save(_ config: HAServerConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Saving credentials failed: \(status)")
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
