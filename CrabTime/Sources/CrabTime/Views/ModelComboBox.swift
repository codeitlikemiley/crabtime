import AppKit
import SwiftUI

@MainActor
struct ModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    var placeholder: String = "Model"
    var onCommit: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox(frame: .zero)
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.isEditable = true
        comboBox.isBordered = false
        comboBox.focusRingType = .none
        comboBox.font = .systemFont(ofSize: 12, weight: .medium)
        comboBox.textColor = NSColor.white
        comboBox.backgroundColor = .clear
        comboBox.target = context.coordinator
        comboBox.delegate = context.coordinator
        comboBox.numberOfVisibleItems = 14
        comboBox.cell?.lineBreakMode = .byTruncatingTail
        comboBox.placeholderString = placeholder
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        let selectedRange = comboBox.currentEditor()?.selectedRange
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: items)
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        if let selectedRange, comboBox.window?.firstResponder === comboBox.currentEditor() {
            comboBox.currentEditor()?.selectedRange = selectedRange
        }
        context.coordinator.onCommit = onCommit
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
        @Binding var text: String
        var onCommit: ((String) -> Void)?

        init(text: Binding<String>, onCommit: ((String) -> Void)?) {
            _text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            text = comboBox.stringValue
        }

        @MainActor
        func controlTextDidEndEditing(_ notification: Notification) {
            commit(notification.object as? NSComboBox)
        }

        @MainActor
        func comboBoxSelectionDidChange(_ notification: Notification) {
            commit(notification.object as? NSComboBox)
        }

        @MainActor
        private func commit(_ comboBox: NSComboBox?) {
            let value = comboBox?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else {
                return
            }
            text = value
            onCommit?(value)
        }
    }
}
