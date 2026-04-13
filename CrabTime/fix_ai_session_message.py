with open("Sources/CrabTime/Services/ProcessStore.swift", "r") as f:
    ps_text = f.read()

# Remove appendAISessionMessage usage
ps_text = ps_text.replace("    func appendAISessionMessage(_ message: String) {\n        store.appendSessionMessage(\"[AI] \(message)\")\n    }\n\n", "")
ps_text = ps_text.replace("        appendAISessionMessage(message)\n", "")
ps_text = ps_text.replace("        appendAISessionMessage(", "        // appendAISessionMessage(")

with open("Sources/CrabTime/Services/ProcessStore.swift", "w") as f:
    f.write(ps_text)

