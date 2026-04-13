with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    text = f.read()

count = 0
for i, c in enumerate(text):
    if c == '{': count += 1
    elif c == '}': count -= 1
    if count == 0 and i > 100:
        print("Closed at line:", text.count('\n', 0, i) + 1)
        break
