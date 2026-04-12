import Foundation

struct SourcePresentationBuilder: Sendable {
    func build(from source: String) -> SourcePresentation {
        return SourcePresentation(
            prefix: "",
            visibleSource: source.trimmingTrailingWhitespace().appendingTrailingNewlineIfNeeded(),
            suffix: "",
            hiddenChecks: extractChecks(from: source)
        )
    }

    private func extractChecks(from source: String) -> [ExerciseCheck] {
        guard
            let markerRange = source.range(of: "#[cfg(test", options: .backwards),
            let modRange = source.range(of: "mod tests", range: markerRange.lowerBound..<source.endIndex),
            modRange.lowerBound >= markerRange.lowerBound
        else {
            return []
        }

        let testBlock = String(source[markerRange.lowerBound...])

        return testBlock
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .reduce(into: ExtractionState()) { state, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#[") {
                    state.pendingAttributes.append(line)
                    return
                }

                guard line.hasPrefix("fn ") else {
                    if !line.isEmpty {
                        state.pendingAttributes.removeAll()
                    }
                    return
                }

                defer { state.pendingAttributes.removeAll() }

                guard
                    state.pendingAttributes.contains(where: { $0.contains("#[test") }),
                    !state.pendingAttributes.contains(where: { $0.contains("#[ignore") }),
                    let signature = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).last,
                    let name = signature.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true).first
                else {
                    return
                }

                let identifier = String(name)
                state.checks.append(
                    ExerciseCheck(
                        id: identifier,
                        title: identifier.replacingOccurrences(of: "_", with: " ").capitalized,
                        detail: "Test: \(identifier)",
                        symbolName: "checklist"
                    )
                )
            }
            .checks
    }
}

private extension SourcePresentationBuilder {
    struct ExtractionState {
        var pendingAttributes: [String] = []
        var checks: [ExerciseCheck] = []
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }

    func appendingTrailingNewlineIfNeeded() -> String {
        guard !isEmpty, !hasSuffix("\n") else {
            return self
        }

        return self + "\n"
    }
}
