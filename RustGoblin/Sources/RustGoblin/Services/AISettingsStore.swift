import Foundation
import Observation

@Observable
@MainActor
final class AISettingsStore {
    private let defaults: UserDefaults
    private let preferenceKey = "ai-provider-preferences"
    private let defaultProviderKey = "ai-default-provider"

    var preferences: [AIProviderPreference]
    var defaultProvider: AIProviderKind

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.loadPreferences(from: defaults) ?? AIProviderKind.defaultChatProviders.map { AIProviderPreference(kind: $0) }
        self.defaultProvider = Self.loadDefaultProvider(from: defaults) ?? .codexCLI
        ensureAllProvidersExist()
    }

    func preference(for kind: AIProviderKind) -> AIProviderPreference {
        preferences.first(where: { $0.kind == kind }) ?? AIProviderPreference(kind: kind)
    }

    func updateModel(_ model: String, for kind: AIProviderKind) {
        updatePreference(for: kind) { preference in
            preference.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.defaultModel : model
        }
    }

    func setEnabled(_ isEnabled: Bool, for kind: AIProviderKind) {
        updatePreference(for: kind) { preference in
            preference.isEnabled = isEnabled
        }
    }

    func setDefaultProvider(_ kind: AIProviderKind) {
        defaultProvider = kind
        defaults.set(kind.rawValue, forKey: defaultProviderKey)
    }

    private func updatePreference(for kind: AIProviderKind, update: (inout AIProviderPreference) -> Void) {
        guard let index = preferences.firstIndex(where: { $0.kind == kind }) else {
            var preference = AIProviderPreference(kind: kind)
            update(&preference)
            preferences.append(preference)
            persist()
            return
        }

        update(&preferences[index])
        persist()
    }

    private func ensureAllProvidersExist() {
        for kind in AIProviderKind.defaultChatProviders where !preferences.contains(where: { $0.kind == kind }) {
            preferences.append(AIProviderPreference(kind: kind))
        }
        persist()
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            defaults.set(encoded, forKey: preferenceKey)
        }
        defaults.set(defaultProvider.rawValue, forKey: defaultProviderKey)
    }

    private static func loadPreferences(from defaults: UserDefaults) -> [AIProviderPreference]? {
        guard let data = defaults.data(forKey: "ai-provider-preferences") else {
            return nil
        }
        return try? JSONDecoder().decode([AIProviderPreference].self, from: data)
    }

    private static func loadDefaultProvider(from defaults: UserDefaults) -> AIProviderKind? {
        guard let rawValue = defaults.string(forKey: "ai-default-provider") else {
            return nil
        }
        return AIProviderKind(rawValue: rawValue)
    }
}
