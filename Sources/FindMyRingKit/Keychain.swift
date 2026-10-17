import Foundation
import Security
import os

/// Stores the Apple Account password in the Keychain. The app and its widget
/// read it here; the sign-in itself keeps nothing. A generic-password item,
/// one per Apple Account, whose account attribute is the Apple Account email.
///
/// Items go in the **data protection keychain** (`kSecUseDataProtectionKeychain`).
/// On macOS that is the only keychain where `kSecAttrAccessGroup` means
/// anything: in the legacy login keychain the group is ignored, so a widget
/// extension can't read what its app saved. Pass `accessGroup` to share the
/// item between processes that hold that keychain-access-group entitlement.
///
/// Every query carries the flag. On macOS a query without it may target
/// *both* keychains: 0.2.2's "delete the old login-keychain copy" also
/// deleted the shared item, so the password vanished at launch.
public enum KeychainStore {
    public static let service = "com.danielyakobian.findmy-ring"

    private static let log = Logger(subsystem: "com.danielyakobian.findmy-ring", category: "keychain")

    public static func save(password: String, account: String, accessGroup: String? = nil) throws {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Couldn't save the password (OSStatus \(status, privacy: .public))")
            throw RingError(.server, "Could not save the password to the Keychain (\(status)).")
        }
    }

    public static func read(account: String, accessGroup: String? = nil) -> String? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return string(matching: query, what: "read the password")
    }

    public static func delete(account: String, accessGroup: String? = nil) {
        SecItemDelete(baseQuery(account: account, accessGroup: accessGroup) as CFDictionary)
    }

    /// The Apple Account of the saved password, if there is one, so the app
    /// can find its sign-in even when its settings file doesn't name it.
    public static func savedAccount(accessGroup: String? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return account(matching: query)
    }

    // MARK: Helpers

    private static func string(matching query: [String: Any], what: String) -> String? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound {
                log.error("Couldn't \(what, privacy: .public) (OSStatus \(status, privacy: .public))")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Attributes only, never the secret, so a lookup can't raise a prompt.
    private static func account(matching base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let attributes = out as? [String: Any] else {
            if status != errSecItemNotFound {
                log.error("Couldn't look up the saved account (OSStatus \(status, privacy: .public))")
            }
            return nil
        }
        return attributes[kSecAttrAccount as String] as? String
    }

    private static func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }
}
