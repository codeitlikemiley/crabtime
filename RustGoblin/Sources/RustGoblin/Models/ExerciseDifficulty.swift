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
            RustGoblinTheme.Palette.moss
        case .medium:
            RustGoblinTheme.Palette.panelTint
        case .hard:
            RustGoblinTheme.Palette.ember
        case .core:
            RustGoblinTheme.Palette.cyan
        case .kata:
            RustGoblinTheme.Palette.ink.opacity(0.82)
        case .unknown:
            RustGoblinTheme.Palette.textMuted
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
