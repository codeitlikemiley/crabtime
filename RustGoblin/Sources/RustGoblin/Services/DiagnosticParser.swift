import Foundation

enum DiagnosticParser {
    // Matches "error[E0106]: missing lifetime specifier" or "error: could not compile"
    // Also matches file paths like "src/main.rs:13:55"
    private static let headerPattern = try? NSRegularExpression(
        pattern: #"(error|warning)(\[E\d+\])?: (.+)"#
    )
    private static let linePattern = try? NSRegularExpression(pattern: #"^\s*--> .+?:(\d+):\d+"#)
    private static let sourceLinePattern = try? NSRegularExpression(pattern: #"^\s*\d+\s*\|"#)
    private static let helpLinePattern = try? NSRegularExpression(pattern: #"^\s*= (help|note):"#)

    static func parse(_ output: String) -> [Diagnostic] {
        // Strip ANSI escape sequences for parsing
        let cleaned = stripANSI(output)
        let lines = cleaned.components(separatedBy: "\n")
        var diagnostics: [Diagnostic] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Check if this line starts an error or warning
            guard let headerMatch = matchHeader(line) else {
                i += 1
                continue
            }

            let severity: DiagnosticSeverity = line.contains("error") ? .error : .warning
            let summaryMessage = headerMatch
            var lineNumber: Int? = nil
            var contextLines: [String] = []

            // Collect context lines (source, arrows, help, notes) until next header or blank gap
            i += 1
            var blankCount = 0

            while i < lines.count {
                let contextLine = lines[i]
                let trimmed = contextLine.trimmingCharacters(in: .whitespaces)

                // Stop at next error/warning header
                if matchHeader(contextLine) != nil {
                    break
                }

                // Track blank lines — two consecutive blanks means end of this diagnostic
                if trimmed.isEmpty {
                    blankCount += 1
                    if blankCount >= 2 { i += 1; break }
                    i += 1
                    continue
                }
                blankCount = 0

                // Parse --> for line number
                if lineNumber == nil, let ln = parseArrowLineNumber(contextLine) {
                    lineNumber = ln
                }

                // Collect source lines, pointer lines, help text
                if isContextLine(contextLine) {
                    contextLines.append(contextLine)
                }

                i += 1
            }

            // Build full message with context
            var fullMessage = summaryMessage
            if !contextLines.isEmpty {
                fullMessage += "\n" + contextLines.joined(separator: "\n")
            }

            diagnostics.append(Diagnostic(
                message: fullMessage,
                line: lineNumber,
                severity: severity
            ))
        }

        // Deduplicate by message
        var seen = Set<String>()
        return diagnostics.filter { seen.insert($0.message).inserted }
    }

    // MARK: - Helpers

    private static func matchHeader(_ line: String) -> String? {
        guard let headerPattern else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = headerPattern.firstMatch(in: line, range: range) else {
            return nil
        }
        if let msgRange = Range(match.range(at: 0), in: line) {
            return String(line[msgRange]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseArrowLineNumber(_ line: String) -> Int? {
        guard let linePattern else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = linePattern.firstMatch(in: line, range: range),
              let numRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[numRange])
    }

    private static func isContextLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Source lines:  "13 | fn get_value..."
        // Pointer lines: "   |     ^ expected..."
        // Help lines:    "= help: ..."
        // Arrow lines:   "--> src/main.rs:13:55"
        return trimmed.contains(" | ") ||
               trimmed.hasPrefix("| ") ||
               trimmed.hasPrefix("= help:") ||
               trimmed.hasPrefix("= note:") ||
               trimmed.hasPrefix("-->") ||
               trimmed.hasPrefix("...") ||
               (trimmed.hasPrefix("|") && trimmed.count > 1)
    }

    static func stripANSI(_ string: String) -> String {
        // Remove ANSI escape sequences: ESC[...m, ESC[...K, etc.
        let pattern = "\\x1B\\[[0-9;]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return string
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }
}
