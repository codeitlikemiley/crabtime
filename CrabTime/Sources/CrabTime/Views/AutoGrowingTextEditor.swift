import SwiftUI
import AppKit

// MARK: - AutoGrowingTextEditor
//
// A macOS-native multiline text input backed by NSTextView.
// Behaviors:
//   • Starts at 1 line high and grows intrinsically as text is typed.
//   • Once content exceeds `maxHeight`, the view stops expanding and
//     the inner NSTextView becomes scrollable.
//   • Return key inserts a newline (normal text editing behaviour).
//   • Cmd+Return fires `onSubmit`.
//   • Supports placeholder text, focus state, and SwiftUI text binding.

struct AutoGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var maxHeight: CGFloat = 180
    var isDisabled: Bool = false
    var isFocused: Bool = false
    var onSubmit: () -> Void = {}
    var onTextChange: ((String) -> Void)? = nil
    /// Called when the underlying NSTextView gains or loses first-responder status.
    var onFocusChange: ((Bool) -> Void)? = nil

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let textView = context.coordinator.textView
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.delegate = context.coordinator
        textView.string = text
        // Wire focus callbacks
        textView.onFocusGained = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocusChange?(true)
        }
        textView.onFocusLost = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocusChange?(false)
        }

        context.coordinator.updatePlaceholderVisibility()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let textView = coordinator.textView

        // Only update string if it differs (avoids cursor-jumping on every keystroke).
        // This branch ONLY fires on programmatic/SwiftUI-driven text changes (e.g. applySlashCommand,
        // replaceLastWord). User keystrokes keep textView.string in sync via textDidChange, so by the
        // time updateNSView runs after a keystroke, textView.string == text and we skip this block.
        // After a programmatic full-text replacement, move cursor to the end.
        if textView.string != text {
            textView.string = text
            let endLoc = (text as NSString).length
            textView.setSelectedRange(NSRange(location: endLoc, length: 0))
        }

        textView.isEditable = !isDisabled
        textView.alphaValue = isDisabled ? 0.5 : 1.0

        coordinator.updatePlaceholderVisibility()

        // Manage focus
        if isFocused, let window = scrollView.window,
           window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }

        // Recompute height
        coordinator.invalidateHeight(in: scrollView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingTextEditor
        let textView = PlaceholderTextView()
        private var heightConstraint: NSLayoutConstraint?

        init(parent: AutoGrowingTextEditor) {
            self.parent = parent
            super.init()
        }

        func updatePlaceholderVisibility() {
            textView.placeholderString = parent.placeholder
            textView.needsDisplay = true
        }

        func invalidateHeight(in scrollView: NSScrollView) {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }

            layoutManager.ensureLayout(for: container)
            let usedHeight = layoutManager.usedRect(for: container).height
            let inset = textView.textContainerInset.height * 2
            let natural = usedHeight + inset + 2
            let clamped = min(natural, parent.maxHeight)

            if scrollView.frame.height != clamped {
                // Express desired height as a constraint on the scroll view
                if let existing = heightConstraint {
                    existing.constant = clamped
                } else {
                    let c = scrollView.heightAnchor.constraint(equalToConstant: clamped)
                    c.priority = .defaultHigh
                    c.isActive = true
                    heightConstraint = c
                }
                scrollView.needsLayout = true
            }
        }

        // NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newText = tv.string
            parent.text = newText
            parent.onTextChange?(newText)
            updatePlaceholderVisibility()
            if let sv = tv.enclosingScrollView {
                invalidateHeight(in: sv)
            }
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // Cmd+Return → submit
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                parent.onSubmit()
                return true
            }
            // Plain Return → insert newline (default behaviour, return false)
            return false
        }
    }
}

// MARK: - PlaceholderTextView

/// NSTextView subclass that draws placeholder text when empty,
/// and fires focus-change callbacks when it becomes/resigns first responder.
final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    /// Called (on main thread) when this view becomes first responder.
    var onFocusGained: (() -> Void)?
    /// Called (on main thread) when this view resigns first responder.
    var onFocusLost: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in self?.onFocusGained?() }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in self?.onFocusLost?() }
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: inset.width + padding,
            y: inset.height,
            width: bounds.width - inset.width * 2 - padding,
            height: bounds.height - inset.height * 2
        )
        placeholderString.draw(in: rect, withAttributes: attrs)
    }
}
