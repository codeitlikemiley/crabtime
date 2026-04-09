import Foundation
import Security

struct CredentialStore {
    private let service = "RustGoblin.AIProviders"

    func readSecret(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return secret
    }

    func saveSecret(_ secret: String, for key: String) throws {
        let data = Data(secret.utf8)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.operationFailed(status: updateStatus)
        }

        var insertQuery = baseQuery
        insertQuery[kSecValueData] = data
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw CredentialStoreError.operationFailed(status: insertStatus)
        }
    }

    func deleteSecret(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.operationFailed(status: status)
        }
    }
}

enum CredentialStoreError: LocalizedError {
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            "Credential storage failed with status \(status)."
        }
    }
}
