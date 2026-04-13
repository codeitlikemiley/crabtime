with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    lines = f.read().splitlines()

ranges_to_drop = [
    (60, 70),       # aiRuntimeProviderTitle to aiRuntimeToolCalls (lines 61-71)
    (947, 1045),    # handleAITransportEvent to openAIRuntimeLogs (lines 948-1046)
    (2542, 2711),   # performRun to performExercismSubmit (lines 2543-2712)
    (3397, 3423),   # appendAIRuntimeEvent, updateAIToolCall (lines 3398-3424)
]

new_lines = []
for i, line in enumerate(lines):
    drop = False
    for start, end in ranges_to_drop:
        if start <= i <= end:
            drop = True
            break
    if not drop:
        new_lines.append(line)

code = "\n".join(new_lines) + "\n"

# 1. remove private from exercismCLI
code = code.replace("    @ObservationIgnored private let exercismCLI: ExercismCLI", "    @ObservationIgnored let exercismCLI: ExercismCLI")
# 2. remove private from applyCheckResults
code = code.replace("    private func applyCheckResults(from result: ProcessOutput)", "    func applyCheckResults(from result: ProcessOutput)")

with open("Sources/CrabTime/WorkspaceStore.swift", "w") as f:
    f.write(code)
