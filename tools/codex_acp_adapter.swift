#!/usr/bin/env swift

import Foundation

private let protocolVersion = 1

private struct SessionState {
    let sessionID: String
    let cwd: String
    var history: [(role: String, content: String)] = []
}

private struct ACPError: Error {
    let code: Int
    let message: String
}

private final class DataBox {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let value = storage
        lock.unlock()
        return value
    }
}

private final class CodexACPAdapter {
    private let model: String
    private var sessions: [String: SessionState] = [:]

    init(model: String) {
        self.model = model
    }

    func serve() -> Int32 {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard
                let data = trimmed.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let requestID = object["id"]
            let method = object["method"] as? String
            let params = object["params"] as? [String: Any] ?? [:]

            do {
                guard let method else {
                    throw ACPError(code: -32600, message: "Invalid request")
                }

                let result = try handleRequest(method: method, params: params)
                if let requestID {
                    send([
                        "jsonrpc": "2.0",
                        "id": requestID,
                        "result": result
                    ])
                }
            } catch let error as ACPError {
                if let requestID {
                    send([
                        "jsonrpc": "2.0",
                        "id": requestID,
                        "error": [
                            "code": error.code,
                            "message": error.message
                        ]
                    ])
                }
            } catch {
                if let requestID {
                    send([
                        "jsonrpc": "2.0",
                        "id": requestID,
                        "error": [
                            "code": -32000,
                            "message": error.localizedDescription
                        ]
                    ])
                }
            }
        }

        return 0
    }

    private func handleRequest(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": protocolVersion,
                "agentInfo": [
                    "name": "codex-acp-adapter",
                    "title": "Codex ACP Adapter",
                    "version": "0.1"
                ],
                "agentCapabilities": [
                    "loadSession": false,
                    "promptCapabilities": [
                        "image": false,
                        "audio": false,
                        "embeddedContext": false
                    ],
                    "mcpCapabilities": [
                        "http": false,
                        "sse": false
                    ]
                ],
                "authMethods": []
            ]
        case "session/new":
            guard let cwd = params["cwd"] as? String, !cwd.isEmpty else {
                throw ACPError(code: -32602, message: "session/new requires cwd")
            }

            let sessionID = "codex-\(UUID().uuidString.lowercased())"
            sessions[sessionID] = SessionState(sessionID: sessionID, cwd: cwd)
            return ["sessionId": sessionID]
        case "session/load":
            guard let sessionID = params["sessionId"] as? String, sessions[sessionID] != nil else {
                throw ACPError(code: -32001, message: "Unknown sessionId")
            }
            return ["sessionId": sessionID]
        case "session/prompt":
            guard let sessionID = params["sessionId"] as? String else {
                throw ACPError(code: -32602, message: "session/prompt requires sessionId")
            }
            guard var session = sessions[sessionID] else {
                throw ACPError(code: -32001, message: "Unknown sessionId")
            }
            guard let promptItems = params["prompt"] as? [[String: Any]] else {
                throw ACPError(code: -32602, message: "session/prompt requires prompt array")
            }

            let promptText = promptItems.compactMap { item -> String? in
                guard let type = item["type"] as? String, type == "text" else {
                    return nil
                }
                return item["text"] as? String
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !promptText.isEmpty else {
                throw ACPError(code: -32602, message: "session/prompt requires text content")
            }

            session.history.append((role: "user", content: promptText))
            let assistantText = try runCodex(session: session)
            session.history.append((role: "assistant", content: assistantText))
            sessions[sessionID] = session

            send([
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": [
                    "sessionId": sessionID,
                    "update": [
                        "sessionUpdate": "agent_message_chunk",
                        "content": [
                            "type": "text",
                            "text": assistantText
                        ]
                    ]
                ]
            ])

            return [
                "stopReason": "end_turn",
                "content": assistantText
            ]
        default:
            throw ACPError(code: -32601, message: "Unsupported ACP method \(method)")
        }
    }

    private func runCodex(session: SessionState) throws -> String {
        let transcript = session.history.map { message in
            "\(message.role.uppercased()):\n\(message.content)"
        }.joined(separator: "\n\n")

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let streamGroup = DispatchGroup()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "codex",
            "exec",
            "-",
            "--skip-git-repo-check",
            "--json",
            "--ephemeral",
            "--color",
            "never",
            "--full-auto",
            "-m",
            model,
            "-C",
            session.cwd
        ]
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        guard let stdinPipe = process.standardInput as? Pipe else {
            throw ACPError(code: -32010, message: "Failed to create stdin pipe for Codex.")
        }

        streamGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }

        streamGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }

        try process.run()

        if let inputData = transcript.data(using: .utf8) {
            try stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
        }
        try stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()
        streamGroup.wait()

        let stdoutData = stdoutBox.data()
        let stderrData = stderrBox.data()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ACPError(code: -32010, message: message.isEmpty ? "Codex exec failed." : message)
        }

        let assistantText = extractAssistantText(from: stdoutText)
        if assistantText.isEmpty {
            let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ACPError(
                code: -32011,
                message: message.isEmpty ? "Codex exec returned an empty response." : message
            )
        }
        return assistantText
    }

    private func extractAssistantText(from stdout: String) -> String {
        var assistantText = ""
        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.first == "{", let data = line.data(using: .utf8) else {
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard let type = object["type"] as? String, type == "item.completed" else {
                continue
            }
            guard
                let item = object["item"] as? [String: Any],
                let itemType = item["type"] as? String,
                itemType == "agent_message",
                let text = item["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            assistantText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return assistantText
    }

    private func send(_ payload: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let line = String(data: data, encoding: .utf8)
        else {
            return
        }

        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

private func parseModelArgument() -> String? {
    let arguments = CommandLine.arguments
    guard let modelIndex = arguments.firstIndex(of: "--model"), arguments.indices.contains(modelIndex + 1) else {
        return nil
    }
    return arguments[modelIndex + 1]
}

guard let model = parseModelArgument() else {
    FileHandle.standardError.write(Data("Missing required --model argument.\n".utf8))
    exit(2)
}

exit(CodexACPAdapter(model: model).serve())
