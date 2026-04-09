import Foundation
import SwiftUI

enum ExerciseFileRole: String, Codable, Sendable {
    case primary
    case tests

    var title: String {
        switch self {
        case .primary:
            ""
        case .tests:
            "Tests"
        }
    }

    var tint: Color {
        switch self {
        case .primary:
            RustGoblinTheme.Palette.textMuted
        case .tests:
            RustGoblinTheme.Palette.cyan
        }
    }
}
