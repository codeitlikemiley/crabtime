import AppKit
import SwiftUI

struct CloneRepositorySheetView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clone Repository")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(RustGoblinTheme.Palette.ink)

                Text("Paste a Git repository URL. RustGoblin will clone it into the local workspace library and load it.")
                    .font(.footnote)
                    .foregroundStyle(RustGoblinTheme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CloneRepositoryURLField(
                text: $store.cloneRepositoryURL,
                placeholder: "https://github.com/rust-lang/rustlings.git"
            )
            .frame(height: 28)

            if let cloneErrorMessage = store.cloneErrorMessage, !cloneErrorMessage.isEmpty {
                Text(cloneErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .interactivePointer()

                Button(store.isCloningRepository ? "Cloning…" : "Clone") {
                    store.cloneRepository()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isCloningRepository || store.cloneRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .interactivePointer()
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            store.cloneErrorMessage = nil
        }
    }
}

private struct CloneRepositoryURLField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = FirstResponderTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.font = .systemFont(ofSize: 13)
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .default
        textField.bezelStyle = .roundedBezel
        textField.lineBreakMode = .byTruncatingMiddle
        textField.usesSingleLineMode = true
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.commit(_:))
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        guard nsView.stringValue != text else {
            return
        }

        nsView.stringValue = text
    }
}

private extension CloneRepositoryURLField {
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else {
                return
            }

            text = field.stringValue
        }

        @MainActor
        @objc func commit(_ sender: NSTextField) {
            text = sender.stringValue
        }
    }
}

private final class FirstResponderTextField: NSTextField {
    private var hasBecomeFirstResponder = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard !hasBecomeFirstResponder else {
            return
        }

        hasBecomeFirstResponder = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else {
                return
            }

            window.makeFirstResponder(self)
            currentEditor()?.selectAll(nil)
        }
    }
}
