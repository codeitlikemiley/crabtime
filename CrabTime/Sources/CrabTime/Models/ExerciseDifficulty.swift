import Foundation
import SwiftUI

enum ExerciseDifficulty: String, CaseIterable, Codable, Hashable, Sendable {
    case easy
    case medium
    case hard
    case core
    case kata
    case unknown

    var title: String {
        switch self {
        case .easy:
            "Easy"
        case .medium:
            "Medium"
        case .hard:
            "Hard"
        case .core:
            "Core"
        case .kata:
            "Kata"
        case .unknown:
            "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .easy:
            CrabTimeTheme.Palette.moss
        case .medium:
            CrabTimeTheme.Palette.panelTint
        case .hard:
            CrabTimeTheme.Palette.ember
        case .core:
            CrabTimeTheme.Palette.cyan
        case .kata:
            CrabTimeTheme.Palette.ink.opacity(0.82)
        case .unknown:
            CrabTimeTheme.Palette.textMuted
        }
    }

    static func inferred(from text: String, fallbackIndex: Int = 0) -> ExerciseDifficulty {
        let lowercased = text.lowercased()

        if lowercased.contains("easy") {
            return .easy
        }
        if lowercased.contains("medium") {
            return .medium
        }
        if lowercased.contains("hard") {
            return .hard
        }
        if lowercased.contains("core") {
            return .core
        }
        if lowercased.contains("kata") {
            return .kata
        }

        return .unknown
    }
}
