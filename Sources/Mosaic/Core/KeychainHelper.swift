import Foundation
import Security

public enum KeychainHelper {
    private static let service = "com.ryncalpin.mosaic"

    public static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    public static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Credential Helpers

    public static func savePassword(_ password: String, connectionID: String) {
        save(password, for: "password-\(connectionID)")
    }

    public static func loadPassword(connectionID: String) -> String? {
        load(for: "password-\(connectionID)")
    }

    public static func savePrivateKey(_ key: String, connectionID: String) {
        save(key, for: "privatekey-\(connectionID)")
    }

    public static func loadPrivateKey(connectionID: String) -> String? {
        load(for: "privatekey-\(connectionID)")
    }

    public static func deleteCredentials(connectionID: String) {
        delete(for: "password-\(connectionID)")
        delete(for: "privatekey-\(connectionID)")
    }
}
