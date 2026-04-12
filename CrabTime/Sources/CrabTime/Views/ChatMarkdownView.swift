import AppKit
import SwiftUI

struct ChatMarkdownView: View {
    let markdown: String

    private var blocks: [ChatMarkdownBlock] {
        ChatMarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ChatMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMarkdownBlockView: View {
    let block: ChatMarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            ChatInlineMarkdownText(markdown: text)
                .font(font(for: level))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
        case .paragraph(let text):
            ChatInlineMarkdownText(markdown: text)
                .font(.body)
                .foregroundStyle(CrabTimeTheme.Palette.ink)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    ChatMarkdownListItemView(marker: "•", markdown: item)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ChatMarkdownListItemView(marker: "\(index + 1).", markdown: item)
                }
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(CrabTimeTheme.Palette.panelTint)
                    .frame(width: 3)

                ChatInlineMarkdownText(markdown: text)
                    .font(.body)
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)
            }
            .padding(.vertical, 4)
        case .codeBlock(let language, let code):
            ChatCodeBlockView(language: language, code: code)
        case .thematicBreak:
            Rectangle()
                .fill(CrabTimeTheme.Palette.divider)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1:
            .title3.weight(.bold)
        case 2:
            .headline.weight(.bold)
        default:
            .subheadline.weight(.semibold)
        }
    }
}

private struct ChatMarkdownListItemView: View {
    let marker: String
    let markdown: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.body.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.textMuted)
                .frame(width: 20, alignment: .leading)

            ChatInlineMarkdownText(markdown: markdown)
                .font(.body)
                .foregroundStyle(CrabTimeTheme.Palette.ink)
        }
    }
}

private struct ChatCodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CrabTimeTheme.Palette.textMuted)

                Spacer()

                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(CrabTimeTheme.Palette.buttonFill))
                .overlay {
                    Capsule().stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
                }
            }

            Text(code)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(CrabTimeTheme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CrabTimeTheme.Palette.subtleFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CrabTimeTheme.Palette.divider, lineWidth: 1)
        }
    }
}

private struct ChatInlineMarkdownText: View {
    let markdown: String

    var body: some View {
        Text(renderedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var renderedText: AttributedString {
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return parsed
        }

        return AttributedString(markdown)
    }
}

private enum ChatMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case codeBlock(language: String?, code: String)
    case thematicBreak
}

private enum ChatListKind {
    case bullet
    case ordered
}

private enum ChatMarkdownParser {
    static func parse(_ markdown: String) -> [ChatMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [ChatMarkdownBlock] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text: text))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let text = quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.blockquote(text: text))
            }
            quoteLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let language = codeFenceLanguage(from: trimmed) {
                flushParagraph()
                flushQuote()

                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }

                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                if index < lines.count {
                    index += 1
                }
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                flushQuote()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                flushParagraph()
                flushQuote()
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let quoteText = quoteText(from: line) {
                flushParagraph()
                quoteLines.append(quoteText)
                index += 1
                continue
            }

            if let firstItem = bulletItemText(from: line) {
                flushParagraph()
                flushQuote()
                let collection = collectList(
                    from: lines,
                    startingAt: index,
                    firstItem: firstItem,
                    kind: .bullet
                )
                blocks.append(.bulletList(items: collection.items))
                index = collection.nextIndex
                continue
            }

            if let firstItem = orderedItemText(from: line) {
                flushParagraph()
                flushQuote()
                let collection = collectList(
                    from: lines,
                    startingAt: index,
                    firstItem: firstItem,
                    kind: .ordered
                )
                blocks.append(.orderedList(items: collection.items))
                index = collection.nextIndex
                continue
            }

            flushQuote()
            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        flushQuote()

        return blocks.isEmpty ? [.paragraph(text: markdown)] : blocks
    }

    private static func collectList(
        from lines: [String],
        startingAt startIndex: Int,
        firstItem: String,
        kind: ChatListKind
    ) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var currentItem = firstItem
        var index = startIndex + 1

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                break
            }

            if let nextItem = itemText(from: line, kind: kind) {
                items.append(currentItem.trimmingCharacters(in: .whitespacesAndNewlines))
                currentItem = nextItem
                index += 1
                continue
            }

            if heading(from: trimmed) != nil ||
                codeFenceLanguage(from: trimmed) != nil ||
                quoteText(from: line) != nil ||
                isThematicBreak(trimmed) ||
                itemText(from: line, kind: otherKind(for: kind)) != nil {
                break
            }

            let continuation = trimmed
            currentItem += continuation.isEmpty ? "\n" : "\n\(continuation)"
            index += 1
        }

        items.append(currentItem.trimmingCharacters(in: .whitespacesAndNewlines))
        return (items, index)
    }

    private static func otherKind(for kind: ChatListKind) -> ChatListKind {
        kind == .bullet ? .ordered : .bullet
    }

    private static func itemText(from line: String, kind: ChatListKind) -> String? {
        switch kind {
        case .bullet:
            bulletItemText(from: line)
        case .ordered:
            orderedItemText(from: line)
        }
    }

    private static func codeFenceLanguage(from line: String) -> String?? {
        guard line.hasPrefix("```") else {
            return nil
        }

        let suffix = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? .some(nil) : .some(suffix)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else {
            return nil
        }

        let remainder = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else {
            return nil
        }

        return (level, remainder)
    }

    private static func quoteText(from line: String) -> String? {
        let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
        guard stripped.first == ">" else {
            return nil
        }

        let text = stripped.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        return String(text)
    }

    private static func bulletItemText(from line: String) -> String? {
        let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
        guard stripped.count >= 2 else {
            return nil
        }

        let marker = stripped.first
        guard marker == "-" || marker == "*" || marker == "+" else {
            return nil
        }

        let remainder = stripped.dropFirst()
        guard remainder.first == " " else {
            return nil
        }

        return String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItemText(from line: String) -> String? {
        let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
        guard !stripped.isEmpty else {
            return nil
        }

        var digitCount = 0
        while digitCount < stripped.count, stripped[stripped.index(stripped.startIndex, offsetBy: digitCount)].isNumber {
            digitCount += 1
        }

        guard digitCount > 0 else {
            return nil
        }

        let dotIndex = stripped.index(stripped.startIndex, offsetBy: digitCount)
        guard dotIndex < stripped.endIndex, stripped[dotIndex] == "." else {
            return nil
        }

        let afterDot = stripped.index(after: dotIndex)
        guard afterDot < stripped.endIndex, stripped[afterDot] == " " else {
            return nil
        }

        let text = stripped[stripped.index(after: afterDot)...]
        return String(text).trimmingCharacters(in: .whitespaces)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let condensed = line.filter { !$0.isWhitespace }
        guard condensed.count >= 3, let first = condensed.first else {
            return false
        }
        return (first == "-" || first == "*" || first == "_") && condensed.allSatisfy { $0 == first }
    }
}
