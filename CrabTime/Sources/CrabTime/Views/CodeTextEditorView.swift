import AppKit
import SwiftUI

extension Notification.Name {
    static let goToLineRequested = Notification.Name("goToLineRequested")
    static let focusTextEditorRequested = Notification.Name("focusTextEditorRequested")
    static let saveCursorPositionRequested = Notification.Name("saveCursorPositionRequested")
    static let restoreCursorPositionRequested = Notification.Name("restoreCursorPositionRequested")
}

@MainActor
struct CodeTextEditorView: NSViewRepresentable {
    @Binding var text: String
    var onRun: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onTest: (() -> Void)? = nil
    var onCursorChange: ((Int) -> Void)? = nil
    /// Fires on every cursor movement with the raw byte offset (NSRange.location).
    /// Used to continuously track cursor position for reliable restoration.
    var onCursorOffsetChange: ((Int) -> Void)? = nil
    var onSaveCursorPosition: ((Int, String) -> Void)? = nil
    var showLineNumbers: Bool = true
    var goToLine: Int? = nil

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, onCursorChange: onCursorChange, onCursorOffsetChange: onCursorOffsetChange)
        coordinator.onSaveCursorPosition = onSaveCursorPosition
        return coordinator
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
        textView.font = SyntaxHighlighter.font
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

        // Configure line numbers via left-only inset
        textView.showLineNumbers = showLineNumbers
        textView.updateGutter()

        context.coordinator.isApplyingProgrammaticChange = true
        context.coordinator.applyProgrammaticText(text, to: textView)
        context.coordinator.applyHighlighting(to: textView)
        context.coordinator.isApplyingProgrammaticChange = false

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Observe scroll changes to redraw line numbers
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        textView.onRun = onRun
        textView.onSave = onSave
        textView.onTest = onTest

        if textView.showLineNumbers != showLineNumbers {
            textView.showLineNumbers = showLineNumbers
            textView.updateGutter()
            textView.needsDisplay = true
        }

        // Handle go-to-line is now done via notification (see Coordinator.handleGoToLine)

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
        var clearGoToLine: (() -> Void)?
        private var onCursorChange: ((Int) -> Void)?
        private var onCursorOffsetChange: ((Int) -> Void)?
        /// Callback to persist cursor offset for a specific file path.
        var onSaveCursorPosition: ((Int, String) -> Void)?

        init(text: Binding<String>, onCursorChange: ((Int) -> Void)? = nil, onCursorOffsetChange: ((Int) -> Void)? = nil) {
            _text = text
            self.onCursorChange = onCursorChange
            self.onCursorOffsetChange = onCursorOffsetChange
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleGoToLine(_:)),
                name: .goToLineRequested,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusEditor(_:)),
                name: .focusTextEditorRequested,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSaveCursorPosition(_:)),
                name: .saveCursorPositionRequested,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRestoreCursorPosition(_:)),
                name: .restoreCursorPositionRequested,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        func applyProgrammaticText(_ string: String, to textView: NSTextView) {
            textView.allowsUndo = false
            textView.string = string
            textView.allowsUndo = true
            if let undoManager = textView.undoManager {
                while undoManager.groupingLevel > 0 {
                    undoManager.endUndoGrouping()
                }
                undoManager.removeAllActions()
            }
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
            textView.updateGutter()
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isApplyingProgrammaticChange else { return }
            let location = textView.selectedRange().location
            // Always track raw byte offset — used for reliable cursor restoration
            // after terminal toggle, regardless of first-responder state.
            onCursorOffsetChange?(location)
            let nsString = textView.string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
            var lineNumber = 1
            var searchRange = NSRange(location: 0, length: min(lineRange.location, nsString.length))
            while searchRange.length > 0 {
                let foundRange = nsString.range(of: "\n", options: .literal, range: searchRange)
                if foundRange.location != NSNotFound {
                    lineNumber += 1
                    let consumed = foundRange.location + 1 - searchRange.location
                    searchRange.location += consumed
                    searchRange.length -= consumed
                } else {
                    break
                }
            }
            onCursorChange?(lineNumber)
        }

        @MainActor
        func applyHighlighting(to textView: NSTextView) {
            SyntaxHighlighter.apply(to: textView, fileExtension: "rs")
        }

        @MainActor
        @objc func viewDidScroll(_ notification: Notification) {
            textView?.setGutterNeedsDisplay()
        }

        @MainActor
        @objc func handleGoToLine(_ notification: Notification) {
            guard let textView,
                  let line = notification.userInfo?["line"] as? Int,
                  line > 0 else { return }

            let nsString = textView.string as NSString
            var currentLine = 1
            var targetCharIndex = 0
            var searchRange = NSRange(location: 0, length: nsString.length)
            
            while currentLine < line, searchRange.length > 0 {
                let foundRange = nsString.range(of: "\n", options: .literal, range: searchRange)
                if foundRange.location != NSNotFound {
                    currentLine += 1
                    targetCharIndex = foundRange.location + 1
                    let consumed = foundRange.location + 1 - searchRange.location
                    searchRange.location += consumed
                    searchRange.length -= consumed
                } else {
                    break
                }
            }
            // Move to end of this line
            var endOfLine = targetCharIndex
            while endOfLine < nsString.length {
                if nsString.character(at: endOfLine) == 0x000A { break }
                endOfLine += 1
            }
            let targetRange = NSRange(location: min(endOfLine, nsString.length), length: 0)
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)

            // Focus the text editor so cursor is active
            textView.window?.makeFirstResponder(textView)
        }

        @MainActor
        @objc func handleFocusEditor(_ notification: Notification) {
            guard let textView else { return }
            let savedRange = textView.selectedRange()
            textView.window?.makeFirstResponder(textView)
            // Restore cursor position — makeFirstResponder can sometimes reset it
            textView.setSelectedRange(savedRange.clamped(to: textView.string.utf16.count))
        }

        @MainActor
        @objc func handleSaveCursorPosition(_ notification: Notification) {
            guard let textView,
                  let path = notification.userInfo?["path"] as? String else { return }
            let offset = textView.selectedRange().location
            onSaveCursorPosition?(offset, path)
        }

        @MainActor
        @objc func handleRestoreCursorPosition(_ notification: Notification) {
            guard let textView,
                  let offset = notification.userInfo?["offset"] as? Int else { return }
            let maxOffset = textView.string.utf16.count
            let clampedOffset = min(offset, maxOffset)
            let range = NSRange(location: clampedOffset, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.window?.makeFirstResponder(textView)
        }
    }
}

// MARK: - RunAwareTextView with inline line numbers

final class RunAwareTextView: NSTextView {
    private static let pairedDelimiters: [Character: Character] = [
        "{": "}",
        "(": ")",
        "[": "]",
        "\"": "\""
    ]

    private static let lineNumFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let lineNumColor = NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.63, alpha: 0.7)
    private static let gutterBg = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1)

    var onRun: (() -> Void)?
    var onSave: (() -> Void)?
    var onTest: (() -> Void)?
    var showLineNumbers: Bool = false
    
    private let customUndoManager = UndoManager()
    
    override var undoManager: UndoManager? {
        return customUndoManager
    }
    private var gutterWidth: CGFloat = 0

    /// Compute gutter width based on total line count, then shift the text container.
    func updateGutter() {
        guard showLineNumbers else {
            gutterWidth = 0
            textContainerInset = NSSize(width: 16, height: 18)
            return
        }

        let lineCount = max(1, string.components(separatedBy: "\n").count)
        let digits = max(2, String(lineCount).count)  // at least 2 digits wide
        let sampleString = String(repeating: "0", count: digits) as NSString
        let digitWidth = sampleString.size(withAttributes: [.font: Self.lineNumFont]).width
        gutterWidth = ceil(digitWidth + 20)  // padding on both sides of numbers

        // textContainerInset.width applies to BOTH sides equally.
        // We use it for the left gutter. The right waste is acceptable.
        textContainerInset = NSSize(width: gutterWidth, height: 18)
    }

    func setGutterNeedsDisplay() {
        guard showLineNumbers, let visibleRect = enclosingScrollView?.contentView.documentVisibleRect else { return }
        let gutterRect = NSRect(x: visibleRect.origin.x, y: visibleRect.origin.y, width: gutterWidth, height: visibleRect.height)
        setNeedsDisplay(gutterRect)
    }

    override var textContainerOrigin: NSPoint {
        // Shift text container right by gutter width, but only add normal padding on top
        if showLineNumbers {
            return NSPoint(x: gutterWidth, y: textContainerInset.height)
        }
        return super.textContainerOrigin
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard showLineNumbers else { return }

        // The dirtyRect may NOT include the gutter (inset) area.
        // Use the full visible rect to draw line numbers.
        let visibleRect = enclosingScrollView?.documentVisibleRect ?? bounds

        NSGraphicsContext.current?.saveGraphicsState()
        // Expand clip to include gutter area
        NSBezierPath(rect: visibleRect).setClip()

        // Draw gutter background
        let gutterRect = NSRect(x: visibleRect.origin.x, y: visibleRect.origin.y,
                                 width: gutterWidth, height: visibleRect.height)
        Self.gutterBg.setFill()
        gutterRect.fill()

        drawLineNumbers(in: visibleRect)

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawLineNumbers(in visibleRect: NSRect) {
        guard let layoutManager, let textContainer else { return }

        let origin = textContainerOrigin
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.lineNumFont,
            .foregroundColor: Self.lineNumColor
        ]

        let nsString = string as NSString
        let totalLength = nsString.length

        guard totalLength > 0 else {
            drawNumber("1", y: origin.y, attrs: attrs)
            return
        }

        // Convert visible rect from view coords to container coords
        let containerRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Count lines before visible range
        var lineNumber = 1
        var searchRange = NSRange(location: 0, length: visibleCharRange.location)
        while searchRange.length > 0 {
            let foundRange = nsString.range(of: "\n", options: .literal, range: searchRange)
            if foundRange.location != NSNotFound {
                lineNumber += 1
                let consumed = foundRange.location + 1 - searchRange.location
                searchRange.location += consumed
                searchRange.length -= consumed
            } else {
                break
            }
        }


        // Draw visible line numbers
        var charIndex = visibleCharRange.location
        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            // Convert from container coords to view coords
            let y = lineRect.origin.y + origin.y
            drawNumber("\(lineNumber)", y: y, attrs: attrs)
            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }

        // Handle trailing newline
        if charIndex == totalLength, totalLength > 0, nsString.character(at: totalLength - 1) == 0x000A {
            let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: max(0, totalLength - 1))
            let lastRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            let y = lastRect.origin.y + lastRect.height + origin.y
            drawNumber("\(lineNumber)", y: y, attrs: attrs)
        }
    }

    private func drawNumber(_ string: String, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let size = (string as NSString).size(withAttributes: attrs)
        let x = gutterWidth - size.width - 6
        (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    // MARK: - Key handling

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

    // MARK: - Auto-pairing

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

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        NSRange(location: min(location, length), length: min(self.length, max(0, length - min(location, length))))
    }
}
