with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    text = f.read()

count = 0
for i, line in enumerate(text.split('\n')):
    if "func toggleProblemPaneVisibility()" in line:
        print("Inserting brace before line", i+1)
        break
