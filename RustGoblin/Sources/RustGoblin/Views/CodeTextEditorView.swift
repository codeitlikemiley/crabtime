import AppKit
import SwiftUI

struct CodeTextEditorView: NSViewRepresentable {
    @Binding var text: String
    var onRun: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        context.coordinator.isApplyingProgrammaticChange = true
        textView.string = text
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

        guard textView.string != text else {
            return
        }

        let selectedRange = textView.selectedRange()
        context.coordinator.isApplyingProgrammaticChange = true
        textView.string = text
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

        init(text: Binding<String>) {
            _text = text
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
    var onRun: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandCharacters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command, commandCharacters == "r" {
            onRun?()
            return true
        }

        return super.performKeyEquivalent(with: event)
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
