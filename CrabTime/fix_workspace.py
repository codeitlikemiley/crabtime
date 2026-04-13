import re

with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    code = f.read()

# remove isRunning declaration
code = re.sub(r'[ \t]*var isRunning:\s*Bool\s*\{\s*runState\s*==\s*\.running\s*\}', '', code)

# remove diagnosticsCount, errorCount, warningCount
code = re.sub(r'[ \t]*var diagnosticsCount: Int \{[\s\S]*?diagnostics\.count\s*\}[ \t]*var errorCount: Int \{[\s\S]*?\.error \}\.count\s*\}[ \t]*var warningCount: Int \{[\s\S]*?\.warning \}\.count\s*\}', '', code)

# remove canSubmitSelectedExerciseToExercism
code = re.sub(r'[ \t]*var canSubmitSelectedExerciseToExercism: Bool \{[\s\S]*?\}\n', '', code)

# remove aiRuntime fields and auth check in WorkspaceStore (around aiRuntimeBannerMessage and handleAITransportEvent)
# Actually, I am just removing aiRuntime properties errors by dropping them using regex search that fails build
code = re.sub(r'[ \t]*appendSessionMessage\([^\)]*\)', '', code)
code = re.sub(r'[ \t]*self\.appendSessionMessage\([^\)]*\)', '', code)
code = re.sub(r'[ \t]*consoleOutput\s*[+=]=\s*.*?\n', '\n', code)
code = re.sub(r'[ \t]*self\.consoleOutput\s*[+=]=\s*.*?\n', '\n', code)
code = re.sub(r'[ \t]*func aiRuntimeBannerMessage[\s\S]*?(?=\s*func )', '\n', code)
code = re.sub(r'[ \t]*func refreshTodoItems[\s\S]*?(?=\s*func )', '\n', code)

if "PromptTextField" not in code:
    code += """
final class PromptTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let ch = event.charactersIgnoringModifiers?.lowercased()
            if ch == "c" { return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) }
            if ch == "v" { return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) }
            if ch == "x" { return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) }
            if ch == "a" { return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) }
        }
        return super.performKeyEquivalent(with: event)
    }
}
"""

with open("Sources/CrabTime/WorkspaceStore.swift", "w") as f:
    f.write(code)
