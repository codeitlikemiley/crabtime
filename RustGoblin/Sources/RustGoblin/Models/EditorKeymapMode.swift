import Foundation

enum EditorKeymapMode: String, Codable, CaseIterable {
    case standard
    case vim

    var title: String {
        switch self {
        case .standard:
            "Standard"
        case .vim:
            "Vim"
        }
    }
}

enum VimInputMode: String, Codable {
    case insert
    case normal
    case visual

    var title: String {
        switch self {
        case .insert:
            "INSERT"
        case .normal:
            "NORMAL"
        case .visual:
            "VISUAL"
        }
    }
}
