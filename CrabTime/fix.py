lines = open("Sources/CrabTime/WorkspaceStore.swift").read().split('\n')

new_lines = []
skip = False
for i, line in enumerate(lines):
    # Remove vars between 61 and 71
    if "var aiRuntimeProviderTitle" in line:
        skip = True
    if skip and "var diagnostics: [Diagnostic]" in line:
        skip = False

    if "var isRunning: Bool {" in line:
        skip = True
    if skip and "var diagnosticsCount: Int {" in line:
        pass # Wait, let's not overlap logic.
