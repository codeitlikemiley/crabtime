import Foundation

struct AIProviderPreference: Identifiable, Equatable, Codable, Sendable {
    let kind: AIProviderKind
    var model: String
    var isEnabled: Bool

    var id: String { kind.rawValue }

    init(kind: AIProviderKind, model: String? = nil, isEnabled: Bool = true) {
        self.kind = kind
        self.model = model ?? kind.defaultModel
        self.isEnabled = isEnabled
    }
}
