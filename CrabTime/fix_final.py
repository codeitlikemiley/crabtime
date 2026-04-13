with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    text = f.read()

# Fix `diagnostics = []` compilation error in WorkspaceStore
text = text.replace("            diagnostics = []\n", "")
text = text.replace("        diagnostics = []\n", "")

with open("Sources/CrabTime/WorkspaceStore.swift", "w") as f:
    f.write(text)
