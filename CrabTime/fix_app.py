with open("Sources/CrabTime/Services/ProcessStore.swift", "r") as f:
    text = f.read()

text = text.replace("consoleOutput +=", "store.consoleOutput +=")
text = text.replace("consoleOutput =", "store.consoleOutput =")
# also remove clearConsoleOutput from ProcessStore as WorkspaceStore has it
import re
text = re.sub(r'    func clearConsoleOutput\(\) \{\n        store\.consoleOutput = ""\n    \}\n\n', '', text)
text = re.sub(r'    func clearConsoleOutput\(\) \{\n        consoleOutput = ""\n    \}\n\n', '', text)

with open("Sources/CrabTime/Services/ProcessStore.swift", "w") as f:
    f.write(text)

with open("Sources/CrabTime/Services/ExercismStore.swift", "r") as f:
    text = f.read()

text = text.replace("processStore.consoleOutput", "store.consoleOutput")

with open("Sources/CrabTime/Services/ExercismStore.swift", "w") as f:
    f.write(text)

with open("Sources/CrabTime/Services/ExerciseContextBuilder.swift", "r") as f:
    text = f.read()

text = text.replace("processStore.consoleOutput", "store.consoleOutput")

with open("Sources/CrabTime/Services/ExerciseContextBuilder.swift", "w") as f:
    f.write(text)

