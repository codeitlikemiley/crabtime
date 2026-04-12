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
            CrabTimeTheme.Palette.textMuted
        case .tests:
            CrabTimeTheme.Palette.cyan
        }
    }
}
