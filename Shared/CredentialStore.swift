import Foundation
import HomeAssistantKit
import OSLog
import Security

private let logger = Logger(subsystem: "HomeAssistantTV", category: "Keychain")

/// Persists the server address and access token in the Keychain, in the App
/// Group's access group so the Top Shelf extension can read it too.
enum CredentialStore {
    private static let service = "HomeAssistantTV"
    private static let account = "server"

    private static func query(shared: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared {
            // App Groups double as Keychain access groups.
            query[kSecAttrAccessGroup as String] = SharedContainer.appGroup
        }
        return query
    }

    static func load() -> HAServerConfig? {
        if let config = read(shared: true) {
            return config
        }
        // Items saved before the extension existed live in the app's private group: move them.
        // Delete first: a query without an access group matches every group,
        // so deleting afterwards would also remove the newly saved copy.
        if let config = read(shared: false) {
            SecItemDelete(query(shared: false) as CFDictionary)
            save(config)
            return config
        }
        return nil
    }

    static func save(_ config: HAServerConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        delete()
        var query = query()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Saving credentials failed: \(status)")
        }
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
    }

    private static func read(shared: Bool) -> HAServerConfig? {
        var query = query(shared: shared)
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
}
