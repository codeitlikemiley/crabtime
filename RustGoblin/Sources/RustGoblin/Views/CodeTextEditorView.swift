import AppKit
import SwiftUI

struct CodeTextEditorView: NSViewRepresentable {
    @Binding var text: String
    var onRun: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onTest: (() -> Void)? = nil
    var onCursorChange: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCursorChange: onCursorChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = RunAwareTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 18)
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        textView.delegate = context.coordinator
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.allowsImageEditing = false
        textView.onRun = onRun
        textView.onSave = onSave
        textView.onTest = onTest
        context.coordinator.isApplyingProgrammaticChange = true
        context.coordinator.applyProgrammaticText(text, to: textView)
        context.coordinator.applyHighlighting(to: textView)
        context.coordinator.isApplyingProgrammaticChange = false

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        textView.onRun = onRun
        textView.onSave = onSave
        textView.onTest = onTest

        guard textView.string != text else {
            return
        }

        let selectedRange = textView.selectedRange()
        context.coordinator.isApplyingProgrammaticChange = true
        context.coordinator.applyProgrammaticText(text, to: textView)
        context.coordinator.applyHighlighting(to: textView)
        textView.setSelectedRange(selectedRange.clamped(to: text.utf16.count))
        context.coordinator.isApplyingProgrammaticChange = false
    }
}

extension CodeTextEditorView {
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        fileprivate weak var textView: RunAwareTextView?
        var isApplyingProgrammaticChange = false
        private var onCursorChange: ((Int) -> Void)?

        init(text: Binding<String>, onCursorChange: ((Int) -> Void)? = nil) {
            _text = text
            self.onCursorChange = onCursorChange
        }

        @MainActor
        func applyProgrammaticText(_ string: String, to textView: NSTextView) {
            let previousAllowsUndo = textView.allowsUndo
            textView.allowsUndo = false
            textView.string = string
            textView.allowsUndo = previousAllowsUndo
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            guard
                !isApplyingProgrammaticChange,
                let textView
            else {
                return
            }

            let selection = textView.selectedRange()
            applyHighlighting(to: textView)
            textView.setSelectedRange(selection.clamped(to: textView.string.utf16.count))
            text = textView.string
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isApplyingProgrammaticChange else { return }
            let location = textView.selectedRange().location
            let nsString = textView.string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
            var lineNumber = 1
            var index = 0
            while index < lineRange.location && index < nsString.length {
                if nsString.character(at: index) == 0x000A { // newline
                    lineNumber += 1
                }
                index += 1
            }
            onCursorChange?(lineNumber)
        }

        @MainActor
        func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else {
                return
            }

            let string = textView.string
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            let palette = RustSyntaxPalette.current

            textStorage.beginEditing()
            textStorage.setAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: palette.foreground
                ],
                range: fullRange
            )

            for rule in RustSyntaxRule.allCases {
                rule.regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                    guard let match else {
                        return
                    }

                    textStorage.addAttribute(
                        .foregroundColor,
                        value: palette.color(for: rule),
                        range: match.range
                    )
                }
            }

            textStorage.endEditing()
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: palette.foreground
            ]
        }
    }
}

private final class RunAwareTextView: NSTextView {
    private static let pairedDelimiters: [Character: Character] = [
        "{": "}",
        "(": ")",
        "[": "]",
        "\"": "\""
    ]

    var onRun: (() -> Void)?
    var onSave: (() -> Void)?
    var onTest: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandCharacters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command, commandCharacters == "r" {
            onRun?()
            return true
        }

        if modifiers == .command, commandCharacters == "s" {
            onSave?()
            return true
        }

        if modifiers == .command, commandCharacters == "t" {
            onTest?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard shouldAutoPairDelimiters else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let stringValue: String
        if let string = insertString as? String {
            stringValue = string
        } else if let attributedString = insertString as? NSAttributedString {
            stringValue = attributedString.string
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        guard stringValue.count == 1, let character = stringValue.first else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        if let closing = Self.pairedDelimiters[character] {
            insertPairedDelimiter(opening: character, closing: closing, replacementRange: replacementRange)
            return
        }

        if Self.pairedDelimiters.values.contains(character), advanceThroughExistingClosingDelimiter(character, replacementRange: replacementRange) {
            return
        }

        super.insertText(stringValue, replacementRange: replacementRange)
    }



    private var shouldAutoPairDelimiters: Bool {
        return true
    }

    private func insertPairedDelimiter(opening: Character, closing: Character, replacementRange: NSRange) {
        let effectiveRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange

        if effectiveRange.length > 0 {
            let selectedText = (string as NSString).substring(with: effectiveRange)
            let wrapped = String(opening) + selectedText + String(closing)
            super.insertText(wrapped, replacementRange: effectiveRange)
            setSelectedRange(NSRange(location: effectiveRange.location + wrapped.utf16.count, length: 0))
            return
        }

        let paired = String(opening) + String(closing)
        super.insertText(paired, replacementRange: effectiveRange)
        setSelectedRange(NSRange(location: effectiveRange.location + 1, length: 0))
    }

    private func advanceThroughExistingClosingDelimiter(_ character: Character, replacementRange: NSRange) -> Bool {
        let effectiveRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        guard effectiveRange.length == 0 else {
            return false
        }

        let nsString = string as NSString
        guard effectiveRange.location < nsString.length else {
            return false
        }

        let nextCharacter = nsString.substring(with: NSRange(location: effectiveRange.location, length: 1))
        guard nextCharacter == String(character) else {
            return false
        }

        setSelectedRange(NSRange(location: effectiveRange.location + 1, length: 0))
        return true
    }
}

private enum RustSyntaxRule: CaseIterable {
    case keyword
    case type
    case string
    case number
    case comment
    case attribute
    case macro

    var regex: NSRegularExpression {
        switch self {
        case .keyword:
            return try! NSRegularExpression(pattern: #"\b(fn|let|mut|pub|use|mod|struct|enum|impl|match|if|else|loop|while|for|in|return|async|await|move|where|trait|const|static|crate|self|super)\b"#)
        case .type:
            return try! NSRegularExpression(pattern: #"\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|String|str|Self|Option|Result|Vec)\b"#)
        case .string:
            return try! NSRegularExpression(pattern: #""([^"\\]|\\.)*""#)
        case .number:
            return try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
        case .comment:
            return try! NSRegularExpression(pattern: #"(?m)//.*$"#)
        case .attribute:
            return try! NSRegularExpression(pattern: #"#\[[^\]]+\]"#)
        case .macro:
            return try! NSRegularExpression(pattern: #"\b[a-zA-Z_][a-zA-Z0-9_]*!"#)
        }
    }
}

private struct RustSyntaxPalette {
    let foreground: NSColor
    let keyword: NSColor
    let type: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let attribute: NSColor
    let macro: NSColor

    static let current = RustSyntaxPalette(
        foreground: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1),
        keyword: NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.66, alpha: 1),
        type: NSColor(calibratedRed: 0.56, green: 0.82, blue: 1.0, alpha: 1),
        string: NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.58, alpha: 1),
        number: NSColor(calibratedRed: 0.47, green: 0.84, blue: 0.63, alpha: 1),
        comment: NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.63, alpha: 1),
        attribute: NSColor(calibratedRed: 0.93, green: 0.57, blue: 0.73, alpha: 1),
        macro: NSColor(calibratedRed: 0.90, green: 0.67, blue: 1.0, alpha: 1)
    )

    func color(for rule: RustSyntaxRule) -> NSColor {
        switch rule {
        case .keyword:
            keyword
        case .type:
            type
        case .string:
            string
        case .number:
            number
        case .comment:
            comment
        case .attribute:
            attribute
        case .macro:
            macro
        }
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        NSRange(location: min(location, length), length: min(self.length, max(0, length - min(location, length))))
    }
}
