import Foundation

struct ExercismExercise: Identifiable, Codable, Sendable {
    let slug: String
    let type: String
    let title: String
    let iconURL: URL
    let difficulty: String
    let blurb: String
    let isUnlocked: Bool
    let isRecommended: Bool
    
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, type, title, difficulty, blurb
        case iconURL = "icon_url"
        case isUnlocked = "is_unlocked"
        case isRecommended = "is_recommended"
    }
}

struct ExercismExercisesResponse: Codable, Sendable {
    let exercises: [ExercismExercise]
}
