import Foundation

struct CredentialStore {
    private let prefix = "RustGoblin.Secrets."

    func readSecret(for key: String) -> String? {
        return UserDefaults.standard.string(forKey: prefix + key)
    }

    func saveSecret(_ secret: String, for key: String) throws {
        UserDefaults.standard.set(secret, forKey: prefix + key)
    }

    func deleteSecret(for key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
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
