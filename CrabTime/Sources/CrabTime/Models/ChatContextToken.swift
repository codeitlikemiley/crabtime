import Foundation

enum ChatContextToken: Equatable, Hashable {
    case file(URL)
    case output
    case diagnostics

    var description: String {
        switch self {
        case .file(let url):
            return "@\(url.lastPathComponent)"
        case .output:
            return "#output"
        case .diagnostics:
            return "#diagnostics"
        }
    }
}

struct ChatContextTokenParser {
    static func parse(_ text: String, workspaceRoot: URL) -> [ChatContextToken] {
        var tokens: [ChatContextToken] = []
        
        // Use a simple scanner to find tokens, avoiding punctuation issues
        let parts = text.split(whereSeparator: \.isWhitespace)
        
        for part in parts {
            let str = String(part).trimmingCharacters(in: .init(charactersIn: ".,:;?!()[]{}"))
            if str == "#output" {
                if !tokens.contains(.output) { tokens.append(.output) }
            } else if str == "#diagnostics" {
                if !tokens.contains(.diagnostics) { tokens.append(.diagnostics) }
            } else if str.hasPrefix("@") && str.count > 1 {
                let relPath = String(str.dropFirst())
                let url = workspaceRoot.appendingPathComponent(relPath)
                let token = ChatContextToken.file(url)
                if !tokens.contains(token) { tokens.append(token) }
            }
        }
        
        return tokens
    }
}
