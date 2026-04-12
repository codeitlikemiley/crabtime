import Foundation

struct AIProviderPreference: Identifiable, Equatable, Codable, Sendable {
    let kind: AIProviderKind
    var model: String
    var isEnabled: Bool
    var transport: AITransportKind

    private enum CodingKeys: String, CodingKey {
        case kind
        case model
        case isEnabled
        case transport
    }

    var id: String { kind.rawValue }

    init(
        kind: AIProviderKind,
        model: String? = nil,
        isEnabled: Bool = true,
        transport: AITransportKind? = nil
    ) {
        self.kind = kind
        self.model = model ?? kind.defaultModel
        self.isEnabled = isEnabled
        self.transport = transport ?? kind.defaultTransport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AIProviderKind.self, forKey: .kind)
        self.kind = kind
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModel
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.transport = try container.decodeIfPresent(AITransportKind.self, forKey: .transport) ?? kind.defaultTransport
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(model, forKey: .model)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(transport, forKey: .transport)
    }
}
