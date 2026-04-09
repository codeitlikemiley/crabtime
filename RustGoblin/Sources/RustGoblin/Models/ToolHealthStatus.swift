import Foundation

struct ToolHealthStatus: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let executablePath: String?
    let version: String?
    let isInstalled: Bool
    let isConfigured: Bool
    let guidance: String?
}
