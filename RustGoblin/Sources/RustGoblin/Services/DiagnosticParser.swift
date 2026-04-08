import Foundation

enum DiagnosticParser {
    private static let linePattern = try? NSRegularExpression(pattern: #":(\d+):\d+"#)

    static func parse(_ output: String) -> [Diagnostic] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = String(rawLine)

                if line.contains("error:") || line.contains("error[") {
                    return Diagnostic(
                        message: line.trimmingCharacters(in: .whitespaces),
                        line: parseLineNumber(from: line),
                        severity: .error
                    )
                }

                if line.contains("warning:") || line.contains("warning[") {
                    return Diagnostic(
                        message: line.trimmingCharacters(in: .whitespaces),
                        line: parseLineNumber(from: line),
                        severity: .warning
                    )
                }

                return nil
            }
    }

    private static func parseLineNumber(from line: String) -> Int? {
        guard
            let linePattern,
            let match = linePattern.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
            ),
            let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return Int(line[range])
    }
}
