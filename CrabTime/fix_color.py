with open("Sources/CrabTime/Views/ConsolePanelView.swift", "r") as f:
    text = f.read()

text = text.replace("processStore.errorCount > 0 ? .red : CrabTimeTheme.Palette.ember", "processStore.errorCount > 0 ? Color.red : CrabTimeTheme.Palette.ember")

with open("Sources/CrabTime/Views/ConsolePanelView.swift", "w") as f:
    f.write(text)

