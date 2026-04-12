import Foundation
import Security

struct CredentialStore {
    private let service = AppBrand.keychainService
    private let legacyService = AppBrand.legacyKeychainService
    private let legacyPrefix = AppBrand.legacyUserDefaultsSecretPrefix

    func readSecret(for key: String) -> String? {
        if let secret = readSecret(for: key, service: service) {
            return secret
        }

        if let legacySecret = readSecret(for: key, service: legacyService) {
            try? saveSecret(legacySecret, for: key)
            try? deleteSecret(for: key, service: legacyService)
            return legacySecret
        }

        // Secure Migration: Check insecure fallback to transport legacy tokens transparently
        if let oldSecret = UserDefaults.standard.string(forKey: legacyPrefix + key) {
             try? saveSecret(oldSecret, for: key)
             UserDefaults.standard.removeObject(forKey: legacyPrefix + key)
             return oldSecret
        }

        return nil
    }

    func saveSecret(_ secret: String, for key: String) throws {
        guard let data = secret.data(using: .utf8) else { return }

        // Always clean up legacy default if we are specifically saving over it
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)

        try upsertSecret(data, for: key, service: service)
    }

    func deleteSecret(for key: String) throws {
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)

        try deleteSecret(for: key, service: service)
    }

    private func readSecret(for key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    private func upsertSecret(_ data: Data, for key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status != errSecSuccess {
            throw CredentialStoreError.operationFailed(status: status)
        }
    }

    private func deleteSecret(for key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialStoreError.operationFailed(status: status)
        }
    }
}

enum CredentialStoreError: LocalizedError {
    case operationFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            return "Credential storage failed with status \(status)."
        }
    }
}
