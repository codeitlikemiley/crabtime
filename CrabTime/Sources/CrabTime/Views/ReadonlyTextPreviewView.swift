import AppKit
import SwiftUI

struct ReadonlyTextPreviewView: NSViewRepresentable {
    let text: String
    var fileExtension: String? = nil
    var showLineNumbers: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = LineNumberTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = SyntaxHighlighter.font
        textView.textColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.showLineNumbers = showLineNumbers
        textView.string = text
        textView.updateGutter()

        SyntaxHighlighter.apply(to: textView, fileExtension: fileExtension)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Observe scroll to redraw line numbers
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
        guard let textView = context.coordinator.textView as? LineNumberTextView else {
            return
        }

        if textView.showLineNumbers != showLineNumbers {
            textView.showLineNumbers = showLineNumbers
            textView.updateGutter()
            textView.needsDisplay = true
        }

        guard textView.string != text else {
            return
        }

        let selectedRange = textView.selectedRange()
        textView.string = text
        textView.updateGutter()
        SyntaxHighlighter.apply(to: textView, fileExtension: fileExtension)
        textView.setSelectedRange(NSRange(location: min(selectedRange.location, text.utf16.count), length: 0))
    }
}

extension ReadonlyTextPreviewView {
    final class Coordinator: NSObject {
        weak var textView: NSTextView?

        @objc func viewDidScroll(_ notification: Notification) {
            textView?.needsDisplay = true
        }
    }
}

// MARK: - Readonly text view with inline line numbers

final class LineNumberTextView: NSTextView {
    private static let lineNumFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let lineNumColor = NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.63, alpha: 0.7)
    private static let gutterBg = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1)

    var showLineNumbers: Bool = false
    private var gutterWidth: CGFloat = 0

    func updateGutter() {
        guard showLineNumbers else {
            gutterWidth = 0
            textContainerInset = NSSize(width: 16, height: 18)
            return
        }

        let lineCount = max(1, string.components(separatedBy: "\n").count)
        let digits = max(2, String(lineCount).count)
        let sampleString = String(repeating: "0", count: digits) as NSString
        let digitWidth = sampleString.size(withAttributes: [.font: Self.lineNumFont]).width
        gutterWidth = ceil(digitWidth + 20)

        textContainerInset = NSSize(width: gutterWidth, height: 18)
    }

    override var textContainerOrigin: NSPoint {
        if showLineNumbers {
            return NSPoint(x: gutterWidth, y: textContainerInset.height)
        }
        return super.textContainerOrigin
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard showLineNumbers else { return }

        let visibleRect = enclosingScrollView?.documentVisibleRect ?? bounds

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: visibleRect).setClip()

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

        let containerRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        var i = 0
        while i < visibleCharRange.location {
            if nsString.character(at: i) == 0x000A { lineNumber += 1 }
            i += 1
        }

        var charIndex = visibleCharRange.location
        while charIndex < NSMaxRange(visibleCharRange) {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let y = lineRect.origin.y + origin.y

            drawNumber("\(lineNumber)", y: y, attrs: attrs)
            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }

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
}
