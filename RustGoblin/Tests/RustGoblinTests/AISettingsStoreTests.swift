import XCTest
@testable import RustGoblin

@MainActor
final class AISettingsStoreTests: XCTestCase {
    func testProviderPreferencesDefaultToExpectedTransport() {
        let defaults = makeDefaults()
        let store = AISettingsStore(defaults: defaults)

        XCTAssertEqual(store.preference(for: .geminiCLI).transport, .acp)
        XCTAssertEqual(store.preference(for: .openCodeCLI).transport, .acp)
        XCTAssertEqual(store.preference(for: .codexCLI).transport, .legacyCLI)
        XCTAssertEqual(store.preference(for: .claudeCLI).transport, .legacyCLI)
    }

    func testLegacyPreferencePayloadFallsBackToProviderDefaultTransport() throws {
        let defaults = makeDefaults()
        let legacyPayload = """
        [
          {
            "kind": "geminiCLI",
            "model": "gemini-2.5-pro",
            "isEnabled": true
          }
        ]
        """

        defaults.set(Data(legacyPayload.utf8), forKey: "ai-provider-preferences")
        let store = AISettingsStore(defaults: defaults)

        XCTAssertEqual(store.preference(for: .geminiCLI).transport, .acp)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RustGoblinTests.AISettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
