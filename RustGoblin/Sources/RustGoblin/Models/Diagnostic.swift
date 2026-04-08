import Foundation

struct Diagnostic: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
    let line: Int?
    let severity: DiagnosticSeverity
}
