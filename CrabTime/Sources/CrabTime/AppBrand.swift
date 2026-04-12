import Foundation

enum AppBrand {
    static let shortName = "Crab Time"
    static let longName = "Crab Time"
    static let bundleIdentifier = "dev.crab.time"

    static let applicationSupportDirectoryName = "crab-time"
    static let keychainService = "\(bundleIdentifier).secrets"
    static let diffTempDirectoryPrefix = "crab-time-Diff"
    static let fallbackStoragePrefix = "crab-time-Fallback"

    static let legacyApplicationSupportDirectoryName = "RustGoblin"
    static let legacyKeychainService = "com.rustgoblin.secrets"
    static let legacyUserDefaultsSecretPrefix = "CrabTime.Secrets."
}
