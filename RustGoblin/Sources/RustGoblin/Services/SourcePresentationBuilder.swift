import Foundation

struct SourcePresentationBuilder: Sendable {
    func build(from source: String) -> SourcePresentation {
        let prefixRange = hiddenPrefixRange(in: source)
        let suffixRange = hiddenTestsRange(in: source, startingAt: prefixRange.upperBound)

        let prefix = String(source[prefixRange])
        let visibleSource = String(source[prefixRange.upperBound..<suffixRange.lowerBound])
        let suffix = String(source[suffixRange])

        return SourcePresentation(
            prefix: prefix,
            visibleSource: visibleSource.trimmingCharacters(in: .newlines).appendingTrailingNewlineIfNeeded(),
            suffix: suffix,
            hiddenChecks: extractChecks(from: suffix)
        )
    }

    private func hiddenPrefixRange(in source: String) -> Range<String.Index> {
        var cursor = source.startIndex

        if source[cursor...].hasPrefix("#!") {
            cursor = endOfLine(after: cursor, in: source)
        }

        loop: while cursor < source.endIndex {
            let lineRange = source.lineRange(for: cursor)
            let line = source[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)

            switch line {
            case "---":
                cursor = consumeDashedManifestBlock(startingAt: lineRange.lowerBound, in: source)
            case let value where value.hasPrefix("// cargo-deps:"):
                cursor = lineRange.upperBound
            case let value where value.hasPrefix("//! ```cargo"):
                cursor = consumeDocManifestBlock(startingAt: lineRange.lowerBound, in: source)
            case "":
                cursor = lineRange.upperBound
            default:
                break loop
            }
        }

        return source.startIndex..<cursor
    }

    private func hiddenTestsRange(in source: String, startingAt minimumStart: String.Index) -> Range<String.Index> {
        guard
            let markerRange = source.range(of: "#[cfg(test", options: .backwards, range: minimumStart..<source.endIndex),
            let modRange = source.range(of: "mod tests", range: markerRange.lowerBound..<source.endIndex),
            modRange.lowerBound >= markerRange.lowerBound,
            let openingBrace = source[modRange.upperBound...].firstIndex(of: "{"),
            let closingBrace = matchingBrace(from: openingBrace, in: source)
        else {
            return source.endIndex..<source.endIndex
        }

        let trailingRange = closingBrace..<source.endIndex
        let trailingText = source[trailingRange]

        guard trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return source.endIndex..<source.endIndex
        }

        return markerRange.lowerBound..<source.endIndex
    }

    private func consumeDashedManifestBlock(startingAt start: String.Index, in source: String) -> String.Index {
        var cursor = source.lineRange(for: start).upperBound

        while cursor < source.endIndex {
            let lineRange = source.lineRange(for: cursor)
            let line = source[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = lineRange.upperBound

            if line == "---" {
                break
            }
        }

        return cursor
    }

    private func consumeDocManifestBlock(startingAt start: String.Index, in source: String) -> String.Index {
        var cursor = source.lineRange(for: start).upperBound

        while cursor < source.endIndex {
            let lineRange = source.lineRange(for: cursor)
            let line = source[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = lineRange.upperBound

            if line == "//! ```" {
                break
            }
        }

        return cursor
    }

    private func matchingBrace(from openingBrace: String.Index, in source: String) -> String.Index? {
        var depth = 0
        var index = openingBrace

        while index < source.endIndex {
            let character = source[index]

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1

                if depth == 0 {
                    return source.index(after: index)
                }
            }

            index = source.index(after: index)
        }

        return nil
    }

    private func extractChecks(from hiddenTestsBlock: String) -> [ExerciseCheck] {
        hiddenTestsBlock
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
                        detail: "Hidden test: \(identifier)",
                        symbolName: "checklist"
                    )
                )
            }
            .checks
    }

    private func endOfLine(after index: String.Index, in source: String) -> String.Index {
        source[index...].firstIndex(of: "\n").map { source.index(after: $0) } ?? source.endIndex
    }
}

private extension SourcePresentationBuilder {
    struct ExtractionState {
        var pendingAttributes: [String] = []
        var checks: [ExerciseCheck] = []
    }
}

private extension String {
    func lineRange(for index: Index) -> Range<Index> {
        let start = self[..<index].lastIndex(of: "\n").map { self.index(after: $0) } ?? startIndex
        let end = self[index...].firstIndex(of: "\n").map { self.index(after: $0) } ?? endIndex
        return start..<end
    }

    func appendingTrailingNewlineIfNeeded() -> String {
        guard !isEmpty, !hasSuffix("\n") else {
            return self
        }

        return self + "\n"
    }
}
