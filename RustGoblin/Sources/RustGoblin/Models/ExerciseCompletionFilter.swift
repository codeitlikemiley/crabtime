import Foundation

enum ExerciseCompletionFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case open
    case done

    var title: String {
        switch self {
        case .open:
            "Open"
        case .done:
            "Done"
        }
    }
}
