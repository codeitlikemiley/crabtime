with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    lines = f.read().splitlines()

ranges_to_drop = [
    (3030, 3083),   # resolveExercismDownloadInput, parseExercismDownloadCommand, firstRegexCapture (lines 3031-3084)
    (3188, 3201),   # PromptValidationError (lines 3189-3202)
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

with open("Sources/CrabTime/WorkspaceStore.swift", "w") as f:
    f.write(code)
