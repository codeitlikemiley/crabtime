import Foundation

struct TodoScanner: Sendable {
    /// Scan all `.rs` files under the given root directory for TODO markers.
    func scanWorkspace(rootURL: URL) -> [TodoItem] {
        var items: [TodoItem] = []
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "rs" else { continue }
            // Skip temporary build/harness files
            if fileURL.lastPathComponent.hasPrefix(".rustgoblin-") { continue }
            if fileURL.path.contains("/target/") { continue }

            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let fileItems = scanFile(source: source, fileURL: fileURL, rootURL: rootURL)
            items.append(contentsOf: fileItems)
        }

        return items.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            return lhs.line < rhs.line
        }
    }

    /// Scan a single source string for TODO markers.
    func scanFile(source: String, fileURL: URL, rootURL: URL) -> [TodoItem] {
        var items: [TodoItem] = []
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let relativePath = filePath.hasPrefix(rootPath + "/")
            ? String(filePath.dropFirst(rootPath.count + 1))
            : filePath
        let fileName = fileURL.lastPathComponent

        let lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1 // 1-based

            // todo!() macro
            if let range = line.range(of: "todo!") {
                let col = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                let context = extractContext(from: line, around: "todo!")
                items.append(TodoItem(
                    id: "\(relativePath):\(lineNumber):todo_macro",
                    filePath: relativePath,
                    fileName: fileName,
                    line: lineNumber,
                    column: col,
                    text: context,
                    kind: .todoMacro
                ))
            }

            // unimplemented!() macro
            if let range = line.range(of: "unimplemented!") {
                let col = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                let context = extractContext(from: line, around: "unimplemented!")
                items.append(TodoItem(
                    id: "\(relativePath):\(lineNumber):unimplemented",
                    filePath: relativePath,
                    fileName: fileName,
                    line: lineNumber,
                    column: col,
                    text: context,
                    kind: .unimplemented
                ))
            }

            // /// TODO: doc comment
            if trimmed.hasPrefix("/// TODO") || trimmed.hasPrefix("///TODO") {
                let text = trimmed
                    .replacingOccurrences(of: "/// TODO:", with: "")
                    .replacingOccurrences(of: "/// TODO", with: "")
                    .replacingOccurrences(of: "///TODO:", with: "")
                    .replacingOccurrences(of: "///TODO", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(
                    id: "\(relativePath):\(lineNumber):doc_todo",
                    filePath: relativePath,
                    fileName: fileName,
                    line: lineNumber,
                    column: 1,
                    text: text.isEmpty ? "TODO" : text,
                    kind: .todoDocComment
                ))
            }
            // // TODO: line comment (but not doc comments already captured)
            else if trimmed.hasPrefix("// TODO") || trimmed.hasPrefix("//TODO") {
                let text = trimmed
                    .replacingOccurrences(of: "// TODO:", with: "")
                    .replacingOccurrences(of: "// TODO", with: "")
                    .replacingOccurrences(of: "//TODO:", with: "")
                    .replacingOccurrences(of: "//TODO", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(
                    id: "\(relativePath):\(lineNumber):comment_todo",
                    filePath: relativePath,
                    fileName: fileName,
                    line: lineNumber,
                    column: 1,
                    text: text.isEmpty ? "TODO" : text,
                    kind: .todoComment
                ))
            }

            // FIXME comments
            if trimmed.hasPrefix("// FIXME") || trimmed.hasPrefix("//FIXME")
                || trimmed.hasPrefix("/// FIXME") || trimmed.hasPrefix("///FIXME") {
                let text = trimmed
                    .replacingOccurrences(of: "/// FIXME:", with: "")
                    .replacingOccurrences(of: "/// FIXME", with: "")
                    .replacingOccurrences(of: "// FIXME:", with: "")
                    .replacingOccurrences(of: "// FIXME", with: "")
                    .replacingOccurrences(of: "///FIXME:", with: "")
                    .replacingOccurrences(of: "///FIXME", with: "")
                    .replacingOccurrences(of: "//FIXME:", with: "")
                    .replacingOccurrences(of: "//FIXME", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(
                    id: "\(relativePath):\(lineNumber):fixme",
                    filePath: relativePath,
                    fileName: fileName,
                    line: lineNumber,
                    column: 1,
                    text: text.isEmpty ? "FIXME" : text,
                    kind: .fixme
                ))
            }
        }
        return items
    }

    private func extractContext(from line: String, around marker: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Try to extract the message inside todo!("message") or todo!()
        if let openParen = trimmed.range(of: "\(marker)(") {
            let afterParen = trimmed[openParen.upperBound...]
            if let closeParen = afterParen.range(of: ")") {
                let content = String(afterParen[..<closeParen.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return content.isEmpty ? marker : content
            }
        }
        return marker
    }
}
