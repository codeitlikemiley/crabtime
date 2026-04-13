with open("Sources/CrabTime/Services/ProcessStore.swift", "r") as f:
    text = f.read()

funcs = """
    func moveDiagnosticSelectionUp() {
        guard !diagnostics.isEmpty else { return }
        selectedDiagnosticIndex = max(selectedDiagnosticIndex - 1, 0)
    }

    func moveDiagnosticSelectionDown() {
        guard !diagnostics.isEmpty else { return }
        selectedDiagnosticIndex = min(selectedDiagnosticIndex + 1, diagnostics.count - 1)
    }

    func activateSelectedDiagnostic(using store: WorkspaceStore) {
        guard diagnostics.indices.contains(selectedDiagnosticIndex) else { return }
        if let line = diagnostics[selectedDiagnosticIndex].line {
            store.goToLine(line)
        }
    }
}
"""

text = text.replace("\n}\n", "\n" + funcs)

with open("Sources/CrabTime/Services/ProcessStore.swift", "w") as f:
    f.write(text)

with open("Sources/CrabTime/Views/ConsolePanelView.swift", "r") as f:
    cp_text = f.read()

cp_text = cp_text.replace("store.moveDiagnosticSelectionUp(processStore: processStore)", "processStore.moveDiagnosticSelectionUp()")
cp_text = cp_text.replace("store.moveDiagnosticSelectionDown(processStore: processStore)", "processStore.moveDiagnosticSelectionDown()")
cp_text = cp_text.replace("store.activateSelectedDiagnostic(processStore: processStore)", "processStore.activateSelectedDiagnostic(using: store)")

with open("Sources/CrabTime/Views/ConsolePanelView.swift", "w") as f:
    f.write(cp_text)

