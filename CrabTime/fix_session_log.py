import re

# 1. ProcessStore: remove sessionLog and appendSessionMessage
with open("Sources/CrabTime/Services/ProcessStore.swift", "r") as f:
    ps_text = f.read()

ps_text = re.sub(r'    var sessionLog: \[String\] = \[\]\n', '', ps_text)
ps_text = re.sub(r'    func appendSessionMessage\(_ message: String\) \{\n(?:        .*\n)*?    \}\n\n?', '', ps_text)

# Fix ProcessStore's own usages to use `store.appendSessionMessage`
ps_text = ps_text.replace("appendSessionMessage(", "store.appendSessionMessage(")
ps_text = ps_text.replace("store.store.appendSessionMessage(", "store.appendSessionMessage(") # just in case

with open("Sources/CrabTime/Services/ProcessStore.swift", "w") as f:
    f.write(ps_text)

# 2. ExercismStore: replace processStore.appendSessionMessage with store.appendSessionMessage
with open("Sources/CrabTime/Services/ExercismStore.swift", "r") as f:
    es_text = f.read()

es_text = es_text.replace("processStore.appendSessionMessage(", "store.appendSessionMessage(")

with open("Sources/CrabTime/Services/ExercismStore.swift", "w") as f:
    f.write(es_text)

# 3. WorkspaceStore: remove `private` from `appendSessionMessage`
with open("Sources/CrabTime/WorkspaceStore.swift", "r") as f:
    ws_text = f.read()

ws_text = ws_text.replace("private func appendSessionMessage(_ message: String)", "func appendSessionMessage(_ message: String)")

with open("Sources/CrabTime/WorkspaceStore.swift", "w") as f:
    f.write(ws_text)

# 4. ConsolePanelView: replace processStore.sessionLog and processStore.consoleOutput with store.XX
with open("Sources/CrabTime/Views/ConsolePanelView.swift", "r") as f:
    cp_text = f.read()

cp_text = cp_text.replace("processStore.sessionLog", "store.sessionLog")
cp_text = cp_text.replace("processStore.consoleOutput", "store.consoleOutput")

with open("Sources/CrabTime/Views/ConsolePanelView.swift", "w") as f:
    f.write(cp_text)

